/// Reduces long repeated punctuation runs before synthesis. This keeps the
/// visible assistant message untouched while preventing TTS engines from
/// over-extending pauses, sighs, or emphatic sounds.
String compressRepeatedTtsPunctuation(String text) {
  final pattern = RegExp(r'([.!?。！？…~～、，,：:；;])\1+');
  return text.replaceAllMapped(pattern, (match) {
    final run = match.group(0)!;
    final keep = (run.runes.length + 1) ~/ 2;
    final codePoint = run.runes.first;
    return String.fromCharCodes(List<int>.filled(keep, codePoint));
  });
}
