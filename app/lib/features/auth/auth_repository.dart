import 'package:characters/characters.dart';

import '../../core/network/api_client.dart';

class HostelRef {
  const HostelRef({
    required this.id,
    required this.name,
    this.block,
    this.room,
  });

  final String id;
  final String name;
  final String? block;
  final String? room;

  factory HostelRef.fromJson(Map<String, dynamic> j) => HostelRef(
    id: j['id'] as String,
    name: j['name'] as String,
    block: j['block'] as String?,
    room: j['room'] as String?,
  );

  String get label => [name, if (block != null) 'Block $block'].join(', ');
}

class Student {
  const Student({
    required this.id,
    required this.studentId,
    required this.name,
    this.email,
    this.enrollmentStatus,
    this.department,
    this.cohort,
    required this.role,
    required this.accountStatus,
    this.hostel,
  });

  final String id;
  final String studentId;
  final String name;

  /// College email (@ceconline.edu). Null for staff accounts.
  final String? email;

  /// Provisioning lifecycle: created → details_verified → face_enrolled →
  /// account_provisioned → active (or suspended).
  final String? enrollmentStatus;

  final String? department;
  final String? cohort;
  final String role;
  final String accountStatus;
  final HostelRef? hostel;

  bool get isWarden => role == 'warden' || role == 'admin';
  bool get isAdmin => role == 'admin';
  bool get isStudent => role == 'student';
  bool get isEnrolled => enrollmentStatus == 'active' || accountStatus == 'active';

  factory Student.fromJson(Map<String, dynamic> j) => Student(
    id: j['id'] as String,
    studentId: j['student_id'] as String,
    name: j['name'] as String,
    email: j['email'] as String?,
    enrollmentStatus: j['enrollment_status'] as String?,
    department: j['department'] as String?,
    cohort: j['cohort'] as String?,
    role: (j['role'] as String?) ?? 'student',
    accountStatus: (j['account_status'] as String?) ?? 'active',
    hostel: j['hostel'] is Map
        ? HostelRef.fromJson(j['hostel'] as Map<String, dynamic>)
        : null,
  );

  /// "Rohan Sharma" → "RS" for the initials monogram avatar.
  List<String> get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return const ['?'];
    if (parts.length == 1) return [parts.first.characters.first.toUpperCase()];
    return [
      parts.first.characters.first.toUpperCase(),
      parts.last.characters.first.toUpperCase(),
    ];
  }
}

class LoginResult {
  const LoginResult({
    required this.accessToken,
    required this.expiresIn,
    required this.student,
  });

  final String accessToken;
  final int expiresIn;
  final Student student;
}

/// Every authentication call the warden console makes. There is intentionally
/// NO `register`/`signUp` method AND no `activate` method: warden accounts
/// are created by an administrator, and the activation-token redemption flow
/// belongs to the student app — the backend exposes no endpoint here that
/// would allow self-registration.
class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  /// Sign in with staff username (or email) + password.
  ///
  /// The backend `POST /auth/login` accepts `{"student_id": "<username>"}`
  /// OR `{"email": ...}` plus the password. It never accepts a `role` from
  /// the client — the role is derived server-side from the account row.
  Future<LoginResult> login({
    required String identifier,
    required String password,
  }) async {
    final trimmed = identifier.trim();
    final isEmail = trimmed.contains('@');
    final body = <String, dynamic>{'password': password};
    if (isEmail) {
      body['email'] = trimmed;
    } else {
      // Staff username (e.g. "warden") — accepted by the backend.
      body['student_id'] = trimmed;
    }
    final data = await _api.post('/api/v1/auth/login', body: body)
        as Map<String, dynamic>;
    return _parseLogin(data);
  }

  /// Sign in with a Google ID token. Existing provisioned accounts only —
  /// the server never creates an account from this call.
  Future<LoginResult> loginWithGoogle(String idToken) async {
    final data = await _api.post(
      '/api/v1/auth/google',
      body: {'id_token': idToken},
    ) as Map<String, dynamic>;
    return _parseLogin(data);
  }

  Future<Student> me() async {
    final data = await _api.get('/api/v1/auth/me') as Map<String, dynamic>;
    return Student.fromJson(data);
  }

  Future<void> logout() => _api.post('/api/v1/auth/logout');

  LoginResult _parseLogin(Map<String, dynamic> data) => LoginResult(
    accessToken: data['access_token'] as String,
    expiresIn: (data['expires_in'] as num?)?.toInt() ?? 1800,
    student: Student.fromJson(data['student'] as Map<String, dynamic>),
  );
}
