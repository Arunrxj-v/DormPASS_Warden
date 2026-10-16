import 'dart:async';

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

/// Account-status filter (Active/Inactive) for the roster.
///
/// `StudentQueryController` (owned by the shared providers file) exposes no
/// setter for the `status` field of the query, so this screen keeps the
/// account-status half of the filter locally and passes it to the SAME
/// repository method (`WardenRepository.students`) — no endpoint is invented.
final accountStatusFilterProvider = StateProvider<String?>((ref) => null);

/// Roster: the shared query (search / hostel / enrollment status / room) plus
/// the local account-status filter, resolved by the same repository call the
/// shared `wardenStudentsProvider` makes.
final wardenRosterProvider = FutureProvider<Paged<WardenStudent>>((ref) async {
  final q = ref.watch(studentQueryProvider);
  final accountStatus = ref.watch(accountStatusFilterProvider);
  return ref
      .watch(wardenRepositoryProvider)
      .students(
        q: q.q,
        hostelId: q.hostelId,
        room: q.room,
        enrollmentStatus: q.enrollmentStatus,
        status: accountStatus,
      );
});

/// Warden student roster tab: debounced search, filters, and the lifecycle
/// badge for each record.
class WardenStudentsScreen extends ConsumerStatefulWidget {
  const WardenStudentsScreen({super.key});

  @override
  ConsumerState<WardenStudentsScreen> createState() =>
      _WardenStudentsScreenState();
}

