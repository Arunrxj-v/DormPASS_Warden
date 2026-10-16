import 'package:flutter_test/flutter_test.dart';
import 'package:hostelpass_warden/features/warden/warden_models.dart';

/// Roster model parsing + the `Paged` envelope, against payloads captured
/// verbatim from a live `GET /api/v1/warden/students` (dev warden token).
void main() {
  // Captured live: items carry a nested `hostel` object; the envelope wraps
  // them with page/page_size/total_pages/has_more.
  Map<String, dynamic> rosterPayload() => {
    'page': 1,
    'page_size': 5,
    'total_pages': 2,
    'has_more': true,
    'items': [
      {
        'id': '12aa5b8b-2fac-46e7-864c-e3dc5dfe6340',
        'student_id': 'CS-2022-084',
        'name': 'Rohan Sharma',
        'email': 'cs-2022-084@ceconline.edu',
        'enrollment_status': 'active',
        'department': 'Computer Science & Engg',
        'cohort': '3rd Year (B.Tech 22–26)',
        'role': 'student',
        'account_status': 'active',
        'hostel': {
          'id': '95bb0f53-1423-4f15-b2f4-f0f916d761eb',
          'name': 'Ganga Boys Hostel',
          'block': 'B',
          'room': '314',
        },
      },
      {
        'id': '2c10c096-aa55-476f-8523-25d976fc6061',
        'student_id': 'CS-2022-117',
        'name': 'Ishaan Verma',
        'email': 'cs-2022-117@ceconline.edu',
        'enrollment_status': 'details_verified',
        'department': 'Computer Science & Engg',
        'cohort': '3rd Year (B.Tech 22–26)',
        'role': 'student',
        'account_status': 'inactive',
        'hostel': {
          'id': '95bb0f53-1423-4f15-b2f4-f0f916d761eb',
          'name': 'Ganga Boys Hostel',
          'block': 'B',
          'room': '316',
        },
      },
    ],
  };

  group('WardenStudent.fromJson', () {
    test('parses identity, lifecycle and nested hostel from the live shape',
        () {
      final items = rosterPayload()['items'] as List;
      final s = WardenStudent.fromJson(items.first as Map<String, dynamic>);

      expect(s.id, '12aa5b8b-2fac-46e7-864c-e3dc5dfe6340');
      expect(s.studentId, 'CS-2022-084');
      expect(s.name, 'Rohan Sharma');
      expect(s.email, 'cs-2022-084@ceconline.edu');
      expect(s.enrollmentStatus, 'active');
      expect(s.role, 'student');
      expect(s.accountStatus, 'active');
      expect(s.hostelId, '95bb0f53-1423-4f15-b2f4-f0f916d761eb');
      expect(s.hostelName, 'Ganga Boys Hostel');
      expect(s.block, 'B');
      expect(s.room, '314');
    });

    test('reads an honest non-active lifecycle state', () {
      final items = rosterPayload()['items'] as List;
      final s = WardenStudent.fromJson(items.last as Map<String, dynamic>);
      expect(s.enrollmentStatus, 'details_verified');
      // The client never marks a student active — this comes from the server.
      expect(s.accountStatus, 'inactive');
    });

    test('missing optional fields fall back to null, never invented values',
        () {
      final s = WardenStudent.fromJson(const {
        'id': 'x',
        'student_id': 'CS-1',
        'name': 'A',
      });
      expect(s.email, isNull);
      expect(s.enrollmentStatus, isNull);
      expect(s.hostelId, isNull);
      expect(s.hostelName, isNull);
      expect(s.room, isNull);
      expect(s.role, 'student', reason: 'role defaults only when absent');
      expect(s.accountStatus, 'active');
    });

    test('a payload without a nested hostel does not throw', () {
      final s = WardenStudent.fromJson(const {
        'id': 'x',
        'student_id': 'CS-1',
        'name': 'A',
        'hostel': null,
      });
      expect(s.hostelId, isNull);
      expect(s.room, isNull);
    });
  });

  group('Paged<WardenStudent> envelope', () {
    test('parses items and every paging flag from the live shape', () {
      final p = Paged.fromJson(rosterPayload(), WardenStudent.fromJson);

      expect(p.items, hasLength(2));
      expect(p.page, 1);
      expect(p.pageSize, 5);
      expect(p.totalPages, 2);
      expect(p.hasMore, isTrue);
      expect(p.items.first.studentId, 'CS-2022-084');
      expect(p.items.last.enrollmentStatus, 'details_verified');
    });

    test('an empty page parses to empty items, not an error', () {
      final p = Paged.fromJson(
        {
          'items': <Map<String, dynamic>>[],
          'page': 1,
          'page_size': 50,
          'total_pages': 0,
          'has_more': false,
        },
        WardenStudent.fromJson,
      );
      expect(p.items, isEmpty);
      expect(p.hasMore, isFalse);
      expect(p.totalPages, 0);
    });

    test('missing envelope keys fall back to safe defaults', () {
      final p = Paged.fromJson(const {}, WardenStudent.fromJson);
      expect(p.items, isEmpty);
      expect(p.page, 1);
      expect(p.pageSize, 50);
      expect(p.totalPages, 0);
      expect(p.hasMore, isFalse);
    });
  });

  group('EnrollmentStatus (student detail) parses the live shape', () {
    test('reads every server-reported flag verbatim', () {
      // Captured live: GET /api/v1/warden/students/CS-2022-117
      final e = EnrollmentStatus.fromJson(const {
        'student_id': '2c10c096-aa55-476f-8523-25d976fc6061',
        'roll': 'CS-2022-117',
        'name': 'Ishaan Verma',
        'email': 'cs-2022-117@ceconline.edu',
        'enrollment_status': 'details_verified',
        'account_status': 'inactive',
        'details_complete': true,
        'face_enrolled': false,
        'password_set': false,
        'activation_pending': false,
        'hostel_id': '95bb0f53-1423-4f15-b2f4-f0f916d761eb',
        'room': '316',
      });
      expect(e.enrollmentStatus, 'details_verified');
      expect(e.detailsComplete, isTrue);
      expect(e.faceEnrolled, isFalse,
          reason: 'the app must show "not face_enrolled" as the server says');
      expect(e.passwordSet, isFalse);
      expect(e.activationPending, isFalse);
      expect(e.room, '316');
    });

    test('absent optional flags default to false, never true', () {
      final e = EnrollmentStatus.fromJson(const {
        'student_id': 'u',
        'roll': 'CS-1',
        'name': 'A',
        'enrollment_status': 'created',
        'account_status': 'inactive',
      });
      expect(e.detailsComplete, isFalse);
      expect(e.faceEnrolled, isFalse);
      expect(e.passwordSet, isFalse);
      expect(e.activationPending, isFalse);
    });
  });

  group('ActivationIssue (issue/resend activation link)', () {
    test('production response (no inline token) is parsed honestly', () {
      final a = ActivationIssue.fromJson(const {
        'enrollment_status': 'account_provisioned',
        'activation_pending': true,
        'delivered': false,
        'email_status': 'not_configured',
        'email_detail': 'Email delivery is not configured on this '
            'deployment (EMAIL_MODE=off).',
        'expires_at': '2026-10-20T15:00:00Z',
        'activation_token': null,
        'setup_url': null,
      });
      expect(a.activationToken, isNull);
      expect(a.setupUrl, isNull);
      // A stored activation record alone must NEVER read as a delivery.
      expect(a.delivered, isFalse);
      expect(a.emailStatus, 'not_configured');
      expect(a.emailDetail, contains('EMAIL_MODE=off'));
      expect(a.activationPending, isTrue);
    });

    test('a genuinely sent email is reported as sent + delivered', () {
      final a = ActivationIssue.fromJson(const {
        'enrollment_status': 'account_provisioned',
        'activation_pending': true,
        'delivered': true,
        'email_status': 'sent',
        'activation_token': null,
      });
      expect(a.emailStatus, 'sent');
      expect(a.delivered, isTrue);
      expect(a.activationToken, isNull);
    });

    test('a failed send is surfaced with its token-free reason', () {
      final a = ActivationIssue.fromJson(const {
        'enrollment_status': 'account_provisioned',
        'activation_pending': true,
        'delivered': false,
        'email_status': 'failed',
        'email_detail': 'ConnectionRefusedError: relay down',
      });
      expect(a.emailStatus, 'failed');
      expect(a.delivered, isFalse);
      expect(a.emailDetail, contains('relay down'));
    });

    test('development outbox mode is distinct from a real send', () {
      final a = ActivationIssue.fromJson(const {
        'enrollment_status': 'account_provisioned',
        'activation_pending': true,
        'delivered': false,
        'email_status': 'logged',
        'email_detail': 'activation-20261014T120000Z-CS.eml',
      });
      expect(a.emailStatus, 'logged');
      // Logged means "written to the server outbox", NOT delivered.
      expect(a.delivered, isFalse);
    });

    test('a server without status fields falls back to null, not invented',
        () {
      final a = ActivationIssue.fromJson(const {
        'enrollment_status': 'account_provisioned',
        'activation_pending': true,
        'delivered': false,
      });
      expect(a.emailStatus, isNull);
      expect(a.emailDetail, isNull);
      expect(a.delivered, isFalse);
    });

    test('development inline token is surfaced when the server returns it', () {
      final a = ActivationIssue.fromJson(const {
        'enrollment_status': 'account_provisioned',
        'activation_pending': true,
        'delivered': false,
        'email_status': 'logged',
        'activation_token': 'tok-43-chars-long-enough-for-validation-here',
      });
      expect(a.activationToken, isNotNull);
      expect(a.delivered, isFalse);
    });
  });

  group('WardenDashboard + ActivityEntry parse the live shape', () {
    test('parses totals, hostel summary and recent activity', () {
      // Captured live from GET /api/v1/warden/dashboard.
      final d = WardenDashboard.fromJson(const {
        'total_students': 7,
        'active_students': 4,
        'pending_enrollment': 2,
        'face_enrolled': 0,
        'suspended_students': 0,
        'hostels': [
          {
            'id': '95bb0f53-1423-4f15-b2f4-f0f916d761eb',
            'name': 'Ganga Boys Hostel',
            'block': 'B',
            'room': null,
            'students': 7,
            'window': '20:30–22:30',
          },
        ],
        'recent_activity': [
          {
            'action': 'student.unsuspend',
            'actor': 'warden',
            'target': '0138674f-f622-4d78-8722-d3077f86dff9',
            'at': '2026-10-13T17:24:45.197956Z',
          },
        ],
        'attendance_today': {'date': '2026-10-13', 'present': 2, 'roster': 7},
      });

      expect(d.totalStudents, 7);
      expect(d.activeStudents, 4);
      expect(d.hostels.single.id, '95bb0f53-1423-4f15-b2f4-f0f916d761eb');
      expect(d.recentActivity.single.action, 'student.unsuspend');
      expect(d.attendanceToday['present'], 2);
    });
  });
}
