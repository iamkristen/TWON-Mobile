import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'models.dart';

abstract class SessionStore {
  Future<Json?> read();
  Future<void> write(Json session);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  static const key = 'twon.session.v1';
  @override
  Future<Json?> read() async {
    final raw = await storage.read(key: key);
    if (raw == null) return null;
    try {
      return asJson(jsonDecode(raw));
    } catch (_) {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(Json session) =>
      storage.write(key: key, value: jsonEncode(session));
  @override
  Future<void> clear() => storage.delete(key: key);
}
