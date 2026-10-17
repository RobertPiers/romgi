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

  Future<String?> find(RetroArchContent content) async {
    final names = <String>{
      content.title,
      p.basenameWithoutExtension(content.filename),
    };

    for (final root in _roots) {
      for (final folder in _folders) {
        for (final name in names) {
          for (final candidate in _nameVariants(name)) {
            for (final extension in _extensions) {
              final file = File(
                p.join(root, content.databaseName, folder, '$candidate.$extension'),
              );
              if (await file.exists()) return file.path;
            }
          }
        }
      }
    }
    return null;
  }

  Iterable<String> _nameVariants(String name) sync* {
    yield name;
    final sanitized = name.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    if (sanitized != name) yield sanitized;
  }
}
