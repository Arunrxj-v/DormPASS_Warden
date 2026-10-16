import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_providers.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/warden/create_student_screen.dart';
import '../../features/warden/student_detail_screen.dart';
import '../../features/warden/warden_dashboard_screen.dart';
import '../../features/warden/warden_enrollment_screen.dart';
import '../../features/warden/warden_students_screen.dart';
import '../../features/auth/sign_in_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/app_header.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Warden shell: Dashboard · Students · Profile.
///
/// This app is the warden console only. Attendance history and any
/// student-facing flow deliberately do not exist here — students mark their
/// own attendance in the student app, and face enrollment is initiated from
/// a student's record, never from a self-service tab.
class _WardenShell extends StatelessWidget {
  const _WardenShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = location.startsWith('/warden/students')
        ? 1
        : location.startsWith('/warden/profile')
        ? 2
        : 0;

    final headerTitle = switch (index) {
      1 => 'Students',
      2 => 'Profile',
      _ => 'Dashboard',
    };

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          AppHeader(title: headerTitle),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: _NavBar(
        index: index,
        onSelect: (i) => switch (i) {
          0 => context.go('/warden/dashboard'),
          1 => context.go('/warden/students'),
          _ => context.go('/warden/profile'),
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Students',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.index,
    required this.onSelect,
    required this.destinations,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: NavigationBar(
        height: 56,
        backgroundColor: AppColors.card,
        indicatorColor: AppColors.primaryTint.withValues(alpha: 0.45),
        selectedIndex: index.clamp(0, destinations.length - 1),
        onDestinationSelected: onSelect,
        destinations: destinations,
      ),
    );
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider);

  final signedIn = auth.isAuthenticated;
  // The role comes from the server-verified `GET /auth/me` payload — never
  // from anything the client stores or edits. This app only hosts the warden
  // shell: a non-staff session (e.g. a student token pasted in) is refused
  // client-side, and the backend rejects every /warden call with 403 anyway.
  final staff = signedIn && (auth.student?.isWarden ?? false);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/warden/dashboard',
    redirect: (context, state) {
      if (auth.status == AuthStatus.unknown) return null;

      final path = state.matchedLocation;
      final onSignIn = path == '/signin';

      // Signed out: only the sign-in screen is reachable.
      if (!signedIn) {
        return onSignIn ? null : '/signin';
      }

      // Signed in as staff: never show the sign-in screen again.
      if (staff) return onSignIn ? '/warden/dashboard' : null;

      // A non-staff account has no place in this console — hold it on the
      // sign-in screen (the screen itself explains and signs it out).
      return onSignIn ? null : '/signin';
    },
    routes: [
      GoRoute(
        path: '/signin',
        builder: (context, state) => const SignInScreen(),
      ),

      // ------------------------------------------------------- staff shell
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _WardenShell(child: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/warden/dashboard',
                builder: (context, state) => const WardenDashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/warden/students',
                builder: (context, state) => const WardenStudentsScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const CreateStudentScreen(),
                  ),
                  GoRoute(
                    path: ':ref',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => StudentDetailScreen(
                      studentRef: state.pathParameters['ref'] ?? '',
                    ),
                    routes: [
                      GoRoute(
                        path: 'enroll',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) => WardenEnrollmentScreen(
                          studentRef: state.pathParameters['ref'] ?? '',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/warden/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
