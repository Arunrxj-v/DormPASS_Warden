import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/validation/college_email.dart';
import '../../core/widgets/common.dart';
import 'warden_models.dart';
import 'warden_providers.dart';
import 'warden_students_screen.dart' show wardenRosterProvider;

/// Create a student record (staff only). Creating a record does NOT activate
/// an account — the lifecycle continues on the student's detail screen.
class CreateStudentScreen extends ConsumerStatefulWidget {
  const CreateStudentScreen({super.key});

  @override
  ConsumerState<CreateStudentScreen> createState() =>
      _CreateStudentScreenState();
}

class _CreateStudentScreenState extends ConsumerState<CreateStudentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _roll = TextEditingController();
  final _email = TextEditingController();
  final _room = TextEditingController();
  final _department = TextEditingController();
  final _cohort = TextEditingController();

  String? _hostelId;
  bool _submitting = false;
  bool _created = false;
  String? _error;

  // Client-side field errors for server-side failures (conflict / invalid).
  String? _rollServerError;
  String? _emailServerError;

  static final _rollPattern = RegExp(r'^[A-Za-z0-9._\-/]{3,32}$');

  @override
  void dispose() {
    _name.dispose();
    _roll.dispose();
    _email.dispose();
    _room.dispose();
    _department.dispose();
    _cohort.dispose();
    super.dispose();
  }

  String? _validateName(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return 'Enter the student’s full name.';
    if (v.length < 2) return 'Name must be at least 2 characters.';
    return null;
  }

  String? _validateRoll(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return 'Enter the student ID / roll number.';
    if (!_rollPattern.hasMatch(v)) {
      return '3–32 characters: letters, digits and - _ . / only.';
    }
    return null;
  }

  String? _validateEmail(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return 'Enter the student’s college email.';
    if (!isCollegeEmail(v)) {
      return 'Must be an exact $collegeEmailDomain address '
          '(subdomains and look-alike domains are rejected).';
    }
    return null;
  }

  String? _validateHostel(String? v) {
    if (v == null) return 'Select the student’s hostel.';
    return null;
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _rollServerError = null;
      _emailServerError = null;
    });
    if (!_formKey.currentState!.validate()) return;
    final hostelId = _hostelId;
    if (hostelId == null) return;

    setState(() => _submitting = true);
    try {
      final created = await ref
          .read(wardenRepositoryProvider)
          .createStudent(
            studentId: _roll.text.trim(),
            name: _name.text.trim(),
            email: _email.text.trim(),
            hostelId: hostelId,
            room: _room.text.trim().isEmpty ? null : _room.text.trim(),
            department: _department.text.trim().isEmpty
                ? null
                : _department.text.trim(),
            cohort: _cohort.text.trim().isEmpty ? null : _cohort.text.trim(),
          );
      ref.invalidate(wardenStudentsProvider);
      ref.invalidate(wardenRosterProvider);
      ref.invalidate(wardenDashboardProvider);
      if (!mounted) return;
      setState(() => _created = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Student record created for ${created.name}. '
            'Next: verify details, enroll the face, then issue the '
            'activation link.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.pushReplacement('/warden/students/${created.studentId}');
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == 'conflict') {
          // Duplicate roll or email — surface which field the server flagged
          // when it tells us, otherwise explain both possibilities.
          final field = '${e.details['field']}';
          if (field.contains('student_id') || field.contains('roll')) {
            _rollServerError =
                'This roll number already exists. Open the existing record '
                'from the Students tab instead of creating a duplicate.';
          } else if (field.contains('email')) {
            _emailServerError =
                'This email is already registered. Open the existing record '
                'from the Students tab instead of creating a duplicate.';
          } else {
            _error =
                'A student with this roll number or email already '
                'exists. Check the Students tab before creating a duplicate. '
                '(${e.displayMessage})';
          }
        } else if (e.code == 'invalid_payload') {
          _error =
              'The server rejected one of the entered values. '
              'Check each field and try again. (${e.displayMessage})';
        } else {
          _error = e.displayMessage;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not create the student. Try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hostelsAsync = ref.watch(wardenHostelsProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Add Student')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: hostelsAsync.when(
            loading: () => const LoadingView(label: 'Loading hostels…'),
            error: (e, _) => ErrorBar(
              message: e is AppException
                  ? e.displayMessage
                  : 'Could not load your hostels.',
              onRetry: () => ref.invalidate(wardenHostelsProvider),
            ),
            data: (hostels) => _buildForm(context, hostels),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, List<WardenHostel> hostels) {
    final noHostels = hostels.isEmpty;

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- Lifecycle note ----
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
                    'Creating a record does not activate the account. '
                    'Next: verify details → enroll face → issue activation link. '
                    'No password is ever set by staff — the student sets their '
                    'own by redeeming the single-use activation link.',
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

          if (noHostels) ...[
            ErrorBar(
              message:
                  'No hostels are assigned to your account. Contact an '
                  'administrator.',
            ),
            const SizedBox(height: 16),
          ],

          // ---- Full name ----
          Text('Full name', style: AppTextStyles.labelLg),
          const SizedBox(height: 8),
          TextFormField(
            controller: _name,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            validator: _validateName,
            style: AppTextStyles.bodyLg,
            decoration: const InputDecoration(
              hintText: 'e.g. Ananya Rao',
              prefixIcon: Padding(
                padding: EdgeInsets.only(left: 12, right: 10),
                child: Icon(
                  Icons.person_outline,
                  size: 22,
                  color: AppColors.textSecondary,
                ),
              ),
              prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
            ),
          ),
          const SizedBox(height: 16),

          // ---- Roll ----
          Text('Student ID / Roll number', style: AppTextStyles.labelLg),
          const SizedBox(height: 8),
          TextFormField(
            controller: _roll,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            validator: (v) => _rollServerError ?? _validateRoll(v),
            style: AppTextStyles.bodyLg,
            decoration: const InputDecoration(
              hintText: 'e.g. 21CS1042',
              prefixIcon: Padding(
                padding: EdgeInsets.only(left: 12, right: 10),
                child: Icon(
                  Icons.badge_outlined,
                  size: 22,
                  color: AppColors.textSecondary,
                ),
              ),
              prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
            ),
          ),
          const SizedBox(height: 16),

          // ---- College email ----
          Text('College email', style: AppTextStyles.labelLg),
          const SizedBox(height: 8),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            validator: (v) => _emailServerError ?? _validateEmail(v),
            style: AppTextStyles.bodyLg,
            decoration: InputDecoration(
              hintText: 'name@$collegeEmailDomain',
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

          // ---- Hostel ----
          Text('Hostel', style: AppTextStyles.labelLg),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _hostelId,
            validator: _validateHostel,
            isExpanded: true,
            style: AppTextStyles.bodyLg,
            dropdownColor: AppColors.card,
            decoration: const InputDecoration(
              prefixIcon: Padding(
                padding: EdgeInsets.only(left: 12, right: 10),
                child: Icon(
                  Icons.domain_outlined,
                  size: 22,
                  color: AppColors.textSecondary,
                ),
              ),
              prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
            ),
            items: [
              for (final h in hostels)
                DropdownMenuItem<String>(
                  value: h.id,
                  child: Text(h.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: noHostels ? null : (v) => setState(() => _hostelId = v),
          ),
          const SizedBox(height: 16),

          // ---- Room ----
          Text('Room (optional)', style: AppTextStyles.labelLg),
          const SizedBox(height: 8),
          TextFormField(
            controller: _room,
            textInputAction: TextInputAction.next,
            style: AppTextStyles.bodyLg,
            decoration: const InputDecoration(
              hintText: 'e.g. B-214',
              prefixIcon: Padding(
                padding: EdgeInsets.only(left: 12, right: 10),
                child: Icon(
                  Icons.door_front_door_outlined,
                  size: 22,
                  color: AppColors.textSecondary,
                ),
              ),
              prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
            ),
          ),
          const SizedBox(height: 8),

          // ---- Optional details ----
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text(
                'More details (optional)',
                style: AppTextStyles.labelLg.copyWith(color: AppColors.primary),
              ),
              iconColor: AppColors.primary,
              collapsedIconColor: AppColors.primary,
              children: [
                Text('Department', style: AppTextStyles.labelLg),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _department,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  style: AppTextStyles.bodyLg,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Computer Science',
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(left: 12, right: 10),
                      child: Icon(
                        Icons.school_outlined,
                        size: 22,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    prefixIconConstraints: BoxConstraints(
                      minWidth: 0,
                      minHeight: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Cohort / batch', style: AppTextStyles.labelLg),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _cohort,
                  textCapitalization: TextCapitalization.words,
                  style: AppTextStyles.bodyLg,
                  decoration: const InputDecoration(
                    hintText: 'e.g. B.Tech 2024–2028',
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(left: 12, right: 10),
                      child: Icon(
                        Icons.calendar_month_outlined,
                        size: 22,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    prefixIconConstraints: BoxConstraints(
                      minWidth: 0,
                      minHeight: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_error != null) ...[
            ErrorBar(message: _error!),
            const SizedBox(height: 14),
          ],

          FilledButton(
            onPressed: _submitting || _created || noHostels ? null : _submit,
            child: _submitting
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
                      Icon(Icons.person_add_alt_1_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('Create student record'),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
