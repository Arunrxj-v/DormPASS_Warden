import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import 'enrollment_status_ui.dart';
import 'warden_models.dart';
import 'warden_providers.dart';

/// One student's truthful lifecycle snapshot + every staff action, each gated
/// on real server state (disabled buttons always say why).
class StudentDetailScreen extends ConsumerWidget {
  const StudentDetailScreen({super.key, required this.studentRef});

  final String studentRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(studentDetailProvider(studentRef));

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Student Record')),
      body: SafeArea(
        child: detailAsync.when(
          loading: () => const LoadingView(label: 'Loading student…'),
          error: (e, _) {
            if (e is AppException && e.code == 'not_found') {
              return _NotFoundBody(studentRef: studentRef);
            }
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ErrorBar(
                  message: e is AppException
                      ? e.displayMessage
                      : 'Could not load this student.',
                  onRetry: () =>
                      ref.invalidate(studentDetailProvider(studentRef)),
                ),
              ),
            );
          },
          data: (student) => _DetailBody(
            studentRef: studentRef,
            student: student,
            onActionCompleted: () => _refreshAfterMutation(ref),
          ),
        ),
      ),
    );
  }

  static void _refreshAfterMutation(WidgetRef ref) {
    ref.read(studentDetailRefreshProvider.notifier).state++;
    ref.invalidate(wardenStudentsProvider);
    ref.invalidate(wardenDashboardProvider);
  }
}

class _NotFoundBody extends StatelessWidget {
  const _NotFoundBody({required this.studentRef});

