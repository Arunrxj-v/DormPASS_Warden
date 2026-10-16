import 'package:flutter_test/flutter_test.dart';
import 'package:hostelpass_warden/core/widgets/common.dart';
import 'package:hostelpass_warden/features/warden/enrollment_status_ui.dart';

/// Every backend enrollment-status code must map to a real presentation —
/// the roster filter sheet and the lifecycle badges depend on this being a
/// total function over the server's vocabulary.
///
/// Lifecycle (server-side, docs/API.md and server/app/services/enrollment.py):
///   created → details_verified → face_enrolled → account_provisioned → active
///   (any non-created state may go to `suspended`)
void main() {
  const expected = <String, (String, BadgeVariant)>{
    'created': ('Details incomplete', BadgeVariant.danger),
    'details_verified': ('Awaiting face enrollment', BadgeVariant.pending),
    'face_enrolled': ('Face enrolled', BadgeVariant.pending),
    'account_provisioned': ('Ready to activate', BadgeVariant.tint),
    'active': ('Active', BadgeVariant.verified),
    'suspended': ('Suspended', BadgeVariant.danger),
  };

  group('presentEnrollmentStatus — every backend status code', () {
    for (final entry in expected.entries) {
      test('"${entry.key}" → "${entry.value.$1}"', () {
        final p = presentEnrollmentStatus(entry.key);
        expect(p.label, entry.value.$1);
        expect(p.variant, entry.value.$2);
        // Every presentation must carry an honest description.
        expect(p.description, isNotEmpty);
      });
    }

    test('kEnrollmentStatusCodes covers every code exactly, in lifecycle order',
        () {
      expect(kEnrollmentStatusCodes, orderedEquals(expected.keys));
    });

    test('an unknown code falls through to the raw code, never an invented '
        'state', () {
      final p = presentEnrollmentStatus('some_future_status');
      expect(p.label, 'some_future_status');
      expect(p.variant, BadgeVariant.neutral);
      expect(p.description, 'Status reported by the server.');
    });

    test('an empty code renders as empty with a neutral badge', () {
      final p = presentEnrollmentStatus('');
      expect(p.label, '');
      expect(p.variant, BadgeVariant.neutral);
    });
  });

  group('humanizeActivityAction — every audit action the backend writes', () {
    const actions = <String, String>{
      'student.create': 'Student created',
      'student.details_verified': 'Details verified',
      'face_enrollment.enroll': 'Face enrolled',
      'face_enrollment.re_enroll': 'Face re-enrolled',
      'student.provision': 'Account provisioned',
      'auth.activate': 'Student activated',
      'student.suspend': 'Suspended',
      'student.unsuspend': 'Restored',
      'student.activate_issue': 'Activation key issued',
      'student.resend_activation': 'Activation key reissued',
    };
    for (final entry in actions.entries) {
      test('"${entry.key}" → "${entry.value}"', () {
        expect(humanizeActivityAction(entry.key), entry.value);
      });
    }

    test('an unknown action falls back to the raw code', () {
      expect(humanizeActivityAction('future.action'), 'future.action');
      expect(humanizeActivityAction(''), 'Unknown action');
    });
  });

  group('formatActivityTime — never fabricates a time', () {
    test('null / empty report honestly', () {
      expect(formatActivityTime(null), 'Time not recorded');
      expect(formatActivityTime(''), 'Time not recorded');
    });

    test('an unparsable timestamp is shown raw, not guessed', () {
      expect(formatActivityTime('not-a-date'), 'not-a-date');
    });

    test('a recent timestamp is relative', () {
      final recent = DateTime.now().subtract(const Duration(seconds: 30));
      expect(formatActivityTime(recent.toIso8601String()), 'Just now');
      final minutes = DateTime.now().subtract(const Duration(minutes: 5));
      expect(formatActivityTime(minutes.toIso8601String()), '5 min ago');
    });
  });

  group('monogramInitials', () {
    test('handles one-, two- and blank names', () {
      expect(monogramInitials('Rohan Sharma'), ['R', 'S']);
      expect(monogramInitials('Rohan'), ['R']);
      expect(monogramInitials('  '), ['?']);
      expect(monogramInitials(''), ['?']);
    });
  });
}
