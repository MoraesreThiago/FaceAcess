import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  DateTime _lastSpoken = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> initialize() async {
    if (_initialized) return;
    await _tts.setLanguage('pt-BR');
    await _tts.setSpeechRate(0.5); // slower, clearer
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);
    _initialized = true;
  }

  /// Throttles to avoid overlapping announcements.
  Future<void> _speak(String text,
      {Duration minInterval = const Duration(seconds: 2)}) async {
    if (!_initialized) await initialize();
    final now = DateTime.now();
    if (now.difference(_lastSpoken) < minInterval) return;
    _lastSpoken = now;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> announceAuthorized(String personName) =>
      _speak('Acesso autorizado. $personName.');

  Future<void> announceGreeting(String greeting, String personName) =>
      _speak('$greeting, $personName!', minInterval: const Duration(seconds: 1));

  Future<void> announceDenied() => _speak('Acesso negado.');

  Future<void> dispose() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
