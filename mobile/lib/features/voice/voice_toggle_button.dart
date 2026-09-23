import 'package:flutter/material.dart';
import 'package:nova_ai/features/voice/voice_service.dart';

/// Mic on/off for the whole assistant.
///
/// Off means the microphone is never opened: no wake word, no listening, and
/// nothing to be tripped by background noise. The choice is remembered, so it
/// stays off until it is switched back on.
class VoiceToggleButton extends StatelessWidget {
  const VoiceToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: VoiceService.instance,
      builder: (context, _) {
        final on = VoiceService.instance.enabled;
        final state = VoiceService.instance.state;
        final busy = on &&
            (state == JarvisState.awake ||
             state == JarvisState.processing ||
             state == JarvisState.speaking);

        return Tooltip(
          message: on ? 'Voice is on — tap to mute' : 'Voice is off — tap to listen',
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () async {
              await VoiceService.instance.toggle();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                ..removeCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  duration: const Duration(seconds: 2),
                  content: Text(VoiceService.instance.enabled
                      ? 'Voice on — say "Jarvis"'
                      : 'Voice off — mic closed'),
                ));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    on ? (busy ? Icons.graphic_eq : Icons.mic) : Icons.mic_off,
                    size: 21,
                    color: on
                        ? (busy ? Colors.lightBlueAccent : Colors.greenAccent.shade400)
                        : Theme.of(context).disabledColor,
                  ),
                  const SizedBox(width: 5),
                  // a small dot so the state reads at a glance, without text
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: on
                          ? (busy ? Colors.lightBlueAccent : Colors.greenAccent.shade400)
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
