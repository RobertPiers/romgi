import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/services.dart';
import 'download_provider.dart';

class LibraryState {
  final List<LocalGame> items;
  final String? selectedPlatform;
  final String searchQuery;
  final bool isLoading;

  const LibraryState({
    this.items = const [],
    this.selectedPlatform,
    this.searchQuery = '',
    this.isLoading = false,
  });

  LibraryState copyWith({
    List<LocalGame>? items,
    String? selectedPlatform,
    bool clearPlatform = false,
    String? searchQuery,
    bool? isLoading,
  }) {
    return LibraryState(
      items: items ?? this.items,
      selectedPlatform: clearPlatform
          ? null
          : (selectedPlatform ?? this.selectedPlatform),
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  List<LocalGame> get filteredItems {
    var result = items;

    if (selectedPlatform != null) {
      result = result
          .where((item) => item.platform == selectedPlatform)
          .toList();
    }

    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      result = result
          .where(
            (item) =>
                item.title.toLowerCase().contains(query) ||
                item.platform.toLowerCase().contains(query),
          )
          .toList();
    }

    return result;
  }

  List<String> get platforms {
    final platformSet = items.map((item) => item.platform).toSet();
    return platformSet.toList()..sort();
  }

}

class LibraryNotifier extends StateNotifier<LibraryState> {
  final LocalGameLibraryService _service;
  final DatabaseService _db;
  final StorageService _storage;

  LibraryNotifier(this._service, this._db, this._storage)
      : super(const LibraryState()) {
    refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    try {
      final items = await _service.load();
      state = state.copyWith(items: items, isLoading: false);
    } catch (_) {
      state = state.copyWith(items: const [], isLoading: false);
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setSelectedPlatform(String? platform) {
    if (platform == null) {
      state = state.copyWith(clearPlatform: true);
    } else {
      state = state.copyWith(selectedPlatform: platform);
    }
  }

  Future<void> deleteItem(LocalGame game, {bool deleteFile = true}) async {
    // A scanned file has no database record to remove. It leaves the library
    // only when the file itself is deleted or moved.
    if (game.downloadId != null) await _db.deleteDownload(game.downloadId!);
    if (deleteFile) {
      await _storage.deleteFile(game.filePath);
    }
    await refresh();
  }

  Future<void> verifyFiles() async {
    await refresh();
  }

  /// Remove entries for missing files
  Future<void> cleanupMissingFiles() async {
    await refresh();
  }
}

final libraryProvider = StateNotifierProvider<LibraryNotifier, LibraryState>((
  ref,
) {
  return LibraryNotifier(
    LocalGameLibraryService(
      db: ref.watch(databaseServiceProvider),
      storage: ref.watch(storageServiceProvider),
      launcher: ref.watch(retroArchLauncherProvider),
    ),
    ref.watch(databaseServiceProvider),
    ref.watch(storageServiceProvider),
  );
});

/// Provider for all downloaded slugs (for badge display)
/// Watches libraryProvider to auto-refresh when library changes
final downloadedSlugsProvider = FutureProvider<Set<String>>((ref) async {
  final libraryState = ref.watch(libraryProvider);
  // Use library items if available (faster), otherwise fetch from db
  if (!libraryState.isLoading && libraryState.items.isNotEmpty) {
    return libraryState.items
        .map((game) => game.slug)
        .whereType<String>()
        .toSet();
  }
  final db = ref.watch(databaseServiceProvider);
  final completed = await db.getCompletedDownloads();

  return completed.map((task) => task.slug).toSet();
});
