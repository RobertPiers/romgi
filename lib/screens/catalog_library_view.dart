import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/download_service.dart';
import '../services/link_resolver.dart';
import '../utils/utils.dart';
import 'entry_detail_screen.dart';

/// Catalog-backed collection view.
///
/// Romgi owns the lightweight catalog and install state, while RetroArch is
/// the backend that actually loads the content and its core. Only one page of
/// catalog entries is held by this view at a time; the complete collection is
/// never turned into Flutter widgets.
class CatalogLibraryView extends ConsumerStatefulWidget {
  const CatalogLibraryView({super.key});

  @override
  ConsumerState<CatalogLibraryView> createState() =>
      _CatalogLibraryViewState();
}

class _CatalogLibraryViewState extends ConsumerState<CatalogLibraryView> {
  final _queryController = TextEditingController();
  final _scrollController = ScrollController();
  final _busySlugs = <String>{};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreWhenNeeded);
  }

  @override
  void dispose() {
    _queryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _loadMoreWhenNeeded() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      ref.read(catalogLibraryProvider.notifier).loadNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogLibraryProvider);
    final downloads = ref.watch(downloadProvider);
    final downloaded = ref.watch(downloadedSlugsProvider).valueOrNull ?? {};
    final installedSlugs = {
      ...downloaded,
      ...downloads.completedDownloads.map((task) => task.slug),
    };
    final activeBySlug = <String, DownloadTask>{
      for (final task in downloads.activeDownloads) task.slug: task,
    };

    return Column(
      children: [
        _buildToolbar(context, catalog),
        Expanded(
          child: _buildContent(
            context,
            catalog,
            installedSlugs,
            activeBySlug,
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context, CatalogLibraryState catalog) {
    final selected = catalog.selectedPlatform;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          if (selected != null) ...[
            IconButton(
              tooltip: 'All systems',
              onPressed: () {
                _queryController.clear();
                ref.read(catalogLibraryProvider.notifier).loadSystems();
              },
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                PlatformNames.getDisplayName(selected),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ] else
            Expanded(
              child: TextField(
                controller: _queryController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search the collection',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _queryController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _queryController.clear();
                            ref
                                .read(catalogLibraryProvider.notifier)
                                .loadSystems();
                            setState(() {});
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (query) => ref
                    .read(catalogLibraryProvider.notifier)
                    .setQuery(query),
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh collection',
            onPressed: catalog.isLoading
                ? null
                : () => ref.read(catalogLibraryProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    CatalogLibraryState catalog,
    Set<String> installedSlugs,
    Map<String, DownloadTask> activeBySlug,
  ) {
    if (catalog.error != null && !catalog.showingGames) {
      return _errorState(catalog.error!);
    }
    if (catalog.isLoading && catalog.platforms.isEmpty && !catalog.showingGames) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!catalog.showingGames) {
      return _buildSystems(context, catalog.platforms);
    }

    final result = catalog.result;
    if (catalog.isLoading && result == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (catalog.error != null && result == null) {
      return _errorState(catalog.error!);
    }
    if (result == null || result.entries.isEmpty) {
      return const Center(child: Text('No games found'));
    }

    final entries = result.entries;
    return RefreshIndicator(
      onRefresh: () => ref.read(catalogLibraryProvider.notifier).refresh(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1200
              ? 6
              : constraints.maxWidth >= 900
                  ? 5
                  : constraints.maxWidth >= 600
                      ? 4
                      : 2;
          final itemCount = entries.length + (result.hasMore ? 1 : 0);
          return GridView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.67,
            ),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              if (index >= entries.length) {
                return const Center(child: CircularProgressIndicator());
              }
              final entry = entries[index];
              return _CatalogGameCard(
                entry: entry,
                installed: installedSlugs.contains(entry.slug),
                activeTask: activeBySlug[entry.slug],
                busy: _busySlugs.contains(entry.slug),
                onPlayOrInstall: () => _playOrInstall(entry),
                onDetails: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EntryDetailScreen(slug: entry.slug),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSystems(BuildContext context, List<CatalogPlatform> platforms) {
    if (platforms.isEmpty) {
      return const Center(child: Text('No RetroArch-compatible systems found'));
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(catalogLibraryProvider.notifier).refresh(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900 ? 4 : 2;
          return GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.45,
            ),
            itemCount: platforms.length,
            itemBuilder: (context, index) {
              final platform = platforms[index];
              return _CatalogPlatformCard(
                platform: platform,
                onTap: () => ref
                    .read(catalogLibraryProvider.notifier)
                    .selectPlatform(platform.id),
              );
            },
          );
        },
      ),
    );
  }

  Widget _errorState(String message) {
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
            FilledButton(
              onPressed: () => ref.read(catalogLibraryProvider.notifier).refresh(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _playOrInstall(RomEntry summary) async {
    if (_busySlugs.contains(summary.slug)) return;
    setState(() => _busySlugs.add(summary.slug));

    try {
      final db = ref.read(databaseServiceProvider);
      final completed = await db.getCompletedDownloads();
      DownloadTask? completedTask;
      for (final task in completed) {
        if (task.slug == summary.slug) {
          completedTask = task;
          break;
        }
      }
      final completedPath = completedTask?.filePath;
      if (completedPath != null && _pathExists(completedPath)) {
        await _launch(completedPath, platform: summary.platform);
        return;
      }

      DownloadTask? active;
      for (final task in ref.read(downloadProvider).activeDownloads) {
        if (task.slug == summary.slug) {
          active = task;
          break;
        }
      }
      if (active != null) {
        _message('${summary.title} is already ${active.statusText.toLowerCase()}');
        return;
      }

      final entry = summary.links.isEmpty
          ? await ref.read(romDatabaseProvider).getEntry(summary.slug)
          : summary;
      if (entry == null) {
        _message('This game is no longer available in the catalog');
        return;
      }

      final settings = ref.read(settingsProvider);
      final iaLoggedIn = await ref.read(iaLoggedInProvider.future);
      final ranked = const LinkResolver(
        sourcePriority: kKnownSourcePriority,
      ).rank(
        entry.links,
        LinkResolverPrefs(
          isIaLoggedIn: iaLoggedIn,
          torrentsDisabled: settings.torrentsDisabled,
          debridEnabled: settings.debridEnabled,
        ),
      );
      if (ranked.isEmpty) {
        _message('No usable RetroArch download is available for this game');
        return;
      }

      final link = ranked.first.link;
      if (link.requiresAuth && !iaLoggedIn) {
        _message('Open the game details to sign in to Internet Archive');
        return;
      }
      if (link.isTorrent && !settings.debridEnabled) {
        _message('Enable a debrid provider before installing this game');
        return;
      }

      final (result, _) = await ref.read(downloadProvider.notifier).addDownload(
            slug: entry.slug,
            title: entry.title,
            platform: entry.platform,
            boxartUrl: entry.boxartUrl,
            link: link,
          );
      if (result == AddDownloadResult.duplicate) {
        _message('${entry.title} is already in the download queue');
      } else {
        _message('Installing ${entry.title}… It will be available in Library');
      }
    } catch (error) {
      _message('Could not install ${summary.title}: $error');
    } finally {
      if (mounted) setState(() => _busySlugs.remove(summary.slug));
    }
  }

  Future<void> _launch(String path, {String? platform}) async {
    try {
      await ref.read(retroArchLauncherProvider).launch(
            path,
            platform: platform,
          );
    } on PlatformException catch (error) {
      _message(error.message ?? 'RetroArch is not installed');
    } catch (error) {
      _message('Could not launch RetroArch: $error');
    }
  }

  bool _pathExists(String path) =>
      File(path).existsSync() || Directory(path).existsSync();

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CatalogPlatformCard extends StatelessWidget {
  final CatalogPlatform platform;
  final VoidCallback onTap;

  const _CatalogPlatformCard({required this.platform, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (platform.artworkUrl != null)
              CachedNetworkImage(
                imageUrl: platform.artworkUrl!,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => _placeholder(theme),
              )
            else
              _placeholder(theme),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: .88)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    PlatformNames.getDisplayName(platform.id),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${platform.gameCount} games',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(ThemeData theme) => ColoredBox(
        color: theme.colorScheme.primaryContainer,
        child: Icon(
          Icons.videogame_asset,
          size: 52,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      );
}

class _CatalogGameCard extends StatelessWidget {
  final RomEntry entry;
  final bool installed;
  final DownloadTask? activeTask;
  final bool busy;
  final VoidCallback onPlayOrInstall;
  final VoidCallback onDetails;

  const _CatalogGameCard({
    required this.entry,
    required this.installed,
    required this.activeTask,
    required this.busy,
    required this.onPlayOrInstall,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final downloading = activeTask != null;
    final label = installed
        ? 'Play'
        : downloading
            ? activeTask!.statusText
            : 'Install';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onDetails,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _artwork(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 8, 9, 2),
              child: Text(
                entry.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Text(
                PlatformNames.getDisplayName(entry.platform),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (downloading && activeTask!.progress > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 5, 9, 0),
                child: LinearProgressIndicator(value: activeTask!.progress),
              ),
            Padding(
              padding: const EdgeInsets.all(7),
              child: FilledButton.tonalIcon(
                onPressed: busy || downloading && !installed
                    ? null
                    : onPlayOrInstall,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(installed ? Icons.play_arrow : Icons.download),
                label: Text(label, maxLines: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _artwork(BuildContext context) {
    if (entry.boxartUrl == null) {
      return const ColoredBox(
        color: Colors.black12,
        child: Icon(Icons.videogame_asset, size: 48),
      );
    }
    return CachedNetworkImage(
      imageUrl: entry.boxartUrl!,
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
