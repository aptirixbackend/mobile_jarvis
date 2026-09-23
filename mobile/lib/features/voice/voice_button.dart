import 'package:flutter/material.dart';

// TODO: wire up STT (record package) → send transcript to chat
class VoiceButton extends StatelessWidget {
  const VoiceButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice input coming soon!')),
        );
      },
      icon: const Icon(Icons.mic_rounded),
      tooltip: 'Voice input',
    );
  }
}
