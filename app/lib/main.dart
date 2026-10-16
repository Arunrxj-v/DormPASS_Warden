import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/common.dart';
import 'features/auth/auth_providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const ProviderScope(child: HostelPassWardenApp()));
}

class HostelPassWardenApp extends ConsumerStatefulWidget {
  const HostelPassWardenApp({super.key});

  @override
  ConsumerState<HostelPassWardenApp> createState() => _HostelPassWardenAppState();
}

class _HostelPassWardenAppState extends ConsumerState<HostelPassWardenApp> {
  @override
  void initState() {
    super.initState();
    // Validate any stored session before the router makes decisions.
    Future.microtask(
      () => ref.read(authControllerProvider.notifier).restoreSession(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'HostelPass Warden',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
      builder: (context, child) {
        final auth = ref.watch(authControllerProvider);
        if (auth.status == AuthStatus.unknown) {
          return const Scaffold(
            backgroundColor: AppColors.surface,
            body: LoadingView(),
          );
        }
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
