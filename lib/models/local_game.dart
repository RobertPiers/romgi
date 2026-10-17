/// A game that exists locally and can be launched by an emulator frontend.
///
/// This deliberately contains no remote catalog data. Local library scans
/// should remain cheap even when Romgi's downloadable catalog is very large.
class LocalGame {
  final String id;
  final String title;
  final String platform;
  final String filePath;
  final String format;
  final int size;
  final String? boxartUrl;
  final String? artworkPath;
  final String? slug;
  final String? downloadId;

  const LocalGame({
    required this.id,
    required this.title,
    required this.platform,
    required this.filePath,
    required this.format,
    required this.size,
    this.boxartUrl,
    this.artworkPath,
    this.slug,
    this.downloadId,
  });

  bool get isManagedDownload => downloadId != null;
}
