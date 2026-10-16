import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/network/api_client.dart';
import 'auth_repository.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState {
  const AuthState(this.status, [this.student]);
  final AuthStatus status;
  final Student? student;

  bool get isAuthenticated =>
      status == AuthStatus.authenticated && student != null;

  /// This app hosts ONLY the warden console. `isStaff` is true when the
  /// server-reported role is warden or admin; a student session has no
  /// screens here.
  bool get isStaff => student?.isWarden ?? false;
}

/// Holds the session. Restores on app start by validating the stored JWT
/// against /auth/me — a stored-but-expired token lands in `unauthenticated`.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState(AuthStatus.unknown);

  Future<void> restoreSession() async {
    final api = ref.read(apiClientProvider);
    final token = await api.tokenStore.read();
    if (token == null) {
      state = const AuthState(AuthStatus.unauthenticated);
      return;
    }
    try {
      final student = await ref.read(authRepositoryProvider).me();
      if (!student.isWarden) {
        // A student token has no place in the warden console — do not keep
        // it around pretending to be a session.
        await api.tokenStore.clear();
        state = const AuthState(AuthStatus.unauthenticated);
        return;
      }
      state = AuthState(AuthStatus.authenticated, student);
    } catch (_) {
      // Expired / revoked / server unreachable with no session to trust.
      await api.tokenStore.clear();
      state = const AuthState(AuthStatus.unauthenticated);
    }
  }

  /// Staff username (or email) + password.
  Future<void> login({
    required String identifier,
    required String password,
  }) async {
    final api = ref.read(apiClientProvider);
    final result = await ref
        .read(authRepositoryProvider)
        .login(identifier: identifier, password: password);
    if (!result.student.isWarden) {
      // The credentials are real, but the account is a student account —
      // this console is wardens-only. Report it instead of signing in.
      await api.tokenStore.clear();
      throw const AppException(
        'forbidden',
        message:
            'This account does not have warden access. Sign in with your '
            'warden username, or ask an administrator to create one.',
      );
    }
    await api.tokenStore.write(result.accessToken);
    state = AuthState(AuthStatus.authenticated, result.student);
  }

  /// Google ID token -> server-verified sign-in for an EXISTING account.
  Future<void> loginWithGoogle(String idToken) async {
    final api = ref.read(apiClientProvider);
    final result = await ref
        .read(authRepositoryProvider)
        .loginWithGoogle(idToken);
    if (!result.student.isWarden) {
      await api.tokenStore.clear();
      throw const AppException(
        'forbidden',
        message:
            'This Google account is not linked to a warden account. Ask an '
            'administrator to create your warden account.',
      );
    }
    await api.tokenStore.write(result.accessToken);
    state = AuthState(AuthStatus.authenticated, result.student);
  }

  /// Replaces the cached staff profile (e.g. after profile refresh).
  void setStudent(Student student) {
    state = AuthState(AuthStatus.authenticated, student);
  }

  Future<void> signOut() async {
    final api = ref.read(apiClientProvider);
    try {
      await ref.read(authRepositoryProvider).logout();
    } catch (_) {
      // Best effort — local sign-out must always succeed.
    }
    await api.tokenStore.clear();
    state = const AuthState(AuthStatus.unauthenticated);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// Convenience selector used by the router redirect.
final isAuthenticatedProvider = Provider<bool>(
  (ref) => ref.watch(authControllerProvider).isAuthenticated,
);

/// True when the signed-in user is a warden or administrator.
final isStaffProvider = Provider<bool>(
  (ref) => ref.watch(authControllerProvider).isStaff,
);
