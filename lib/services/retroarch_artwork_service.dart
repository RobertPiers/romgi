import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/retroarch_content.dart';
import 'retroarch_catalog_service.dart';

/// Finds artwork already downloaded by RetroArch before falling back to
/// Romgi's catalog artwork.
class RetroArchArtworkService {
  static const _roots = <String>[
    '/storage/emulated/0/RetroArch/thumbnails',
    '/storage/emulated/0/RetroArch/Thumbnails',
    '/storage/emulated/0/Android/data/com.retroarch.ra32/files/thumbnails',
    '/storage/emulated/0/Android/data/com.retroarch.aarch64/files/thumbnails',
    '/storage/emulated/0/Android/data/com.retroarch/files/thumbnails',
  ];

  static const _folders = <String>['Named_Boxarts', 'Named_Titles'];
  static const _extensions = <String>['png', 'jpg', 'jpeg'];
  final _directoryIndexes = <String, Future<Map<String, String>>>{};

  Future<String?> find(RetroArchContent content) async {
    return _find(
      databaseName: content.databaseName,
      names: {
        content.title,
        p.basenameWithoutExtension(content.filename),
      },
    );
  }

  /// Finds native RetroArch artwork for a file discovered outside Romgi's
  /// download database.
  Future<String?> findForGame({
    required String platform,
    required String title,
  }) async {
    final definition = RetroArchPlatformRegistry.forPlatform(platform);
    if (definition == null) return null;

    return _find(databaseName: definition.databaseName, names: {title});
  }

  Future<String?> _find({
    required String databaseName,
    required Set<String> names,
  }) async {
    for (final root in _roots) {
      for (final folder in _folders) {
        final files = await _directoryIndex(root, databaseName, folder);
        for (final name in names) {
          for (final candidate in _nameVariants(name)) {
            for (final extension in _extensions) {
              final path = files['$candidate.$extension'.toLowerCase()];
              if (path != null) return path;
            }
          }
        }
      }
    }
    return null;
  }

  Future<Map<String, String>> _directoryIndex(
    String root,
    String databaseName,
    String folder,
  ) {
    final key = '$root/$databaseName/$folder';
    return _directoryIndexes.putIfAbsent(key, () async {
      final result = <String, String>{};
      try {
        final directory = Directory(p.join(root, databaseName, folder));
        if (!await directory.exists()) return result;
        await for (final entity in directory.list(followLinks: false)) {
          if (entity is File) {
            result[p.basename(entity.path).toLowerCase()] = entity.path;
          }
        }
      } catch (_) {
        // Android/data and app-private RetroArch folders may be inaccessible
        // even when public RetroArch thumbnails are readable.
      }
      return result;
    });
  }

  Iterable<String> _nameVariants(String name) sync* {
    yield name;
    final sanitized = name.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    if (sanitized != name) yield sanitized;
  }
}
