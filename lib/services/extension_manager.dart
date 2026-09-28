import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/source.dart';
import 'js_source.dart';
import 'keiyoshi_downloader.dart';
import 'keiyoshi_source.dart';

class ExtensionException implements Exception {
  final String message;
  ExtensionException(this.message);
  @override
  String toString() => message;
}

String normalizeSourceUrl(String input) {
  var u = input.trim();
  if (u.isEmpty) throw ExtensionException('Enter a URL first.');
  if (!u.contains('://')) u = 'https://$u';
  final uri = Uri.tryParse(u);
  if (uri == null || uri.host.isEmpty || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    throw ExtensionException('That does not look like a valid http(s) URL.');
  }
  if (uri.host == 'github.com' || uri.host == 'www.github.com') {
    final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (seg.length >= 5 && seg[2] == 'blob') {
      return 'https://raw.githubusercontent.com/${seg[0]}/${seg[1]}/${seg[3]}/${seg.sublist(4).join('/')}';
    }
    if (seg.length == 2) {
      return 'https://raw.githubusercontent.com/${seg[0]}/${seg[1]}/main/index.json';
    }
  }
  return u;
}

String _safeNormalize(String input) {
  try {
    return normalizeSourceUrl(input);
  } on ExtensionException {
    return input.trim();
  }
}

Future<String> fetchText(String url) async {
  try {
    final res = await Dio().get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
        headers: {'Accept': 'application/json, text/plain, */*'},
      ),
    );
    final data = res.data;
    if (data == null || data.trim().isEmpty) {
      throw ExtensionException('The server returned an empty response.');
    }
    return data;
  } on DioException catch (e) {
    final code = e.response?.statusCode;
    if (code != null) {
      throw ExtensionException('The server returned HTTP $code for $url');
    }
    throw ExtensionException('Could not reach $url (${e.type.name}). Check the URL and your connection.');
  }
}

List<ExtensionManifest> parseManifests(String body, String baseUrl) {
  dynamic decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    if (body.trimLeft().startsWith('<')) {
      throw ExtensionException(
          'That URL returned a web page, not JSON. Use the raw GitHub URL of the index file.');
    }
    throw ExtensionException('The response is not valid JSON.');
  }

  List items;
  if (decoded is List) {
    items = decoded;
  } else if (decoded is Map) {
    final nested = decoded['sources'] ?? decoded['extensions'] ?? decoded['items'] ?? decoded['repo'];
    if (nested is List) {
      items = nested;
    } else if (decoded.containsKey('id') && decoded.containsKey('script')) {
      items = [decoded];
    } else {
      throw ExtensionException('The JSON is valid but has no recognizable source list.');
    }
  } else {
    throw ExtensionException('Unexpected JSON format.');
  }

  final base = Uri.parse(baseUrl);
  final out = <ExtensionManifest>[];
  Object? firstError;

  for (final raw in items) {
    if (raw is! Map) continue;
    try {
      final map = Map<String, dynamic>.from(raw);
      
      if (map.containsKey('pkg') && !map.containsKey('id')) {
        map['id'] = map['pkg'];
      }
      if (map.containsKey('apk') && !map.containsKey('script')) {
        String apkPath = map['apk'];
        map['script'] = base.resolve(apkPath.startsWith('http') ? apkPath : 'apk/$apkPath').toString();
      }
      if (map.containsKey('icon') && map['icon'] is String) {
        String iconPath = map['icon'];
        map['icon'] = base.resolve(iconPath.startsWith('http') ? iconPath : 'icon/$iconPath').toString();
      }
      map['type'] ??= 'manga';

      for (final key in ['script', 'icon']) {
        final v = map[key];
        if (v is String && v.isNotEmpty && !v.contains('://')) {
          map[key] = base.resolve(v).toString();
        }
      }
      out.add(ExtensionManifest.fromJson(map));
    } catch (e) {
      firstError ??= e;
    }
  }

  if (out.isEmpty) {
    throw ExtensionException(firstError == null
        ? 'No sources found in that repository.'
        : 'Found entries but none were valid sources ($firstError).');
  }
  return out;
}

class ExtensionRepo {
  final String url;
  ExtensionRepo(this.url);

  Future<List<ExtensionManifest>> fetchIndex() async {
    final body = await fetchText(url);
    return parseManifests(body, url);
  }
}

class ExtensionManager extends StateNotifier<Map<String, Source>> {
  ExtensionManager() : super({}) {
    _restore();
  }

  static const _installedKey = 'installed_sources';
  static const _reposKey = 'custom_repos';
  
