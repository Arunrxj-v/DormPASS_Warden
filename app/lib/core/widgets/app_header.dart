import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Small header lockup + signed-in staff avatar shared by the three warden
/// shell tabs.
class AppHeader extends ConsumerWidget {
  const AppHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(authControllerProvider).student;
    // The shell places this header at the very top of its Column, above the
    // screen's own SafeArea, so it has to claim the status-bar inset itself —
    // otherwise the initials avatar renders underneath the system clock.
    return SafeArea(
      bottom: false,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(bottom: BorderSide(color: AppColors.hairline)),
        ),
        child: Row(
          children: [
            const HostelPassLogo(height: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'HOSTELPASS WARDEN',
                    style: AppTextStyles.labelSm.copyWith(
                      color: AppColors.textSecondary,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    title,
                    style: AppTextStyles.headlineSm.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (staff != null)
              GestureDetector(
                onTap: () => context.go('/warden/profile'),
                child: InitialsAvatar(initials: staff.initials, size: 32),
              ),
          ],
        ),
      ),
    );
  }
}
