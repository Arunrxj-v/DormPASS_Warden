/// Warden/admin data contracts — mirror `server/app/schemas/admin.py`.
///
/// Enrollment status is read from the server, never guessed by the client.
/// The values are the backend's lifecycle states:
///
///   created → details_verified → face_enrolled → account_provisioned → active
///   (any non-created state may go to `suspended`)
library;

class WardenStudent {
  const WardenStudent({
    required this.id,
    required this.studentId,
    required this.name,
    this.email,
    this.enrollmentStatus,
    this.department,
    this.cohort,
    required this.role,
    required this.accountStatus,
    this.hostelId,
    this.hostelName,
    this.block,
    this.room,
  });

  final String id;
  final String studentId;
  final String name;
  final String? email;
  final String? enrollmentStatus;
  final String? department;
  final String? cohort;
  final String role;
  final String accountStatus;
  final String? hostelId;
  final String? hostelName;
  final String? block;
  final String? room;

  factory WardenStudent.fromJson(Map<String, dynamic> j) {
    final hostel = j['hostel'];
    return WardenStudent(
      id: j['id'] as String,
      studentId: j['student_id'] as String,
      name: j['name'] as String,
      email: j['email'] as String?,
      enrollmentStatus: j['enrollment_status'] as String?,
      department: j['department'] as String?,
      cohort: j['cohort'] as String?,
      role: (j['role'] as String?) ?? 'student',
      accountStatus: (j['account_status'] as String?) ?? 'active',
      hostelId: hostel is Map ? hostel['id'] as String? : null,
      hostelName: hostel is Map ? hostel['name'] as String? : null,
      block: hostel is Map ? hostel['block'] as String? : null,
      room: hostel is Map ? hostel['room'] as String? : null,
    );
  }
}

/// `GET /warden/students/{id}` — the truthful lifecycle snapshot.
///
/// Every flag is derived server-side from real rows (a stored template, a
/// used activation token, …). The client cannot influence these values.
class EnrollmentStatus {
  const EnrollmentStatus({
    required this.studentId,
    required this.roll,
    required this.name,
    this.email,
    required this.enrollmentStatus,
    required this.accountStatus,
    required this.detailsComplete,
    required this.faceEnrolled,
    required this.passwordSet,
    required this.activationPending,
    this.hostelId,
    this.room,
  });

  final String studentId;
  final String roll;
  final String name;
  final String? email;
  final String enrollmentStatus;
  final String accountStatus;
  final bool detailsComplete;
  final bool faceEnrolled;
  final bool passwordSet;
  final bool activationPending;
  final String? hostelId;
  final String? room;

  factory EnrollmentStatus.fromJson(Map<String, dynamic> j) =>
      EnrollmentStatus(
        studentId: j['student_id'] as String,
        roll: j['roll'] as String,
        name: j['name'] as String,
        email: j['email'] as String?,
        enrollmentStatus: j['enrollment_status'] as String,
        accountStatus: j['account_status'] as String,
        detailsComplete: j['details_complete'] as bool? ?? false,
        faceEnrolled: j['face_enrolled'] as bool? ?? false,
        passwordSet: j['password_set'] as bool? ?? false,
        activationPending: j['activation_pending'] as bool? ?? false,
        hostelId: j['hostel_id'] as String?,
        room: j['room'] as String?,
      );
}

/// `POST /warden/students/{id}/activate` and `…/resend-activation`.
class ActivationIssue {
  const ActivationIssue({
    required this.enrollmentStatus,
    required this.activationPending,
    required this.delivered,
    this.emailStatus,
    this.emailDetail,
    this.expiresAt,
    this.activationToken,
    this.setupUrl,
  });

  final String enrollmentStatus;
  final bool activationPending;

  /// True ONLY when the backend's email transport reported an accepted send.
  /// Never inferred from the mere creation of an activation record.
  final bool delivered;

  /// Raw backend delivery outcome: 'sent', 'logged' (dev outbox — no real
  /// email), 'failed' (see [emailDetail]), 'not_configured' (EMAIL_MODE=off),
  /// or null when the server predates honest status reporting.
  final String? emailStatus;

  /// Token-free human-readable reason for a 'failed' status.
  final String? emailDetail;

  final String? expiresAt;

  /// The freshly issued single-use key, returned at the issuance moment so
  /// the warden can copy it and hand it to the student (WhatsApp workflow).
  /// Null only when the deployment withholds it (ALLOW_INLINE_ACTIVATION_TOKEN
  /// = false) — reads and logs never carry it.
  final String? activationToken;
  final String? setupUrl;

