# HostelPass Warden

The standalone **warden console** app for HostelPass: roster management,
student lifecycle actions (verify details → enroll face → issue activation
link → suspend/restore) and the warden-initiated face-enrollment flow.

There is no second backend here. This app talks to the SAME FastAPI server
as the student app (`DormPASS_Student/server/`), under `/api/v1`. Every
number and status shown comes from that API — the client never invents or
optimistically updates lifecycle state.

## What lives where

- `lib/features/auth/` — sign-in (staff username/email + password), session
  restore via `GET /auth/me`, honest Google-SSO gating on the server's
  `google_sso_enabled` flag. **No self-registration**: warden accounts are
  created by an administrator, and there is deliberately no activation or
  sign-up screen.
- `lib/features/warden/` — dashboard, roster (search/filter/pagination),
  create-student form (exact `@ceconline.edu` domain validation, client-side),
  student detail with every lifecycle action gated on real server state, and
  the face-enrollment camera flow (identity banner first, multi-sample
  capture, real backend result only).
- `lib/features/face/` — the shared on-device pipeline (ML Kit detection +
  bundled MobileFaceNet TFLite) used for warden face enrollment.
- `lib/core/` — theme tokens, Dio `ApiClient` with the
  `{"error":{"code","message","details"}}` envelope mapping, router.

Deleted relative to the student app: student attendance, location/geofence,
attendance history, the student shell, the admin console (admin moves to a
web app) and the student activation screen.

## Backend

Default base URL targets the Android emulator host loopback
(`http://10.0.2.2:8000`); override with:

```
flutter run --dart-define=API_BASE_URL=http://<server>:8000
```

`android/app/src/main/res/xml/network_security_config.xml` allow-lists
cleartext only for `10.0.2.2`, `10.0.3.2`, `localhost` and `127.0.0.1`.

Dev warden credentials (Ganga Boys Hostel): `warden` / `WardenPass123!`.

## Tests

```
flutter analyze
flutter test
```
