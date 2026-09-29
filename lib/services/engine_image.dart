import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'engine_channel.dart';

/// Displays an image either from a plain network URL, or through the
/// EngineChannel bridge for engine:// tokens that need special headers.
class SourceImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, dynamic)? errorWidget;

  const SourceImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  bool get _isEngineToken => url.startsWith('engine://');

  @override
  Widget build(BuildContext context) {
    if (!_isEngineToken) {
      return Image.network(
        url,
        fit: fit,
        width: width,
        height: height,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return placeholder?.call(context, url) ??
              const Center(child: CircularProgressIndicator());
        },
        errorBuilder: (context, error, stackTrace) =>
            errorWidget?.call(context, url, error) ??
            const Center(child: Icon(Icons.broken_image, color: Colors.white38)),
      );
    }

    return FutureBuilder<Uint8List>(
      future: _fetchEngineImage(url),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return placeholder?.call(context, url) ??
              const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return errorWidget?.call(context, url, snapshot.error) ??
              const Center(child: Icon(Icons.broken_image, color: Colors.white38));
        }
        return Image.memory(
          snapshot.data!,
          fit: fit,
          width: width,
          height: height,
        );
      },
    );
  }

  /// Parses an engine://s/<sourceId>?... token and fetches bytes via EngineChannel.
  Future<Uint8List> _fetchEngineImage(String token) async {
    final uri = Uri.parse(token);
    final sourceId = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    final isCover = uri.queryParameters['cover'] == '1';
    final imageUrl = uri.queryParameters['img'];
    final index = int.tryParse(uri.queryParameters['i'] ?? '') ?? 0;
    final pageUrl = uri.queryParameters['u'] ?? '';

    return EngineChannel.image(
      sourceId: sourceId,
      cover: isCover,
      index: index,
      url: pageUrl,
      imageUrl: imageUrl,
    );
  }
}
