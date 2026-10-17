import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/models.dart';
import 'database_service.dart';
import 'retroarch_catalog_service.dart';
import 'rom_database_service.dart';
import 'storage_service.dart';

/// Builds the Steam-like RetroArch library shown by Romgi.
///
/// RetroArch remains the player and core host. Romgi owns the catalog and
/// source resolution, then marks an item installed when its selected content
/// or a completed task's playable path is present on disk.
class RetroArchLibraryService {
  final RomDatabaseService _romDb;
  final DatabaseService _db;
  final StorageService _storage;
  final RetroArchCatalogAdapter _catalog;

  RetroArchLibraryService({
    required RomDatabaseService romDb,
    required DatabaseService db,
    required StorageService storage,
    RetroArchCatalogAdapter? catalog,
  })  : _romDb = romDb,
        _db = db,
        _storage = storage,
        _catalog = catalog ?? RetroArchCatalogAdapter();

  Future<List<RetroArchLibraryItem>> load({
    bool isIaLoggedIn = false,
  }) async {
    final platformEntries = await Future.wait(
      _catalog.supportedPlatforms.map(
        (platform) => _romDb.getEntriesWithLinksForPlatform(platform),
      ),
    );

    final contents = [
      ..._catalog.adaptAll(
        platformEntries.expand((entries) => entries),
        isIaLoggedIn: isIaLoggedIn,
      ),
    ]
      ..sort((a, b) {
        final platform = a.platform.compareTo(b.platform);
        if (platform != 0) return platform;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });

    final completed = await _db.getCompletedDownloads();
    final completedBySlug = <String, DownloadTask>{};
    for (final task in completed) {
      completedBySlug.putIfAbsent(task.slug, () => task);
    }

    final installedByPlatform = <String, Map<String, String>>{};
    for (final platform in _catalog.supportedPlatforms) {
      installedByPlatform[platform] = await _scanPlatform(platform);
    }

    return contents
        .map(
          (content) => RetroArchLibraryItem(
            content: content,
            installedPath: _installedPath(
              content,
              completedBySlug[content.romgiSlug],
              installedByPlatform[content.platform] ?? const {},
            ),
          ),
        )
        .toList(growable: false);
  }

  Future<Map<String, String>> _scanPlatform(String platform) async {
    final directory = await _storage.getPlatformDirectory(platform);
    if (!await directory.exists()) return const {};

    final result = <String, String>{};
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        result[p.basename(entity.path).toLowerCase()] = entity.path;
      }
    }
    return result;
  }

  String? _installedPath(
    RetroArchContent content,
    DownloadTask? completedTask,
    Map<String, String> files,
  ) {
    final taskPath = completedTask?.filePath;
    if (taskPath != null && _pathExists(taskPath)) return taskPath;

    return files[content.filename.toLowerCase()];
  }

  bool _pathExists(String path) {
    return File(path).existsSync() || Directory(path).existsSync();
  }
}
