import 'package:flutter_test/flutter_test.dart';
import 'package:ryza_chat_mvp/src/tts_text_normalizer.dart';

void main() {
  test('compresses repeated punctuation without changing regular text', () {
    expect(
      compressRepeatedTtsPunctuation('等一下......真的！！！好？'),
      '等一下...真的！！好？',
    );
    expect(compressRepeatedTtsPunctuation('普通句子。'), '普通句子。');
  });
}
