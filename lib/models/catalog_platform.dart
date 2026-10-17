/// A platform displayed by the lightweight catalog frontend.
///
/// Only one row per platform is kept in memory. Games are loaded separately
/// in pages when the user opens a system, so a large catalog does not become a
/// giant widget/model tree.
class CatalogPlatform {
  final String id;
  final String brand;
  final String name;
  final int gameCount;
  final String? artworkUrl;

  const CatalogPlatform({
    required this.id,
    required this.brand,
    required this.name,
    required this.gameCount,
    this.artworkUrl,
  });
}
