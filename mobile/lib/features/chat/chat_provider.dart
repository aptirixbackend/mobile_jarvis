import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:nova_ai/core/api/nova_client.dart';
import 'package:nova_ai/features/voice/voice_service.dart';
import 'package:uuid/uuid.dart';

class ChatMessage {
  final String role;
  final String content;
  final DateTime createdAt;
  final bool isVoice;

  ChatMessage({
    required this.role,
    required this.content,
    this.isVoice = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

final sessionIdProvider = Provider<String>((ref) => const Uuid().v4());

final chatLoadingProvider = StateProvider<bool>((ref) => false);

final chatProvider =
    NotifierProvider<ChatNotifier, List<ChatMessage>>(ChatNotifier.new);

class ChatNotifier extends Notifier<List<ChatMessage>> {
  @override
  List<ChatMessage> build() => [];

  String get _sessionId => ref.read(sessionIdProvider);

  Future<void> sendMessage(String text, {bool isVoice = false}) async {
    state = [...state, ChatMessage(role: 'user', content: text, isVoice: isVoice)];
    ref.read(chatLoadingProvider.notifier).state = true;

    try {
      final reply = await NovaClient.instance.chat(text, sessionId: _sessionId);
      state = [...state, ChatMessage(role: 'assistant', content: reply, isVoice: isVoice)];
      // Answer out loud as well, so a typed question still gets a spoken
      // reply. Silent when the mic is switched off.
      if (!isVoice && VoiceService.instance.enabled) {
        unawaited(VoiceService.instance.speak(reply));
      }
    } catch (_) {
      state = [
        ...state,
        ChatMessage(role: 'assistant', content: "Hmm, I couldn't reach the server. Check your connection.")
      ];
    } finally {
      ref.read(chatLoadingProvider.notifier).state = false;
    }
  }

  void addVoiceExchange(String transcript, String reply) {
    state = [
      ...state,
      ChatMessage(role: 'user', content: transcript, isVoice: true),
      ChatMessage(role: 'assistant', content: reply, isVoice: true),
    ];
  }

  void clear() {
    state = [];
    NovaClient.instance.clearHistory(_sessionId);
  }
}
