import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spine_flutter/spine_flutter.dart';
import 'package:ryza_chat_mvp/src/local_skin_store.dart';
import 'package:ryza_chat_mvp/src/protected_character_assets.dart';
import 'package:ryza_chat_mvp/src/protected_asset_format.dart';

Uint8List png(int width, int height) {
  final bytes = Uint8List(33);
  bytes.setAll(0, [137, 80, 78, 71, 13, 10, 26, 10]);
  bytes.setAll(12, ascii.encode('IHDR'));
  ByteData.sublistView(bytes)
    ..setUint32(16, width)
    ..setUint32(20, height);
  return bytes;
}

Uint8List package({
  String prefix = 'nested/',
  bool missing = false,
  String? extra,
}) {
  final archive = Archive();
  void add(String name, List<int> bytes) =>
      archive.addFile(ArchiveFile('$prefix$name', bytes.length, bytes));
  add('skin.atlas', utf8.encode('skin.png\nsize:2,3\n'));
  add('skin.png', png(2, 3));
  add('skin.skel', [...List.filled(8, 0), 7, ...ascii.encode('4.2.43'), 0]);
  if (!missing) {
    add(
      'skin_gesture.json',
      utf8.encode('{"emotionalGesture":{"MotionGroups":[]}}'),
    );
  }
  if (extra != null) add(extra, [1]);
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('texture overlay accepts an immutable decrypted pack and preserves original', () async {
    final key = Uint8List(32);
    final original = png(2, 3);
    final replacement = png(2, 3)..[32] = 2;
    final encrypted = await encryptProtectedAssetFiles(
      files: {'skin.png': original},
      key: key,
      packId: 'test/skin',
    );
    final files = await decryptProtectedAssetFiles(
      encrypted: encrypted,
      key: key,
      packId: 'test/skin',
    );
    final custom = ProtectedCharacterAssetBundle.withTexture(
      files,
      replacement,
    );
    expect((await custom.load('skin.png')).buffer.asUint8List(), replacement);
    final restored = ProtectedCharacterAssetBundle.withTexture(files, null);
    expect((await restored.load('skin.png')).buffer.asUint8List(), original);
    expect(files['skin.png'], original);
  });
  test('nested packages normalize only the four matching resources', () {
    expect(
      decodeSkinZip(package()).keys,
      containsAll(['skin.atlas', 'skin.png', 'skin.skel', 'skin_gesture.json']),
    );
  });
  test('reject incomplete ZIPs and traversal without extraction', () {
    expect(() => decodeSkinZip(package(missing: true)), throwsFormatException);
    expect(() => decodeSkinZip(package(prefix: '../')), throwsFormatException);
    expect(
      () => decodeSkinZip(package(extra: '../escaped.png')),
      throwsFormatException,
    );
  });
  test('PNG header and dimensions have bounded validation', () {
    expect(pngSize(png(4096, 3148)), (4096, 3148));
    expect(() => pngSize(Uint8List(33)), throwsFormatException);
    expect(() => pngSize(png(9000, 1)), throwsFormatException);
  });
  test(
    'imports survive restart and texture switches preserve original bytes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp('aar_skin_test_');
      addTearDown(() => directory.delete(recursive: true));
      final store = LocalSkinStore.forTesting();
      await store.initialize(storageDirectory: directory);
      final record = await store.importPackage(package());
      final id = record['id']!;
      final original = (await store.filesFor(id))!.values
          .firstWhere((b) => b.length == 33);
      final replacement = png(2, 3)..[32] = 1;
      await expectLater(
        store.importTexture(id, png(3, 2), original),
        throwsFormatException,
      );
      expect(store.hasTexture(id), isFalse);
      await store.importTexture(id, replacement, original);
      expect(await store.textureFor(id), replacement);
      await store.setTextureEnabled(id, false);
      expect(await store.textureFor(id), isNull);
      final reloaded = LocalSkinStore.forTesting();
      await reloaded.initialize(storageDirectory: directory);
      expect(reloaded.skins.single['id'], id);
      expect(reloaded.hasTexture(id), isTrue);
      expect(reloaded.usesTexture(id), isFalse);
      await reloaded.setTextureEnabled(id, true);
      expect(await reloaded.textureFor(id), replacement);
      expect(
        (await reloaded.filesFor(id))!['assets/character/ryza/$id/skin.png'],
        original,
      );
    },
  );
  final sample = File(
    '../downloaded_skin_resources/crf_skn_002_0002_01_r2.zip',
  );
  test(
    'native Spine loads imported bundle with remapped atlas paths',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp(
        'aar_skin_native_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = LocalSkinStore.forTesting();
      await store.initialize(storageDirectory: directory);
      final record = await store.importPackage(sample.readAsBytesSync());
      final id = record['id']!;
      await initSpineFlutter();
      final bundle = ProtectedCharacterAssetBundle((await store.filesFor(id))!);
      final root = 'assets/character/ryza/$id/$id';
      final drawable = await SkeletonDrawable.fromAsset(
        '$root.atlas',
        '$root.skel',
        bundle: bundle,
      );
      try {
        expect(
          drawable.skeletonData.findAnimation('motion_A_001_idle'),
          isNotNull,
        );
        drawable.animationState.setAnimationByName(
          0,
          'motion_A_001_idle',
          true,
        );
        drawable.update(0.1);
        expect(drawable.skeleton.getBounds().width.isFinite, isTrue);
        expect(drawable.render(), isNotEmpty);
      } finally {
        drawable.dispose();
      }
    },
    skip:
        !sample.existsSync() ||
        Platform.environment['AAR_SPINE_NATIVE_TEST'] != '1',
  );
  test('user supplied r2 package passes actual structure validation', () {
    final files = decodeSkinZip(sample.readAsBytesSync());
    expect(files.length, 4);
    expect(pngSize(files['crf_skn_002_0002_01.png']!), (4096, 2736));
  }, skip: !sample.existsSync());
}
