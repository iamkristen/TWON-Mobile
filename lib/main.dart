import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/api.dart';
import 'core/env_config.dart';
import 'core/token_store.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validate();
  final preferences = await SharedPreferences.getInstance();
  final api = DioRepository(
    baseUrl: AppConfig.apiUrl,
    store: SecureSessionStore(),
  );
  runApp(TwonApp(api: api, preferences: preferences));
}
