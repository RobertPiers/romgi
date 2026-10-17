import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/retroarch_catalog_service.dart';
import '../services/retroarch_launcher.dart';
import '../services/rom_database_service.dart';
import 'api_provider.dart';
import 'retroarch_provider.dart';

const int _catalogPageSize = 48;

class CatalogLibraryState {
  final List<CatalogPlatform> platforms;
  final String? selectedPlatform;
  final String query;
  final SearchResult? result;
  final bool isLoading;
  final String? error;

  const CatalogLibraryState({
    this.platforms = const [],
    this.selectedPlatform,
    this.query = '',
    this.result,
    this.isLoading = false,
    this.error,
  });

  CatalogLibraryState copyWith({
    List<CatalogPlatform>? platforms,
    String? selectedPlatform,
    bool clearSelectedPlatform = false,
    String? query,
    SearchResult? result,
    bool clearResult = false,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return CatalogLibraryState(
      platforms: platforms ?? this.platforms,
      selectedPlatform: clearSelectedPlatform
          ? null
          : (selectedPlatform ?? this.selectedPlatform),
      query: query ?? this.query,
      result: clearResult ? null : (result ?? this.result),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  bool get showingGames => selectedPlatform != null || query.isNotEmpty;
}

class CatalogLibraryNotifier extends StateNotifier<CatalogLibraryState> {
  final RomDatabaseService _romDb;
  final RetroArchLauncher _launcher;

  CatalogLibraryNotifier(this._romDb, this._launcher)
      : super(const CatalogLibraryState()) {
    loadSystems();
  }

  Future<void> loadSystems() async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearSelectedPlatform: true,
      clearResult: true,
    );
    try {
      final allPlatforms = await _romDb.getCatalogPlatforms();
      final supported = await _supportedPlatforms();
      final platforms = allPlatforms
          .where((platform) => supported.contains(platform.id))
          .toList(growable: false);
      state = CatalogLibraryState(platforms: platforms);
    } catch (error) {
      state = CatalogLibraryState(error: error.toString());
    }
  }

  Future<void> selectPlatform(String platform) async {
    state = state.copyWith(
      selectedPlatform: platform,
      query: '',
      clearResult: true,
      isLoading: true,
      clearError: true,
    );
    await _loadPage(page: 1);
  }

  Future<void> setQuery(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      await loadSystems();
      return;
    }

    state = state.copyWith(
      query: normalized,
      clearSelectedPlatform: true,
      clearResult: true,
      isLoading: true,
      clearError: true,
    );
    await _loadPage(page: 1);
  }

  Future<void> loadNextPage() async {
    final result = state.result;
    if (result == null || !result.hasMore || state.isLoading) return;
    await _loadPage(page: result.currentPage + 1, appendTo: result);
  }

  Future<void> refresh() async {
    if (state.showingGames) {
      final page = state.result?.currentPage ?? 1;
      state = state.copyWith(isLoading: true, clearError: true);
      await _loadPage(page: page);
    } else {
      await loadSystems();
    }
  }

  Future<void> _loadPage({required int page, SearchResult? appendTo}) async {
    try {
      final result = await _romDb.search(
        query: state.query.isEmpty ? null : state.query,
        platforms: state.selectedPlatform == null
            ? null
            : [state.selectedPlatform!],
        page: page,
        maxResults: _catalogPageSize,
      );
      final entries = appendTo == null
          ? result.entries
          : [...appendTo.entries, ...result.entries];
      state = state.copyWith(
        result: SearchResult(
          entries: entries,
          totalResults: result.totalResults,
          currentPage: result.currentPage,
          totalPages: result.totalPages,
          currentResults: entries.length,
        ),
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<Set<String>> _supportedPlatforms() async {
    final coreNames = await _launcher.installedCoreNames();
    if (coreNames == null || coreNames.isEmpty) {
      return RetroArchPlatformRegistry.definitions.keys.toSet();
    }
    final detected = RetroArchPlatformRegistry.platformsForCoreNames(coreNames);
    return detected.isEmpty
        ? RetroArchPlatformRegistry.definitions.keys.toSet()
        : detected;
  }
}

final catalogLibraryProvider = StateNotifierProvider<
    CatalogLibraryNotifier, CatalogLibraryState>((ref) {
  return CatalogLibraryNotifier(
    ref.watch(romDatabaseProvider),
    ref.watch(retroArchLauncherProvider),
  );
});
