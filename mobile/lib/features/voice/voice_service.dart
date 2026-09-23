import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nova_ai/core/api/nova_client.dart';

enum JarvisState { idle, listening, awake, processing, speaking }

class VoiceService extends ChangeNotifier {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  final SpeechToText _stt = SpeechToText();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  JarvisState _state = JarvisState.idle;
  String _liveText = '';
  bool _sttAvailable = false;

  /// Voice on/off. Off means the mic is never opened — no wake word, no
  /// listening — until it is switched back on. Remembered between launches.
  bool _enabled = true;
  bool get enabled => _enabled;

  // one restart timer, not one per call: the old code scheduled a new restart
  // every time it started listening, so the timers piled up and several
  // recognisers ran at once
  Timer? _restartTimer;
  Timer? _speakWatchdog;
  DateTime _lastWake = DateTime.fromMillisecondsSinceEpoch(0);

  JarvisState get state => _state;
  String get liveText => _liveText;

  void Function(String transcript, String reply)? onResponse;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool('voice_enabled') ?? true;

    await Permission.microphone.request();

    _sttAvailable = await _stt.initialize(
      onError: (e) => debugPrint('[STT] $e'),
      onStatus: (s) {
        // the recogniser stops itself on silence or error; pick it back up
        if (s == 'done' || s == 'notListening') _scheduleRestart();
      },
    );

    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) _doneSpeaking();
    });
    notifyListeners();
  }

  // ─── On / off ──────────────────────────────────────────────────────────────

  Future<void> setEnabled(bool on) async {
    if (_enabled == on) return;
    _enabled = on;
    (await SharedPreferences.getInstance()).setBool('voice_enabled', on);
    if (on) {
      await startWakeWordListening();
    } else {
      await stop();
    }
    notifyListeners();
  }

  Future<void> toggle() => setEnabled(!_enabled);

  // ─── Wake word ─────────────────────────────────────────────────────────────

  Future<void> startWakeWordListening() async {
    if (!_enabled || !_sttAvailable) return;
    _setState(JarvisState.listening);
    _listenForWakeWord();
  }

  void _scheduleRestart([Duration wait = const Duration(milliseconds: 400)]) {
    _restartTimer?.cancel();
    if (!_enabled) return;
    _restartTimer = Timer(wait, () {
      if (_enabled && _state == JarvisState.listening) _listenForWakeWord();
    });
  }

  void _listenForWakeWord() {
    if (!_enabled || !_sttAvailable || _state != JarvisState.listening) return;
    if (_stt.isListening) return;               // never stack recognisers

    _stt.listen(
      onResult: (result) {
        final words = result.recognizedWords;
        _liveText = words;
        notifyListeners();
        if (_isWakeWord(words)) {
          _stt.stop();
          _awaken();
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 6),
      listenMode: ListenMode.confirmation,
      cancelOnError: false,
      partialResults: true,
    );

    _scheduleRestart(const Duration(seconds: 31));
  }

  /// "jarvis" as a word of its own, not as part of something else, and not
  /// twice within a couple of seconds — background chatter used to trip this
  /// constantly.
  bool _isWakeWord(String heard) {
    if (DateTime.now().difference(_lastWake) < const Duration(seconds: 3)) {
      return false;
    }
    final hit = RegExp(r'\b(jarvis|jervis|jarvist)\b', caseSensitive: false)
        .hasMatch(heard);
    if (hit) _lastWake = DateTime.now();
    return hit;
  }

  // ─── Record command ────────────────────────────────────────────────────────

  void _awaken() {
    if (!_enabled) return;
    _setState(JarvisState.awake);
    _liveText = 'Listening...';
    notifyListeners();
    _recordCommand();
  }

  static const _minRecord = Duration(milliseconds: 700);
  static const _maxRecord = Duration(seconds: 12);
  static const _silenceToStop = Duration(milliseconds: 900);
  static const _minSpeechAbove = 8.0; // dB over the room's own noise level

  /// Stop as soon as the person stops talking.
  ///
  /// This used to record a flat 8 seconds every time. It now watches the mic
  /// level, but against the noise in the room rather than a fixed number: a
  /// noisy office or a TV in the background sits well above any fixed
  /// threshold, which used to keep the recorder running to its full limit.
  /// The first 400 ms set the noise floor, and only sound clearly above that
  /// floor counts as speech.
  Future<void> _recordCommand() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/cmd_${DateTime.now().millisecondsSinceEpoch}.wav';

    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
        path: path,
      );
    } catch (e) {
      debugPrint('[VoiceService] recorder failed: $e');
      _backToListening();
      return;
    }

    final started = DateTime.now();
    DateTime? lastSpeech;
    double floor = -45.0;               // provisional, replaced below
    var samples = 0;
    var heardAnything = false;

    final amp = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((a) {
      final db = a.current;
      samples++;
      if (samples <= 4) {
        // first ~400 ms: learn how loud this room is
        floor = samples == 1 ? db : (floor * 0.6 + db * 0.4);
        return;
      }
      if (db > floor + _minSpeechAbove) {
        lastSpeech = DateTime.now();
        heardAnything = true;
      }
    });

    _sendNow = false;
    while (true) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_sendNow) break;              // the talk button was tapped: send now
      final elapsed = DateTime.now().difference(started);
      if (elapsed >= _maxRecord) break;
      if (elapsed < _minRecord) continue;
      final last = lastSpeech;
      if (last == null) {
        if (elapsed > const Duration(seconds: 3)) break;  // nothing said
        continue;
      }
      if (DateTime.now().difference(last) >= _silenceToStop) break;
    }

    await amp.cancel();
    final tappedSend = _sendNow;       // an explicit tap always sends
    _sendNow = false;
    final filePath = await _recorder.stop();

    if (filePath == null || (!heardAnything && !tappedSend)) {
      // woken by a noise, not a person — go straight back to listening
      _liveText = '';
      _backToListening();
      return;
    }

    await _processCommand(File(filePath));
  }

  Future<void> _processCommand(File audio) async {
    _setState(JarvisState.processing);
    _liveText = 'Thinking...';
    notifyListeners();

    try {
      final result = await NovaClient.instance.processVoice(audio);
      _liveText = result.reply;
      notifyListeners();

      onResponse?.call(result.transcript, result.reply);

      if (result.audio.isEmpty) {        // nothing to play — do not hang
        _backToListening();
        return;
      }

      _setState(JarvisState.speaking);
      final dir = await getTemporaryDirectory();
      final wavFile = File('${dir.path}/response.wav');
      await wavFile.writeAsBytes(result.audio);

      final dur = await _player.setFilePath(wavFile.path);
      await _player.play();
      // if playback never reports completion, do not stay stuck in speaking
      _speakWatchdog?.cancel();
      _speakWatchdog = Timer(
        (dur ?? const Duration(seconds: 20)) + const Duration(seconds: 3),
        () { if (_state == JarvisState.speaking) _doneSpeaking(); },
      );
    } catch (e) {
      debugPrint('[VoiceService] $e');
      _liveText = 'Something went wrong.';
      notifyListeners();
      _backToListening();
    } finally {
      try {
        if (await audio.exists()) await audio.delete();   // temp files piled up
      } catch (_) {}
    }
  }

  void _doneSpeaking() {
    _speakWatchdog?.cancel();
    _backToListening();
  }

  void _backToListening() {
    if (!_enabled) {
      _setState(JarvisState.idle);
      return;
    }
    _setState(JarvisState.listening);
    _scheduleRestart(const Duration(milliseconds: 300));
  }

  // ─── Manual push-to-talk ───────────────────────────────────────────────────

  Future<void> manualActivate() async {
    if (!_enabled) await setEnabled(true);
    if (_state == JarvisState.awake || _state == JarvisState.processing) return;
    await _stt.stop();
    await _player.stop();          // talking over the last reply means: stop it
    _awaken();
  }

  /// Tapped while recording: send what has been said so far instead of waiting
  /// for the silence timer.
  bool _sendNow = false;
  Future<void> finishListening() async {
    if (_state == JarvisState.awake) _sendNow = true;
  }

  /// Tapped while it is talking: stop the audio and go back to listening.
  Future<void> stopSpeaking() async {
    _speakWatchdog?.cancel();
    await _player.stop();
    _backToListening();
  }

  /// Say something out loud — used for replies to typed messages, so the
  /// assistant answers in voice whichever way you asked.
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    try {
      final audio = await NovaClient.instance.speak(text);
      if (audio.isEmpty) return;
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/say_${DateTime.now().millisecondsSinceEpoch}.wav');
      await f.writeAsBytes(audio);
      _liveText = text;
      _setState(JarvisState.speaking);
      final dur = await _player.setFilePath(f.path);
      await _player.play();
      _speakWatchdog?.cancel();
      _speakWatchdog = Timer(
        (dur ?? const Duration(seconds: 20)) + const Duration(seconds: 3),
        () { if (_state == JarvisState.speaking) _doneSpeaking(); },
      );
    } catch (e) {
      debugPrint('[VoiceService] speak failed: $e');
      _backToListening();
    }
  }

  Future<void> stop() async {
    _restartTimer?.cancel();
    _speakWatchdog?.cancel();
    await _stt.stop();
    if (await _recorder.isRecording()) await _recorder.stop();
    await _player.stop();
    _setState(JarvisState.idle);
    _liveText = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _restartTimer?.cancel();
    _speakWatchdog?.cancel();
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _setState(JarvisState s) {
    _state = s;
    notifyListeners();
  }
}
