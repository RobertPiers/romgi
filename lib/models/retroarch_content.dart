import 'download_link.dart';

/// The RetroArch database name associated with a romgi platform.
///
/// RetroArch owns the actual metadata, thumbnails, and playlist database. This
/// model only carries the identity information needed to connect that content
/// to a romgi source link.
class RetroArchPlatformDefinition {
  final String romgiPlatform;
  final String databaseName;

  const RetroArchPlatformDefinition({
    required this.romgiPlatform,
    required this.databaseName,
  });
}

/// A Romgi catalog entry that can be exposed through a RetroArch provider.
///
/// The selected [link] is deliberately resolved with cache-only preferences
/// by [RetroArchCatalogAdapter]. A torrent link here means "send this to the
/// configured debrid provider", never "start libtorrent in RetroArch".
class RetroArchContent {
  final String romgiSlug;
  final String title;
  final String platform;
  final String databaseName;
  final String filename;
  final String? romId;
  final List<String> regions;
  final DownloadLink link;

  const RetroArchContent({
    required this.romgiSlug,
    required this.title,
    required this.platform,
    required this.databaseName,
    required this.filename,
    required this.romId,
    required this.regions,
    required this.link,
  });

  /// Stable identity used by the future RetroArch bridge/sidecar mapping.
  String get identityKey =>
      '$platform|${romId ?? title.toLowerCase()}|$filename';

  /// Whether serving this item requires a debrid cache provider.
  bool get requiresDebrid => link.isTorrent;
}
