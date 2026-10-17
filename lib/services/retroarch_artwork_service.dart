import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/retroarch_content.dart';

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
    final names = <String>{
      content.title,
      p.basenameWithoutExtension(content.filename),
    };

    for (final root in _roots) {
      for (final folder in _folders) {
        final files = await _directoryIndex(root, content.databaseName, folder);
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
