import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/source.dart';
import 'engine_channel.dart';
import 'engine_source.dart';
import 'js_source.dart';

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

  final out = <ExtensionManifest>[];
  Object? firstError;

  for (final raw in items) {
    if (raw is! Map) continue;
    try {
      final map = Map<String, dynamic>.from(raw);
      if (map['version'] != null) {
        map['version'] = int.tryParse(map['version'].toString()) ?? 1;
      } else if (map['versionCode'] != null) {
        map['version'] = int.tryParse(map['versionCode'].toString()) ?? 1;
      } else {
        map['version'] = 1;
      }
      map['type'] ??= 'manga';
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

/// Prefix used on ExtensionManifest.scriptUrl to mark "this manifest actually
/// represents a Wammy/Mihon engine extension" instead of a plain JS source.
const _enginePrefix = 'engine://';

class ExtensionManager extends StateNotifier<Map<String, Source>> {
  ExtensionManager() : super({}) {
    _restore();
  }

  static const _installedKey = 'installed_sources';
  static const _reposKey = 'custom_repos';

  static const List<String> defaultRepoUrls = [];

  final List<ExtensionRepo> _repos = defaultRepoUrls.map((url) => ExtensionRepo(url)).toList();
  List<ExtensionRepo> get repos => _repos;

  final Map<String, String> repoErrors = {};

  /// Browse both custom JS repos and Wammy's own engine extension stores.
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

    try {
      final available = await EngineChannel.listAvailable();
      for (final ext in available) {
        final pkgName = ext['pkgName'] as String? ?? '';
        final extName = ext['name'] as String? ?? 'Unknown';
        final isNovel = ext['isNovel'] == true;
        final versionCode = ext['versionCode'] as int? ?? 1;
        final iconUrl = ext['iconUrl'] as String? ?? '';
        final sources = (ext['sources'] as List?) ?? const [];
        for (final rawSource in sources) {
          final s = Map<String, dynamic>.from(rawSource as Map);
          final sourceId = s['id']?.toString() ?? '';
          final label = sources.length > 1 ? '$extName (${s['lang'] ?? ''})' : extName;
          final id = 'engine:$pkgName:$sourceId';
          if (!seen.add(id)) continue;
          results.add(ExtensionManifest(
            id: id,
            name: label,
            lang: s['lang']?.toString() ?? 'en',
            type: isNovel ? ContentType.novel : ContentType.manga,
            iconUrl: iconUrl,
            scriptUrl: '$_enginePrefix$pkgName',
            version: versionCode,
          ));
        }
      }
    } catch (e) {
      repoErrors['Wammy extension store'] = e.toString();
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
    // Try Wammy's own store registration first — lets the user paste a
    // Mihon/Tachiyomi-style repo index and have it register natively.
    try {
      final ok = await EngineChannel.addStore(normalizeSourceUrl(url), false);
      if (ok) return 0; // count unknown up front; browseAll() will pick it up
    } catch (_) {
      // fall through to JS repo handling
    }

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
      for (final item in raw) {
        try {
          final decodedMap = jsonDecode(item);
          final manifest = ExtensionManifest.fromJson(decodedMap);
          map[manifest.id] = JsSource(manifest);
        } catch (_) {}
      }
    }
    state = map;

    await refreshEngineSources();
  }

  /// Pull currently-installed Wammy engine extensions and merge them into state.
  Future<void> refreshEngineSources() async {
    try {
      final installed = await EngineChannel.listInstalled();
      final next = {...state};
      for (final ext in installed) {
        final pkgName = ext['pkgName'] as String? ?? '';
        final sources = (ext['sources'] as List?) ?? const [];
        for (final rawSource in sources) {
          final s = EngineSource.fromManifest(ext, Map<String, dynamic>.from(rawSource as Map));
          next['engine:$pkgName:${s.id}'] = s;
        }
      }
      state = next;
    } catch (_) {
      // Engine not reachable (e.g. running outside Wammy host) — ignore.
    }
  }

  Future<void> _persistRepos() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = _repos.where((r) => !defaultRepoUrls.contains(r.url)).map((r) => r.url).toList();
    await prefs.setStringList(_reposKey, custom);
  }

  /// Persists only JS sources — engine sources are owned by Wammy and are
  /// restored via [refreshEngineSources] instead.
  Future<void> _persistInstalled() async {
    final prefs = await SharedPreferences.getInstance();
    final list = state.values.whereType<JsSource>().map((s) {
      final m = s.manifest;
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
    if (manifest.scriptUrl.startsWith(_enginePrefix)) {
      final pkgName = manifest.scriptUrl.substring(_enginePrefix.length);
      try {
        final result = await EngineChannel.install(pkgName);
        if (result != 'Installed') {
          throw ExtensionException('Failed to install ${manifest.name}.');
        }
        try {
          await EngineChannel.trust(pkgName);
        } catch (_) {}
        await refreshEngineSources();
      } catch (e) {
        throw ExtensionException('Failed to install ${manifest.name}: $e');
      }
      return;
    }

    try {
      final source = JsSource(manifest);
      state = {...state, manifest.id: source};
      await _persistInstalled();
      _notify();
    } catch (e) {
      throw ExtensionException('Failed to install ${manifest.name}: $e');
    }
  }

  Future<void> uninstall(String sourceId) async {
    final existing = state[sourceId];
    if (existing is EngineSource) {
      try {
        await EngineChannel.uninstall(existing.pkgName);
      } catch (_) {}
      final next = {...state}..removeWhere((_, s) => s is EngineSource && s.pkgName == existing.pkgName);
      state = next;
      return;
    }

    final next = {...state}..remove(sourceId);
    state = next;
    await _persistInstalled();
  }
}

final extensionManagerProvider =
    StateNotifierProvider<ExtensionManager, Map<String, Source>>((ref) => ExtensionManager());
