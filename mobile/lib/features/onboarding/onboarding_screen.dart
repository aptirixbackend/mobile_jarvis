import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nova_ai/core/api/nova_client.dart';
import 'package:nova_ai/core/preferences/app_preferences.dart';
import 'package:nova_ai/features/chat/chat_screen.dart';
import 'package:path_provider/path_provider.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageCtrl   = PageController();
  int _page         = 0;
  final _nameCtrl   = TextEditingController();  // user's name
  final _botCtrl    = TextEditingController();  // bot's name
  String _gender    = '';
  String _speaker   = '';

  void _goToPage(int page) {
    _pageCtrl.animateToPage(page,
        duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
  }

  Future<void> _finish() async {
    if (_nameCtrl.text.trim().isEmpty || _botCtrl.text.trim().isEmpty ||
        _gender.isEmpty || _speaker.isEmpty) return;
    await AppPreferences.instance.completeOnboarding(
      gender: _gender,
      speaker: _speaker,
      userName: _nameCtrl.text.trim(),
      botName: _botCtrl.text.trim(),
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ChatScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _pageCtrl,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (i) => setState(() => _page = i),
            children: [
              _WelcomePage(
                nameCtrl: _nameCtrl,
                botCtrl: _botCtrl,
                onNext: () => _goToPage(1),
              ),
              _GenderPage(
                selected: _gender,
                botName: _botCtrl.text.trim().isEmpty ? 'your AI' : _botCtrl.text.trim(),
                onSelect: (g) {
                  setState(() { _gender = g; _speaker = ''; });
                  _goToPage(2);
                },
              ),
              _VoicePage(
                gender: _gender,
                selected: _speaker,
                onSelect: (v) => setState(() => _speaker = v),
                onFinish: _finish,
                onBack: () => _goToPage(1),
              ),
            ],
          ),
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) => _ProgressDot(active: i == _page)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Page 1 — Welcome + name your AI ─────────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController botCtrl;
  final VoidCallback onNext;
  const _WelcomePage({
    required this.nameCtrl,
    required this.botCtrl,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 60),
            const CircleAvatar(
              radius: 40,
              backgroundColor: Color(0xFF6C63FF),
              child: Icon(Icons.auto_awesome, color: Colors.white, size: 38),
            ),
            const SizedBox(height: 24),
            const Text('Create your AI',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Smarter than Siri, closer than Google.\nYours, completely.',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade400, height: 1.5),
            ),
            const SizedBox(height: 36),

            // Bot name
            const Text('Name your AI',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'What should your personal AI be called?',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: botCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: 'e.g. Jarvis, Nova, Max...',
                prefixIcon: const Icon(Icons.smart_toy_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                filled: true,
              ),
              onSubmitted: (_) => onNext(),
            ),

            const SizedBox(height: 24),

            // User name
            const Text('Your name',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: 'What should your AI call you?',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                filled: true,
              ),
              onSubmitted: (_) => onNext(),
            ),

            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Get Started', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ─── Page 2 — Gender ──────────────────────────────────────────────────────────

class _GenderPage extends StatelessWidget {
  final String selected;
  final String botName;
  final void Function(String) onSelect;
  const _GenderPage({required this.selected, required this.botName, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("$botName's voice gender",
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Pick the voice personality that feels right.',
                style: TextStyle(fontSize: 15, color: Colors.grey.shade400)),
            const SizedBox(height: 40),
            _GenderCard(
              emoji: '👩',
              title: 'Female Voice',
              desc: 'Warm, friendly, and expressive',
              selected: selected == 'female',
              onTap: () => onSelect('female'),
            ),
            const SizedBox(height: 16),
            _GenderCard(
              emoji: '👨',
              title: 'Male Voice',
              desc: 'Deep, calm, and confident',
              selected: selected == 'male',
              onTap: () => onSelect('male'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenderCard extends StatelessWidget {
  final String emoji, title, desc;
  final bool selected;
  final VoidCallback onTap;
  const _GenderCard({required this.emoji, required this.title, required this.desc,
      required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? c.primary : Colors.grey.shade700,
              width: selected ? 2 : 1),
          color: selected ? c.primary.withOpacity(0.12) : c.surface,
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 36)),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text(desc, style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
          ]),
          const Spacer(),
          if (selected) Icon(Icons.check_circle, color: c.primary),
        ]),
      ),
    );
  }
}