  final String studentRef;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.person_off_outlined,
              size: 32,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: 10),
            Text('Student not found', style: AppTextStyles.headlineSm),
            const SizedBox(height: 6),
            Text(
              'No record matches “$studentRef”. The roll number may be '
              'wrong, or the record was removed. Check the Students tab for '
              'the current roster.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => context.canPop()
                  ? context.pop()
                  : context.go('/warden/students'),
              child: const Text('Back to students'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({
    required this.studentRef,
    required this.student,
    required this.onActionCompleted,
  });

  final String studentRef;
  final EnrollmentStatus student;
  final VoidCallback onActionCompleted;

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
    String successMessage,
  ) async {
    try {
      await action();
      if (!context.mounted) return;
      onActionCompleted();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on AppException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.displayMessage),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(title, style: AppTextStyles.headlineSm),
        content: Text(
          body,
          style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              confirmLabel,
              style: TextStyle(
                color: destructive ? AppColors.dangerText : AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _showActivationIssue(
    BuildContext context,
    ActivationIssue issue, {
    required String verb,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => ActivationIssueDialog(
        issue: issue,
        studentName: student.name,
        studentEmail: student.email,
        verb: verb,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presentation = presentEnrollmentStatus(student.enrollmentStatus);
    final repo = ref.read(wardenRepositoryProvider);

    final canVerify = student.enrollmentStatus == 'created';
    final canActivate =
        student.enrollmentStatus == 'face_enrolled' ||
        student.enrollmentStatus == 'account_provisioned';
    final canResend = student.activationPending;
    final isSuspended =
        student.enrollmentStatus == 'suspended' ||
        student.accountStatus == 'suspended';
    final canSuspend = !isSuspended && student.enrollmentStatus != 'created';
    final location = [
      if (student.hostelId != null) student.hostelId!,
      if (student.room != null) 'Room ${student.room}',
    ].join(' • ');

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- Identity banner (whose face is about to be enrolled) ----
          SectionCard(
            color: AppColors.cardLow,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MicroLabel('Student identity — confirm before enrolling'),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InitialsAvatar(
                      initials: monogramInitials(student.name),
                      size: 52,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(student.name, style: AppTextStyles.headlineSm),
                          const SizedBox(height: 2),
                          Text(
                            [
                              'Roll ${student.roll}',
                              if (student.email != null) student.email!,
                            ].join('\n'),
                            style: AppTextStyles.tabularSm.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (location.isNotEmpty)
                            Text(
                              location,
                              style: AppTextStyles.bodySm.copyWith(
                                color: AppColors.textDisabled,
                              ),
                            ),
                        ],
                      ),
                    ),
                    StatusBadge(
                      label: presentation.label,
                      variant: presentation.variant,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  presentation.description,
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (isSuspended) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.dangerBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'This account is suspended — attendance and sign-in '
                      'are blocked until it is restored.',
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.dangerText,
                        height: 16 / 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ---- Lifecycle stepper (server booleans only) ----
          SectionCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MicroLabel('Enrollment lifecycle'),
                const SizedBox(height: 10),
                _LifecycleStep(
                  title: 'Details verified',
                  done: student.detailsComplete,
                ),
                _LifecycleStep(
                  title: 'Face enrolled',
                  done: student.faceEnrolled,
                ),
                _LifecycleStep(
                  title: 'Activation key issued',
                  done: student.activationPending || student.passwordSet,
                  note: student.passwordSet
                      ? 'Key redeemed — password set by the student'
                      : null,
                ),
                _LifecycleStep(
                  title: 'Account active',
                  done: student.enrollmentStatus == 'active',
                  last: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ---- Lifecycle actions ----
          SectionCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MicroLabel('Lifecycle actions'),
                const SizedBox(height: 12),

                // Verify details
                _ActionButton(
                  label: 'Verify details',
                  icon: Icons.fact_check_outlined,
                  enabled: canVerify,
                  disabledReason: canVerify
                      ? null
                      : 'Only available while details are unverified '
                            '(current stage: ${presentation.label}).',
                  loading: false,
                  onPressed: () => _run(
                    context,
                    () => repo.verifyDetails(studentRef),
                    'Details verified. Next: enroll the student’s face.',
                  ),
                ),
                const SizedBox(height: 10),

                // Enroll / re-enroll face
                _ActionButton(
                  label: student.faceEnrolled
                      ? 'Re-enroll face'
                      : 'Enroll face',
                  icon: Icons.face_outlined,
                  enabled: true,
                  disabledReason: null,
                  subtitle: student.faceEnrolled
                      ? 'Replaces the existing biometric template for '
                            '${student.name}.'
                      : 'Opens the camera to capture ${student.name}’s '
                            'face template.',
                  onPressed: () async {
                    if (student.faceEnrolled) {
                      final ok = await _confirm(
                        context,
                        title: 'Replace face template?',
                        body:
                            '${student.name} already has a stored biometric '
                            'template. Enrolling again replaces it — the '
                            'previous template stops matching immediately. '
                            'Confirm the person in front of you is '
                            '${student.name} (roll ${student.roll}).',
                        confirmLabel: 'Replace template',
                      );
                      if (!ok || !context.mounted) return;
                    }
                    if (!context.mounted) return;
                    context.push('/warden/students/$studentRef/enroll');
                  },
                ),
                const SizedBox(height: 10),

                // Issue activation key
                _ActionButton(
                  label: 'Issue activation key',
                  icon: Icons.vpn_key_outlined,
                  enabled: canActivate,
                  disabledReason: canActivate
                      ? null
                      : student.enrollmentStatus == 'created'
                      ? 'Verify details and enroll the face first.'
                      : student.enrollmentStatus == 'active'
                      ? 'The account is already active.'
                      : student.enrollmentStatus == 'suspended'
                      ? 'Restore the account before issuing a key.'
                      : 'Available once the face is enrolled '
                            '(current stage: ${presentation.label}).',
                  onPressed: () async {
                    final issue = await repo.activate(studentRef);
                    if (!context.mounted) return;
                    onActionCompleted();
                    _showActivationIssue(
                      context,
                      issue,
                      verb: 'Activation key issued',
                    );
                  },
                ),
                const SizedBox(height: 10),

                // Resend activation key (reissues — the old key stops working)
                _ActionButton(
                  label: 'Resend activation key',
                  icon: Icons.refresh,
                  enabled: canResend,
                  disabledReason: canResend
                      ? null
                      : 'No activation key is currently outstanding for '
                            'this student.',
                  onPressed: () async {
                    final issue = await repo.resendActivation(studentRef);
                    if (!context.mounted) return;
                    onActionCompleted();
                    _showActivationIssue(
                      context,
                      issue,
                      verb: 'Activation key reissued',
                    );
                  },
                ),
                const SizedBox(height: 10),

                // Suspend
                _ActionButton(
                  label: 'Suspend account',
                  icon: Icons.block_outlined,
                  enabled: canSuspend,
                  disabledReason: canSuspend
                      ? null
                      : isSuspended
                      ? 'The account is already suspended.'
                      : 'Records still being set up cannot be suspended '
                            '— verify details first or delete the record '
                            'at the hostel office.',
                  onPressed: () async {
                    final ok = await _confirm(
                      context,
                      title: 'Suspend this account?',
                      body:
                          '${student.name} (${student.roll}) will be blocked '
                          'from signing in and marking attendance immediately. '
                          'You can restore the account later from this screen. '
                          'The action is recorded in the audit log.',
                      confirmLabel: 'Suspend',
                      destructive: true,
                    );
                    if (!ok || !context.mounted) return;
                    await _run(
                      context,
                      () => repo.suspend(studentRef),
                      'Account suspended.',
                    );
                  },
                ),
                const SizedBox(height: 10),

                // Restore
                _ActionButton(
                  label: 'Restore account',
                  icon: Icons.settings_backup_restore_outlined,
                  enabled: isSuspended,
                  disabledReason: isSuspended
                      ? null
                      : 'Only suspended accounts can be restored.',
                  onPressed: () => _run(
                    context,
                    () => repo.unsuspend(studentRef),
                    'Account restored.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---- Biometric template management ----
          _ActionButton(
            label: 'Delete face template',
            icon: Icons.delete_outline,
            enabled: student.faceEnrolled,
            destructive: true,
            disabledReason: student.faceEnrolled
                ? null
                : 'No face template is stored for this student.',
            subtitle: student.faceEnrolled
                ? 'Removes ${student.name}’s biometric template and rolls '
                      'the record back to awaiting re-enrollment.'
                : null,
            onPressed: () async {
              final ok = await _confirm(
                context,
                title: 'Delete face template?',
                body:
                    'This removes the stored biometric template for '
                    '${student.name} (${student.roll}). The record rolls '
                    'back to “awaiting face enrollment” and attendance '
                    'will fail until a new template is captured. This '
                    'destructive action is recorded in the audit log.',
                confirmLabel: 'Delete template',
                destructive: true,
              );
              if (!ok || !context.mounted) return;
              await _run(
                context,
                () => repo.deleteFace(studentRef),
                'Face template deleted. Re-enroll the student to restore '
                'attendance.',
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LifecycleStep extends StatelessWidget {
  const _LifecycleStep({
    required this.title,
    required this.done,
    this.note,
    this.last = false,
  });

  final String title;
  final bool done;
  final String? note;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: done ? AppColors.primary : AppColors.card,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: done ? AppColors.primary : AppColors.hairline,
                    width: done ? 0 : 1.5,
                  ),
                ),
                child: done
                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                    : null,
              ),
              if (!last)
                Expanded(
                  child: Container(width: 1.5, color: AppColors.hairline),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.labelLg.copyWith(
                      color: done
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                  if (note != null)
                    Text(
                      note!,
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.textDisabled,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Design-consistent action button. When disabled it is visibly disabled AND
/// explains why (subtitle + tooltip) — no dead buttons without reasons.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.disabledReason,
    required this.onPressed,
    this.subtitle,
    this.destructive = false,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final String? disabledReason;
  final VoidCallback onPressed;
  final String? subtitle;
  final bool destructive;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final button = Opacity(
      opacity: enabled ? 1 : 0.55,
      child: destructive
          ? OutlinedButton(
              onPressed: enabled ? onPressed : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.dangerText,
                side: const BorderSide(color: AppColors.dangerText),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                  Text(label),
                ],
              ),
            )
          : FilledButton(
              onPressed: enabled ? onPressed : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                  Text(label),
                ],
              ),
            ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (enabled)
          button
        else
          Tooltip(
            message: disabledReason ?? 'Not available in this state.',
            triggerMode: TooltipTriggerMode.tap,
            child: button,
          ),
        if (!enabled && disabledReason != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              disabledReason!,
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.textDisabled,
                height: 16 / 12,
              ),
            ),
          )
        else if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              subtitle!,
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.textSecondary,
                height: 16 / 12,
              ),
            ),
          ),
      ],
    );
  }
}

/// Dialog shown the moment an activation key is issued (also on reissue):
/// the student's name, the key itself, a prominent Copy Key action with an
/// "Activation key copied." confirmation, the WhatsApp hand-off instruction,
/// and the activation email kept as a SECONDARY delivery path. Public (not
/// private) so widget tests can drive exactly the UI the warden sees.
class ActivationIssueDialog extends StatelessWidget {
  const ActivationIssueDialog({
    super.key,
    required this.issue,
    required this.studentName,
    required this.studentEmail,
    required this.verb,
  });

  final ActivationIssue issue;
  final String studentName;
  final String? studentEmail;
  final String verb;

  @override
  Widget build(BuildContext context) {
    final token = issue.activationToken;
    // Honest one-line delivery summary, shown SECONDARY to the key itself:
    // the activation email remains an additional delivery path, never the
    // only way to obtain the activation key.
    final String emailNote;
    if (issue.emailStatus == 'sent') {
      emailNote =
          'The activation email was also sent to '
          '${studentEmail ?? 'the student’s college email'}.';
    } else if (issue.emailStatus == 'logged') {
      emailNote =
          'Development email mode: an .eml copy was written to the server '
          'outbox instead of being sent (no real email left the server).';
    } else if (issue.emailStatus == 'failed') {
      emailNote =
          'Email delivery failed: '
          '${issue.emailDetail ?? 'no reason was reported'} '
          '— the key above still works.';
    } else {
      emailNote =
          'Email delivery is not configured on this deployment; send the '
          'key above directly.';
    }
    return AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(verb, style: AppTextStyles.headlineSm),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (token != null) ...[
              // ---- Who this key is for --------------------------------
              Text('STUDENT', style: AppTextStyles.labelSm),
              const SizedBox(height: 2),
              Text(studentName, style: AppTextStyles.headlineSm),
              const SizedBox(height: 14),

              // ---- The activation key ---------------------------------
              Text('ACTIVATION KEY', style: AppTextStyles.labelSm),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.cardLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: SelectableText(
                  token,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 15,
                    letterSpacing: 1.2,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: token));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Activation key copied.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.content_copy, size: 18),
                  label: const Text('Copy Key'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Send this key to the student through WhatsApp.',
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'The student enters it in the HostelPass Student app '
                '(Activate) together with a password of their own. '
                'Single-use — it stops working once redeemed, and '
                'reissuing revokes it. '
                'Expires: ${issue.expiresAt ?? 'not reported'}',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.pendingText,
                  height: 16 / 12,
                ),
              ),
              const SizedBox(height: 10),

              // ---- Email stays a SECONDARY delivery path --------------
              Text(
                emailNote,
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.textSecondary,
                  height: 16 / 12,
                ),
              ),
            ] else if (issue.emailStatus == 'sent') ...[
              Text(
                'The activation email was sent to '
                '${studentEmail ?? 'the student’s college email'}. It '
                'contains a single-use link the student opens in the '
                'HostelPass Student app to set their password.',
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ] else if (issue.emailStatus == 'logged') ...[
              Text(
                'Development email mode: the activation email was written '
                'to the server’s local outbox file instead of being sent. '
                'No real email left the server.',
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.pendingText,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Set EMAIL_MODE=smtp on the deployment for real delivery.',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.pendingText,
                  height: 16 / 12,
                ),
              ),
            ] else if (issue.emailStatus == 'failed') ...[
              Text(
                'Email delivery FAILED: '
                '${issue.emailDetail ?? 'no reason was reported'}.',
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.dangerText,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'The activation key itself was created and is still '
                'valid — the student just has not received it by email. '
                'Fix the deployment’s email configuration, then resend '
                'the activation key.',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.textSecondary,
                  height: 16 / 12,
                ),
              ),
            ] else if (issue.emailStatus == 'not_configured') ...[
              Text(
                'The activation key was created, but email delivery is '
                'not configured on this deployment (EMAIL_MODE=off). The '
                'student cannot receive it by email.',
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.pendingText,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Hand the key over through the hostel office, or '
                'configure SMTP and resend the activation key.',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.textSecondary,
                  height: 16 / 12,
                ),
              ),
            ] else ...[
              Text(
                'The server issued a single-use activation key but did '
                'not return it and did not report an email transport. '
                'No delivery was observed.',
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Ask the student to contact the hostel office, or re-issue '
                'the key later from this screen.',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.pendingText,
                  height: 16 / 12,
                ),
              ),
            ],
            if (issue.expiresAt != null && token == null) ...[
              const SizedBox(height: 8),
              Text(
                'Key expires: ${issue.expiresAt}',
                style: AppTextStyles.tabularSm.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
