import 'dart:io';

import 'package:dio/dio.dart';

import '../models/models.dart';
import 'host_adapter.dart';
import 'retroarch_catalog_service.dart';
import 'rom_database_service.dart';

/// A small local implementation of RetroArch's asset-server protocol.
///
/// RetroArch's Content Downloader expects a static-looking HTTP tree under
/// `/assets/cores`: `.index-dirs`, per-platform `.index`, then the selected
/// filename. This server supplies that tree from romgi's catalog and resolves
/// the selected link at request time. It is intentionally bound to loopback
/// by default; a later Android foreground-service wrapper can keep it alive
/// while RetroArch is running.
class RetroArchAssetServer {
  final RomDatabaseService _romDb;
  final RetroArchCatalogAdapter _catalog;
  final RetroArchSourceResolver _sourceResolver;
  final HostAdapterRegistry _adapters;
  final Dio _dio;
  final InternetAddress address;

  HttpServer? _server;
  final Map<String, Future<List<RetroArchContent>>> _catalogCache = {};

  RetroArchAssetServer({
    required RomDatabaseService romDb,
    RetroArchCatalogAdapter? catalog,
    RetroArchSourceResolver? sourceResolver,
    HostAdapterRegistry? adapters,
    Dio? dio,
    InternetAddress? address,
  })  : _romDb = romDb,
        _catalog = catalog ?? RetroArchCatalogAdapter(),
        _sourceResolver = sourceResolver ?? const RetroArchSourceResolver(),
        _adapters = adapters ?? HostAdapterRegistry(),
        _dio = dio ?? Dio(),
        address = address ?? InternetAddress.loopbackIPv4;

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  Uri? get baseUri {
    final currentPort = port;
    if (currentPort == null) return null;
    return Uri(
      scheme: 'http',
      host: address.address,
      port: currentPort,
      path: '/assets/',
    );
  }

  Future<Uri> start({int port = 0}) async {
    if (_server != null) return baseUri!;

    _server = await HttpServer.bind(address, port, shared: true);
    _server!.listen(_handleRequest, onError: (_) {});
    return baseUri!;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _catalogCache.clear();
    await server?.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      await _textResponse(
        request.response,
        HttpStatus.methodNotAllowed,
        'GET required',
      );
      return;
    }

    final segments = request.uri.pathSegments;
    if (segments.length == 3 &&
        segments[0] == 'assets' &&
        segments[1] == 'cores' &&
        segments[2] == '.index-dirs') {
      await _serveDirectoryIndex(request.response);
      return;
    }

    if (segments.length == 3 &&
        segments[0] == 'assets' &&
        segments[1] == 'cores') {
      await _redirectToPlatform(request.response, segments[2]);
      return;
    }

    if (segments.length == 4 &&
        segments[0] == 'assets' &&
        segments[1] == 'cores' &&
        segments[3] == '.index') {
      await _servePlatformIndex(request.response, segments[2]);
      return;
    }

    if (segments.length == 4 &&
        segments[0] == 'assets' &&
        segments[1] == 'cores') {
      await _serveContent(
        request,
        directory: segments[2],
        filename: segments[3],
      );
      return;
    }

