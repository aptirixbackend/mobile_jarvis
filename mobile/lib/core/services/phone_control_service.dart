import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Bridges the backend WebSocket → native Android Accessibility Service.
///
/// Also exposes [isInControl] and [currentAction] so the UI can show
/// a live overlay whenever the bot is doing something on the phone.
class PhoneControlService {
  PhoneControlService._();
  static final PhoneControlService instance = PhoneControlService._();

  static const _channel = MethodChannel('com.nova.nova_ai/control');

  WebSocketChannel? _ws;
  StreamSubscription? _sub;
  bool _wsConnected = false;
  Timer? _reconnectTimer;

  // ─── Observable state ──────────────────────────────────────────────────────

  /// True while the bot is actively controlling the phone
  final ValueNotifier<bool> isInControl = ValueNotifier(false);

  /// Human-readable description of what the bot is currently doing
  final ValueNotifier<String> currentAction = ValueNotifier('');

  bool get connected => _wsConnected;

  // Update the WS URL for real device: change 10.0.2.2 to your PC's local IP
  // ngrok tunnel: wss://<id>.ngrok-free.app/api/control/ws
  static const String _wsUrl = 'wss://d23e-223-178-85-116.ngrok-free.app/api/control/ws';

  // ─── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    _connect();
  }

  void _connect() {
    try {
      const token = String.fromEnvironment('NOVA_API_TOKEN', defaultValue: '');
      final url = token.isEmpty ? _wsUrl : '$_wsUrl?token=$token';
      _ws = WebSocketChannel.connect(Uri.parse(url));
      _sub = _ws!.stream.listen(
        _onMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
      );
      _wsConnected = true;
      debugPrint('[PhoneControl] Connected to backend');
    } catch (e) {
      debugPrint('[PhoneControl] Connect failed: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _wsConnected = false;
    _sub?.cancel();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), _connect);
  }

  // ─── Message routing ───────────────────────────────────────────────────────

  Future<void> _onMessage(dynamic raw) async {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = msg['type'] as String?;

    // ── Backend notifications (no response needed) ──
    if (type == 'task_started') {
      isInControl.value = true;
      currentAction.value = msg['message'] as String? ?? 'Working...';
      // system overlay, so the glow stays visible over WhatsApp, Spotify,
      // Settings — wherever the work is actually happening
      _overlay('overlay_show', currentAction.value);
      return;
    }
    if (type == 'task_ended') {
      isInControl.value = false;
      currentAction.value = '';
      _overlay('overlay_hide');
      return;
    }
    if (type == 'task_update') {
      currentAction.value = _actionLabel(msg['action'] as String? ?? '');
      _overlay('overlay_update', currentAction.value);
      return;
    }

    // ── Regular command (execute and reply) ──
    final id = msg['id'] as String?;
    if (id == null) return;

    final action = msg['action'] as String? ?? '';
    final args = Map<String, dynamic>.from(msg)
      ..remove('id')
      ..remove('action');

    // Update overlay label for visible actions
    if (action != 'screenshot' && action != 'read_screen' && action != 'ui_tree') {
      currentAction.value = _actionLabel(action, args);
      _overlay('overlay_update', currentAction.value);
    }

    Map<String, dynamic> result;
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(action, args);
      result = res ?? {'status': 'ok'};
    } catch (e) {
      result = {'error': e.toString()};
    }

    result['id'] = id;
    _ws?.sink.add(jsonEncode(result));
  }

  String _actionLabel(String action, [Map<String, dynamic>? args]) {
    switch (action) {
      case 'open_app':   return 'Opening app...';
      case 'tap_text':   return 'Tapping "${args?['text'] ?? ''}"';
      case 'tap_at':     return 'Tapping screen...';
      case 'type_text':  return 'Typing "${args?['text'] ?? ''}"';
      case 'clear_field':return 'Clearing field...';
      case 'press_back': return 'Going back...';
      case 'press_home': return 'Going home...';
      case 'scroll':     return 'Scrolling ${args?['direction'] ?? ''}...';
      case 'read_screen':return 'Reading screen...';
      case 'screenshot': return currentAction.value;
      default:           return action;
    }
  }

  // ─── Cancel ────────────────────────────────────────────────────────────────

  void cancel() {
    // Tell backend to stop the current task
    _ws?.sink.add(jsonEncode({'type': 'cancel'}));
    isInControl.value = false;
    currentAction.value = '';
    _overlay('overlay_hide');
  }

  // ─── Control glow (system overlay) ─────────────────────────────────────────

  void _overlay(String method, [String? label]) {
    // fire and forget: the glow must never delay or break the actual work
    _channel.invokeMethod(method, label == null ? null : {'label': label})
        .catchError((_) => null);
  }

  /// Is the "display over other apps" permission granted?
  Future<bool> canDrawOverlay() async {
    try {
      return await _channel.invokeMethod<bool>('overlay_can_draw') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('overlay_request_permission');
    } catch (_) {}
  }

  // ─── Accessibility service check ───────────────────────────────────────────

  Future<bool> isServiceEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isServiceEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }

  /// Take a screenshot directly (for the live overlay — no backend round trip)
  Future<Uint8List?> takeLocalScreenshot() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('screenshot');
      final b64 = res?['image'] as String?;
      if (b64 == null) return null;
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _ws?.sink.close();
  }
}
