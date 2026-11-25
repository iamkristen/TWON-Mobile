import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/api.dart';
import 'core/responsive_media.dart';
import 'core/env_config.dart';
import 'core/token_store.dart';
import 'app.dart';
import 'features/chat/chat_outbox.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Task 14: bounded decoded-image memory.
  PaintingBinding.instance.imageCache
    ..maximumSize = imageCacheMaxImages
    ..maximumSizeBytes = imageCacheMaxBytes;
  AppConfig.validate();
  final preferences = await SharedPreferences.getInstance();
  // CHAT-5: unsent messages survive the app being closed (encrypted storage).
  ChatOutbox.shared = ChatOutbox(SecureOutboxStore());
  final api = DioRepository(
    baseUrl: AppConfig.apiUrl,
    store: SecureSessionStore(),
  );
  runApp(TwonApp(api: api, preferences: preferences));
}
