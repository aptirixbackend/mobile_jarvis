import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova_ai/core/preferences/app_preferences.dart';
import 'package:nova_ai/features/chat/chat_provider.dart';
import 'package:nova_ai/features/chat/message_bubble.dart';
import 'package:nova_ai/features/control/bot_control_overlay.dart';
import 'package:nova_ai/features/settings/settings_screen.dart';
import 'package:nova_ai/features/voice/voice_service.dart';
import 'package:nova_ai/features/voice/talk_button.dart';
import 'package:nova_ai/features/voice/voice_status_bar.dart';
import 'package:nova_ai/features/voice/voice_toggle_button.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  String _botName = 'Jarvis';

  @override
  void initState() {
    super.initState();
    _initVoice();
    _loadBotName();
  }

  Future<void> _loadBotName() async {
    final name = await AppPreferences.instance.getBotName();
    if (mounted) setState(() => _botName = name);
  }

  Future<void> _initVoice() async {
    final voice = VoiceService.instance;
    await voice.init();

    // When voice round-trip completes, add messages to chat
    voice.onResponse = (transcript, reply) {
      ref.read(chatProvider.notifier).addVoiceExchange(transcript, reply);
      _scrollToBottom();
    };

    // Start wake word listening automatically
    await voice.startWakeWordListening();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    ref.read(chatProvider.notifier).sendMessage(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider);
    final isLoading = ref.watch(chatLoadingProvider);

    return BotControlOverlay.wrap(Scaffold(
      appBar: AppBar(
        title: _AppBarTitle(botName: _botName),
        actions: [
          const VoiceToggleButton(),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear chat',
            onPressed: () => ref.read(chatProvider.notifier).clear(),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const VoiceStatusBar(),
          Expanded(
            child: messages.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: messages.length + (isLoading ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == messages.length) return const _TypingBubble();
                      return MessageBubble(message: messages[i]);
                    },
                  ),
          ),
          _InputBar(controller: _controller, onSend: _send),
        ],
      ),
    ));
  }
}

class _AppBarTitle extends StatelessWidget {
  final String botName;
  const _AppBarTitle({required this.botName});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: VoiceService.instance,
      builder: (_, __) {
        final state = VoiceService.instance.state;
        final dot = switch (state) {
          JarvisState.listening => '🟢',
          JarvisState.awake => '🔴',
          JarvisState.processing => '🟡',
          JarvisState.speaking => '🔵',
          JarvisState.idle => '⚪',
        };
        return Row(
          children: [
            const CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFF6C63FF),
              child: Text('J', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(botName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('$dot ${state.name}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(
            radius: 40,
            backgroundColor: Color(0xFF6C63FF),
            child: Text('J', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
          Text(
            'Hey! Say "Hey Jarvis" to start,\nor type a message below.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Text('Jarvis is thinking...', style: TextStyle(color: Colors.grey, fontSize: 12)),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  const _InputBar({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(
          children: [
            // Tap to talk — says what it is doing and can be stopped
            const TalkButton(),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                onSubmitted: (_) => onSend(),
                maxLines: null,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: 'Type or say "Hey Jarvis"...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: onSend,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
