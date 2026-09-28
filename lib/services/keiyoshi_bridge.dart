import 'package:flutter/services.dart';
import 'dart:convert';

class KeiyoshiBridge {
  static const MethodChannel _channel = MethodChannel('com.kaimono/keiyoshi');

  /// Fetches popular manga from a local Keiyoshi APK
  static Future<List<Map<String, dynamic>>> fetchPopular({
    required String apkPath,
    required String className, 
    int page = 1,
  }) async {
    try {
      final String jsonResult = await _channel.invokeMethod('fetchPopular', {
        'apkPath': apkPath,
        'className': className,
        'page': page,
      });
      
      final List<dynamic> parsed = jsonDecode(jsonResult);
      return parsed.cast<Map<String, dynamic>>();
    } on PlatformException catch (e) {
      throw Exception("Extension Error: ${e.message}");
    }
  }
}
