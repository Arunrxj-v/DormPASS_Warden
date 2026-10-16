import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/common.dart';

/// One-line presentation for a backend enrollment-status code.
///
/// The mapping is total: unknown codes fall through to the raw code with a
/// neutral badge — the client never invents a state the server didn't send.
class EnrollmentStatusPresentation {
  const EnrollmentStatusPresentation({
    required this.label,
    required this.variant,
    required this.description,
  });

  final String label;
  final BadgeVariant variant;
  final String description;
}

/// Maps a server `enrollment_status` code to its design-system presentation.
EnrollmentStatusPresentation presentEnrollmentStatus(String code) {
  switch (code) {
    case 'created':
      return const EnrollmentStatusPresentation(
        label: 'Details incomplete',
        variant: BadgeVariant.danger,
        description: 'Record created; details have not been verified yet.',
      );
    case 'details_verified':
      return const EnrollmentStatusPresentation(
        label: 'Awaiting face enrollment',
        variant: BadgeVariant.pending,
        description:
            'Details confirmed; the face template is not captured yet.',
      );
    case 'face_enrolled':
      return const EnrollmentStatusPresentation(
        label: 'Face enrolled',
        variant: BadgeVariant.pending,
        description:
            'Face template stored; the account is not provisioned yet.',
      );
    case 'account_provisioned':
      return const EnrollmentStatusPresentation(
        label: 'Ready to activate',
        variant: BadgeVariant.tint,
        description:
            'Account provisioned; issue the single-use activation link.',
      );
    case 'active':
      return const EnrollmentStatusPresentation(
        label: 'Active',
        variant: BadgeVariant.verified,
        description: 'Fully enrolled and activated.',
      );
    case 'suspended':
      return const EnrollmentStatusPresentation(
        label: 'Suspended',
        variant: BadgeVariant.danger,
        description: 'Account suspended; restore it to re-enable access.',
      );
    default:
      return EnrollmentStatusPresentation(
        label: code,
        variant: BadgeVariant.neutral,
        description: 'Status reported by the server.',
      );
  }
}

/// The lifecycle options offered in the roster filter sheet, in lifecycle
/// order. Every value is a real backend code.
const List<String> kEnrollmentStatusCodes = [
  'created',
  'details_verified',
  'face_enrolled',
  'account_provisioned',
  'active',
  'suspended',
];

/// "Rohan Sharma" → ["R", "S"] for the monogram avatar.
List<String> monogramInitials(String name) {
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

/// Human timestamp for audit/activity rows: relative when recent, absolute
/// otherwise. Never fabricates a time — unparsable values are shown raw.
String formatActivityTime(String? at) {
  if (at == null || at.isEmpty) return 'Time not recorded';
  final parsed = DateTime.tryParse(at)?.toLocal();
  if (parsed == null) return at;
  final diff = DateTime.now().difference(parsed);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return DateFormat('d MMM yyyy, h:mm a').format(parsed);
}

/// Humanizes backend audit action codes. Unknown codes fall back to the raw
/// code — never an invented label.
String humanizeActivityAction(String action) {
  switch (action) {
    case 'student.create':
      return 'Student created';
    case 'student.details_verified':
      return 'Details verified';
    case 'face_enrollment.enroll':
      return 'Face enrolled';
    case 'face_enrollment.re_enroll':
      return 'Face re-enrolled';
    case 'student.provision':
      return 'Account provisioned';
    case 'auth.activate':
      return 'Student activated';
    case 'student.suspend':
      return 'Suspended';
    case 'student.unsuspend':
      return 'Restored';
    case 'student.activate_issue':
      return 'Activation key issued';
    case 'student.resend_activation':
      return 'Activation key reissued';
    default:
      return action.isEmpty ? 'Unknown action' : action;
  }
}

/// Curfew/roll-call window label, e.g. "20:00 – 22:30". Honest fallback when
/// the server sent no window.
String formatCurfewWindow(String? start, String? end) {
  if (start == null || end == null) return 'No curfew window configured';
  return '$start – $end';
}
