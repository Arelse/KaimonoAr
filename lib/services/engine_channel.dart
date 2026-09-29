import 'package:flutter/services.dart';

/// Dart-side bridge to Wammy's Mihon extension engine (Kotlin EngineChannel.kt).
class EngineChannel {
  static const MethodChannel _channel = MethodChannel('com.kaimono/engine');

  static Future<bool> init() async {
    final result = await _channel.invokeMethod('init');
    return result == true;
  }

  static Future<List<Map<String, dynamic>>> listInstalled() async {
    final result = await _channel.invokeMethod('listInstalled');
    return List<Map<String, dynamic>>.from(
      (result as List).map((e) => Map<String, dynamic>.from(e)),
    );
  }

  static Future<List<Map<String, dynamic>>> listAvailable() async {
    final result = await _channel.invokeMethod('listAvailable');
    return List<Map<String, dynamic>>.from(
      (result as List).map((e) => Map<String, dynamic>.from(e)),
    );
  }

  static Future<List<Map<String, dynamic>>> listUntrusted() async {
    final result = await _channel.invokeMethod('listUntrusted');
    return List<Map<String, dynamic>>.from(
      (result as List).map((e) => Map<String, dynamic>.from(e)),
    );
  }

  static Future<bool> trust(String pkgName) async {
    final result = await _channel.invokeMethod('trust', {'pkgName': pkgName});
    return result == true;
  }

  static Future<String> install(String pkgName) async {
    final result = await _channel.invokeMethod('install', {'pkgName': pkgName});
    return result as String;
  }

  static Future<bool> uninstall(String pkgName) async {
    final result = await _channel.invokeMethod('uninstall', {'pkgName': pkgName});
    return result == true;
  }

  static Future<bool> addStore(String indexUrl, bool isNovel) async {
    final result = await _channel.invokeMethod('addStore', {
      'indexUrl': indexUrl,
      'isNovel': isNovel,
    });
    return result == true;
  }

  static Future<Map<String, dynamic>> popular(String sourceId, int page) async {
    final result = await _channel.invokeMethod('popular', {
      'sourceId': sourceId,
      'page': page,
    });
    return Map<String, dynamic>.from(result);
  }

  static Future<Map<String, dynamic>> latest(String sourceId, int page) async {
    final result = await _channel.invokeMethod('latest', {
      'sourceId': sourceId,
      'page': page,
    });
    return Map<String, dynamic>.from(result);
  }

  static Future<Map<String, dynamic>> search(String sourceId, String query, int page) async {
    final result = await _channel.invokeMethod('search', {
      'sourceId': sourceId,
      'query': query,
      'page': page,
    });
    return Map<String, dynamic>.from(result);
  }

  static Future<Map<String, dynamic>> details(String sourceId, String url, {String? title}) async {
    final result = await _channel.invokeMethod('details', {
      'sourceId': sourceId,
      'url': url,
      if (title != null) 'title': title,
    });
    return Map<String, dynamic>.from(result);
  }

  static Future<List<Map<String, dynamic>>> pages(String sourceId, String chapterUrl, {String? chapterName}) async {
    final result = await _channel.invokeMethod('pages', {
      'sourceId': sourceId,
      'chapterUrl': chapterUrl,
      if (chapterName != null) 'chapterName': chapterName,
    });
    return List<Map<String, dynamic>>.from(
      (result as List).map((e) => Map<String, dynamic>.from(e)),
    );
  }

  static Future<String> pageText(String sourceId, int index, String url, String? imageUrl) async {
    final result = await _channel.invokeMethod('pageText', {
      'sourceId': sourceId,
      'index': index,
      'url': url,
      'imageUrl': imageUrl,
    });
    return result as String;
  }

  /// Fetch a cover or page image as raw bytes through the source's own client/headers.
  static Future<Uint8List> image({
    required String sourceId,
    bool cover = false,
    int index = 0,
    String url = '',
    String? imageUrl,
  }) async {
    final result = await _channel.invokeMethod('image', {
      'sourceId': sourceId,
      'cover': cover,
      'index': index,
      'url': url,
      'imageUrl': imageUrl,
    });
    return Uint8List.fromList(List<int>.from(result));
  }
}
