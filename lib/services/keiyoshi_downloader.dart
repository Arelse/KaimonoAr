import 'dart:io';
import 'package:dio/dio.dart';

class KeiyoshiDownloader {
  static final Dio _dio = Dio();

  /// Downloads an extension APK to the system temp directory and makes it read-only
  static Future<String> downloadApk({
    required String downloadUrl,
    required String extensionId,
  }) async {
    try {
      final tempDir = Directory.systemTemp;
      final extDir = Directory('${tempDir.path}/keiyoshi_extensions');
      if (!await extDir.exists()) {
        await extDir.create(recursive: true);
      }

      final savePath = '${extDir.path}/$extensionId.apk';
      await _dio.download(downloadUrl, savePath);

      // CRITICAL FIX: Android 14+ blocks loading writable dex files for security.
      // Explicitly marking the APK file as read-only satisfies the runtime policy.
      final file = File(savePath);
      if (await file.exists()) {
        file.setReadOnly(); 
      }

      return savePath;
    } catch (e) {
      throw Exception("Failed to download Keiyoshi APK: $e");
    }
  }
}
