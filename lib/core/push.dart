import 'dart:async';
import 'api.dart';

/// CHAT-5: device push registration. The platform part (FCM on Android, FCM or
/// APNs on iOS) supplies tokens through [PushTokenSource]; it needs the owner's
/// Firebase project files and is not part of this build ([NoPushTokens]).
/// What is here: the token goes to the server bound to the current sign-in, is
/// sent again when it changes or the user signs in, and is removed on sign-out.
/// A notification never carries message text.
abstract class PushTokenSource {
  /// 'android' or 'ios'.
  String get platform;
  Future<String?> token();
  Stream<String> get tokenChanges;

  /// Conversation ids of notifications the member opened.
  Stream<String> get opened;
}

class NoPushTokens implements PushTokenSource {
  @override
  String get platform => 'android';
  @override
  Future<String?> token() async => null;
  @override
  Stream<String> get tokenChanges => const Stream.empty();
  @override
  Stream<String> get opened => const Stream.empty();
}

class PushRegistration {
  PushRegistration(this.api, this.source);
  final AppRepository api;
  final PushTokenSource source;
  StreamSubscription<String>? _changes;
  static final _id = RegExp(r'^[a-f0-9]{24}$');

  /// After signing in and on every start: the token is (re)bound to this session.
  Future<void> start() async {
    await _changes?.cancel();
    _changes = source.tokenChanges.listen(_register);
    final token = await source.token();
    if (token != null) await _register(token);
  }

  Future<void> _register(String token) async {
    try {
      await api.request(
        'push/devices',
        method: 'POST',
        body: {'provider': 'fcm', 'platform': source.platform, 'token': token},
      );
    } catch (_) {
      /* Off on the server, or offline: tried again on the next start. */
    }
  }

  /// Before signing out (while the session is still valid). The server also
  /// stops using a device whose session has ended.
  Future<void> stop() async {
    await _changes?.cancel();
    _changes = null;
    try {
      await api.request('push/devices/current', method: 'DELETE');
    } catch (_) {}
  }

  /// A tapped notification opens its chat (only a well-formed id).
  Stream<String> get openedChats => source.opened.where(_id.hasMatch);
}
