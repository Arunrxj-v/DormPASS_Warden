import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostelpass_warden/core/errors/app_exception.dart';
import 'package:hostelpass_warden/core/network/api_client.dart';

/// Stub HTTP adapter returning canned responses to exercise the
/// {"error":{"code","message","details"}} envelope mapping.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.statusCode, this.body, {this.contentType = 'application/json'});

  final int statusCode;
  final String body;
  final String contentType;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    statusCode,
    headers: {Headers.contentTypeHeader: [contentType]},
  );

  @override
  void close({bool force = false}) {}
}

/// Adapter that always throws [error] — simulates transport-level failures
/// (DNS failure, refused connection, timeout, bad certificate)
/// deterministically.
class _ThrowingAdapter implements HttpClientAdapter {
  _ThrowingAdapter(this.error);

  final Object error;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw error;

  @override
  void close({bool force = false}) {}
}

ApiClient _clientWith(int statusCode, String body) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
  dio.httpClientAdapter = _StubAdapter(statusCode, body);
  return ApiClient(tokenStore: InMemoryTokenStore(), dio: dio);
}

Future<AppException> _expectFailure(Future<Object?> run) async {
  try {
    await run;
    fail('expected AppException');
  } on AppException catch (e) {
    return e;
  }
}

/// Client whose transport always fails with [error], with the device's link
/// state injected so DEVICE OFFLINE vs API UNREACHABLE is deterministic.
ApiClient _transportClient(
  DioException error, {
  required Future<bool> Function() hasNetwork,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
  dio.httpClientAdapter = _ThrowingAdapter(error);
  return ApiClient(
    tokenStore: InMemoryTokenStore(),
    dio: dio,
    hasNetwork: hasNetwork,
  );
}

DioException _transportError(DioExceptionType type) => DioException(
  requestOptions: RequestOptions(
    baseUrl: 'http://api.test',
    path: '/v1/warden/students',
  ),
  type: type,
);

void main() {
  group('ApiClient error envelope mapping', () {
    test('error envelope code/message/details are surfaced', () async {
      final client = _clientWith(409, jsonEncode({
        'error': {
          'code': 'duplicate_attendance',
          'message': 'Attendance already marked for this date.',
          'details': {'date': '2026-10-13'},
        },
      }));

      final ex = await _expectFailure(client.get('/v1/attendance/status'));
      expect(ex.code, 'duplicate_attendance');
      expect(ex.message, contains('already marked'));
      expect(ex.details['date'], '2026-10-13');
    });

    test('outside_geofence code from verify endpoint', () async {
      final client = _clientWith(422, jsonEncode({
        'error': {
          'code': 'outside_geofence',
          'message': 'Location is outside the permitted zone.',
          'details': {'distance_m': 420.5, 'permitted_radius_m': 100.0},
        },
      }));

      final ex = await _expectFailure(
        client.post('/v1/attendance/verify', body: const {}),
      );
      expect(ex.code, 'outside_geofence');
      expect(ex.details['distance_m'], 420.5);
    });

    test('non-envelope JSON 401 falls back to token_invalid', () async {
      final client = _clientWith(401, '{"detail":"Not authenticated"}');
      final ex = await _expectFailure(client.get('/v1/auth/me'));
      expect(ex.code, 'token_invalid');
    });

    test('non-envelope 429 maps to rate_limited', () async {
      final client = _clientWith(429, '{"detail":"slow down"}');
      final ex = await _expectFailure(client.get('/v1/attendance/verify'));
      expect(ex.code, 'rate_limited');
    });

    test('bare HTTP 500 (no envelope) maps to local_server_error', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
      dio.httpClientAdapter = _StubAdapter(
        502,
        '<html>Bad Gateway</html>',
        contentType: 'text/html',
      );
      final client = ApiClient(
        tokenStore: InMemoryTokenStore(),
        dio: dio,
        hasNetwork: () async => true,
      );

      final ex = await _expectFailure(client.get('/v1/warden/students'));
      expect(ex.code, 'local_server_error');
      // Server-reachable but errored: the message names the address and the
      // HTTP status so the state cannot be confused with a network failure.
      expect(ex.message, contains('http://api.test'));
      expect(ex.message, contains('502'));
    });

    test('envelope 500 keeps the server-provided code and message', () async {
      final client = _clientWith(500, jsonEncode({
        'error': {
          'code': 'internal_error',
          'message': 'Database exploded.',
          'details': {},
        },
      }));

      final ex = await _expectFailure(client.get('/v1/warden/students'));
      expect(ex.code, 'internal_error');
      expect(ex.message, contains('Database exploded'));
    });

    test('proxy 405 with an HTML body → local_api_not_hostelpass, not a '
        'generic error (nginx SPA catch-all on POST)', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
      dio.httpClientAdapter = _StubAdapter(
        405,
        '<html><head><title>405 Not Allowed</title></head></html>',
        contentType: 'text/html',
      );
      final client = ApiClient(
        tokenStore: InMemoryTokenStore(),
        dio: dio,
        hasNetwork: () async => true,
      );

      final ex = await _expectFailure(
        client.post('/v1/auth/login', body: const {}),
      );
      expect(ex.code, 'local_api_not_hostelpass');
      // Actionable: names the address and the HTTP status it got.
      expect(ex.message, contains('http://api.test'));
      expect(ex.message, contains('405'));
      expect(ex.displayMessage, isNot(contains('Something went wrong')));
    });

    test('proxy 200 with an HTML body (SPA catch-all) → '
        'local_api_not_hostelpass instead of a downstream cast crash',
        () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
      dio.httpClientAdapter = _StubAdapter(
        200,
        '<!doctype html><html><title>HostelPass Admin Console</title></html>',
        contentType: 'text/html',
      );
      final client = ApiClient(
        tokenStore: InMemoryTokenStore(),
        dio: dio,
        hasNetwork: () async => true,
      );

      final ex = await _expectFailure(client.post('/v1/auth/login', body: const {}));
      expect(ex.code, 'local_api_not_hostelpass');
    });

    test('envelope-free 4xx/5xx codes never render the bare generic message',
        () {
      expect(
        const AppException('internal_error').displayMessage,
        contains('internal error'),
      );
      expect(
        const AppException('invalid_payload').displayMessage,
        contains('rejected the request data'),
      );
      expect(
        const AppException('conflict').displayMessage,
        contains('conflicts'),
      );
    });
  });

  group('connectivity classification (DEVICE OFFLINE vs API UNREACHABLE)', () {
    test('connection refused with NO network interface → device offline',
        () async {
      final client = _transportClient(
        _transportError(DioExceptionType.connectionError),
        hasNetwork: () async => false,
      );

      final ex = await _expectFailure(client.get('/v1/warden/students'));
      expect(ex.code, 'local_device_offline');
    });

    test('connection refused while ONLINE → api unreachable, names the '
        'configured API address', () async {
      final client = _transportClient(
        _transportError(DioExceptionType.connectionError),
        hasNetwork: () async => true,
      );

      final ex = await _expectFailure(client.get('/v1/warden/students'));
      expect(ex.code, 'local_api_unreachable');
      // The whole point of the distinction: the user is told the phone IS
      // online and WHICH address failed, instead of "no internet".
      expect(ex.message, contains('online'));
      expect(ex.message, contains('http://api.test'));
      expect(ex.displayMessage, ex.message);
    });

    test('timeout with no network interface → device offline', () async {
      final client = _transportClient(
        _transportError(DioExceptionType.connectionTimeout),
        hasNetwork: () async => false,
      );

      final ex = await _expectFailure(client.get('/v1/warden/students'));
      expect(ex.code, 'local_device_offline');
    });

    test('timeout while online → api unreachable', () async {
      final client = _transportClient(
        _transportError(DioExceptionType.receiveTimeout),
        hasNetwork: () async => true,
      );

      final ex = await _expectFailure(client.get('/v1/warden/students'));
      expect(ex.code, 'local_api_unreachable');
    });

    test('bad certificate → local_bad_certificate naming the address',
        () async {
      final client = _transportClient(
        _transportError(DioExceptionType.badCertificate),
        hasNetwork: () async => true,
      );

      final ex = await _expectFailure(client.get('/v1/warden/students'));
      expect(ex.code, 'local_bad_certificate');
      expect(ex.message, contains('http://api.test'));
    });
  });
}
