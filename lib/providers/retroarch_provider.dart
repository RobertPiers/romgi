import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/services.dart';
import 'api_provider.dart';
import 'debrid_provider.dart';
import 'download_provider.dart';

/// Shared provider for the local RetroArch asset-server prototype.
///
/// The server is not started automatically yet. The future integration UI or
/// Android foreground wrapper can start/stop this instance without creating a
/// second database, debrid, or host-adapter stack.
final retroArchAssetServerProvider = Provider<RetroArchAssetServer>((ref) {
  final romDb = ref.watch(romDatabaseProvider);
  final debrid = ref.watch(debridServiceProvider);
  final adapters = ref.watch(hostAdapterRegistryProvider);

  return RetroArchAssetServer(
    romDb: romDb,
    sourceResolver: RetroArchSourceResolver(debrid: debrid),
    adapters: adapters,
  );
});

class RetroArchServerState {
  final bool starting;
  final Uri? uri;
  final String? error;

  const RetroArchServerState({
    this.starting = false,
    this.uri,
    this.error,
  });
}

class RetroArchServerNotifier extends StateNotifier<RetroArchServerState> {
  static const int port = 8765;

  RetroArchServerNotifier(this._server) : super(const RetroArchServerState());

  final RetroArchAssetServer _server;

  Future<void> start() async {
    if (state.starting || _server.isRunning) {
      if (_server.baseUri != null) {
        state = RetroArchServerState(uri: _server.baseUri);
      }
      return;
    }

    state = const RetroArchServerState(starting: true);
    try {
      final uri = await _server.start(port: port);
      state = RetroArchServerState(uri: uri);
    } catch (error) {
      state = RetroArchServerState(error: error.toString());
    }
  }

  Future<void> stop() async {
    await _server.stop();
    state = const RetroArchServerState();
  }

  @override
  void dispose() {
    unawaited(_server.stop());
    super.dispose();
  }
}

final retroArchServerProvider = StateNotifierProvider<RetroArchServerNotifier,
    RetroArchServerState>((ref) {
  return RetroArchServerNotifier(ref.watch(retroArchAssetServerProvider));
});
