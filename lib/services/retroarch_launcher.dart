import 'package:flutter/services.dart';

/// Starts an installed RetroArch Android package with a local content file.
///
/// The native side tries the official 32-bit/64-bit package IDs and the
/// common F-Droid package. Keeping this behind a service makes the library UI
/// testable and leaves the launch contract in one place.
class RetroArchLauncher {
  static const MethodChannel _channel = MethodChannel('com.caprado.romgi/open');

  Future<void> launch(String path) async {
    await _channel.invokeMethod<void>('launchRetroArch', {'path': path});
  }
}
