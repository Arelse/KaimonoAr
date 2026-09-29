import '../models/extension.dart';

/// Wraps a Wammy engine extension manifest as an Extension-compatible object.
class EngineSource extends Extension {
  final String sourceId;
  final bool isNovel;

  EngineSource({
    required this.sourceId,
    required this.isNovel,
    required super.package,
    required super.name,
    required super.versionName,
    super.iconUrl,
  });

  factory EngineSource.fromManifest(Map<String, dynamic> manifest) {
    final sources = manifest['sources'] as List<dynamic>? ?? [];
    final firstSource = sources.isNotEmpty ? sources.first as Map<String, dynamic> : {};
    return EngineSource(
      sourceId: firstSource['id']?.toString() ?? '',
      isNovel: manifest['isNovel'] == true,
      package: manifest['pkgName'] as String? ?? '',
      name: manifest['name'] as String? ?? 'Unknown',
      versionName: manifest['versionName'] as String? ?? '',
      iconUrl: manifest['iconUrl'] as String?,
    );
  }
}
