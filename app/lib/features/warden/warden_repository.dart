import '../../core/network/api_client.dart';
import 'warden_models.dart';

/// Every staff operation the warden console performs.
///
/// There is intentionally no method here that would let a student act:
/// the backend rejects those calls with 403 regardless, and the UI layer
/// only exposes this repository to the staff shell.
class WardenRepository {
  WardenRepository(this._api);

  final ApiClient _api;

  static const _base = '/api/v1/warden';

  // ---------------------------------------------------------------- read

  Future<WardenDashboard> dashboard() async {
    final data = await _api.get('$_base/dashboard');
    return WardenDashboard.fromJson(data as Map<String, dynamic>);
  }

  Future<List<WardenHostel>> hostels() async {
    final data = await _api.get('$_base/hostels') as List;
    return [
      for (final h in data)
        if (h is Map<String, dynamic>) WardenHostel.fromJson(h),
    ];
  }

  /// Roster with search + filters. All parameters are optional; the backend
  /// additionally scopes every result to the caller's hostel grant.
  Future<Paged<WardenStudent>> students({
    String? q,
    String? hostelId,
    String? room,
    String? enrollmentStatus,
    String? status,
    int page = 1,
    int pageSize = 50,
  }) async {
    final query = <String, dynamic>{
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      if (hostelId != null) 'hostel_id': hostelId,
      if (room != null && room.isNotEmpty) 'room': room,
      if (enrollmentStatus != null) 'enrollment_status': enrollmentStatus,
      if (status != null) 'status': status,
      'page': page,
      'page_size': pageSize,
    };
    final data = await _api.get('$_base/students', query: query);
    return Paged.fromJson(
      data as Map<String, dynamic>,
      WardenStudent.fromJson,
    );
  }

  /// Full lifecycle view for one student (UUID or roll number).
  Future<EnrollmentStatus> student(String ref) async {
    final data = await _api.get('$_base/students/$ref');
    return EnrollmentStatus.fromJson(data as Map<String, dynamic>);
  }

  // --------------------------------------------------------------- write

  /// Create a student record. No password is ever supplied by staff — the
  /// student sets their own by redeeming an activation token.
  Future<WardenStudent> createStudent({
    required String studentId,
    required String name,
    required String email,
    required String hostelId,
    String? room,
    String? department,
    String? cohort,
  }) async {
    final data = await _api.post(
      '$_base/students',
      body: {
        'student_id': studentId.trim(),
        'name': name.trim(),
        'email': email.trim(),
        'hostel_id': hostelId,
        if (room != null && room.isNotEmpty) 'room': room.trim(),
        if (department != null && department.isNotEmpty)
          'department': department.trim(),
        if (cohort != null && cohort.isNotEmpty) 'cohort': cohort.trim(),
      },
    );
    return WardenStudent.fromJson(data as Map<String, dynamic>);
  }

  Future<WardenStudent> patchStudent(
    String ref, {
    String? name,
    String? email,
    String? room,
    String? hostelId,
    String? department,
    String? cohort,
  }) async {
    final data = await _api.patch(
      '$_base/students/$ref',
      body: {
        if (name != null) 'name': name.trim(),
        if (email != null) 'email': email.trim(),
        if (room != null) 'room': room,
        if (hostelId != null) 'hostel_id': hostelId,
        if (department != null) 'department': department,
        if (cohort != null) 'cohort': cohort,
      },
    );
    return WardenStudent.fromJson(data as Map<String, dynamic>);
  }

  /// Confirm submitted details: created → details_verified.
  Future<EnrollmentStatus> verifyDetails(String ref) async {
    final data = await _api.post('$_base/students/$ref/verify-details');
    return EnrollmentStatus.fromJson(data as Map<String, dynamic>);
  }

  /// Warden-initiated face enrollment. `ref` is the student's UUID or roll;
  /// the embedding was captured and is sent straight to the server, which
  /// validates dimensions/finite values and encrypts it at rest.
  Future<void> enrollFace({
    required String ref,
    required List<double> embedding,
    required String modelVersion,
  }) async {
    await _api.put(
      '$_base/students/$ref/face-enrollment',
      body: {
        'embedding': embedding,
        'embedding_dim': embedding.length,
        'model_version': modelVersion,
      },
    );
  }

  /// Authorized biometric deletion (rolls the lifecycle back recoverably).
  Future<void> deleteFace(String ref) =>
      _api.delete('$_base/students/$ref/face-enrollment');

  /// Provision the account and issue a single-use activation token.
  Future<ActivationIssue> activate(String ref) async {
    final data = await _api.post('$_base/students/$ref/activate');
    return ActivationIssue.fromJson(data as Map<String, dynamic>);
  }

  /// Warden-triggered recovery: revoke the previous link, issue a new one.
  Future<ActivationIssue> resendActivation(String ref) async {
    final data = await _api.post('$_base/students/$ref/resend-activation');
    return ActivationIssue.fromJson(data as Map<String, dynamic>);
  }

  Future<EnrollmentStatus> suspend(String ref) async {
    final data = await _api.post('$_base/students/$ref/suspend');
    return EnrollmentStatus.fromJson(data as Map<String, dynamic>);
  }

  Future<EnrollmentStatus> unsuspend(String ref) async {
    final data = await _api.post('$_base/students/$ref/unsuspend');
    return EnrollmentStatus.fromJson(data as Map<String, dynamic>);
  }
}