class _WardenStudentsScreenState extends ConsumerState<WardenStudentsScreen> {
  late final TextEditingController _search;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(studentQueryProvider).q);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {}); // keeps the clear (×) suffix in sync
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(studentQueryProvider.notifier).search(value);
    });
  }

  void _clearAll() {
    ref.read(studentQueryProvider.notifier).clearFilters();
    ref.read(accountStatusFilterProvider.notifier).state = null;
  }

  Future<void> _pickHostel() async {
    final hostelsAsync = ref.read(wardenHostelsProvider);
    final result = await showModalBottomSheet<_Confirmed<String?>>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetContext) => SafeArea(
        child: hostelsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorBar(
              message: e is AppException
                  ? e.displayMessage
                  : 'Could not load hostels.',
              onRetry: () {
                ref.invalidate(wardenHostelsProvider);
                Navigator.of(sheetContext).pop();
              },
            ),
          ),
          data: (hostels) => _OptionSheet<String?>(
            title: 'Filter by hostel',
            options: [
              const _Option<String?>(value: null, label: 'All hostels'),
              ...hostels.map(
                (h) => _Option<String?>(value: h.id, label: h.label),
              ),
            ],
            selectedValue: ref.read(studentQueryProvider).hostelId,
            onSelected: (v) => Navigator.of(sheetContext).pop(_Confirmed(v)),
          ),
        ),
      ),
    );
    // Dismissing the sheet returns null and changes nothing; picking an
    // option (including "All hostels") returns a [_Confirmed] wrapper so a
    // chosen `null` ("All") is not confused with a dismissal.
    if (result != null) {
      ref.read(studentQueryProvider.notifier).setHostel(result.value);
    }
  }

  Future<void> _pickEnrollmentStatus() async {
    final current = ref.read(studentQueryProvider).enrollmentStatus;
    final result = await showModalBottomSheet<_Confirmed<String?>>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetContext) => SafeArea(
        child: _OptionSheet<String?>(
          title: 'Filter by enrollment status',
          options: [
            const _Option<String?>(value: null, label: 'All statuses'),
            ...kEnrollmentStatusCodes.map(
              (c) => _Option<String?>(
                value: c,
                label: presentEnrollmentStatus(c).label,
              ),
            ),
          ],
          selectedValue: current,
          onSelected: (v) => Navigator.of(sheetContext).pop(_Confirmed(v)),
        ),
      ),
    );
    if (result != null) {
      ref.read(studentQueryProvider.notifier).setStatus(result.value);
    }
  }

  Future<void> _pickAccountStatus() async {
    final current = ref.read(accountStatusFilterProvider);
    final result = await showModalBottomSheet<_Confirmed<String?>>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetContext) => SafeArea(
        child: _OptionSheet<String?>(
          title: 'Filter by account status',
          options: const [
            _Option<String?>(value: null, label: 'All accounts'),
            _Option<String?>(value: 'active', label: 'Active accounts'),
            _Option<String?>(value: 'inactive', label: 'Inactive accounts'),
          ],
          selectedValue: current,
          onSelected: (v) => Navigator.of(sheetContext).pop(_Confirmed(v)),
        ),
      ),
    );
    if (result != null) {
      ref.read(accountStatusFilterProvider.notifier).state = result.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rosterAsync = ref.watch(wardenRosterProvider);
    final query = ref.watch(studentQueryProvider);
    final accountStatus = ref.watch(accountStatusFilterProvider);
    final hostelId = query.hostelId;
    final hostels = ref.watch(wardenHostelsProvider).valueOrNull ?? const [];
    final hostelLabel = hostels
        .where((h) => h.id == hostelId)
        .map((h) => h.label)
        .join();

    final hasFilters = !query.isEmpty || accountStatus != null;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  // ---- Search ----
                  TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    autocorrect: false,
                    style: AppTextStyles.bodyLg,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search name, email, roll or room',
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(left: 12, right: 10),
                        child: Icon(
                          Icons.search,
                          size: 22,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 0,
                        minHeight: 0,
                      ),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(
                                Icons.close,
                                size: 20,
                                color: AppColors.textSecondary,
                              ),
                              onPressed: () {
                                _search.clear();
                                ref
                                    .read(studentQueryProvider.notifier)
                                    .search('');
                                setState(() {});
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ---- Filter row ----
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChipButton(
                          label: hostelId == null ? 'Hostel' : hostelLabel,
                          active: hostelId != null,
                          onTap: _pickHostel,
                        ),
                        const SizedBox(width: 8),
                        _FilterChipButton(
                          label: query.enrollmentStatus == null
                              ? 'Enrollment'
                              : presentEnrollmentStatus(
                                  query.enrollmentStatus!,
                                ).label,
                          active: query.enrollmentStatus != null,
                          onTap: _pickEnrollmentStatus,
                        ),
                        const SizedBox(width: 8),
                        _FilterChipButton(
                          label: accountStatus == null
                              ? 'Account'
                              : accountStatus == 'active'
                              ? 'Active'
                              : 'Inactive',
                          active: accountStatus != null,
                          onTap: _pickAccountStatus,
                        ),
                      ],
                    ),
                  ),

                  // ---- Active filters as removable chips ----
                  if (hasFilters)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  if (hostelId != null)
                                    _RemovableChip(
                                      label: hostelLabel.isEmpty
                                          ? 'Hostel'
                                          : hostelLabel,
                                      onRemove: () => ref
                                          .read(studentQueryProvider.notifier)
                                          .setHostel(null),
                                    ),
                                  if (query.enrollmentStatus != null) ...[
                                    const SizedBox(width: 6),
                                    _RemovableChip(
                                      label: presentEnrollmentStatus(
                                        query.enrollmentStatus!,
                                      ).label,
                                      onRemove: () => ref
                                          .read(studentQueryProvider.notifier)
                                          .setStatus(null),
                                    ),
                                  ],
                                  if (accountStatus != null) ...[
                                    const SizedBox(width: 6),
                                    _RemovableChip(
                                      label: accountStatus == 'active'
                                          ? 'Active'
                                          : 'Inactive',
                                      onRemove: () =>
                                          ref
                                                  .read(
                                                    accountStatusFilterProvider
                                                        .notifier,
                                                  )
                                                  .state =
                                              null,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _clearAll,
                            child: Text(
                              'Clear all',
                              style: AppTextStyles.labelLg.copyWith(
                                color: AppColors.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ---- Roster ----
            Expanded(
              child: rosterAsync.when(
                loading: () => const LoadingView(label: 'Loading students…'),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ErrorBar(
                      message: e is AppException
                          ? e.displayMessage
                          : 'Could not load students.',
                      onRetry: () => ref.invalidate(wardenRosterProvider),
                    ),
                  ),
                ),
                data: (page) {
                  if (page.items.isEmpty) {
                    return _EmptyRoster(
                      filtered: hasFilters || query.q.isNotEmpty,
                      onClearFilters: _clearAll,
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(wardenRosterProvider);
                      ref.invalidate(wardenStudentsProvider);
                      ref.invalidate(wardenHostelsProvider);
                    },
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      itemCount: page.items.length + (page.hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        if (index >= page.items.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              'Showing the first ${page.items.length} of '
                              '${page.totalPages > page.page ? 'more matches' : 'all matching students'} — '
                              'narrow your search or filters to see the rest.',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodySm.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          );
                        }
                        final item = page.items[index];
                        return _StudentRow(
                          student: item,
                          onTap: () => context.push(
                            '/warden/students/${item.studentId}',
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/warden/students/new'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        tooltip: 'Add student',
        icon: const Icon(Icons.person_add_alt_1_outlined, size: 22),
        label: const Text('Add student'),
      ),
    );
  }
}

/// One roster row: monogram, identity, hostel·room and the lifecycle badge.
class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.student, required this.onTap});

  final WardenStudent student;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final presentation = presentEnrollmentStatus(
      student.enrollmentStatus ?? '',
    );
    final location = [
      if (student.hostelName != null) student.hostelName!,
      if (student.block != null) 'Block ${student.block}',
      if (student.room != null) 'Room ${student.room}',
    ].join(' • ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InitialsAvatar(initials: monogramInitials(student.name)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          student.name,
                          style: AppTextStyles.labelLg,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      StatusBadge(
                        label: presentation.label,
                        variant: presentation.variant,
                        dense: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      student.studentId,
                      if (student.email != null && student.email!.isNotEmpty)
                        student.email!,
                    ].join(' • '),
                    style: AppTextStyles.tabularSm.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (location.isNotEmpty)
                    Text(
                      location,
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.textDisabled,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textDisabled,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRoster extends StatelessWidget {
  const _EmptyRoster({required this.filtered, required this.onClearFilters});

  final bool filtered;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.groups_outlined,
              size: 32,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: 10),
            Text(
              filtered ? 'No students match your filters' : 'No students yet',
              style: AppTextStyles.headlineSm,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              filtered
                  ? 'Try a different search term or remove a filter to see '
                        'the full roster.'
                  : 'Create your first student record with “Add student”.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (filtered) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onClearFilters,
                child: const Text('Clear filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.primaryTint : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: AppTextStyles.labelLg.copyWith(
                  color: active
                      ? AppColors.primaryTintText
                      : AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: active
                  ? AppColors.primaryTintText
                  : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _RemovableChip extends StatelessWidget {
  const _RemovableChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.cardHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              style: AppTextStyles.labelMd.copyWith(
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.close,
                size: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Distinguishes "the warden picked this option" from "the sheet was
/// dismissed" — the picked value itself may legitimately be null ("All").
class _Confirmed<T> {
  const _Confirmed(this.value);
  final T value;
}

class _Option<T> {
  const _Option({required this.value, required this.label});

  final T value;
  final String label;
}

/// Design-system bottom-sheet option list (white surface, hairline rows).
class _OptionSheet<T> extends StatelessWidget {
  const _OptionSheet({
    required this.title,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
  });

  final String title;
  final List<_Option<T>> options;
  final T? selectedValue;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(title, style: AppTextStyles.headlineSm),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: options
                .map(
                  (o) => InkWell(
                    onTap: () => onSelected(o.value),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: AppColors.hairline),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(o.label, style: AppTextStyles.bodyLg),
                          ),
                          if (o.value == selectedValue)
                            const Icon(
                              Icons.check,
                              size: 20,
                              color: AppColors.primary,
                            ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
