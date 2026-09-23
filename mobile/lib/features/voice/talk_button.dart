import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nova_ai/features/voice/voice_service.dart';

/// Tap to talk. One button that says what it is doing and can be stopped.
///
///   idle      mic, purple      tap and start talking
///   listening red, pulsing     it is recording you — tap to stop and send
///   thinking  spinner          working on it
///   speaking  speaker icon     tap to cut the reply short
class TalkButton extends StatefulWidget {
  const TalkButton({super.key});

  @override
  State<TalkButton> createState() => _TalkButtonState();
}

class _TalkButtonState extends State<TalkButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: VoiceService.instance,
      builder: (context, _) {
        final voice = VoiceService.instance;
        final state = voice.state;

        final (IconData icon, Color colour, String hint) = switch (state) {
          JarvisState.awake => (Icons.stop_rounded, Colors.red.shade600, 'Listening — tap to send'),
          JarvisState.processing => (Icons.more_horiz, Colors.orange.shade700, 'Working…'),
          JarvisState.speaking => (Icons.volume_up_rounded, Colors.blue.shade600, 'Speaking — tap to stop'),
          _ => (Icons.mic_none_rounded, const Color(0xFF6C63FF),
                voice.enabled ? 'Tap to talk' : 'Voice off — tap to turn on'),
        };

        final pulsing = state == JarvisState.awake;

        return Tooltip(
          message: hint,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final glow = pulsing ? 6.0 + 10.0 * _pulse.value : 0.0;
              return Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: glow == 0
                      ? null
                      : [BoxShadow(color: colour.withValues(alpha: 0.45), blurRadius: glow, spreadRadius: glow / 3)],
                ),
                child: child,
              );
            },
            child: Material(
              color: colour,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  switch (state) {
                    case JarvisState.awake:
                      await voice.finishListening();   // send what it has now
                    case JarvisState.speaking:
                      await voice.stopSpeaking();      // shut it up, keep listening
                    case JarvisState.processing:
                      break;                            // nothing useful to do
                    default:
                      await voice.manualActivate();
                  }
                },
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: state == JarvisState.processing
                      ? const Padding(
                          padding: EdgeInsets.all(13),
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: Colors.white),
                        )
                      : Icon(icon, color: Colors.white, size: 23),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
