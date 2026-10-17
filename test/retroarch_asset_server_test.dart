import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/models/download_link.dart';
import 'package:romgi/models/rom_entry.dart';
import 'package:romgi/services/retroarch_asset_server.dart';
import 'package:romgi/services/retroarch_catalog_service.dart';
import 'package:romgi/services/rom_database_service.dart';

class _FakeRomDatabaseService extends RomDatabaseService {
  _FakeRomDatabaseService(this.entries);

  final List<RomEntry> entries;

  @override
  Future<List<RomEntry>> getEntriesWithLinksForPlatform(String platform) async {
    return entries.where((entry) => entry.platform == platform).toList();
  }
}

const _exampleLink = DownloadLink(
  name: 'Example',
  type: 'Game',
  format: 'zip',
  url: 'https://example.test/example.zip',
  filename: 'Example.zip',
  host: 'example.test',
  size: 123,
  sizeStr: '123B',
  sourceUrl: 'https://example.test/',
  sourceId: 'example',
);

void main() {
  late RetroArchAssetServer server;

  setUp(() {
    server = RetroArchAssetServer(
      romDb: _FakeRomDatabaseService([
        const RomEntry(
          slug: 'example-nes-us',
          title: 'Example',
          platform: 'nes',
          regions: ['us'],
          links: [_exampleLink],
        ),
      ]),
      catalog: RetroArchCatalogAdapter(supportedPlatforms: {'nes'}),
    );
  });

  tearDown(() async {
    await server.stop();
  });

  Future<String> get(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      return utf8.decode(await response.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      ));
    } finally {
      client.close(force: true);
    }
  }

  test('serves RetroArch directory and platform indexes', () async {
    final base = await server.start();

    const directory =
        'Nintendo%20-%20Nintendo%20Entertainment%20System';
    expect(
      await get(base.resolve('cores/.index-dirs')),
      'Nintendo - Nintendo Entertainment System\n',
    );
    expect(
      await get(base.resolve('cores/$directory/.index')),
      'Example.zip\n',
    );
  });
}
