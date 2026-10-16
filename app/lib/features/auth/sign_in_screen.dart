import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import 'auth_providers.dart';
import 'google_sign_in_service.dart';
import 'public_config.dart';

/// Caption under the Google button: `null` means the button is usable and the
/// normal "existing accounts only" note should show instead.
///
/// Every branch states a real condition — never a generic "unavailable".
String? googleUnavailableReason(AsyncValue<PublicConfig> cfg) {
  if (cfg.isLoading) return 'Checking Google Sign-In availability…';
  final config = cfg.valueOrNull;
  if (config == null) {
    return 'Could not check Google Sign-In right now. Sign in with your '
        'warden username and password instead.';
  }
  if (config.googleSsoEnabled) return null;
  return 'Google Sign-In is not enabled for this deployment. Sign in with '
      'your warden username and password instead.';
}

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  final _identifierFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _obscure = true;
  bool _loading = false;
  bool _googleLoading = false;
  String? _error;
  String? _identifierError;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    _identifierFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// Client-side pre-validation only — the backend re-validates everything.
  ///
  /// Wardens sign in with a staff username (e.g. "warden") or an email.
  /// There is deliberately NO college-domain check here: the
  /// @ceconline.edu rule applies to STUDENT emails in the create-student
  /// form, not to warden credentials.
  String? _validateIdentifier(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return 'Enter your warden username or email.';
    if (value.contains('@')) {
      if (!value.contains(RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$'))) {
        return 'Enter a valid email address.';
      }
      return null;
    }
    // Non-email input is a staff username.
    if (value.length < 3) return 'Enter a valid username or email.';
    return null;
  }

  Future<void> _submit() async {
    setState(() {
      _identifierError = _validateIdentifier(_identifier.text);
      _error = null;
    });
    if (_identifierError != null) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(identifier: _identifier.text, password: _password.text);
      // Navigation happens via the router watching auth state.
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.displayMessage);
    } catch (_) {
      if (mounted) setState(() => _error = 'Sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _error = null;
      _identifierError = null;
    });
    setState(() => _googleLoading = true);
    try {
      final token = await GoogleSignInService.acquireIdToken();
      if (token == null) {
        // User backed out, or Google Sign-In is not configured on device.
        // Reported honestly rather than swallowed.
        setState(() => _error = GoogleSignInService.lastFailure);
        return;
      }
      await ref.read(authControllerProvider.notifier).loginWithGoogle(token);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.displayMessage);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Google sign-in failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  void _infoDialog(String title, String body) {
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

  /// Account recovery is administrator-mediated: there is no self-service
  /// password-reset endpoint on the backend, because delivery isn't
  /// configured.
  void _recoveryDialog() {
    _infoDialog(
      'Account recovery',
      'HostelPass does not send self-service reset emails.\n\n'
          '• Forgotten password → ask the administrator who created your '
          'warden account to re-issue your credentials.\n'
          '• Not sure which username you use → your username is the staff '
          'account name (e.g. "warden").',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---- Institutional header strip ----
              Container(
                color: AppColors.cardLow,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.account_balance_outlined,
                            size: 15,
                            color: AppColors.textPrimary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'NATIONAL INSTITUTE OF TECHNOLOGY, TRICHY',
                              style: AppTextStyles.labelMd.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Hostel Warden Console • Student Residential Services',
                      style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ---- Sign-in card ----
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const HostelPassLogo(height: 26),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Warden Console',
                              style: AppTextStyles.headlineSm,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.cardHigh,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'v2.4',
                              style: AppTextStyles.labelSm.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sign in with your warden username to manage your '
                        'hostel’s student roster, enroll faces and manage '
                        'student accounts.',
                        style: AppTextStyles.bodyMd.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ---- Username / email ----
                      Text('Warden username or email', style: AppTextStyles.labelLg),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _identifier,
                        focusNode: _identifierFocus,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.username],
                        onSubmitted: (_) => _passwordFocus.requestFocus(),
                        style: AppTextStyles.bodyLg,
                        decoration: InputDecoration(
                          hintText: 'e.g. warden',
                          errorText: _identifierError,
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(left: 12, right: 10),
                            child: Icon(
                              Icons.alternate_email,
                              size: 22,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 0,
                            minHeight: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ---- Password ----
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Password', style: AppTextStyles.labelLg),
                          GestureDetector(
                            onTap: _recoveryDialog,
                            child: Text(
                              'Forgot password?',
                              style: AppTextStyles.labelMd.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _password,
                        focusNode: _passwordFocus,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _submit(),
                        style: AppTextStyles.bodyLg,
                        decoration: InputDecoration(
                          hintText: 'Your password',
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(left: 12, right: 10),
                            child: Icon(
                              Icons.lock_outline,
                              size: 22,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 0,
                            minHeight: 0,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 22,
                              color: AppColors.textSecondary,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      if (_error != null) ...[
                        ErrorBar(message: _error!),
                        const SizedBox(height: 14),
                      ],

                      FilledButton(
                        onPressed: _loading || _googleLoading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.login, size: 20),
                                  SizedBox(width: 8),
                                  Text('Sign In'),
                                ],
                              ),
                      ),

                      // ---- Google sign-in: existing accounts only ----
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'OR',
                              style: AppTextStyles.labelMd.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // The backend is the authority on whether Google SSO is
                      // actually configured (`google_sso_enabled`, derived from
                      // GOOGLE_OAUTH_CLIENT_ID). When it is not, the button is
                      // visibly inert with the reason stated rather than a
                      // control that fails on press.
                      Builder(
                        builder: (context) {
                          final cfg = ref.watch(publicConfigProvider);
                          final enabled = cfg.valueOrNull?.googleSsoEnabled ??
                              false;
                          final loading = cfg.isLoading;
                          return OutlinedButton(
                            onPressed: !enabled || _loading || _googleLoading
                                ? null
                                : _google,
                            child: _googleLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.g_mobiledata,
                                        size: 24,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        loading
                                            ? 'Checking Google…'
                                            : 'Continue with Google',
                                      ),
                                    ],
                                  ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      Text(
                        googleUnavailableReason(
                          ref.watch(publicConfigProvider),
                        ) ??
                        'Google Sign-In only opens a warden account an '
                            'administrator has already created. It never '
                            'registers a new account.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.textSecondary,
                          height: 16 / 12,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ---- No self-registration: honest direction to the
                      // administrator who creates warden accounts.
                      InfoBox(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Warden accounts are created by an '
                                'administrator. There is no '
                                'self-registration — if you do not have '
                                'credentials, contact the hostel '
                                'administration office.',
                                style: AppTextStyles.bodySm.copyWith(
                                  color: AppColors.textSecondary,
                                  height: 16 / 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          'Session secured • Staff actions are audit-logged',
                          style: AppTextStyles.labelSm.copyWith(
                            color: AppColors.textDisabled,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ---- Footer note ----
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          size: 16,
                          color: AppColors.textPrimary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Staff Console',
                          style: AppTextStyles.labelLg,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Face templates are captured here, at the hostel office, '
                      'on the student’s record. Raw camera frames are never '
                      'stored, and every sensitive action is written to the '
                      'audit log with your account.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.textSecondary,
                        height: 16 / 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
