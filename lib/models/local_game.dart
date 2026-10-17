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
  final bool favorite;
  final bool completed;
  final DateTime? lastPlayed;
  final int playCount;

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
    this.favorite = false,
    this.completed = false,
    this.lastPlayed,
    this.playCount = 0,
  });

  bool get isManagedDownload => downloadId != null;

  LocalGame copyWith({
    bool? favorite,
    bool? completed,
    DateTime? lastPlayed,
    int? playCount,
  }) {
    return LocalGame(
      id: id,
      title: title,
      platform: platform,
      filePath: filePath,
      format: format,
      size: size,
      boxartUrl: boxartUrl,
      artworkPath: artworkPath,
      slug: slug,
      downloadId: downloadId,
      favorite: favorite ?? this.favorite,
      completed: completed ?? this.completed,
      lastPlayed: lastPlayed ?? this.lastPlayed,
      playCount: playCount ?? this.playCount,
    );
  }
}

class LocalGameState {
  final bool favorite;
  final bool completed;
  final DateTime? lastPlayed;
  final int playCount;

  const LocalGameState({
    this.favorite = false,
    this.completed = false,
    this.lastPlayed,
    this.playCount = 0,
  });
}
