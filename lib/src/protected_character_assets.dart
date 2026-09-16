import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'protected_asset_format.dart';

class ProtectedCharacterAssetBundle extends CachingAssetBundle {
  ProtectedCharacterAssetBundle(this._files);

  final Map<String, Uint8List> _files;

  @override
  Future<ByteData> load(String key) async {
    final normalized = key.replaceAll('\\', '/');
    final bytes = _files[normalized];
    if (bytes == null) {
      throw FlutterError('Protected character asset not found: $normalized');
    }
    return ByteData.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
  }
}

class ProtectedCharacterAssets {
  ProtectedCharacterAssets._();

  static const _encodedKey = String.fromEnvironment(
    protectedCharacterAssetKeyDefine,
  );
  static String? _activeAssetName;
  static Future<ProtectedCharacterAssetBundle>? _activeBundle;
  static final Map<String, Future<Uint8List>> _previews = {};

  static Future<ProtectedCharacterAssetBundle> bundleFor(String assetName) {
    if (_activeAssetName == assetName && _activeBundle != null) {
      return _activeBundle!;
    }
    final future = _loadBundle(assetName);
    _activeAssetName = assetName;
    _activeBundle = future;
    return future;
  }

  static Future<Uint8List> previewFor(String assetName) =>
      _previews.putIfAbsent(assetName, () => _loadPreview(assetName));

  static Future<ProtectedCharacterAssetBundle> _loadBundle(
    String assetName,
  ) async {
    final key = _key();
    final encrypted = await _loadRootBytes(
      'assets/protected/character/$assetName.aarpack',
    );
    final files = await decryptProtectedAssetFiles(
      encrypted: encrypted,
      key: key,
      packId: 'character/$assetName',
    );
    return ProtectedCharacterAssetBundle(files);
  }

  static Future<Uint8List> _loadPreview(String assetName) async {
    final key = _key();
    final encrypted = await _loadRootBytes(
      'assets/protected/character/previews/$assetName.aarpreview',
    );
    final files = await decryptProtectedAssetFiles(
      encrypted: encrypted,
      key: key,
      packId: 'preview/$assetName',
    );
    final path = 'assets/images/skins/$assetName.png';
    final preview = files[path];
    if (preview == null) {
      throw FlutterError('Protected character preview not found: $path');
    }
    return preview;
  }

  static Uint8List _key() {
    if (_encodedKey.isEmpty) {
      throw FlutterError(
        'Character resources require a protected build. Run '
        'tool/build_protected.ps1 instead of flutter build directly.',
      );
    }
    return decodeProtectedAssetKey(_encodedKey);
  }

  static Future<Uint8List> _loadRootBytes(String path) async {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  @visibleForTesting
  static void clearCache() {
    _activeAssetName = null;
    _activeBundle = null;
    _previews.clear();
  }
}
