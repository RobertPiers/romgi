import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/storage_service.dart';
import '../utils/utils.dart';
import 'entry_detail_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  bool _showSearch = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(libraryProvider);
    final favoritesAsync = ref.watch(favoritesProvider);

    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search library...',
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  ref.read(libraryProvider.notifier).setSearchQuery(value);
                },
              )
            : const Text('Library'),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchController.clear();
                  ref.read(libraryProvider.notifier).setSearchQuery('');
                }
              });
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'verify') {
                await ref.read(libraryProvider.notifier).verifyFiles();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Files verified')),
                  );
                }
              } else if (value == 'cleanup') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clean Up Library'),
                    content: const Text(
                      'Remove entries for files that no longer exist on disk?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Clean Up'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await ref
                      .read(libraryProvider.notifier)
                      .cleanupMissingFiles();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Library cleaned up')),
                    );
                  }
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'verify',
                child: ListTile(
                  leading: Icon(Icons.verified),
                  title: Text('Verify Files'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'cleanup',
                child: ListTile(
                  leading: Icon(Icons.cleaning_services),
                  title: Text('Clean Up'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.folder, size: 18),
                  const SizedBox(width: 8),
                  Text('Games (${libraryState.items.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.favorite, size: 18),
                  const SizedBox(width: 8),
                  Text('Wishlist (${favoritesAsync.valueOrNull?.length ?? 0})'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Local game frontend
          _buildDownloadedTab(libraryState),
          // Wishlist tab
          _buildWishlistTab(favoritesAsync),
        ],
      ),
    );
  }

  Widget _buildDownloadedTab(LibraryState libraryState) {
    if (libraryState.searchQuery.isEmpty &&
        libraryState.selectedPlatform == null) {
      return _buildSystemsView(libraryState);
    }

    return Column(
      children: [
        if (libraryState.selectedPlatform != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => ref
                  .read(libraryProvider.notifier)
                  .setSelectedPlatform(null),
              icon: const Icon(Icons.arrow_back),
              label: Text(
                'All systems · ${PlatformNames.getDisplayName(libraryState.selectedPlatform!)}',
              ),
            ),
          ),
        Expanded(
          child: libraryState.isLoading
              ? const Center(child: CircularProgressIndicator())
              : libraryState.filteredItems.isEmpty
              ? _buildEmptyState(libraryState)
              : RefreshIndicator(
                  onRefresh: () => ref.read(libraryProvider.notifier).refresh(),
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 230,
                      mainAxisExtent: 300,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: libraryState.filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = libraryState.filteredItems[index];
                        return _LibraryGameCard(
                          item: item,
                          onTap: () => _openFile(item),
                          onDetails: () => _showDetails(item),
                        onDelete: () => _confirmDelete(item),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSystemsView(LibraryState libraryState) {
    if (libraryState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (libraryState.items.isEmpty) {
      return _buildEmptyState(libraryState);
    }

    final counts = <String, int>{};
    final representatives = <String, LocalGame>{};
    for (final game in libraryState.items) {
      counts[game.platform] = (counts[game.platform] ?? 0) + 1;
      representatives.putIfAbsent(game.platform, () => game);
    }
    final platforms = counts.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: () => ref.read(libraryProvider.notifier).refresh(),
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 280,
          mainAxisExtent: 170,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: platforms.length,
        itemBuilder: (context, index) {
          final platform = platforms[index];
          final representative = representatives[platform]!;
          return _SystemCard(
            platform: platform,
            count: counts[platform]!,
            representative: representative,
            onTap: () => ref
                .read(libraryProvider.notifier)
                .setSelectedPlatform(platform),
          );
        },
      ),
    );
  }

  Widget _buildWishlistTab(AsyncValue<List<Favorite>> favoritesAsync) {
    return favoritesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Failed to load wishlist',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
      data: (favorites) {
        if (favorites.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite_border, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'Your wishlist is empty',
                  style: TextStyle(color: Colors.grey[600], fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap the heart icon on any ROM to add it here',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: favorites.length,
          itemBuilder: (context, index) {
            final item = favorites[index];
            return _WishlistItemTile(
              item: item,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EntryDetailScreen(slug: item.slug),
                  ),
                );
              },
              onRemove: () async {
                final messenger = ScaffoldMessenger.of(context);
                await ref
                    .read(favoritesProvider.notifier)
                    .removeFavorite(item.slug);
                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Removed from wishlist')),
                  );
                }
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(LibraryState state) {
    if (state.searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No results for "${state.searchQuery}"',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    if (state.selectedPlatform != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No ${PlatformNames.getDisplayName(state.selectedPlatform!)} ROMs',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_books, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Your library is empty',
            style: TextStyle(color: Colors.grey[600], fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Downloaded or scanned ROMs will appear here',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Future<void> _openFile(LocalGame item) async {
    final file = File(item.filePath);
    final directory = Directory(item.filePath);
    if (!await file.exists() && !await directory.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('File no longer exists')));
      }
      return;
    }

    try {
      await ref.read(retroArchLauncherProvider).launch(item.filePath);
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not launch in RetroArch: ${error.message ?? error.code}',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch in RetroArch: $error')),
        );
      }
    }
  }

  Future<void> _showDetails(LocalGame item) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(item.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('System', PlatformNames.getDisplayName(item.platform)),
            _infoRow('Format', item.format),
            _infoRow('Size', StorageService.formatBytes(item.size)),
            const SizedBox(height: 8),
            Text(
              item.filePath,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _openFile(item);
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Play'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(LocalGame item) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete ROM'),
        content: Text('Delete "${item.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          if (item.isManagedDownload)
            TextButton(
              onPressed: () => Navigator.pop(context, 'remove'),
              child: const Text('Remove from Library'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete File'),
          ),
        ],
      ),
    );

    if (result == 'remove') {
      await ref
          .read(libraryProvider.notifier)
          .deleteItem(item, deleteFile: false);

      // Invalidate download status providers so search results update
      ref.invalidate(downloadedSlugsProvider);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Removed from library')));
      }
    } else if (result == 'delete') {
      await ref
          .read(libraryProvider.notifier)
          .deleteItem(item, deleteFile: true);

      // Invalidate download status providers so search results update
      ref.invalidate(downloadedSlugsProvider);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ROM deleted')));
      }
    }
  }
}

