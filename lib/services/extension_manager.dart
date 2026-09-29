import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/extension.dart';
import '../models/source.dart';
import 'engine_channel.dart';
import 'engine_source.dart';

/// Manages installed and available extensions.
/// Bridges Wammy's Mihon extension loader (via EngineChannel) and local JS sources.
class ExtensionManager extends ChangeNotifier {
  static const String _storageKey = 'installed_extensions';
  static const String _repoKey = 'extension_repos';

  final List<Extension> _installed = [];
  final List<Extension> _available = [];
  bool _isInitialized = false;

  List<Extension> get installed => List.unmodifiable(_installed);
  List<Extension> get available => List.unmodifiable(_available);
  bool get isInitialized => _isInitialized;

  /// Initialize: restore persisted sources, then sync with Wammy engine.
  Future<void> init() async {
    if (_isInitialized) return;

    // Restore JS sources from local storage
    await _restore();

    // Load engine extensions from Wammy
    await refreshEngineSources();

    _isInitialized = true;
    notifyListeners();
  }

  /// Fetch installed engine extensions from Wammy and add as EngineSource wrappers.
  Future<void> refreshEngineSources() async {
    final installed = await EngineChannel.listInstalled();
    for (final manifest in installed) {
      final source = EngineSource.fromManifest(manifest);
      // Avoid duplicates
      if (!_installed.any((e) => e.package == source.package)) {
        _installed.add(source);
      }
    }
    notifyListeners();
  }

  /// Restore JS sources from local storage (if any).
  Future<void> _restore() async {
    // If you have local JS extension storage, restore here.
    // For now, assume all extensions come from Wammy or remote repos.
    // This is a placeholder for future local JS support.
  }

  /// Persist only JS sources to local storage.
  /// Engine sources are managed by Wammy, not persisted here.
  Future<void> _persistInstalled() async {
    // If you add local JS extension support, persist them here.
    // For now, nothing to persist (Wammy manages its own state).
  }

  /// Get list of available extensions from Wammy and any remote JS repos.
  Future<void> browseAll() async {
    _available.clear();

    // Fetch available from Wammy
    final engineAvailable = await EngineChannel.listAvailable();
    for (final manifest in engineAvailable) {
      final source = EngineSource.fromManifest(manifest);
      // Avoid duplicates with installed
      if (!_installed.any((e) => e.package == source.package)) {
        _available.add(source);
      }
    }

    // TODO: Add remote JS repo support here if needed.
    // For now, engine extensions are the only available sources.

    notifyListeners();
  }

  /// Install an extension by package name.
  /// Routes engine:// URIs to Wammy, JS sources to local installer.
  Future<bool> install(String pkgName) async {
    try {
      // Try as engine extension first
      if (pkgName.startsWith('engine://')) {
        return await _installEngine(pkgName);
      }

      // Otherwise assume Wammy package name
      final result = await EngineChannel.install(pkgName);
      if (result == 'Installed') {
        // Trust it if not already trusted
        await EngineChannel.trust(pkgName);
        // Refresh to pick up the new extension
        await refreshEngineSources();
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error installing extension: $e');
      return false;
    }
  }

  /// Install an engine extension: call EngineChannel, then trust and refresh.
  Future<bool> _installEngine(String pkgName) async {
    try {
      final result = await EngineChannel.install(pkgName);
      if (result == 'Installed') {
        await EngineChannel.trust(pkgName);
        await refreshEngineSources();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error installing engine extension: $e');
      return false;
    }
  }

  /// Uninstall an extension.
  /// Routes engine sources to Wammy, JS sources to local uninstall.
  Future<bool> uninstall(Extension extension) async {
    try {
      if (extension is EngineSource) {
        await EngineChannel.uninstall(extension.package);
        _installed.removeWhere((e) => e.package == extension.package);
        notifyListeners();
        return true;
      }
      // TODO: Add JS source uninstall if you support local JS extensions.
      return false;
    } catch (e) {
      debugPrint('Error uninstalling extension: $e');
      return false;
    }
  }

  /// Add a new extension repository.
  /// Tries Wammy first, falls back to JS repo logic if needed.
  Future<bool> addRepoChecked(String indexUrl, {bool isNovel = false}) async {
    try {
      // Try adding to Wammy's extension store list
      final result = await EngineChannel.addStore(indexUrl, isNovel);
      if (result) {
        await browseAll(); // Refresh available list
        return true;
      }
      // If Wammy fails, could fall back to JS repo logic here.
      // For now, just fail.
      return false;
    } catch (e) {
      debugPrint('Error adding repo: $e');
      return false;
    }
  }

  /// Check for updates to installed extensions.
  /// Engine extensions report hasUpdate; JS sources don't (no update mechanism).
  Future<void> checkForUpdates() async {
    for (final ext in _installed) {
      if (ext is EngineSource) {
        // Wammy handles update checks internally.
        // You could poll EngineChannel.listInstalled() and check hasUpdate flags.
      }
    }
  }
}

/// Provider for the extension manager.
final extensionManagerProvider =
    ChangeNotifierProvider<ExtensionManager>((ref) {
  return ExtensionManager();
});

/// Provider for installed extensions.
final installedExtensionsProvider = Provider<List<Extension>>((ref) {
  final manager = ref.watch(extensionManagerProvider);
  return manager.installed;
});

/// Provider for available extensions.
final availableExtensionsProvider = Provider<List<Extension>>((ref) {
  final manager = ref.watch(extensionManagerProvider);
  return manager.available;
});
