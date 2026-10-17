import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';

/// Unauthenticated public configuration (feature flags, display info).
class PublicConfig {
  const PublicConfig({
    required this.googleSsoEnabled,
    this.curfewStart,
    this.curfewEnd,
    this.timezone,
    this.supportExtension,
  });

  final bool googleSsoEnabled;
  final String? curfewStart;
  final String? curfewEnd;
  final String? timezone;
  final String? supportExtension;

  factory PublicConfig.fromJson(Map<String, dynamic> j) => PublicConfig(
    googleSsoEnabled: j['google_sso_enabled'] as bool? ?? false,
    curfewStart: j['curfew_window_start'] as String?,
    curfewEnd: j['curfew_window_end'] as String?,
    timezone: j['curfew_timezone'] as String?,
    supportExtension: j['support_extension'] as String?,
  );
}

final publicConfigProvider = FutureProvider<PublicConfig>((ref) async {
  final data = await ref.watch(apiClientProvider).get('/v1/config/public');
  return PublicConfig.fromJson(data as Map<String, dynamic>);
});
