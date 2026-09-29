import '../models/content_type.dart';
import '../models/entry.dart';
import '../models/source.dart';
import 'engine_channel.dart';

/// Wraps one Wammy/Mihon engine source as a [Source] the rest of the app
/// can use exactly like a JsSource.
class EngineSource implements Source {
  final String pkgName;
  final String sourceId;
  @override
  final String name;
  @override
  final String lang;
  @override
  final ContentType type;
  @override
  final String iconUrl;
  @override
  final int version;

  EngineSource({
    required this.pkgName,
    required this.sourceId,
    required this.name,
    required this.lang,
    required this.type,
    required this.iconUrl,
    required this.version,
  });

  @override
  String get id => sourceId;

  factory EngineSource.fromManifest(
    Map<String, dynamic> extensionManifest,
    Map<String, dynamic> sourceMap,
  ) {
    final isNovel = extensionManifest['isNovel'] == true;
    return EngineSource(
      pkgName: extensionManifest['pkgName'] as String? ?? '',
      sourceId: sourceMap['id']?.toString() ?? '',
      name: sourceMap['name'] as String? ?? extensionManifest['name'] as String? ?? 'Unknown',
      lang: sourceMap['lang']?.toString() ?? 'en',
      type: isNovel ? ContentType.novel : ContentType.manga,
      iconUrl: extensionManifest['iconUrl'] as String? ?? '',
      version: extensionManifest['versionCode'] as int? ?? 1,
    );
  }

  final Map<String, Map<String, dynamic>> _detailsCache = {};

  Future<Map<String, dynamic>> _fetchDetails(String entryId) async {
    final cached = _detailsCache[entryId];
    if (cached != null) return cached;
    final result = await EngineChannel.details(sourceId, entryId);
    _detailsCache[entryId] = result;
    return result;
  }

  @override
  Future<List<Entry>> search(String query, {int page = 1, String? genre}) async {
    final result = await EngineChannel.search(sourceId, query, page);
    final mangas = (result['mangas'] as List?) ?? const [];
    return mangas.map((m) => Entry.fromJson(Map<String, dynamic>.from(m), id, type)).toList();
  }

  @override
  Future<List<Entry>> popular({int page = 1, String? genre}) async {
    final result = await EngineChannel.popular(sourceId, page);
    final mangas = (result['mangas'] as List?) ?? const [];
    return mangas.map((m) => Entry.fromJson(Map<String, dynamic>.from(m), id, type)).toList();
  }

  @override
  Future<List<Entry>> latest({int page = 1, String? genre}) async {
    final result = await EngineChannel.latest(sourceId, page);
    final mangas = (result['mangas'] as List?) ?? const [];
    return mangas.map((m) => Entry.fromJson(Map<String, dynamic>.from(m), id, type)).toList();
  }

  @override
  Future<Entry> getEntryDetails(String entryId) async {
    final details = await _fetchDetails(entryId);
    return Entry.fromJson(Map<String, dynamic>.from(details['manga'] as Map), id, type);
  }

  @override
  Future<List<EntryChunk>> getChunks(String entryId) async {
    final details = await _fetchDetails(entryId);
    final chapters = (details['chapters'] as List?) ?? const [];
    return chapters.map((c) {
      final m = Map<String, dynamic>.from(c as Map);
      return EntryChunk(
        id: m['id']?.toString() ?? '',
        entryId: entryId,
        title: m['title']?.toString() ?? '',
        number: double.tryParse(m['number']?.toString() ?? '') ?? 0,
        uploadDate: m['uploadDate'] != null ? DateTime.tryParse(m['uploadDate'].toString()) : null,
      );
    }).toList();
  }

  @override
  Future<List<String>> getPages(String chunkId) async {
    final pages = await EngineChannel.pages(sourceId, chunkId);

    if (type == ContentType.novel) {
      final texts = <String>[];
      for (final p in pages) {
        final index = p['index'] as int? ?? 0;
        final url = p['url']?.toString() ?? '';
        final imageUrl = p['imageUrl']?.toString();
        texts.add(await EngineChannel.pageText(sourceId, index, url, imageUrl));
      }
      return texts;
    }

    return pages.map((p) {
      final index = p['index'] as int? ?? 0;
      final url = Uri.encodeComponent(p['url']?.toString() ?? '');
      final imageUrl = p['imageUrl']?.toString();
      final imgPart = imageUrl != null ? '&img=${Uri.encodeComponent(imageUrl)}' : '';
      return 'engine://s/$sourceId?i=$index&u=$url$imgPart';
    }).toList();
  }

  @override
  Future<List<StreamLink>> getStreamLinks(String chunkId) async {
    // Wammy's engine currently supports manga/novel extensions only.
    return const [];
  }

  @override
  Future<List<Map<String, String>>> getGenres() async => [];
}
