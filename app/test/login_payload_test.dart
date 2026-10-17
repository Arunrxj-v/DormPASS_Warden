import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostelpass_warden/core/network/api_client.dart';
import 'package:hostelpass_warden/features/auth/auth_repository.dart';

/// Records the last request so tests can assert the exact payload the app
/// sends — the security properties here are the login payload shape and the
/// absence of any self-registration path.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.statusCode, this.body);

  final int statusCode;
  final String body;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

(ApiClient, _RecordingAdapter) _client({
  int status = 200,
  String body = '{}',
}) {
  final adapter = _RecordingAdapter(status, body);
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
  dio.httpClientAdapter = adapter;
  return (ApiClient(tokenStore: InMemoryTokenStore(), dio: dio), adapter);
}

/// Dio decodes a JSON body into a map before [HttpClientAdapter] returns it
/// to the caller, so tests read the sent payload through `options.data`.
Map<String, dynamic> _sentBody(RequestOptions options) {
  final data = options.data;
  if (data is Map<String, dynamic>) return data;
  if (data is String) return jsonDecode(data) as Map<String, dynamic>;
  fail('unexpected request payload type: ${data.runtimeType}');
}

// Captured verbatim from a live POST /api/v1/auth/login with the dev warden
// account ({"student_id": "warden", ...}).
const _loginOk = '''
{
  "access_token": "tok-abc",
  "expires_in": 1800,
  "token_type": "bearer",
  "student": {
    "id": "c7e967ad-1703-4ecd-8ee9-c65b612d313c",
    "student_id": "warden",
    "name": "warden",
    "email": null,
    "enrollment_status": null,
    "role": "warden",
    "account_status": "active",
    "hostel": null
  }
}
''';

void main() {
  // ---------------------------------------------------------------------
  // Requirement: the login payload shape — `student_id` for usernames,
  // `email` for email input, never a client-asserted `role`.
  // ---------------------------------------------------------------------
  group('Login payload shape', () {
    test('a username is sent as student_id + password, never role', () async {
      final (client, adapter) = _client(body: _loginOk);
      await AuthRepository(client)
          .login(identifier: '  warden  ', password: 'pw');

      expect(adapter.last!.path, endsWith('/v1/auth/login'));
      final body = _sentBody(adapter.last!);
      expect(body.keys, unorderedEquals(['student_id', 'password']));
      expect(body['student_id'], 'warden', reason: 'input must be trimmed');
      expect(body.containsKey('role'), isFalse);
      expect(body.containsKey('account_status'), isFalse);
      expect(body.containsKey('enrollment_status'), isFalse);
      expect(body.containsKey('is_warden'), isFalse);
    });

    test('an email identifier is sent as email + password', () async {
      final (client, adapter) = _client(body: _loginOk);
      await AuthRepository(client)
          .login(identifier: 'staff@example.org', password: 'pw');
      final body = _sentBody(adapter.last!);
      expect(body.keys, unorderedEquals(['email', 'password']));
      expect(body['email'], 'staff@example.org');
      expect(body.containsKey('student_id'), isFalse);
      expect(body.containsKey('role'), isFalse);
    });

    test('Google sign-in posts only the ID token', () async {
      final (client, adapter) = _client(body: _loginOk);
      await AuthRepository(client).loginWithGoogle('id-token-value');
      expect(adapter.last!.path, endsWith('/v1/auth/google'));
      final body = _sentBody(adapter.last!);
      expect(body.keys, ['id_token']);
    });

    test('the parsed session reads the server-reported warden role', () async {
      final (client, _) = _client(body: _loginOk);
      final result = await AuthRepository(client)
          .login(identifier: 'warden', password: 'pw');
      expect(result.accessToken, 'tok-abc');
      expect(result.expiresIn, 1800);
      expect(result.student.role, 'warden');
      expect(result.student.isWarden, isTrue);
    });
  });

  // ---------------------------------------------------------------------
  // Requirement: no self-registration path exists in the source.
  // ---------------------------------------------------------------------
  group('No self-registration path exists in the app', () {
    test('AuthRepository exposes no register / signUp / activate method', () {
      // Reflection isn't available in Flutter, so assert against the actual
      // source the app compiles — an honest, observable check.
      final source = File(
        'lib/features/auth/auth_repository.dart',
      ).readAsStringSync();
      for (final banned in [
        'register(',
        'signUp(',
        'signup(',
        'createAccount(',
        'activate(',
        'enrollFace(',
        'selfEnroll(',
      ]) {
        expect(
          source.contains(banned),
          isFalse,
          reason: 'AuthRepository must not expose "$banned"',
        );
      }
      // Sanity: the methods that DO exist are present.
      expect(source.contains('Future<LoginResult> login('), isTrue);
      expect(source.contains('loginWithGoogle('), isTrue);
      expect(source.contains('Future<Student> me()'), isTrue);
      expect(source.contains('logout()'), isTrue);
    });

    test('the router has no activation or self-registration route', () {
      final router = File('lib/core/routing/app_router.dart')
          .readAsStringSync();
      for (final banned in [
        "path: '/activate'",
        "path: '/enroll'",
        'register',
        'signup',
      ]) {
        expect(
          router.contains(banned),
          isFalse,
          reason: 'the router must not expose "$banned"',
        );
      }
      // The warden-initiated enrollment route must exist.
      expect(router.contains("path: 'enroll'"), isTrue);
    });

    test('the sign-in screen offers no activation link or sign-up dialog', () {
      final screen = File(
        'lib/features/auth/sign_in_screen.dart',
      ).readAsStringSync();
      expect(screen.contains("'/activate'"), isFalse);
      expect(screen.toLowerCase(), isNot(contains('activation link')));
      expect(screen.toLowerCase(), isNot(contains('don’t have an account')));
      expect(screen.toLowerCase(), isNot(contains("don't have an account")));
      expect(screen.toLowerCase(), isNot(contains('sign up')));
      // The honest static note must be present (the source splits it across
      // adjacent string literals for line length).
      expect(
        screen,
        contains('Warden accounts are created by an '),
        reason: 'the sign-in screen must state that warden accounts are '
            'created by an administrator',
      );
      expect(screen, contains('administrator.'));
    });

    test('no student-facing screen exists anywhere in lib/', () {
      for (final banned in [
        'lib/features/attendance',
        'lib/features/location',
        'lib/features/attendance_history',
        'lib/features/dashboard',
        'lib/features/admin',
      ]) {
        expect(
          Directory(banned).existsSync(),
          isFalse,
          reason: '$banned must be deleted from the warden app',
        );
      }
      expect(
        File('lib/features/auth/activate_screen.dart').existsSync(),
        isFalse,
      );
    });

    test('the sign-in screen applies NO college-domain check to usernames', () {
      // The @ceconline.edu rule is student-only; the sign-in screen must not
      // import the validator (it is used only by the create-student form).
      final screen = File(
        'lib/features/auth/sign_in_screen.dart',
      ).readAsStringSync();
      expect(screen, isNot(contains('isCollegeEmail')));
      expect(screen, isNot(contains('collegeEmailDomain')));
    });
  });
}
