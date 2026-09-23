import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  AppPreferences._();
  static final AppPreferences instance = AppPreferences._();

  static const _keyOnboardingDone = 'onboarding_done';
  static const _keyGender        = 'voice_gender';
  static const _keyVoice         = 'voice_speaker';
  static const _keyUserName      = 'user_name';
  static const _keyBotName       = 'bot_name';

  // Voice options — must match Sarvam bulbul:v3 speaker names
  static const Map<String, List<Map<String, String>>> voiceOptions = {
    'female': [
      {'id': 'priya',   'label': 'Priya',   'desc': 'Warm & friendly'},
      {'id': 'neha',    'label': 'Neha',    'desc': 'Professional & clear'},
      {'id': 'simran',  'label': 'Simran',  'desc': 'Soft & gentle'},
      {'id': 'kavya',   'label': 'Kavya',   'desc': 'Energetic & bright'},
    ],
    'male': [
      {'id': 'aditya', 'label': 'Aditya', 'desc': 'Deep & calm'},
      {'id': 'rahul',  'label': 'Rahul',  'desc': 'Friendly & warm'},
      {'id': 'rohan',  'label': 'Rohan',  'desc': 'Professional & confident'},
    ],
  };

  Future<bool> isOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOnboardingDone) ?? false;
  }

  Future<void> completeOnboarding({
    required String gender,
    required String speaker,
    required String userName,
    required String botName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingDone, true);
    await prefs.setString(_keyGender, gender);
    await prefs.setString(_keyVoice, speaker);
    await prefs.setString(_keyUserName, userName);
    await prefs.setString(_keyBotName, botName);
  }

  Future<String> getGender() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyGender) ?? 'female';
  }

  Future<String> getSpeaker() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyVoice) ?? 'priya';
  }

  Future<String> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserName) ?? 'there';
  }

  Future<String> getBotName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBotName) ?? 'Jarvis';
  }

  Future<void> updateSpeaker(String speaker) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyVoice, speaker);
  }

  Future<void> updateBotName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBotName, name);
  }
}
