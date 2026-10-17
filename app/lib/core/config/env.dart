import 'package:flutter/foundation.dart';

/// Compile-time API address configuration.
///
/// The address is baked in at build time and there is deliberately no
/// runtime editing: a release build never falls back to a development
/// address, and `localhost`/`10.0.2.2` only ever appear in debug builds.
///
/// Override with either form (both set the same `API_BASE_URL` define):
///
///   # Development — Android emulator hitting the host machine (the default
///   # in debug builds):
///   flutter run --dart-define-from-file=env.development.json
///
///   # Production — HostelPass home server over HTTPS:
///   flutter build apk --release --dart-define-from-file=env.production.json
///
///   # One-off override:
///   flutter build apk --release \
///     --dart-define=API_BASE_URL=https://server.tailda589d.ts.net/api
///
/// Note: repositories append `/v1/...` to this base, so the value is the
/// API MOUNT POINT, never including `/v1` itself. The production value
/// carries the `/api` mount (the reverse proxy serves the FastAPI app
/// there); the local dev backend mounts the same app at `/api` too.
abstract final class Env {
  /// Development default — the Android emulator's alias for the host machine.
  /// Unreachable from a physical phone by design; release builds never use it.
  static const _devApiBaseUrl = 'http://10.0.2.2:8000/api';

  /// Production default — the HostelPass home server, HTTPS, behind the
  /// site's reverse proxy at the `/api` mount. Publicly resolvable, so
  /// phones reach it over any network without Tailscale.
  static const _prodApiBaseUrl = 'https://server.tailda589d.ts.net/api';

  /// Build-time override from --dart-define / --dart-define-from-file.
  static const _override = String.fromEnvironment('API_BASE_URL');

  /// The base URL for this build. A trailing slash is trimmed so Dio's
  /// `baseUrl + path` join always produces exactly one separator.
  static String get apiBaseUrl {
    final value = _override.isNotEmpty
        ? _override
        : (kReleaseMode ? _prodApiBaseUrl : _devApiBaseUrl);
    return value.endsWith('/')
        ? value.substring(0, value.length - 1)
        : value;
  }

  static const appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0',
  );
}
