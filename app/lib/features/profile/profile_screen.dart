import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/env.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_providers.dart';
import '../auth/auth_repository.dart' show Student;
import '../warden/warden_providers.dart';

/// Warden profile & settings — the "Profile" tab of the warden shell.
///
/// This console has exactly one kind of user (staff), so this screen only
/// ever renders the staff profile. The student profile (attendance stats,
/// biometrics, geofence rows) lives in the student app and its providers are
/// not even imported here — a warden session never fires student-only
/// endpoints like /hostels/me/geofence or /face-enrollment.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  void _dialog(BuildContext context, String title, String body) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(title, style: AppTextStyles.headlineSm),
        content: Text(
          body,
          style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Warden/admin profile — no student attendance, biometrics or curfew rows.
  Widget _buildStaff(BuildContext context, WidgetRef ref, Student staff) {
    final hostelsAsync = ref.watch(wardenHostelsProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            SectionCard(
              child: Column(
                children: [
                  InitialsAvatar(initials: staff.initials, size: 84, radius: 12),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(staff.name, style: AppTextStyles.headlineMd),
                      const SizedBox(width: 8),
                      StatusBadge(
                        label: staff.role == 'admin'
                            ? 'Administrator'
                            : 'Warden',
                        variant: BadgeVariant.tint,
                        dense: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ACCOUNT: ${staff.studentId.toUpperCase()}',
                    style: AppTextStyles.labelSm.copyWith(
                      color: AppColors.textSecondary,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cardLow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _InfoLine(label: 'Role', value: staff.role.toUpperCase()),
                        _InfoLine(
                          label: 'Account status',
                          value: staff.accountStatus,
                        ),
                        if (staff.email != null)
                          _InfoLine(label: 'Email', value: staff.email!),
                        const SizedBox(height: 6),
                        Text(
                          'Access scope',
                          style: AppTextStyles.labelMd.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        hostelsAsync.when(
                          loading: () => Text(
                            'Loading assigned hostels…',
                            style: AppTextStyles.labelLg,
                          ),
                          error: (e, _) => Text(
                            'Could not load hostel assignments.',
                            style: AppTextStyles.labelLg,
                          ),
                          data: (hostels) => Text(
                            staff.role == 'admin'
                                ? 'All hostels (administrator)'
                                : hostels.isEmpty
                                ? 'No hostels assigned — ask an administrator'
                                : hostels.map((h) => h.label).join('\n'),
                            style: AppTextStyles.labelLg,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Selecting a different hostel in the roster filter '
                          'does not widen your access — the server scopes '
                          'every request to your assignment.',
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.textDisabled,
                            height: 16 / 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            MicroLabel('Your Work'),
            const SizedBox(height: 8),
            SectionCard(
              padding: const EdgeInsets.all(0),
              child: Column(
                children: [
                  _LinkRow(
                    icon: Icons.dashboard_outlined,
                    title: 'Dashboard',
                    subtitle: 'Roster counts, enrollment activity, tonight\'s attendance',
                    onTap: () => context.go('/warden/dashboard'),
                  ),
                  _LinkRow(
                    icon: Icons.groups_outlined,
                    title: 'Students',
                    subtitle: 'Search, create, enroll faces, issue activation links',
                    onTap: () => context.go('/warden/students'),
                  ),
                  _LinkRow(
                    icon: Icons.face_retouching_natural_outlined,
                    title: 'Face Enrollment',
                    subtitle: 'Performed here, on the student\'s record — '
                        'students cannot enroll themselves',
                    onTap: () => context.go('/warden/students'),
                  ),
                  _LinkRow(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacy & Audit',
                    subtitle: 'What staff actions are recorded',
                    onTap: () => _dialog(
                      context,
                      'Privacy & Audit',
                      'Every sensitive staff action — creating or editing a '
                          'student, enrolling or deleting a face template, '
                          'issuing an activation link, suspending or restoring '
                          'an account — is written to the audit log with your '
                          'account and the affected student.\n\n'
                          'Passwords, activation tokens and biometric templates '
                          'are never recorded there, and raw camera frames are '
                          'never stored on either side.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            OutlinedButton(
              onPressed: () async {
                await ref.read(authControllerProvider.notifier).signOut();
                if (context.mounted) context.go('/signin');
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.dangerText,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.logout, size: 18),
                  SizedBox(width: 8),
                  Text('Sign Out of Device'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'HostelPass Warden v${Env.appVersion}',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(authControllerProvider).student;
    // The router only exposes this screen inside the staff shell, but guard
    // anyway rather than render a profile for a null/foreign session.
    if (staff == null || !staff.isWarden) {
      return const Scaffold(
        backgroundColor: AppColors.surface,
        body: LoadingView(label: 'No staff session'),
      );
    }
    return _buildStaff(context, ref, staff);
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: AppTextStyles.labelMd.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(child: Text(value, style: AppTextStyles.labelLg)),
      ],
    ),
  );
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.hairline)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.labelLg),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
