import '../models/content_type.dart';
import '../models/entry.dart';
import '../models/source.dart';
import 'keiyoshi_bridge.dart';

class KeiyoshiSource implements Source {
  final dynamic manifest; 
  final String apkPath;

  KeiyoshiSource({required this.manifest, required this.apkPath});

  @override
  String get id => manifest.id;

  @override
  String get name => manifest.name;

  @override
  String get lang => manifest.lang;

  @override
  ContentType get type => manifest.type;

  @override
  String get iconUrl => manifest.iconUrl;

  @override
  int get version => manifest.version;

  @override
  Future<List<Entry>> popular({int page = 1, String? genre}) async {
    // Calls the native Android Kotlin bridge we built!
    final rawList = await KeiyoshiBridge.fetchPopular(
      apkPath: apkPath,
      className: manifest.id, // Assumes the repository JSON uses the class name as the ID
      page: page,
    );

    // Converts the raw JSON from Kotlin into Flutter Entry objects
    return rawList.map((data) => Entry(
      id: data['url'] ?? data['id'] ?? data.hashCode.toString(),
      sourceId: id,
      title: data['title'] ?? 'Unknown',
      coverUrl: data['thumbnailUrl'] ?? data['coverUrl'] ?? '',
    )).toList();
  }

  // TODO: The following methods need their own MethodChannel bridge endpoints 
  // implemented in MainActivity.kt later to fully flesh out the reader.

  @override
  Future<List<Entry>> search(String query, {int page = 1, String? genre}) async => [];

  @override
  Future<List<Entry>> latest({int page = 1, String? genre}) async => [];

  @override
  Future<Entry> getEntryDetails(String entryId) async {
    throw UnimplementedError('Details mapping not wired to bridge yet.');
  }

  @override
  Future<List<EntryChunk>> getChunks(String entryId) async => [];

  @override
  Future<List<String>> getPages(String chunkId) async => [];

  @override
  Future<List<StreamLink>> getStreamLinks(String chunkId) async => [];

  @override
  Future<List<Map<String, String>>> getGenres() async => [];
}
