import 'package:flutter_test/flutter_test.dart';
import 'package:ryza_chat_mvp/src/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local save slots capture, restore, and delete game state', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = await AppController.load();
    controller.addUserMessage('存档前的消息');
    controller.setWorldSetting('存档中的世界设定');

    await controller.saveToLocalSlot(0);
    final saved = controller.localSaveSlots.first;
    expect(saved, isNotNull);
    expect(saved!.messageCount, controller.messages.length);
    expect(saved.preview, contains('存档前的消息'));

    controller.clearChatHistory();
    controller.setWorldSetting('之后的世界设定');
    controller.loadFromLocalSlot(0);

    expect(controller.messages.last.text, '存档前的消息');
    expect(controller.worldSetting, '存档中的世界设定');

    await controller.deleteLocalSlot(0);
    expect(controller.localSaveSlots.first, isNull);
  });

  test('empty and out-of-range save slots are rejected', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = await AppController.load();

    expect(() => controller.loadFromLocalSlot(0), throwsFormatException);
    expect(
      () => controller.saveToLocalSlot(AppController.localSaveSlotCount),
      throwsRangeError,
    );
  });
}
