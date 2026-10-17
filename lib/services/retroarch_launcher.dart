import 'dart:io';

import 'package:flutter/services.dart';

/// Starts an installed RetroArch Android package with a local content file.
///
/// The native side tries the official 32-bit/64-bit package IDs and the
/// common F-Droid package. Keeping this behind a service makes the library UI
/// testable and leaves the launch contract in one place.
class RetroArchLauncher {
  static const MethodChannel _channel = MethodChannel('com.caprado.romgi/open');

  Future<void> launch(String path) async {
    final playablePath = await _resolvePlayablePath(path);
    if (playablePath == null) {
      throw PlatformException(
        code: 'FILE_MISSING',
        message: 'No playable RetroArch content was found at $path',
      );
    }
    await _channel.invokeMethod<void>(
      'launchRetroArch',
      {'path': playablePath},
    );
  }

  Future<String?> _resolvePlayablePath(String path) async {
    final file = File(path);
    if (await file.exists()) return file.path;

    final directory = Directory(path);
    if (!await directory.exists()) return null;

    const priority = <String>[
      '.cue',
      '.chd',
      '.iso',
      '.gdi',
      '.cdi',
      '.mds',
      '.pbp',
      '.img',
      '.bin',
      '.nes',
      '.sfc',
      '.smc',
      '.gba',
      '.gbc',
      '.gb',
      '.n64',
      '.z64',
      '.v64',
      '.nds',
    ];

    final files = <File>[];
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) files.add(entity);
    }
    files.sort((a, b) {
      final aExtension = _extension(a.path);
      final bExtension = _extension(b.path);
      final aRank = priority.indexOf(aExtension);
      final bRank = priority.indexOf(bExtension);
      final rankedA = aRank < 0 ? priority.length : aRank;
      final rankedB = bRank < 0 ? priority.length : bRank;
      if (rankedA != rankedB) return rankedA.compareTo(rankedB);
      return a.path.compareTo(b.path);
    });
    return files.isEmpty ? null : files.first.path;
  }

  String _extension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '';
    return path.substring(dot).toLowerCase();
  }
}
