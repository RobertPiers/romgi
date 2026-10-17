import '../models/models.dart';
import 'debrid/debrid_provider.dart';
import 'debrid_service.dart';
import 'link_resolver.dart';

/// The subset of Romgi platforms that have a direct RetroArch database
/// identity. Core availability is intentionally kept separate: callers can
/// pass the cores/platforms supported by their RetroArch build.
class RetroArchPlatformRegistry {
  static const definitions = <String, RetroArchPlatformDefinition>{
    'nes': RetroArchPlatformDefinition(
      romgiPlatform: 'nes',
      databaseName: 'Nintendo - Nintendo Entertainment System',
    ),
    'fds': RetroArchPlatformDefinition(
      romgiPlatform: 'fds',
      databaseName: 'Nintendo - Family Computer Disk System',
    ),
    'snes': RetroArchPlatformDefinition(
      romgiPlatform: 'snes',
      databaseName: 'Nintendo - Super Nintendo Entertainment System',
    ),
    'gb': RetroArchPlatformDefinition(
      romgiPlatform: 'gb',
      databaseName: 'Nintendo - Game Boy',
    ),
    'gbc': RetroArchPlatformDefinition(
      romgiPlatform: 'gbc',
      databaseName: 'Nintendo - Game Boy Color',
    ),
    'gba': RetroArchPlatformDefinition(
      romgiPlatform: 'gba',
      databaseName: 'Nintendo - Game Boy Advance',
    ),
    'vb': RetroArchPlatformDefinition(
      romgiPlatform: 'vb',
      databaseName: 'Nintendo - Virtual Boy',
    ),
    'n64': RetroArchPlatformDefinition(
      romgiPlatform: 'n64',
      databaseName: 'Nintendo - Nintendo 64',
    ),
    'nds': RetroArchPlatformDefinition(
      romgiPlatform: 'nds',
      databaseName: 'Nintendo - Nintendo DS',
    ),
    'gc': RetroArchPlatformDefinition(
      romgiPlatform: 'gc',
      databaseName: 'Nintendo - GameCube',
    ),
    'wii': RetroArchPlatformDefinition(
      romgiPlatform: 'wii',
      databaseName: 'Nintendo - Wii',
    ),
    'ps1': RetroArchPlatformDefinition(
      romgiPlatform: 'ps1',
      databaseName: 'Sony - PlayStation',
    ),
    'psp': RetroArchPlatformDefinition(
      romgiPlatform: 'psp',
      databaseName: 'Sony - PlayStation Portable',
    ),
    'sms': RetroArchPlatformDefinition(
      romgiPlatform: 'sms',
      databaseName: 'Sega - Master System - Mark III',
    ),
    'gg': RetroArchPlatformDefinition(
      romgiPlatform: 'gg',
      databaseName: 'Sega - Game Gear',
    ),
    'smd': RetroArchPlatformDefinition(
      romgiPlatform: 'smd',
      databaseName: 'Sega - Mega Drive - Genesis',
    ),
    'scd': RetroArchPlatformDefinition(
      romgiPlatform: 'scd',
      databaseName: 'Sega - Mega-CD - Sega CD',
    ),
    '32x': RetroArchPlatformDefinition(
      romgiPlatform: '32x',
      databaseName: 'Sega - 32X',
    ),
    'sat': RetroArchPlatformDefinition(
      romgiPlatform: 'sat',
      databaseName: 'Sega - Saturn',
    ),
    'dc': RetroArchPlatformDefinition(
      romgiPlatform: 'dc',
      databaseName: 'Sega - Dreamcast',
    ),
    'a26': RetroArchPlatformDefinition(
      romgiPlatform: 'a26',
      databaseName: 'Atari - 2600',
    ),
    'a52': RetroArchPlatformDefinition(
      romgiPlatform: 'a52',
      databaseName: 'Atari - 5200',
    ),
    'a78': RetroArchPlatformDefinition(
      romgiPlatform: 'a78',
      databaseName: 'Atari - 7800',
    ),
    'lynx': RetroArchPlatformDefinition(
      romgiPlatform: 'lynx',
      databaseName: 'Atari - Lynx',
    ),
    'jag': RetroArchPlatformDefinition(
      romgiPlatform: 'jag',
      databaseName: 'Atari - Jaguar',
    ),
    'tg16': RetroArchPlatformDefinition(
      romgiPlatform: 'tg16',
      databaseName: 'NEC - PC Engine - TurboGrafx 16',
    ),
    'tgcd': RetroArchPlatformDefinition(
      romgiPlatform: 'tgcd',
      databaseName: 'NEC - PC Engine CD - TurboGrafx-CD',
    ),
    'pcfx': RetroArchPlatformDefinition(
      romgiPlatform: 'pcfx',
      databaseName: 'NEC - PC-FX',
    ),
    '3do': RetroArchPlatformDefinition(
      romgiPlatform: '3do',
      databaseName: 'The 3DO Company - 3DO',
    ),
    'ngcd': RetroArchPlatformDefinition(
      romgiPlatform: 'ngcd',
      databaseName: 'SNK - Neo Geo CD',
    ),
  };

  static RetroArchPlatformDefinition? forPlatform(String platform) =>
      definitions[platform];

