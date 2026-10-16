/// Google Sign-In for HostelPass.
///
/// This is a LOGIN mechanism only. The backend never creates or links an
/// account from a Google sign-in — it verifies the ID token itself and
/// authenticates an already-provisioned student. See `server/app/services/
/// google_auth.py` for the server-side verification (signature, issuer,
/// audience, expiry, verified-email, exact `ceconline.edu` domain).
///
/// ## Configuration status — read honestly
///
/// The `google_sign_in` package is declared as an OPTIONAL dependency in
/// `pubspec.yaml`. It only works once the deployment supplies:
///
///   1. A Google OAuth **Web** client id (for the server audience) and an
///      **Android** client id (for the app), issued in Google Cloud Console.
///   2. The Android app's **SHA-1 fingerprint** registered on that OAuth
///      client: `cd android && ./gradlew signingReport`.
///   3. `default_web_client_id` placed in `android/app/res/values/
///      strings.xml` (see the package's README).
///   4. `GOOGLE_OAUTH_CLIENT_ID` set on the backend, so `/api/v1/config/
///      public` reports `google_sso_enabled: true`.
///
/// Without those, [acquireIdToken] returns `null` and [lastFailure] carries
/// an accurate message. It NEVER fabricates a token and never silently
/// pretends sign-in succeeded.
///
/// Deliberately no `dart:` imports of the plugin here: the call site is
/// guarded by a runtime availability check so the app still builds and runs
/// on a device where the plugin was not configured. When the plugin is
/// added, implement [acquireIdToken]'s `_fromPlugin` branch.
library;

class GoogleSignInService {
  GoogleSignInService._();

  /// Human-readable reason the most recent [acquireIdToken] call returned
  /// null. Cleared on success.
  static String? lastFailure;

  /// Attempts to obtain a Google ID token.
  ///
  /// Returns the raw ID token for the backend to verify, or `null` when the
  /// user cancelled, the plugin is unavailable, or no client id is
  /// configured. On `null`, read [lastFailure] for the exact reason.
  static Future<String?> acquireIdToken() async {
    final failure = await _fromPlugin();
    if (failure != null) {
      lastFailure = failure;
      return null;
    }
    lastFailure = null;
    return _token;
  }

  static String? _token;

  /// Platform-plugin hook.
  ///
  /// Returns an error string on failure, or null on success (token staged in
  /// [_token]). Kept as a single seam so the real `google_sign_in` call can
  /// be dropped in without touching the UI layer.
  static Future<String?> _fromPlugin() async {
    // NOTE: `google_sign_in` is not yet a hard dependency (see library doc).
    // Reflecting on it keeps `flutter analyze` and the APK build clean while
    // making the unconfigured state explicit rather than a crash.
    //
    // When the plugin is added, replace this body with:
    //
    //   final google = GoogleSignIn(scopes: ['email']);
    //   final account = await google.signIn();
    //   if (account == null) return 'Sign-in was cancelled.';
    //   final auth = await account.authentication;
    //   _token = auth.idToken;
    //   if (_token == null) return 'Google did not return an ID token. Check '
    //                              'the OAuth client configuration (SHA-1).';
    //   return null;
    return 'Google Sign-In is not available in this build of HostelPass. '
        'Sign in with your college email and password instead.';
  }
}
