import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/services.dart';
import '../utils/utils.dart';

/// Steam-style library for content that can be launched by RetroArch.
///
/// This is deliberately a Romgi screen rather than a second catalog. It uses
/// Romgi's catalog and artwork, while RetroArch remains responsible for core
/// loading and gameplay.
class RetroArchLibraryScreen extends ConsumerStatefulWidget {
  const RetroArchLibraryScreen({super.key});

  @override
  ConsumerState<RetroArchLibraryScreen> createState() =>
      _RetroArchLibraryScreenState();
}

class _RetroArchLibraryScreenState
    extends ConsumerState<RetroArchLibraryScreen> {
  final _searchController = TextEditingController();
  final _pendingLaunches = <String>{};
  final _busySlugs = <String>{};
  String _search = '';
  String? _platform;
  bool _showSearch = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(retroArchLibraryProvider);
    final downloads = ref.watch(downloadProvider);
    final settings = ref.watch(settingsProvider);

    ref.listen<DownloadState>(downloadProvider, (previous, next) {
      final completed = next.completedDownloads;
      for (final task in completed) {
        if (_pendingLaunches.contains(task.slug)) {
          unawaited(_launchCompleted(task));
        }
      }
    });

    final activeBySlug = <String, DownloadTask>{
      for (final task in downloads.activeDownloads) task.slug: task,
    };
    final items = _filteredItems(catalog.items);

    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search RetroArch library...',
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _search = value),
              )
            : const Text('RetroArch Library'),
        actions: [
          IconButton(
            tooltip: _showSearch ? 'Close search' : 'Search',
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchController.clear();
                  _search = '';
                }
              });
            },
          ),
          IconButton(
            tooltip: 'Refresh library',
            icon: const Icon(Icons.refresh),
            onPressed: catalog.isLoading
                ? null
                : () => ref.read(retroArchLibraryProvider.notifier).refresh(),
          ),
        ],
      ),
      body: catalog.isLoading && catalog.items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : catalog.error != null && catalog.items.isEmpty
              ? _ErrorState(
                  message: catalog.error!,
                  onRetry: () =>
                      ref.read(retroArchLibraryProvider.notifier).refresh(),
                )
              : Column(
                  children: [
                    _LibraryHeader(
                      total: catalog.items.length,
                      installed: catalog.items
                          .where((item) => item.isInstalled)
                          .length,
                      pending: activeBySlug.length,
                    ),
                    _PlatformFilter(
                      items: catalog.items,
                      selected: _platform,
                      onSelected: (platform) =>
                          setState(() => _platform = platform),
                    ),
                    Expanded(
                      child: items.isEmpty
                          ? const Center(
                              child: Text('No matching RetroArch content'),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final columns = constraints.maxWidth >= 1200
                                    ? 6
                                    : constraints.maxWidth >= 900
                                        ? 5
                                        : constraints.maxWidth >= 600
                                            ? 4
                                            : 2;
                                return GridView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    4,
                                    12,
                                    24,
                                  ),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                    childAspectRatio: 0.67,
                                  ),
                                  itemCount: items.length,
                                  itemBuilder: (context, index) {
                                    final item = items[index];
                                    return _RetroArchCard(
                                      item: item,
                                      activeTask: activeBySlug[
                                          item.content.romgiSlug],
                                      busy: _busySlugs
                                          .contains(item.content.romgiSlug),
                                      debridEnabled: settings.debridEnabled,
                                      onPressed: () => _playOrInstall(item),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  List<RetroArchLibraryItem> _filteredItems(
    List<RetroArchLibraryItem> source,
  ) {
    final query = _search.trim().toLowerCase();
    return source.where((item) {
      if (_platform != null && item.content.platform != _platform) {
        return false;
      }
      if (query.isEmpty) return true;
      return item.content.title.toLowerCase().contains(query) ||
          item.content.filename.toLowerCase().contains(query) ||
          PlatformNames.getDisplayName(item.content.platform)
              .toLowerCase()
              .contains(query);
    }).toList(growable: false);
  }

  Future<void> _playOrInstall(RetroArchLibraryItem item) async {
    final content = item.content;
    if (_busySlugs.contains(content.romgiSlug)) return;

    final localPath = item.installedPath;
    if (localPath != null && _pathExists(localPath)) {
      await _launchPath(localPath);
      return;
    }

    DownloadTask? active;
    for (final task in ref.read(downloadProvider).activeDownloads) {
      if (task.slug == content.romgiSlug) {
        active = task;
        break;
      }
    }
    if (active != null) {
      _pendingLaunches.add(content.romgiSlug);
      _showMessage('${content.title} is already downloading');
      return;
    }

    if (content.requiresDebrid && !ref.read(settingsProvider).debridEnabled) {
      _showMessage(
        'Enable a debrid provider before installing this torrent-backed game',
      );
      return;
    }

    setState(() => _busySlugs.add(content.romgiSlug));
    _pendingLaunches.add(content.romgiSlug);
    try {
      final (result, task) = await ref
          .read(downloadProvider.notifier)
          .addDownload(
            slug: content.romgiSlug,
            title: content.title,
            platform: content.platform,
            boxartUrl: content.boxartUrl,
            link: content.link,
          );

      if (!mounted) return;
      if (result == AddDownloadResult.duplicate) {
        if (task.status == DownloadStatus.completed &&
            task.filePath != null &&
            _pathExists(task.filePath!)) {
          _pendingLaunches.remove(content.romgiSlug);
          await _launchPath(task.filePath!);
        } else {
          _showMessage('${content.title} is already in the download queue');
        }
      } else {
        _showMessage('Installing ${content.title}… It will launch when ready');
      }
    } catch (error) {
      _pendingLaunches.remove(content.romgiSlug);
      if (mounted) _showMessage('Could not start install: $error');
    } finally {
      if (mounted) setState(() => _busySlugs.remove(content.romgiSlug));
    }
  }

  Future<void> _launchCompleted(DownloadTask task) async {
    _pendingLaunches.remove(task.slug);
    final path = task.filePath;
    if (path == null || !_pathExists(path)) {
      await ref.read(retroArchLibraryProvider.notifier).refresh();
      if (mounted) _showMessage('${task.title} finished but its file is missing');
      return;
    }

    await ref.read(retroArchLibraryProvider.notifier).refresh();
    await _launchPath(path);
  }

  Future<void> _launchPath(String path) async {
    try {
      await ref.read(retroArchLauncherProvider).launch(path);
    } on PlatformException catch (error) {
      if (mounted) {
        _showMessage(error.message ?? 'RetroArch is not installed');
      }
    } catch (error) {
      if (mounted) _showMessage('Could not launch RetroArch: $error');
    }
  }

  bool _pathExists(String path) {
    return File(path).existsSync() || Directory(path).existsSync();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LibraryHeader extends StatelessWidget {
  final int total;
  final int installed;
  final int pending;

  const _LibraryHeader({
    required this.total,
    required this.installed,
    required this.pending,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text('$total games', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(width: 12),
          Text(
            '$installed installed',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (pending > 0) ...[
            const SizedBox(width: 12),
            Text(
              '$pending downloading',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _PlatformFilter extends StatelessWidget {
  final List<RetroArchLibraryItem> items;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const _PlatformFilter({
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final platforms = items.map((item) => item.content.platform).toSet().toList()
      ..sort();
    return SizedBox(
      height: 48,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        scrollDirection: Axis.horizontal,
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          const SizedBox(width: 8),
          ...platforms.map(
            (platform) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(PlatformNames.getDisplayName(platform)),
                selected: selected == platform,
                onSelected: (_) => onSelected(platform),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RetroArchCard extends StatelessWidget {
  final RetroArchLibraryItem item;
  final DownloadTask? activeTask;
  final bool busy;
  final bool debridEnabled;
  final VoidCallback onPressed;

  const _RetroArchCard({
    required this.item,
    required this.activeTask,
    required this.busy,
    required this.debridEnabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final content = item.content;
    final task = activeTask;
    final nativeArtworkPath = item.nativeArtworkPath;
    final isDownloading = task != null;
    final blocked = content.requiresDebrid && !debridEnabled;
    final label = item.isInstalled
        ? 'Play'
        : isDownloading
            ? task.statusText
            : blocked
                ? 'Debrid required'
                : 'Install';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy || isDownloading && !item.isInstalled ? null : onPressed,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: nativeArtworkPath == null
                  ? _fallbackArtwork(context, content)
                  : Image.file(
                      File(nativeArtworkPath),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _fallbackArtwork(context, content),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 8, 9, 2),
              child: Text(
                content.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Text(
                PlatformNames.getDisplayName(content.platform),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (isDownloading && task.progress > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 5, 9, 0),
                child: LinearProgressIndicator(value: task.progress),
              ),
            Padding(
              padding: const EdgeInsets.all(7),
              child: FilledButton.tonalIcon(
                onPressed: busy || isDownloading && !item.isInstalled
                    ? null
                    : onPressed,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(item.isInstalled
                        ? Icons.play_arrow
                        : Icons.download),
                label: Text(label, maxLines: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackArtwork(BuildContext context, RetroArchContent content) {
    if (content.boxartUrl == null) {
      return const ColoredBox(
        color: Colors.black12,
        child: Icon(Icons.videogame_asset, size: 48),
      );
    }
    return CachedNetworkImage(
      imageUrl: content.boxartUrl!,
      fit: BoxFit.cover,
      placeholder: (context, url) => const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      errorWidget: (context, url, error) => const ColoredBox(
        color: Colors.black12,
        child: Icon(Icons.broken_image_outlined, size: 40),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
