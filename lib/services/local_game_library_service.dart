import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/models.dart';
import 'database_service.dart';
import 'retroarch_artwork_service.dart';
import 'retroarch_catalog_service.dart';
import 'retroarch_launcher.dart';
import 'storage_service.dart';

/// Scans only local ROM folders for the launcher screen.
///
/// It intentionally does not query Romgi's remote ROM catalog. The catalog is
/// for Browse/downloads; this service is the small, local collection that a
/// frontend needs to render and launch.
class LocalGameLibraryService {
  final DatabaseService _db;
  final StorageService _storage;
  final RetroArchArtworkService _artwork;
  final RetroArchLauncher _launcher;

  LocalGameLibraryService({
    required DatabaseService db,
    required StorageService storage,
    RetroArchArtworkService? artwork,
    RetroArchLauncher? launcher,
  })  : _db = db,
        _storage = storage,
        _artwork = artwork ?? RetroArchArtworkService(),
        _launcher = launcher ?? RetroArchLauncher();

  Future<List<LocalGame>> load() async {
    final supportedPlatforms = await _supportedPlatforms();
    final games = <String, LocalGame>{};

    // Romgi-managed downloads retain their catalog title and artwork.
    final completed = await _db.getCompletedDownloads();
    for (final task in completed) {
      final filePath = task.filePath;
      if (filePath == null || !await _pathExists(filePath)) continue;
      if (!supportedPlatforms.contains(task.platform)) continue;

      final title = task.title.trim().isEmpty
          ? _titleFromPath(filePath)
          : task.title;
      games[_key(filePath)] = LocalGame(
        id: 'download:${task.id}',
        title: title,
        platform: task.platform,
        filePath: filePath,
        format: _format(filePath, fallback: task.link.format),
        size: await _fileSize(filePath),
        boxartUrl: task.boxartUrl,
        artworkPath: await _artwork.findForGame(
          platform: task.platform,
          title: title,
        ),
        slug: task.slug,
        downloadId: task.id,
      );
    }

    // Also import files already present in common RetroArch/ROM folders.
    for (final root in await _storage.getLibraryDirectories()) {
      await _scanRoot(root, supportedPlatforms, games);
    }

    final result = games.values.toList()
      ..sort((a, b) {
        final platform = a.platform.compareTo(b.platform);
        if (platform != 0) return platform;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    return result;
  }

  Future<void> _scanRoot(
    Directory root,
    Set<String> supportedPlatforms,
    Map<String, LocalGame> games,
  ) async {
    try {
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !_isGameFile(entity.path)) continue;

        final platform = _platformForPath(entity.path);
        if (platform == null || !supportedPlatforms.contains(platform)) {
          continue;
        }

        final key = _key(entity.path);
        if (games.containsKey(key)) continue;

        final title = _titleFromPath(entity.path);
        games[key] = LocalGame(
          id: 'file:$key',
          title: title,
          platform: platform,
          filePath: entity.path,
          format: _format(entity.path),
          size: await _fileSize(entity.path),
          artworkPath: await _artwork.findForGame(
            platform: platform,
            title: title,
          ),
        );
      }
    } catch (_) {
      // One inaccessible root must not prevent the other library roots from
      // loading.
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

  String? _platformForPath(String filePath) {
    final segments = p.split(filePath).map((segment) => segment.toLowerCase());
    for (final segment in segments) {
      final platform = _platformAliases[segment];
      if (platform != null) return platform;
    }

    return _extensionPlatforms[p.extension(filePath).toLowerCase()];
  }

  bool _isGameFile(String filePath) {
    final extension = p.extension(filePath).toLowerCase();
    if (_extensionPlatforms.containsKey(extension)) return true;
    if (!_folderExtensions.contains(extension)) return false;
    return p
        .split(filePath)
        .any((segment) => _platformAliases.containsKey(segment.toLowerCase()));
  }

  String _titleFromPath(String filePath) {
    var title = p.basenameWithoutExtension(filePath).replaceAll('_', ' ');
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    return title.isEmpty ? p.basename(filePath) : title;
  }

  String _format(String filePath, {String fallback = ''}) {
    final extension = p.extension(filePath).replaceFirst('.', '').toUpperCase();
    return extension.isEmpty ? fallback.toUpperCase() : extension;
  }

  Future<bool> _pathExists(String filePath) async {
    return await File(filePath).exists() || await Directory(filePath).exists();
  }

  Future<int> _fileSize(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return 0;
      return file.length();
    } catch (_) {
      return 0;
    }
  }

  String _key(String filePath) => p.normalize(filePath).toLowerCase();

  static const _folderExtensions = <String>{
    '.7z',
    '.bin',
    '.chd',
    '.cso',
    '.cue',
    '.cdi',
    '.fds',
    '.gdi',
    '.gb',
    '.gba',
    '.gbc',
    '.gen',
    '.iso',
    '.m3u',
    '.md',
    '.nds',
    '.nes',
    '.n64',
    '.pce',
    '.pbp',
    '.sfc',
    '.smc',
    '.sms',
    '.v64',
    '.wbfs',
    '.wsc',
    '.z64',
    '.zip',
  };

  static const _extensionPlatforms = <String, String>{
    '.a26': 'a26',
    '.a52': 'a52',
    '.a78': 'a78',
    '.fds': 'fds',
    '.gb': 'gb',
    '.gba': 'gba',
    '.gbc': 'gbc',
    '.gg': 'gg',
    '.j64': 'jag',
    '.lnx': 'lynx',
    '.md': 'smd',
    '.gen': 'smd',
    '.32x': '32x',
    '.nds': 'nds',
    '.nes': 'nes',
    '.n64': 'n64',
    '.pce': 'tg16',
    '.sfc': 'snes',
    '.smc': 'snes',
    '.sms': 'sms',
    '.v64': 'n64',
    '.z64': 'n64',
  };

  static const _platformAliases = <String, String>{
    'a26': 'a26',
    'a52': 'a52',
    'a78': 'a78',
    'atari2600': 'a26',
    'atari5200': 'a52',
    'atari7800': 'a78',
    'dc': 'dc',
    'dreamcast': 'dc',
    'fds': 'fds',
    'gameboy': 'gb',
    'gameboyadvance': 'gba',
    'gameboycolor': 'gbc',
    'gb': 'gb',
    'gba': 'gba',
    'gbc': 'gbc',
    'gc': 'gc',
    'gamecube': 'gc',
    'gamegear': 'gg',
    'gg': 'gg',
    'jag': 'jag',
    'lynx': 'lynx',
    'megadrive': 'smd',
    'md': 'smd',
    'n64': 'n64',
    'nds': 'nds',
    'nes': 'nes',
    'pcengine': 'tg16',
    'pce': 'tg16',
    'ps1': 'ps1',
    'psx': 'ps1',
    'psp': 'psp',
    'sat': 'sat',
    'saturn': 'sat',
    'scd': 'scd',
    'sfc': 'snes',
    'sms': 'sms',
    'snes': 'snes',
    'tg16': 'tg16',
    'tgcd': 'tgcd',
    '32x': '32x',
    'vb': 'vb',
    'wii': 'wii',
    'smd': 'smd',
  };
}
