import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/models/download_link.dart';
import 'package:romgi/models/rom_entry.dart';
import 'package:romgi/services/retroarch_catalog_service.dart';

DownloadLink _http({String filename = 'Game.zip'}) => DownloadLink(
      name: 'Game',
      type: 'Game',
      format: 'zip',
      url: 'https://example.test/$filename',
      filename: filename,
      host: 'example.test',
      size: 100,
      sizeStr: '100B',
      sourceUrl: 'https://example.test/',
      sourceId: 'internet_archive',
    );

DownloadLink _torrent({String filename = 'Game.zip'}) => DownloadLink(
      name: 'Game',
      type: 'Game',
      format: 'zip',
      url: 'https://example.test/Game.torrent',
      filename: filename,
      host: 'MiNERVA Archive',
      size: 100,
      sizeStr: '100B',
      sourceUrl: 'https://example.test/',
      sourceId: 'minerva',
      torrentInfohash: 'aabbccddeeff00112233445566778899aabbccdd',
      torrentFileIndex: 0,
      torrentFilePath: filename,
    );

RomEntry _entry({
  String platform = 'nes',
  List<DownloadLink> links = const [],
}) => RomEntry(
      slug: 'game-$platform-us',
      title: 'Game',
      platform: platform,
      regions: const ['us'],
      links: links,
    );

void main() {
  group('RetroArchCatalogAdapter', () {
    test('maps a supported entry to its RetroArch database name', () {
      final result = RetroArchCatalogAdapter().adapt(
        _entry(links: [_http()]),
      );

      expect(result, isNotNull);
      expect(
        result!.databaseName,
        'Nintendo - Nintendo Entertainment System',
      );
      expect(result.filename, 'Game.zip');
      expect(result.requiresDebrid, isFalse);
      expect(result.identityKey, 'nes|game|Game.zip');
    });

    test('keeps torrent links only as debrid-resolved candidates', () {
      final result = RetroArchCatalogAdapter().adapt(
        _entry(links: [_torrent()]),
      );

      expect(result, isNotNull);
      expect(result!.requiresDebrid, isTrue);
      expect(result.link.isTorrent, isTrue);
    });

    test('prefers direct HTTP over a tied torrent candidate', () {
      final result = RetroArchCatalogAdapter().adapt(
        _entry(links: [_torrent(), _http()]),
      );

      expect(result, isNotNull);
      expect(result!.link.isTorrent, isFalse);
    });

    test('does not expose platforms outside the configured RetroArch build', () {
      final adapter = RetroArchCatalogAdapter(
        supportedPlatforms: {'nes'},
      );

      expect(adapter.adapt(_entry(links: [_http()])), isNotNull);
      expect(
        adapter.adapt(_entry(platform: 'wii', links: [_http()])),
        isNull,
      );
    });

    test('does not expose entries without a usable link', () {
      expect(RetroArchCatalogAdapter().adapt(_entry()), isNull);
    });

    test('maps installed core filenames to compatible platforms', () {
      final platforms = RetroArchPlatformRegistry.platformsForCoreNames([
        'snes9x_libretro_android.so',
        'mgba_libretro_android.so',
      ]);

      expect(platforms, containsAll(<String>['snes', 'gb', 'gbc', 'gba']));
      expect(platforms, isNot(contains('ps1')));
    });

    test('does not treat the NES-only quicknes core as SNES-compatible', () {
      final platforms = RetroArchPlatformRegistry.platformsForCoreNames([
        'quicknes_libretro_android.so',
      ]);

      expect(platforms, contains('nes'));
      expect(platforms, isNot(contains('snes')));
    });

    test('does not treat the Atari 7800 prosystem core as Atari 2600', () {
      final platforms = RetroArchPlatformRegistry.platformsForCoreNames([
        'prosystem_libretro_android.so',
      ]);

      expect(platforms, contains('a78'));
      expect(platforms, isNot(contains('a26')));
    });
  });

  group('RetroArchSourceResolver', () {
    test('passes direct HTTP links through unchanged', () async {
      final content = RetroArchCatalogAdapter().adapt(
        _entry(links: [_http()]),
      )!;

      final resolved = await const RetroArchSourceResolver().resolve(content);

      expect(resolved, same(content.link));
    });

    test('rejects torrent links when no debrid resolver is available', () async {
      final content = RetroArchCatalogAdapter().adapt(
        _entry(links: [_torrent()]),
      )!;

      final resolved = await const RetroArchSourceResolver().resolve(content);

      expect(resolved, isNull);
    });
  });
}
