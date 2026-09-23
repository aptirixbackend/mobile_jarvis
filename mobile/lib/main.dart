import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_ai/core/preferences/app_preferences.dart';
import 'package:nova_ai/core/services/phone_control_service.dart';
import 'package:nova_ai/features/chat/chat_screen.dart';
import 'package:nova_ai/features/onboarding/onboarding_screen.dart';
import 'package:nova_ai/features/control/bot_control_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final onboardingDone = await AppPreferences.instance.isOnboardingDone();

  // Start the WebSocket bridge to the backend so Jarvis can control the phone
  await PhoneControlService.instance.init();

  runApp(ProviderScope(child: NovaApp(showOnboarding: !onboardingDone)));
}

class NovaApp extends StatelessWidget {
  final bool showOnboarding;
  const NovaApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jarvis',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),
      // WRAP with full-screen overlay - shows when bot takes control
      home: BotControlOverlay.wrap(
        showOnboarding ? const OnboardingScreen() : const ChatScreen(),
      ),
    );
  }
}