    await _textResponse(request.response, HttpStatus.notFound, 'Not found');
  }

  Future<void> _serveDirectoryIndex(HttpResponse response) async {
    final directories = _catalog.supportedPlatforms
        .map(_directoryNameForPlatform)
        .whereType<String>()
        .toList()
      ..sort();
    await _textResponse(
      response,
      HttpStatus.ok,
      '${directories.join('\n')}\n',
    );
  }

  Future<void> _redirectToPlatform(
    HttpResponse response,
    String directory,
  ) async {
    final platform = _platformForDirectory(directory);
    if (platform == null) {
      await _textResponse(response, HttpStatus.notFound, 'Platform not found');
      return;
    }

    response.statusCode = HttpStatus.movedPermanently;
    final encodedDirectory = Uri.encodeComponent(
      _directoryNameForPlatform(platform)!,
    );
    response.headers.set(
      HttpHeaders.locationHeader,
      '/assets/cores/$encodedDirectory/',
    );
    await response.close();
  }

  Future<void> _servePlatformIndex(
    HttpResponse response,
    String directory,
  ) async {
    final platform = _platformForDirectory(directory);
    if (platform == null) {
      await _textResponse(response, HttpStatus.notFound, 'Platform not found');
      return;
    }

    final contents = await _contentsFor(platform);
    if (contents == null) {
      await _textResponse(response, HttpStatus.notFound, 'Platform not found');
      return;
    }

    final filenames = contents.map((content) => content.filename).toSet().toList()
      ..sort();
    await _textResponse(response, HttpStatus.ok, '${filenames.join('\n')}\n');
  }

  Future<void> _serveContent(
    HttpRequest request, {
    required String directory,
    required String filename,
  }) async {
    final response = request.response;
    final platform = _platformForDirectory(directory);
    if (platform == null) {
      await _textResponse(response, HttpStatus.notFound, 'Platform not found');
      return;
    }

    final contents = await _contentsFor(platform);
    if (contents == null) {
      await _textResponse(response, HttpStatus.notFound, 'Platform not found');
      return;
    }

    final matches = contents.where((content) => content.filename == filename);
    if (matches.isEmpty) {
      await _textResponse(response, HttpStatus.notFound, 'Content not found');
      return;
    }

    // The filename is the RetroArch asset-server identity. If multiple Romgi
    // sources publish the same filename, the catalog adapter has already
    // ranked them and the first match is deterministic.
    final content = matches.first;
    final resolved = await _sourceResolver.resolve(content);
    if (resolved == null) {
      await _textResponse(
        response,
        HttpStatus.serviceUnavailable,
        'Content is not available from the configured debrid cache',
      );
      return;
    }

    final adapter = _adapters.adapterFor(resolved);
    if (adapter.isTorrent) {
      // Defensive guard: the resolver must never hand the server a local
      // torrent link.
      await _textResponse(
        response,
        HttpStatus.serviceUnavailable,
        'Peer-to-peer transport is disabled for RetroArch content',
      );
      return;
    }

    if (!await adapter.canStartDownload(resolved)) {
      await _textResponse(response, HttpStatus.unauthorized, adapter.authError);
      return;
    }

    if (request.method == 'HEAD') {
      if (resolved.size > 0) response.contentLength = resolved.size;
      response.headers.contentType = ContentType.binary;
      await response.close();
      return;
    }

    final headers = <String, dynamic>{
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Connection': 'keep-alive',
    };
    await adapter.prepareHeaders(headers, resolved);

    var responseStarted = false;
    try {
      final upstream = await _dio.get<ResponseBody>(
        resolved.url,
        options: Options(
          responseType: ResponseType.stream,
          headers: headers,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      final upstreamBody = upstream.data;
      if (upstreamBody == null ||
          upstream.statusCode == null ||
          upstream.statusCode! < 200 ||
          upstream.statusCode! >= 300) {
        await _textResponse(
          response,
          upstream.statusCode == HttpStatus.unauthorized ||
                  upstream.statusCode == HttpStatus.forbidden
              ? HttpStatus.unauthorized
              : HttpStatus.badGateway,
          'Source did not return downloadable content',
        );
        return;
      }

      final upstreamLength = upstream.headers.contentLength;
      if (upstreamLength > 0) {
        response.contentLength = upstreamLength;
      } else if (resolved.size > 0) {
        response.contentLength = resolved.size;
      }
      response.headers.contentType = ContentType.binary;
      responseStarted = true;
      await response.addStream(upstreamBody.stream);
      await response.close();
    } on DioException catch (error) {
      if (!responseStarted) {
        await _textResponse(
          response,
          HttpStatus.badGateway,
          'Source download failed: ${error.message ?? 'unknown error'}',
        );
      }
    } catch (_) {
      if (!responseStarted) {
        await _textResponse(
          response,
          HttpStatus.badGateway,
          'Source download failed',
        );
      }
    }
  }

  Future<List<RetroArchContent>?> _contentsFor(String platform) {
    if (!_catalog.supportedPlatforms.contains(platform)) {
      return Future.value(null);
    }

    return _catalogCache.putIfAbsent(platform, () async {
      final entries = await _romDb.getEntriesWithLinksForPlatform(platform);
      return _catalog.adaptAll(entries);
    });
  }

  String? _directoryNameForPlatform(String platform) {
    final definition = RetroArchPlatformRegistry.forPlatform(platform);
    return definition?.databaseName;
  }

  String? _platformForDirectory(String directory) {
    for (final platform in _catalog.supportedPlatforms) {
      final definition = RetroArchPlatformRegistry.forPlatform(platform);
      if (definition?.databaseName == directory || platform == directory) {
        return platform;
      }
    }
    return null;
  }

  Future<void> _textResponse(
    HttpResponse response,
    int status,
    String body,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.text;
    response.write(body);
    await response.close();
  }
}
