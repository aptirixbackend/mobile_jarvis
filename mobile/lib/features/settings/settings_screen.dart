import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nova_ai/core/services/phone_control_service.dart';
import 'package:nova_ai/features/settings/usage_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  bool _serviceEnabled = false;
  bool _backendConnected = false;
  bool _overlayAllowed = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final enabled = await PhoneControlService.instance.isServiceEnabled();
    final overlay = await PhoneControlService.instance.canDrawOverlay();
    if (mounted) {
      setState(() {
        _serviceEnabled = enabled;
        _overlayAllowed = overlay;
        _backendConnected = PhoneControlService.instance.connected;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jarvis Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const UsageCard(),
          const SizedBox(height: 8),
          _SectionHeader('Phone Control'),
          _StatusTile(
            icon: Icons.accessibility_new,
            title: 'Accessibility Service',
            subtitle: _serviceEnabled
                ? 'Active — Jarvis can control your phone'
                : 'Disabled — tap to enable',
            active: _serviceEnabled,
            onTap: _serviceEnabled
                ? null
                : () async {
                    await PhoneControlService.instance.openAccessibilitySettings();
                  },
          ),
          _StatusTile(
            icon: Icons.blur_on,
            title: 'Control Glow',
            subtitle: _overlayAllowed
                ? 'On — the glowing border shows over any app Jarvis touches'
                : 'Off — without this the glow only shows inside this app. Tap to allow.',
            active: _overlayAllowed,
            onTap: _overlayAllowed
                ? null
                : () async {
                    await PhoneControlService.instance.requestOverlayPermission();
                  },
          ),
          _StatusTile(
            icon: Icons.wifi,
            title: 'Backend Connection',
            subtitle: _backendConnected
                ? 'Connected to Jarvis backend'
                : 'Not connected — make sure backend is running',
            active: _backendConnected,
            onTap: null,
          ),
          const SizedBox(height: 24),
          if (!_serviceEnabled)
            Card(
              color: Colors.orange.withOpacity(0.15),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How to enable Phone Control',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    SizedBox(height: 8),
                    Text('1. Tap "Accessibility Service" above'),
                    Text('2. Find "Jarvis Phone Control" in the list'),
                    Text('3. Toggle it ON'),
                    Text('4. Come back here — it will show Active'),
                    const SizedBox(height: 8),
                    Text(
                      'This lets Jarvis open apps, send messages, and order food for you.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;
  final VoidCallback? onTap;

  const _StatusTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: active ? Colors.greenAccent : Colors.grey),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: active
            ? const Icon(Icons.check_circle, color: Colors.greenAccent)
            : onTap != null
                ? const Icon(Icons.arrow_forward_ios, size: 16)
                : const Icon(Icons.cancel, color: Colors.redAccent),
        onTap: onTap,
      ),
    );
  }
}