  factory ActivationIssue.fromJson(Map<String, dynamic> j) => ActivationIssue(
    enrollmentStatus: j['enrollment_status'] as String,
    activationPending: j['activation_pending'] as bool? ?? false,
    delivered: j['delivered'] as bool? ?? false,
    emailStatus: j['email_status'] as String?,
    emailDetail: j['email_detail'] as String?,
    expiresAt: j['expires_at'] as String?,
    activationToken: j['activation_token'] as String?,
    setupUrl: j['setup_url'] as String?,
  );
}

class WardenHostel {
  const WardenHostel({
    required this.id,
    required this.name,
    this.block,
    this.latitude,
    this.longitude,
    this.radiusM,
    this.windowStart,
    this.windowEnd,
  });

  final String id;
  final String name;
  final String? block;
  final double? latitude;
  final double? longitude;
  final double? radiusM;
  final String? windowStart;
  final String? windowEnd;

  String get label => block == null ? name : '$name · Block $block';

  /// Two server payloads feed this model and they name the key differently:
  ///
  ///  * `GET /warden/hostels` (full geofence) → `hostel_id`
  ///  * `GET /warden/dashboard` (compact summary) → `id`
  ///
  /// Accepting only one put `wardenHostelsProvider` into a permanent error
  /// state, which blanked every hostel picker downstream (create student,
  /// roster filter, warden/admin assignment).
  factory WardenHostel.fromJson(Map<String, dynamic> j) => WardenHostel(
    id: (j['id'] ?? j['hostel_id']) as String? ?? '',
    name: j['name'] as String? ?? '',
    block: j['block'] as String?,
    latitude: (j['latitude'] as num?)?.toDouble(),
    longitude: (j['longitude'] as num?)?.toDouble(),
    radiusM: (j['permitted_radius_m'] as num?)?.toDouble(),
    windowStart: j['window_start'] as String?,
    windowEnd: j['window_end'] as String?,
  );
}

class WardenDashboard {
  const WardenDashboard({
    required this.totalStudents,
    required this.activeStudents,
    required this.pendingEnrollment,
    required this.faceEnrolled,
    required this.suspendedStudents,
    required this.hostels,
    required this.recentActivity,
    required this.attendanceToday,
  });

  final int totalStudents;
  final int activeStudents;
  final int pendingEnrollment;
  final int faceEnrolled;
  final int suspendedStudents;
  final List<WardenHostel> hostels;
  final List<ActivityEntry> recentActivity;
  final Map<String, dynamic> attendanceToday;

  factory WardenDashboard.fromJson(Map<String, dynamic> j) => WardenDashboard(
    totalStudents: (j['total_students'] as num?)?.toInt() ?? 0,
    activeStudents: (j['active_students'] as num?)?.toInt() ?? 0,
    pendingEnrollment: (j['pending_enrollment'] as num?)?.toInt() ?? 0,
    faceEnrolled: (j['face_enrolled'] as num?)?.toInt() ?? 0,
    suspendedStudents: (j['suspended_students'] as num?)?.toInt() ?? 0,
    hostels: [
      for (final h in (j['hostels'] as List? ?? const []))
        if (h is Map<String, dynamic>)
          WardenHostel.fromJson({
            ...h,
            // The dashboard embeds a compact summary, not the full geofence.
            'id': h['id'] as String? ?? '',
            'name': h['name'] as String? ?? '',
          }),
    ],
    recentActivity: [
      for (final a in (j['recent_activity'] as List? ?? const []))
        if (a is Map<String, dynamic>) ActivityEntry.fromJson(a),
    ],
    attendanceToday:
        (j['attendance_today'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{},
  );
}

class ActivityEntry {
  const ActivityEntry({
    required this.action,
    this.actor,
    this.target,
    this.at,
  });

  final String action;
  final String? actor;
  final String? target;
  final String? at;

  factory ActivityEntry.fromJson(Map<String, dynamic> j) => ActivityEntry(
    action: j['action'] as String? ?? '',
    actor: j['actor'] as String?,
    target: j['target'] as String?,
    at: j['at'] as String?,
  );
}

/// One page of a list response.
class Paged<T> {
  const Paged({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.totalPages,
    required this.hasMore,
  });

  final List<T> items;
  final int page;
  final int pageSize;
  final int totalPages;
  final bool hasMore;

  factory Paged.fromJson(
    Map<String, dynamic> j,
    T Function(Map<String, dynamic>) fromItem,
  ) => Paged(
    items: [
      for (final it in (j['items'] as List? ?? const []))
        if (it is Map<String, dynamic>) fromItem(it),
    ],
    page: (j['page'] as num?)?.toInt() ?? 1,
    pageSize: (j['page_size'] as num?)?.toInt() ?? 50,
    totalPages: (j['total_pages'] as num?)?.toInt() ?? 0,
    hasMore: j['has_more'] as bool? ?? false,
  );
}