  static const List<String> defaultRepoUrls = [
    'https://raw.githubusercontent.com/Arelse/Kaimono/main/assets/sample_repo/index.json',
    'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json',
  ];

  final List<ExtensionRepo> _repos = defaultRepoUrls.map((url) => ExtensionRepo(url)).toList();
  List<ExtensionRepo> get repos => _repos;

  final Map<String, String> repoErrors = {};

  Future<List<ExtensionManifest>> browseAll() async {
    repoErrors.clear();
    final results = <ExtensionManifest>[];
    final seen = <String>{};
    for (final repo in _repos) {
      try {
        for (final m in await repo.fetchIndex()) {
          if (seen.add(m.id)) results.add(m);
        }
      } catch (e) {
        repoErrors[repo.url] = e.toString();
      }
    }
    return results;
  }

  void _notify() => state = {...state};

  void addRepo(String url) {
    final normalized = _safeNormalize(url);
    if (normalized.isEmpty || _repos.any((r) => r.url == normalized)) return;
    _repos.add(ExtensionRepo(normalized));
    unawaited(_persistRepos());
    _notify();
  }

  Future<int> addRepoChecked(String url) async {
    final normalized = normalizeSourceUrl(url);
    if (_repos.any((r) => r.url == normalized)) {
      throw ExtensionException('That repository is already added.');
    }
    final repo = ExtensionRepo(normalized);
    final manifests = await repo.fetchIndex();
    _repos.add(repo);
    await _persistRepos();
    _notify();
    return manifests.length;
  }

  void removeRepo(String url) {
    _repos.removeWhere((r) => r.url == url);
    unawaited(_persistRepos());
    _notify();
  }

  Future<List<ExtensionManifest>> installFromUrl(String url) async {
    final normalized = normalizeSourceUrl(url);
    if (normalized.toLowerCase().endsWith('.js')) {
      throw ExtensionException(
          'That URL is a script, not a source description. Use the URL of the JSON file that lists sources.');
    }
    final body = await fetchText(normalized);
    final manifests = parseManifests(body, normalized);
    for (final m in manifests) {
      await install(m);
    }
    return manifests;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();

    final savedRepos = prefs.getStringList(_reposKey) ?? const <String>[];
    for (final u in savedRepos) {
      if (!_repos.any((r) => r.url == u)) _repos.add(ExtensionRepo(u));
    }

    final raw = prefs.getStringList(_installedKey);
    final map = <String, Source>{};
    if (raw != null) {
      final tempDir = Directory.systemTemp;
      for (final item in raw) {
        try {
          final manifest = ExtensionManifest.fromJson(jsonDecode(item));
          
          if (manifest.scriptUrl.toLowerCase().endsWith('.apk')) {
             final localApkPath = '${tempDir.path}/keiyoshi_extensions/${manifest.id}.apk';
             map[manifest.id] = KeiyoshiSource(manifest: manifest, apkPath: localApkPath);
          } else {
             map[manifest.id] = JsSource(manifest);
          }
        } catch (_) {}
      }
    }
    state = map;
  }

  Future<void> _persistRepos() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = _repos.where((r) => !defaultRepoUrls.contains(r.url)).map((r) => r.url).toList();
    await prefs.setStringList(_reposKey, custom);
  }

  Future<void> _persistInstalled() async {
    final prefs = await SharedPreferences.getInstance();
    final list = state.values.map((s) {
      final m = (s as dynamic).manifest;
      return jsonEncode({
        'id': m.id,
        'name': m.name,
        'lang': m.lang,
        'type': m.type.name,
        'icon': m.iconUrl,
        'script': m.scriptUrl,
        'version': m.version,
      });
    }).toList();
    await prefs.setStringList(_installedKey, list);
  }

  Future<void> install(ExtensionManifest manifest) async {
    if (manifest.scriptUrl.toLowerCase().endsWith('.apk')) {
      final localApkPath = await KeiyoshiDownloader.downloadApk(
        downloadUrl: manifest.scriptUrl,
        extensionId: manifest.id,
      );
      
      final source = KeiyoshiSource(manifest: manifest, apkPath: localApkPath);
      state = {...state, manifest.id: source};
      await _persistInstalled();
    } else {
      final source = JsSource(manifest);
      state = {...state, manifest.id: source};
      await _persistInstalled();
    }
  }

  Future<void> uninstall(String sourceId) async {
    final next = {...state}..remove(sourceId);
    state = next;
    await _persistInstalled();
  }
}

final extensionManagerProvider =
    StateNotifierProvider<ExtensionManager, Map<String, Source>>((ref) => ExtensionManager());
