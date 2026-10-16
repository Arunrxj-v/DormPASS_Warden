import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import 'enrollment_status_ui.dart';
import 'warden_models.dart';
import 'warden_providers.dart';

/// Warden dashboard tab: honest, server-derived overview of enrollment
/// lifecycle, hostels, audit activity and tonight's attendance.
class WardenDashboardScreen extends ConsumerWidget {
  const WardenDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(wardenDashboardProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: dashboardAsync.when(
          loading: () => const LoadingView(label: 'Loading dashboard…'),
          error: (e, _) => _DashboardError(
            error: e,
            onRetry: () => ref.invalidate(wardenDashboardProvider),
          ),
          data: (d) {
            // The dashboard payload embeds compact hostel summaries; the
            // curfew window is joined from the same hostels the server
            // lists for this warden (`GET /warden/hostels`), never invented.
            final hostels =
                ref.watch(wardenHostelsProvider).valueOrNull ??
                const <WardenHostel>[];
            final windowById = {for (final h in hostels) h.id: h};
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(wardenDashboardProvider);
                ref.invalidate(wardenStudentsProvider);
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  // ---- Summary stats ----
                  SectionCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        StatTile(
                          label: 'Students',
                          value: '${d.totalStudents}',
                        ),
                        StatTile(label: 'Active', value: '${d.activeStudents}'),
                        StatTile(
                          label: 'Enrolling',
                          value: '${d.pendingEnrollment}',
                        ),
                        StatTile(
                          label: 'Suspended',
                          value: '${d.suspendedStudents}',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ---- Pending tasks (computed from real counts) ----
                  SectionCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MicroLabel('Pending tasks'),
                        const SizedBox(height: 10),
                        if (d.pendingEnrollment == 0 &&
                            d.suspendedStudents == 0 &&
                            _awaitingActivation(d) == 0)
                          Text(
                            'Nothing pending — every student record is complete and active.',
                            style: AppTextStyles.bodyMd.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          )
                        else ...[
                          if (d.pendingEnrollment > 0)
                            _TaskRow(
                              text:
                                  '${d.pendingEnrollment} student${d.pendingEnrollment == 1 ? '' : 's'} '
                                  'not yet fully enrolled — verify details and enroll faces',
                            ),
                          if (_awaitingActivation(d) > 0)
                            _TaskRow(
                              text:
                                  '${_awaitingActivation(d)} face-enrolled '
                                  'student${_awaitingActivation(d) == 1 ? '' : 's'} not currently '
                                  'active — issue activation links from the roster',
                            ),
                          if (d.suspendedStudents > 0)
                            _TaskRow(
                              text:
                                  '${d.suspendedStudents} suspended account'
                                  '${d.suspendedStudents == 1 ? '' : 's'}',
                            ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          'Tap any card in Students to act on a record.',
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.textDisabled,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ---- Add student / Refresh ----
                  FilledButton(
                    onPressed: () => context.push('/warden/students/new'),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_add_alt_1_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('Add student'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () {
                      ref.invalidate(wardenDashboardProvider);
                      ref.invalidate(wardenStudentsProvider);
                    },
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('Refresh'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ---- Today's attendance ----
                  SectionCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MicroLabel("Today's attendance"),
                        const SizedBox(height: 8),
                        if (d.attendanceToday.isEmpty)
                          Text(
                            "Attendance figures unavailable until tonight's window.",
                            style: AppTextStyles.bodyMd.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          )
                        else
                          _TodayAttendance(data: d.attendanceToday),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ---- Hostel overview ----
                  SectionCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MicroLabel('Hostel overview'),
                        const SizedBox(height: 4),
                        if (d.hostels.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'No hostels are assigned to your account.',
                              style: AppTextStyles.bodyMd.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          )
                        else
                          ...d.hostels.map(
                            (h) => _HostelRow(
                              hostel: h,
                              windowHostel: windowById[h.id],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ---- Recent enrollment activity ----
                  SectionCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MicroLabel('Recent enrollment activity'),
                        const SizedBox(height: 8),
                        if (d.recentActivity.isEmpty)
                          Text(
                            'No enrollment activity yet',
                            style: AppTextStyles.bodyMd.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          )
                        else
                          ...d.recentActivity.map(
                            (a) => _ActivityRow(entry: a),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Face-enrolled-but-not-active is the honest difference between two
  /// server-reported counts (clamped — suspended accounts may inflate it).
  static int _awaitingActivation(WardenDashboard d) {
    final n = d.faceEnrolled - d.activeStudents;
    return n > 0 ? n : 0;
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Icon(
              Icons.radio_button_unchecked,
              size: 12,
              color: AppColors.pendingText,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayAttendance extends StatelessWidget {
  const _TodayAttendance({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final date = data['date'] as String?;
    final present = (data['present'] as num?)?.toInt();
    final roster = (data['roster'] as num?)?.toInt();
    if (present == null || roster == null) {
      return Text(
        "Attendance figures unavailable until tonight's window.",
        style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (date != null && date.isNotEmpty)
          Text(
            date,
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        const SizedBox(height: 4),
        Text(
          '$present of $roster marked present',
          style: AppTextStyles.headlineSm.copyWith(
            color: present == roster && roster > 0
                ? AppColors.successText
                : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _HostelRow extends StatelessWidget {
  const _HostelRow({required this.hostel, this.windowHostel});

  final WardenHostel hostel;

  /// The same hostel from `GET /warden/hostels`, which carries the curfew
  /// window. The dashboard's embedded summary does not.
  final WardenHostel? windowHostel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.domain_outlined,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hostel.label, style: AppTextStyles.labelLg),
                const SizedBox(height: 2),
                Text(
                  'Curfew window: ${formatCurfewWindow(windowHostel?.windowStart, windowHostel?.windowEnd)}',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});

  final ActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.history_outlined,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  humanizeActivityAction(entry.action),
                  style: AppTextStyles.labelLg,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (entry.actor != null && entry.actor!.isNotEmpty)
                      entry.actor!,
                    formatActivityTime(entry.at),
                  ].join(' • '),
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (entry.target != null && entry.target!.isNotEmpty)
                  Text(
                    'Target: ${entry.target}',
                    style: AppTextStyles.tabularSm.copyWith(
                      color: AppColors.textDisabled,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error is AppException
        ? (error as AppException).displayMessage
        : 'Could not load the warden dashboard.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ErrorBar(message: message, onRetry: onRetry),
      ),
    );
  }
}