class _LibraryGameCard extends StatelessWidget {
  final LocalGame item;
  final VoidCallback onTap;
  final VoidCallback onDetails;
  final VoidCallback onDelete;

  const _LibraryGameCard({
    required this.item,
    required this.onTap,
    required this.onDetails,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onDetails,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 180,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  item.artworkPath != null
                      ? Image.file(
                          File(item.artworkPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) =>
                              _networkArtwork(theme),
                        )
                      : item.boxartUrl != null
                      ? CachedNetworkImage(
                          imageUrl: item.boxartUrl!,
                          fit: BoxFit.cover,
                          placeholder: (context, string) =>
                              _placeholder(theme),
                          errorWidget: (context, string, error) =>
                              _placeholder(theme),
                        )
                      : _placeholder(theme),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: FloatingActionButton.small(
                      heroTag: 'play-${item.id}',
                      onPressed: onTap,
                      tooltip: 'Play in RetroArch',
                      child: const Icon(Icons.play_arrow),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      if (value == 'details') onDetails();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'details',
                        child: Text('Details'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
              child: Text(
                PlatformNames.getDisplayName(item.platform),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.videogame_asset,
        size: 48,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _networkArtwork(ThemeData theme) {
    final url = item.boxartUrl;
    if (url == null) return _placeholder(theme);
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      errorWidget: (context, string, error) => _placeholder(theme),
    );
  }
}

class _SystemCard extends StatelessWidget {
  final String platform;
  final int count;
  final LocalGame representative;
  final VoidCallback onTap;

  const _SystemCard({
    required this.platform,
    required this.count,
    required this.representative,
    required this.onTap,
  });

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
            if (representative.artworkPath != null)
              Image.file(
                File(representative.artworkPath!),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    _systemPlaceholder(theme),
              )
            else if (representative.boxartUrl != null)
              CachedNetworkImage(
                imageUrl: representative.boxartUrl!,
                fit: BoxFit.cover,
                errorWidget: (context, string, error) =>
                    _systemPlaceholder(theme),
              )
            else
              _systemPlaceholder(theme),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.85),
                    ],
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
                    PlatformNames.getDisplayName(platform),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '$count ${count == 1 ? 'game' : 'games'}',
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

  Widget _systemPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.primaryContainer,
      alignment: Alignment.center,
      child: Icon(
        Icons.videogame_asset,
        size: 56,
        color: theme.colorScheme.onPrimaryContainer,
      ),
    );
  }
}

class _WishlistItemTile extends StatelessWidget {
  final Favorite item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _WishlistItemTile({
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 56,
          height: 56,
          child: item.boxartUrl != null
              ? CachedNetworkImage(
                  imageUrl: item.boxartUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, string) => Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.gamepad, color: Colors.grey),
                  ),
                  errorWidget: (context, string, error) => Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.gamepad, color: Colors.grey),
                  ),
                )
              : Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.gamepad, color: Colors.grey),
                ),
        ),
      ),
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          PlatformNames.getDisplayName(item.platform),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.favorite, color: Colors.red),
        onPressed: onRemove,
        tooltip: 'Remove from wishlist',
      ),
      onTap: onTap,
    );
  }
}
