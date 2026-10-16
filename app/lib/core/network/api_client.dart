import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/env.dart';
import '../errors/app_exception.dart';

abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// Secures the JWT in Android Keystore-backed storage.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'hostelpass.access_token';

  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);
  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// In-memory store for tests.
class InMemoryTokenStore implements TokenStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String token) async => value = token;
  @override
  Future<void> clear() async => value = null;
}

/// Single Dio instance wiring auth headers and normalizing every failure into
/// [AppException] with a machine code from the API contract.
///
/// Transport failures are classified against the device's actual link state
/// so "this phone is offline" never masquerades as "the API is unreachable":
///
///   local_device_offline    — no network interface at all (Wi-Fi/data off)
///   local_api_unreachable   — the phone is online but the configured
///                             API address did not answer (wrong URL, server
///                             down, DNS failure, timeout)
///   local_bad_certificate   — TLS validation failed for the API address
///   local_server_error      — the API answered, but with an HTTP 5xx
///   token_invalid / …       — authentication failures (server envelope)
class ApiClient {
  ApiClient({
    TokenStore? tokenStore,
    Dio? dio,
    String? baseUrl,
    Future<bool> Function()? hasNetwork,
  }) : tokenStore = tokenStore ?? SecureTokenStore(),
      _hasNetwork = hasNetwork ?? _deviceHasNetwork,
      dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl ?? Env.apiBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              contentType: 'application/json',
            ),
          ) {
    this.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await this.tokenStore.read();
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
      ),
    );
  }

  final Dio dio;
  final TokenStore tokenStore;
  final Future<bool> Function() _hasNetwork;

  /// True when the device has any network interface up (Wi-Fi, cellular,
  /// ethernet...). Used only to tell DEVICE OFFLINE apart from API
  /// UNREACHABLE — it says nothing about the API being reachable.
  static Future<bool> _deviceHasNetwork() async {
    final links = await Connectivity().checkConnectivity();
    return links.isNotEmpty && !links.contains(ConnectivityResult.none);
  }

  /// GET helper returning decoded JSON.
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _wrap(() => dio.get(path, queryParameters: query));

  Future<dynamic> post(String path, {Object? body}) =>
      _wrap(() => dio.post(path, data: body));

  Future<dynamic> put(String path, {Object? body}) =>
      _wrap(() => dio.put(path, data: body));

  Future<dynamic> patch(String path, {Object? body}) =>
      _wrap(() => dio.patch(path, data: body));

  Future<dynamic> delete(String path) => _wrap(() => dio.delete(path));

  Future<T> _wrap<T>(Future<Response<T>> Function() run) async {
    try {
      final res = await run();
      // The HostelPass API is JSON-only. A String body on a 2xx means the
      // server sent something else (an HTML page from a proxy catch-all,
      // another service entirely) — never a silent cast crash downstream.
      final data = res.data;
      if (data is String) throw _notHostelpass(res);
      return data as T;
    } on DioException catch (e) {
      throw await _map(e);
    }
  }

  /// Server answered, but not with HostelPass API data (JSON) — the API is
  /// not deployed or not routed at this address. Distinct from transport
  /// failures and from real API errors on purpose.
  AppException _notHostelpass(Response<dynamic> res) {
    final contentType =
        res.headers.value(Headers.contentTypeHeader) ?? 'unknown';
    return AppException(
      'local_api_not_hostelpass',
      message:
          'The server at ${res.requestOptions.baseUrl} answered '
          '${res.requestOptions.method} ${res.requestOptions.path} with '
          'HTTP ${res.statusCode} ($contentType), but not with HostelPass '
          'API data — it sent a web page. The API is not deployed or not '
          'routed at this address.',
    );
  }

  Future<AppException> _map(DioException e) async {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return _classifyTransport(e);
      case DioExceptionType.badCertificate:
        return AppException(
          'local_bad_certificate',
          message:
              "The server's security certificate at "
              '${e.requestOptions.baseUrl} could not be verified, so the '
              'connection was refused. The API address may be wrong or the '
              'network may be intercepting it.',
        );
      case DioExceptionType.cancel:
        return const AppException('local_cancelled');
      default:
        break; // badResponse / unknown → parsed from the response below
    }

    final res = e.response;
    if (res == null) return _classifyTransport(e);

    // Parse the {"error":{"code","message","details"}} envelope.
    String? code;
    String? message;
    var details = <String, dynamic>{};
    final data = res.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      code = (err['code'] as String?) ?? code;
      message = err['message'] as String?;
      if (err['details'] is Map) {
        details = Map<String, dynamic>.from(err['details'] as Map);
      }
    } else {
      code = switch (res.statusCode) {
        400 => 'invalid_payload',
        401 => 'token_invalid',
        403 => 'forbidden',
        404 => 'not_found',
        409 => 'conflict',
        422 => 'invalid_payload',
        429 => 'rate_limited',
        _ => null,
      };
    }

    // A bare 5xx (no error envelope) is still meaningful: the server at the
    // configured address ANSWERED, so this is a server problem, not a
    // connectivity problem. Keep that distinction visible.
    if (code == null) {
      final status = res.statusCode ?? 0;
      if (status >= 500) {
        return AppException(
          'local_server_error',
          message:
              'The HostelPass server at ${e.requestOptions.baseUrl} is '
              'reachable but returned an internal error (HTTP $status). '
              'Try again shortly; if it keeps happening, check the server.',
        );
      }
      // Non-envelope 4xx with a non-JSON body (e.g. nginx "405 Not Allowed"
      // HTML from a proxy that does not route the API) — the server
      // answered, but not with the HostelPass API contract.
      if (res.data is! Map) return _notHostelpass(res);
      code = 'internal_error';
    }
    return AppException(code, message: message, details: details);
  }

  /// Device-online vs API-reachable classification for transport failures.
  ///
  /// A timeout with no network interface is still "offline" (nothing could
  /// have been reached); everything else is "the API address did not answer".
  Future<AppException> _classifyTransport(DioException e) async {
    if (!await _hasNetwork()) {
      return const AppException('local_device_offline');
    }
    final base = e.requestOptions.baseUrl;
    return AppException(
      'local_api_unreachable',
      message:
          'This phone is online, but the HostelPass server at $base did not '
          'respond. The API address in this build may be wrong, or the '
          'server may be down.',
    );
  }
}
