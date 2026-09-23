import 'package:flutter/material.dart';
import 'package:nova_ai/features/voice/voice_service.dart';

class VoiceStatusBar extends StatelessWidget {
  const VoiceStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: VoiceService.instance,
      builder: (_, __) {
        final state = VoiceService.instance.state;
        final text = VoiceService.instance.liveText;

        if (state == JarvisState.idle) return const SizedBox.shrink();

        final (color, icon, label) = switch (state) {
          JarvisState.listening  => (Colors.green.shade700, Icons.hearing, 'Listening for "Hey Jarvis"'),
          JarvisState.awake      => (Colors.red.shade700, Icons.mic, text.isEmpty ? 'Recording...' : text),
          JarvisState.processing => (Colors.orange.shade700, Icons.sync, 'Processing...'),
          JarvisState.speaking   => (Colors.blue.shade700, Icons.volume_up, text),
          JarvisState.idle       => (Colors.grey, Icons.mic_off, ''),
        };

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          color: color.withOpacity(0.15),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: color, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (state == JarvisState.listening)
                _PulsingDot(color: color),
            ],
          ),
        );
      },
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