  /// Best-effort mapping from RetroArch's installed core filenames to Romgi
  /// platforms. The Android core query returns filenames rather than the
  /// core-info database, so these use stable libretro core identifiers.
  static const corePlatformTokens = <String, Set<String>>{
    'nes': {'fceumm', 'nestopia', 'mesen', 'quicknes'},
    'fds': {'fceumm', 'nestopia', 'mesen'},
    'snes': {'snes9x', 'bsnes', 'mesen'},
    'gb': {'gambatte', 'sameboy', 'mgba', 'tgbdual', 'gearboy'},
    'gbc': {'gambatte', 'sameboy', 'mgba', 'tgbdual', 'gearboy'},
    'gba': {'mgba', 'vba', 'gpsp', 'meteor'},
    'vb': {'beetle_vb', 'mednafen_vb'},
    'n64': {'mupen64', 'parallel_n64', 'mupen64plus'},
    'nds': {'melonds', 'desmume', 'noods'},
    'gc': {'dolphin'},
    'wii': {'dolphin'},
    'ps1': {'pcsx_rearmed', 'beetle_psx', 'swanstation', 'duckstation'},
    'psp': {'ppsspp'},
    'sms': {'genesis_plus_gx', 'picodrive', 'smsplus'},
    'gg': {'genesis_plus_gx', 'picodrive', 'smsplus'},
    'smd': {'genesis_plus_gx', 'picodrive'},
    'scd': {'genesis_plus_gx', 'picodrive'},
    '32x': {'picodrive'},
    'sat': {'beetle_saturn', 'yabause', 'kronos'},
    'dc': {'flycast', 'reicast'},
    'a26': {'stella', 'stella2014'},
    'a52': {'atari800'},
    'a78': {'prosystem', 'a7800'},
    'lynx': {'handy', 'mednafen_lynx'},
    'jag': {'virtualjaguar'},
    'tg16': {'mednafen_pce', 'beetle_pce', 'pce_fast'},
    'tgcd': {'mednafen_pce', 'beetle_pce'},
    'pcfx': {'mednafen_pcfx', 'beetle_pcfx'},
    '3do': {'opera', '4do'},
    'ngcd': {'fbneo', 'neocd', 'mednafen_neocd'},
  };

  static Set<String> platformsForCoreNames(Iterable<String> coreNames) {
    final names = coreNames.map((name) => name.toLowerCase()).toList();
    return {
      for (final entry in corePlatformTokens.entries)
        if (entry.value.any(
          (token) => names.any((name) => name.contains(token)),
        ))
          entry.key,
    };
  }
}

/// Converts Romgi entries into the transport records a RetroArch bridge will
/// need. This is intentionally independent of any HTTP server or Android
/// integration so it can be tested and reused by either implementation.
class RetroArchCatalogAdapter {
  final Set<String> supportedPlatforms;
  final LinkResolver _linkResolver;

  RetroArchCatalogAdapter({
    Set<String>? supportedPlatforms,
    Map<String, int> sourcePriority = const {},
  })  : supportedPlatforms = supportedPlatforms ??
            RetroArchPlatformRegistry.definitions.keys.toSet(),
        _linkResolver = LinkResolver(sourcePriority: sourcePriority);

  RetroArchContent? adapt(
    RomEntry entry, {
    bool isIaLoggedIn = false,
  }) {
    if (!supportedPlatforms.contains(entry.platform)) return null;

    final definition = RetroArchPlatformRegistry.forPlatform(entry.platform);
    if (definition == null) return null;

    // A RetroArch provider must never select a local peer-to-peer transport.
    // Torrent links remain eligible only because the future bridge will pass
    // them through DebridService before serving the content.
    final ranked = _linkResolver.rank(
      entry.links,
      LinkResolverPrefs(
        isIaLoggedIn: isIaLoggedIn,
        // Never select a local P2P transport for RetroArch. Torrent links
        // remain eligible only for the debrid resolver used by the bridge.
        torrentsDisabled: true,
        debridEnabled: true,
      ),
    );

    if (ranked.isEmpty) return null;

    // Debrid makes torrent links eligible, but a normal HTTP source should
    // still win an otherwise tied choice. This keeps RetroArch downloads
    // direct whenever possible and reserves cache resolution for torrent-only
    // entries.
    ranked.sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      if (a.link.isTorrent == b.link.isTorrent) return 0;
      return a.link.isTorrent ? 1 : -1;
    });

    final link = ranked.first.link;
    return RetroArchContent(
      romgiSlug: entry.slug,
      title: entry.title,
      platform: entry.platform,
      databaseName: definition.databaseName,
      filename: link.filename,
      boxartUrl: entry.boxartUrl,
      romId: entry.romId,
      regions: List.unmodifiable(entry.regions),
      link: link,
    );
  }

  List<RetroArchContent> adaptAll(
    Iterable<RomEntry> entries, {
    bool isIaLoggedIn = false,
  }) {
    return entries
        .map((entry) => adapt(entry, isIaLoggedIn: isIaLoggedIn))
        .whereType<RetroArchContent>()
        .toList(growable: false);
  }
}

/// Resolves the selected Romgi link for a RetroArch request.
///
/// This deliberately has no local torrent branch. A torrent-backed entry is
/// either turned into a temporary HTTP link by the configured debrid provider
/// or rejected, which keeps RetroArch outside the peer-to-peer transport.
class RetroArchSourceResolver {
  final DebridService? _debrid;

  const RetroArchSourceResolver({DebridService? debrid}) : _debrid = debrid;

  Future<DownloadLink?> resolve(
    RetroArchContent content, {
    void Function(DebridCaching status)? onCaching,
    bool Function()? isCancelled,
  }) async {
    if (!content.link.isTorrent) return content.link;

    final debrid = _debrid;
    if (debrid == null) return null;

    return debrid.resolveTorrentLink(
      content.link,
      onCaching: onCaching,
      isCancelled: isCancelled,
    );
  }
}
