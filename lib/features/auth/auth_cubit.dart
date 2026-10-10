import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/api.dart';
import '../../core/models.dart';

enum AuthStatus { starting, signedOut, authenticated, twoFactor }

class AuthState {
  const AuthState({
    this.status = AuthStatus.starting,
    this.user,
    this.busy = false,
    this.error,
    this.challenge,
  });
  final AuthStatus status;
  final Json? user;
  final bool busy;
  final String? error, challenge;
}

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this.api) : super(const AuthState()) {
    _expired = api.expired.stream.listen(
      (_) => emit(const AuthState(status: AuthStatus.signedOut)),
    );
  }
  final DioRepository api;
  late final StreamSubscription<void> _expired;
  String get userId => entityId(state.user);
  Future<void> bootstrap() async {
    try {
      await api.restore();
      if (api.session == null) {
        emit(const AuthState(status: AuthStatus.signedOut));
        return;
      }
      emit(
        AuthState(
          status: AuthStatus.authenticated,
          user: asJson(api.session!['user']),
        ),
      );
      await refreshProfile();
    } catch (error) {
      emit(AuthState(status: AuthStatus.signedOut, error: error.toString()));
    }
  }

  Future<void> refreshProfile() async {
    try {
      final user = asJson(await api.request('users/me'));
      if (api.session == null) return;
      await api.saveSession({...api.session!, 'user': user});
      emit(AuthState(status: AuthStatus.authenticated, user: user));
    } catch (error) {
      if (api.session != null) {
        emit(
          AuthState(
            status: AuthStatus.authenticated,
            user: state.user,
            error: error.toString(),
          ),
        );
      }
    }
  }

  Future<void> login(String email, String password) async {
    if (state.busy) return;
    emit(const AuthState(status: AuthStatus.signedOut, busy: true));
    try {
      final result = asJson(
        await api.request(
          'auth/login',
          method: 'POST',
          body: {'email': email.trim(), 'password': password},
          authenticated: false,
        ),
      );
      if (result['requiresTwoFactor'] == true) {
        emit(
          AuthState(
            status: AuthStatus.twoFactor,
            challenge: result['tempToken'] as String,
          ),
        );
        return;
      }
      await accept(result);
    } catch (error) {
      emit(AuthState(status: AuthStatus.signedOut, error: error.toString()));
    }
  }

  Future<void> completeTwoFactor(String code) async {
    final challenge = state.challenge;
    if (challenge == null || state.busy) return;
    emit(
      AuthState(status: AuthStatus.twoFactor, challenge: challenge, busy: true),
    );
    try {
      await accept(
        asJson(
          await api.request(
            'auth/2fa/complete',
            method: 'POST',
            body: {'tempToken': challenge, 'token': code.trim()},
            authenticated: false,
          ),
        ),
      );
    } catch (error) {
      emit(
        AuthState(
          status: AuthStatus.twoFactor,
          challenge: challenge,
          error: error.toString(),
        ),
      );
    }
  }

  Future<void> accept(Json result) async {
    await api.saveSession(result);
    emit(
      AuthState(status: AuthStatus.authenticated, user: asJson(result['user'])),
    );
    await refreshProfile();
  }

  Future<void> logout() async {
    try {
      await api.request(
        'auth/logout',
        method: 'POST',
        body: {'refreshToken': api.session?['refreshToken']},
      );
    } catch (_) {
      /* Local sign-out must always be possible. */
    }
    await api.clearSession();
    emit(const AuthState(status: AuthStatus.signedOut));
  }

  void cancelChallenge() => emit(const AuthState(status: AuthStatus.signedOut));
  @override
  Future<void> close() async {
    await _expired.cancel();
    return super.close();
  }
}