// ─── Page 3 — Voice selection with preview ────────────────────────────────────

class _VoicePage extends StatefulWidget {
  final String gender, selected;
  final void Function(String) onSelect;
  final VoidCallback onFinish, onBack;
  const _VoicePage({
    required this.gender, required this.selected,
    required this.onSelect, required this.onFinish, required this.onBack,
  });

  @override
  State<_VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<_VoicePage> {
  final AudioPlayer _player = AudioPlayer();
  String? _playingVoice;
  String? _loadingVoice;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _preview(String voiceId) async {
    if (_playingVoice == voiceId) {
      await _player.stop();
      setState(() => _playingVoice = null);
      return;
    }
    setState(() { _loadingVoice = voiceId; _playingVoice = null; });
    try {
      await _player.stop();
      final bytes = await NovaClient.instance.fetchPreview(voiceId);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/preview_$voiceId.wav');
      await file.writeAsBytes(bytes);
      await _player.setFilePath(file.path);
      setState(() { _loadingVoice = null; _playingVoice = voiceId; });
      await _player.play();
      _player.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed) {
          if (mounted) setState(() => _playingVoice = null);
        }
      });
    } catch (e) {
      setState(() { _loadingVoice = null; _playingVoice = null; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Preview failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final voices = AppPreferences.voiceOptions[widget.gender]
        ?? AppPreferences.voiceOptions['female']!;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
                const SizedBox(width: 4),
                const Text('Pick a voice',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 48),
                child: Text('Tap ▶ to hear each voice before choosing.',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade400)),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: voices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (ctx, i) {
                final v = voices[i];
                final id = v['id']!;
                return _VoiceCard(
                  voiceId: id,
                  label: v['label']!,
                  desc: v['desc']!,
                  gender: widget.gender,
                  selected: widget.selected == id,
                  isPlaying: _playingVoice == id,
                  isLoading: _loadingVoice == id,
                  onTap: () => widget.onSelect(id),
                  onPreview: () => _preview(id),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 64),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: widget.selected.isEmpty ? null : widget.onFinish,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  widget.selected.isEmpty ? 'Select a voice to continue' : "Let's go!",
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceCard extends StatelessWidget {
  final String voiceId, label, desc, gender;
  final bool selected, isPlaying, isLoading;
  final VoidCallback onTap, onPreview;
  const _VoiceCard({
    required this.voiceId, required this.label, required this.desc,
    required this.gender, required this.selected, required this.isPlaying,
    required this.isLoading, required this.onTap, required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? c.primary : Colors.grey.shade700,
              width: selected ? 2 : 1),
          color: selected ? c.primary.withOpacity(0.1) : c.surface,
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: selected ? c.primary : Colors.grey.shade800,
            child: Icon(
              gender == 'female' ? Icons.woman_rounded : Icons.man_rounded,
              color: selected ? Colors.white : Colors.grey.shade400,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(desc, style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
            ]),
          ),
          _PreviewButton(isLoading: isLoading, isPlaying: isPlaying, onTap: onPreview),
          const SizedBox(width: 4),
          Icon(
            selected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: selected ? c.primary : Colors.grey.shade600,
          ),
          const SizedBox(width: 4),
        ]),
      ),
    );
  }
}

class _PreviewButton extends StatelessWidget {
  final bool isLoading, isPlaying;
  final VoidCallback onTap;
  const _PreviewButton({required this.isLoading, required this.isPlaying, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isPlaying
              ? Colors.red.withOpacity(0.15)
              : Theme.of(context).colorScheme.primary.withOpacity(0.12),
        ),
        child: isLoading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                color: isPlaying ? Colors.red : Theme.of(context).colorScheme.primary,
                size: 26,
              ),
      ),
    );
  }
}

class _ProgressDot extends StatelessWidget {
  final bool active;
  const _ProgressDot({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: active ? 20 : 8, height: 8,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: active ? Theme.of(context).colorScheme.primary : Colors.grey.shade700,
      ),
    );
  }
}
