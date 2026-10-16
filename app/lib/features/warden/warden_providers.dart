import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'warden_models.dart';
import 'warden_repository.dart';

/// Staff-only repository. Guarded so it can only be read while the session
/// is authenticated AND the server-reported role is warden/admin — hiding
/// the shell is not authorization, but this keeps accidental reads out.
final wardenRepositoryProvider = Provider<WardenRepository>((ref) {
  return WardenRepository(ref.watch(apiClientProvider));
});

/// Search + filter state for the roster screen.
class StudentQuery {
  const StudentQuery({
    this.q = '',
    this.hostelId,
    this.room,
    this.enrollmentStatus,
    this.status,
  });

  final String q;
  final String? hostelId;
  final String? room;
  final String? enrollmentStatus;
  final String? status;

  StudentQuery copyWith({
    String? q,
    String? Function()? hostelId,
    String? Function()? room,
    String? Function()? enrollmentStatus,
    String? Function()? status,
  }) => StudentQuery(
    q: q ?? this.q,
    hostelId: hostelId != null ? hostelId() : this.hostelId,
    room: room != null ? room() : this.room,
    enrollmentStatus: enrollmentStatus != null
        ? enrollmentStatus()
        : this.enrollmentStatus,
    status: status != null ? status() : this.status,
  );

  bool get isEmpty =>
      q.isEmpty &&
      hostelId == null &&
      room == null &&
      enrollmentStatus == null &&
      status == null;
}

final studentQueryProvider =
    NotifierProvider<StudentQueryController, StudentQuery>(
      StudentQueryController.new,
    );

class StudentQueryController extends Notifier<StudentQuery> {
  @override
  StudentQuery build() => const StudentQuery();

  void search(String value) {
    state = state.copyWith(q: value);
  }

  void setHostel(String? id) {
    state = state.copyWith(hostelId: () => id);
  }

  void setRoom(String? value) {
    state = state.copyWith(room: () => value);
  }

  void setStatus(String? value) {
    state = state.copyWith(enrollmentStatus: () => value);
  }

  void clearFilters() {
    state = const StudentQuery();
  }
}

final wardenDashboardProvider = FutureProvider<WardenDashboard>((ref) async {
  // Refetch whenever the roster query changes so counts stay honest after
  // create/suspend actions invalidate the query provider.
  ref.watch(studentQueryProvider);
  return ref.watch(wardenRepositoryProvider).dashboard();
});

final wardenHostelsProvider = FutureProvider<List<WardenHostel>>((ref) {
  return ref.watch(wardenRepositoryProvider).hostels();
});

final wardenStudentsProvider = FutureProvider<Paged<WardenStudent>>((
  ref,
) async {
  final q = ref.watch(studentQueryProvider);
  return ref.watch(wardenRepositoryProvider).students(
    q: q.q,
    hostelId: q.hostelId,
    room: q.room,
    enrollmentStatus: q.enrollmentStatus,
    status: q.status,
  );
});

/// Lifecycle view for one student (UUID or roll).
///
/// ``autoDispose`` on purpose: the detail screen's lifecycle claims ("link
/// redeemed", "face enrolled") must be re-fetched from the backend every time
/// a record is opened. A permanent family cache served stale — even false —
/// lifecycle statements after the state changed elsewhere.
final studentDetailProvider =
    FutureProvider.autoDispose.family<EnrollmentStatus, String>((
  ref,
  studentRef,
) async {
  ref.watch(studentDetailRefreshProvider);
  return ref.watch(wardenRepositoryProvider).student(studentRef);
});

/// Bump to force a re-read of every [studentDetailProvider].
final studentDetailRefreshProvider = StateProvider<int>((ref) => 0);
