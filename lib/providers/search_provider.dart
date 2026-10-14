import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/prowlarr_service.dart';
import '../services/rom_database_service.dart';
import 'api_provider.dart';
import 'prowlarr_provider.dart';
import 'settings_provider.dart';

class SearchState {
  final String query;
  final List<String> selectedPlatforms;
  final List<String> selectedRegions;
  final bool retroAchievementsOnly;
  final SearchResult? result;
  final bool isLoading;
  final dynamic error;

  const SearchState({
    this.query = '',
    this.selectedPlatforms = const [],
    this.selectedRegions = const [],
    this.retroAchievementsOnly = false,
    this.result,
    this.isLoading = false,
    this.error,
  });

  SearchState copyWith({
    String? query,
    List<String>? selectedPlatforms,
    List<String>? selectedRegions,
    bool? retroAchievementsOnly,
    SearchResult? result,
    bool? isLoading,
    dynamic error,
    bool clearError = false,
  }) {
    return SearchState(
      query: query ?? this.query,
      selectedPlatforms: selectedPlatforms ?? this.selectedPlatforms,
      selectedRegions: selectedRegions ?? this.selectedRegions,
      retroAchievementsOnly:
          retroAchievementsOnly ?? this.retroAchievementsOnly,
      result: result ?? this.result,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class SearchNotifier extends StateNotifier<SearchState> {
  final RomDatabaseService _db;
  final ProwlarrService _prowlarr;
  final bool _prowlarrSearchEnabled;
  final String _prowlarrBaseUrl;

  SearchNotifier(
    this._db,
    this._prowlarr, {
    bool prowlarrSearchEnabled = false,
    String prowlarrBaseUrl = '',
  })  : _prowlarrSearchEnabled = prowlarrSearchEnabled,
        _prowlarrBaseUrl = prowlarrBaseUrl,
        super(const SearchState());

  Future<void> search({String? query}) async {
    state = state.copyWith(
      query: query ?? state.query,
      isLoading: true,
      clearError: true,
    );

    try {
      final effectiveQuery = state.query.isEmpty ? null : state.query;
      // Live Prowlarr results only apply to the first page of a query
      // search — there's no live equivalent of pagination for a source
      // that's just a single request against whatever indexers the
      // user's Prowlarr instance has configured.
      final wantsLive = _prowlarrSearchEnabled &&
          effectiveQuery != null &&
          _prowlarrBaseUrl.isNotEmpty;

      final results = await Future.wait([
        _db.search(
          query: effectiveQuery,
          platforms: state.selectedPlatforms.isEmpty
              ? null
              : state.selectedPlatforms,
          regions:
              state.selectedRegions.isEmpty ? null : state.selectedRegions,
          retroAchievementsOnly: state.retroAchievementsOnly,
          page: 1,
        ),
        wantsLive ? _searchProwlarr(effectiveQuery) : Future.value(<RomEntry>[]),
      ]);

      final localResult = results[0] as SearchResult;
      final liveEntries = results[1] as List<RomEntry>;
      final result = liveEntries.isEmpty
          ? localResult
          : SearchResult(
              entries: [...localResult.entries, ...liveEntries],
              totalResults: localResult.totalResults + liveEntries.length,
              currentPage: localResult.currentPage,
              totalPages: localResult.totalPages,
              currentResults: localResult.currentResults + liveEntries.length,
            );

      state = state.copyWith(result: result, isLoading: false);
    } catch (error) {
      state = state.copyWith(error: error, isLoading: false);
    }
  }

  Future<List<RomEntry>> _searchProwlarr(String query) async {
    try {
      final apiKey = await _prowlarr.getApiKey();
      if (apiKey == null || apiKey.isEmpty) return [];
      return await _prowlarr.search(
        baseUrl: _prowlarrBaseUrl,
        apiKey: apiKey,
        query: query,
      );
    } catch (_) {
      // Best-effort — a Prowlarr hiccup shouldn't fail the whole search.
      return [];
    }
  }

  Future<void> loadNextPage() async {
    final currentResult = state.result;
    if (currentResult == null || !currentResult.hasMore || state.isLoading) {
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final nextPage = currentResult.currentPage + 1;
      final result = await _db.search(
        query: state.query.isEmpty ? null : state.query,
        platforms: state.selectedPlatforms.isEmpty
            ? null
            : state.selectedPlatforms,
        regions: state.selectedRegions.isEmpty ? null : state.selectedRegions,
        retroAchievementsOnly: state.retroAchievementsOnly,
        page: nextPage,
      );

      // Append new entries to existing ones
      final combinedEntries = [...currentResult.entries, ...result.entries];
      final combinedResult = SearchResult(
        entries: combinedEntries,
        totalResults: result.totalResults,
        currentPage: result.currentPage,
        totalPages: result.totalPages,
        currentResults: combinedEntries.length,
      );

      state = state.copyWith(result: combinedResult, isLoading: false);
    } catch (error) {
      state = state.copyWith(error: error, isLoading: false);
    }
  }

  void setSelectedPlatforms(List<String> platforms) {
    state = state.copyWith(selectedPlatforms: platforms);
  }

  void setSelectedRegions(List<String> regions) {
    state = state.copyWith(selectedRegions: regions);
  }

  void setRetroAchievementsOnly(bool value) {
    state = state.copyWith(retroAchievementsOnly: value);
  }

  void clearFilters() {
    state = state.copyWith(
      selectedPlatforms: [],
      selectedRegions: [],
      retroAchievementsOnly: false,
    );
  }

  void reset() {
    state = const SearchState();
  }
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((
  ref,
) {
  final db = ref.watch(romDatabaseProvider);
  final prowlarr = ref.watch(prowlarrServiceProvider);
  final settings = ref.watch(settingsProvider);

  return SearchNotifier(
    db,
    prowlarr,
    prowlarrSearchEnabled: settings.prowlarrSearchEnabled,
    prowlarrBaseUrl: settings.prowlarrBaseUrl,
  );
});
