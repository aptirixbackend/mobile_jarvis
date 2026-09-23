import 'dart:io';
import 'package:dio/dio.dart';
import 'package:nova_ai/core/preferences/app_preferences.dart';

class NovaClient {
  NovaClient._();
  static final NovaClient instance = NovaClient._();

  // Android emulator → 10.0.2.2
  // iOS simulator   → 127.0.0.1
  // Real device     → your PC's local IP e.g. http://192.168.1.x:8000/api
  // ngrok tunnel    → https://<id>.ngrok-free.app/api
  static const String baseUrl = 'https://d23e-223-178-85-116.ngrok-free.app/api';

  final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
  ));

  Future<String> _getSpeaker() => AppPreferences.instance.getSpeaker();
  Future<String> _getBotName() => AppPreferences.instance.getBotName();

  // ─── Chat ─────────────────────────────────────────────────────────────────

  Future<String> chat(String message, {String sessionId = 'default'}) async {
    final botName = await _getBotName();
    final res = await _dio.post('/chat/', data: {
      'session_id': sessionId,
      'message': message,
      'bot_name': botName,
    });
    return res.data['reply'] as String;
  }

  // ─── Voice preview ────────────────────────────────────────────────────────

  /// Fetch a cached preview clip for a voice from the backend
  Future<List<int>> fetchPreview(String voiceId) async {
    final res = await _dio.get<List<int>>(
      '/voice/preview/$voiceId',
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data ?? [];
  }

  // ─── STT ──────────────────────────────────────────────────────────────────

  Future<String> transcribe(File audioFile) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(audioFile.path, filename: 'audio.wav'),
    });
    final res = await _dio.post('/voice/transcribe', data: form);
    return res.data['transcript'] as String;
  }

  // ─── TTS ──────────────────────────────────────────────────────────────────

  Future<List<int>> speak(String text, {String? speaker}) async {
    final s = speaker ?? await _getSpeaker();
    final res = await _dio.post<List<int>>(
      '/voice/speak',
      data: {'text': text, 'speaker': s},
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data ?? [];
  }

  // ─── Full voice pipeline ──────────────────────────────────────────────────

  /// audio → Sarvam STT → Gemini LLM → Sarvam TTS → WAV back
  Future<({String transcript, String reply, List<int> audio})> processVoice(
    File audioFile, {
    String sessionId = 'default',
  }) async {
    final speaker = await _getSpeaker();
    final botName = await _getBotName();
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(audioFile.path, filename: 'audio.wav'),
    });
    final res = await _dio.post<List<int>>(
      '/voice/process',
      queryParameters: {'session_id': sessionId, 'speaker': speaker, 'bot_name': botName},
      data: form,
      options: Options(responseType: ResponseType.bytes),
    );
    return (
      transcript: res.headers.value('x-transcript') ?? '',
      reply:      res.headers.value('x-reply') ?? '',
      audio:      res.data ?? [],
    );
  }

  // ─── Memory ───────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getHistory(String sessionId) async {
    final res = await _dio.get('/memory/history/$sessionId');
    return List<Map<String, dynamic>>.from(res.data);
  }

  Future<void> clearHistory(String sessionId) async {
    await _dio.delete('/memory/history/$sessionId');
  }

  // ─── Token usage ──────────────────────────────────────────────────────────

  /// Tokens spent so far: today, this week, all time, split by model.
  Future<Map<String, dynamic>> usage() async {
    final res = await _dio.get('/usage/');
    return Map<String, dynamic>.from(res.data);
  }

  Future<void> resetUsage() async {
    await _dio.post('/usage/reset');
  }
}
