import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nova_ai/core/services/phone_control_service.dart';

/// JARVIS FULL-SCREEN OVERLAY
/// 
/// Shows when bot is in control with:
/// - Full-screen semi-transparent overlay with blinking border
/// - Small control panel at top with cancel button
/// - Minimal, professional Iron Man style
/// - Auto-dismisses when task completes
class BotControlOverlay extends StatefulWidget {
  final Widget child;
  const BotControlOverlay({super.key, required this.child});

  static Widget wrap(Widget child) => BotControlOverlay(child: child);

  @override
  State<BotControlOverlay> createState() => _BotControlOverlayState();
}

class _BotControlOverlayState extends State<BotControlOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _blinkCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _blinkAnim;

  bool _inControl = false;

  @override
  void initState() {
    super.initState();

    // Fade in/out animation
    _fadeCtrl = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);

    // Blinking border animation
    _blinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _blinkAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _blinkCtrl, curve: Curves.easeInOut),
    );

    PhoneControlService.instance.isInControl.addListener(_onControlChange);
  }

  void _onControlChange() {
    final active = PhoneControlService.instance.isInControl.value;
    if (active == _inControl) return;
    setState(() => _inControl = active);

    if (active) {
      _fadeCtrl.forward();
    } else {
      _fadeCtrl.reverse();
    }
  }

  @override
  void dispose() {
    PhoneControlService.instance.isInControl.removeListener(_onControlChange);
    _fadeCtrl.dispose();
    _blinkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_inControl)
          FadeTransition(
            opacity: _fadeAnim,
            child: _FullScreenOverlay(blinkAnimation: _blinkAnim),
          ),
      ],
    );
  }
}

// ─── Full Screen Overlay ───────────────────────────────────────────────────────

class _FullScreenOverlay extends StatelessWidget {
  final Animation<double> blinkAnimation;
  const _FullScreenOverlay({required this.blinkAnimation});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Semi-transparent backdrop
          Container(
            color: Colors.black.withOpacity(0.65),
          ),

          // Blinking border
          AnimatedBuilder(
            animation: blinkAnimation,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFF6C63FF).withOpacity(blinkAnimation.value),
                    width: 3,
                  ),
                ),
              );
            },
          ),

          // Top control panel
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopControlPanel(),
          ),

          // Center status indicator
          Center(
            child: _CenterStatus(),
          ),
        ],
      ),
    );
  }
}

// ─── Top Control Panel ─────────────────────────────────────────────────────────

class _TopControlPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E).withOpacity(0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF6C63FF).withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C63FF).withOpacity(0.2),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated pulse dot
            _PulseDot(),
            const SizedBox(width: 10),
            
            // Text
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'JARVIS IN CONTROL',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6C63FF),
                      letterSpacing: 1.2,
                    ),
                  ),
                  SizedBox(height: 2),
                  _ActionText(),
                ],
              ),
            ),
            
            const SizedBox(width: 12),
            
            // Cancel button
            GestureDetector(
              onTap: () => PhoneControlService.instance.cancel(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.red.shade700,
                      Colors.red.shade500,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cancel_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'CANCEL',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Center Status ─────────────────────────────────────────────────────────────

class _CenterStatus extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E).withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF6C63FF).withOpacity(0.5),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated icon
          _RotatingIcon(),
          const SizedBox(height: 16),
          
          // Action text
          const _ActionText(centerStyle: true),
          
          const SizedBox(height: 8),
          const Text(
            'Please wait...',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Action Text Widget ───────────────────────────────────────────────────────

class _ActionText extends StatelessWidget {
  final bool centerStyle;
  const _ActionText({this.centerStyle = false});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: PhoneControlService.instance.currentAction,
      builder: (_, action, __) {
        final text = action.isEmpty ? 'Starting task...' : action;
        return Text(
          text,
          style: TextStyle(
            fontSize: centerStyle ? 15 : 11,
            color: centerStyle ? Colors.white : Colors.grey.shade400,
            fontWeight: centerStyle ? FontWeight.w500 : FontWeight.normal,
          ),
          textAlign: centerStyle ? TextAlign.center : TextAlign.left,
          maxLines: centerStyle ? 3 : 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

// ─── Pulsing Dot ───────────────────────────────────────────────────────────────

class _PulseDot extends StatefulWidget {
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _scale = Tween(begin: 0.7, end: 1.3)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF6C63FF),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C63FF).withOpacity(0.6),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Rotating Icon ─────────────────────────────────────────────────────────────

class _RotatingIcon extends StatefulWidget {
  @override
  State<_RotatingIcon> createState() => _RotatingIconState();
}

class _RotatingIconState extends State<_RotatingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: const Icon(
        Icons.settings_rounded,
        size: 48,
        color: Color(0xFF6C63FF),
      ),
    );
  }
}
