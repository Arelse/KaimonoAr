import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class KeiyoshiDownloader {
  static final Dio _dio = Dio();

  /// Downloads an extension APK and returns the local file path
  static Future<String> downloadApk({
    required String downloadUrl,
    required String extensionId,
  }) async {
    try {
      // Find the app's secure internal storage directory
      final directory = await getApplicationDocumentsDirectory();
      
      // Create a specific folder for Keiyoshi extensions
      final extDir = Directory('${directory.path}/keiyoshi_extensions');
      if (!await extDir.exists()) {
        await extDir.create(recursive: true);
      }

      final savePath = '${extDir.path}/$extensionId.apk';

      // Download the APK using Dio
      await _dio.download(downloadUrl, savePath);

      return savePath;
    } catch (e) {
      throw Exception("Failed to download Keiyoshi APK: $e");
    }
  }
}
