import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hostelpass_warden/features/warden/warden_models.dart';

/// Regression tests for the two server payloads that feed [WardenHostel].
///
/// `GET /api/v1/warden/hostels` names the key `hostel_id`, while
/// `GET /api/v1/warden/dashboard` embeds a compact summary naming it `id`.
/// Reading only one of them threw a `TypeError` on every hostel request,
/// which put `wardenHostelsProvider` into a permanent error state and blanked
/// every hostel picker downstream — the warden could not open the
/// create-student form at all.
void main() {
  // Captured verbatim from a live `GET /api/v1/warden/hostels`.
  const geofencePayload = '''
[
  {
    "hostel_id": "95bb0f53-1423-4f15-b2f4-f0f916d761eb",
    "name": "Ganga Boys Hostel",
    "block": "B",
    "anchor_label": "Ganga Block B",
    "latitude": 12.9716,
    "longitude": 79.1585,
    "permitted_radius_m": 120.0,
    "max_location_accuracy_m": 50.0,
    "boundary_policy": "conservative",
    "timezone": "Asia/Kolkata",
    "window_start": "20:30",
    "window_end": "22:30",
    "require_liveness": true,
    "face_match_threshold": 0.75,
    "warden_name": "Dr. K. Raman",
    "warden_extension": "204"
  }
]
''';

  // The compact summary the dashboard embeds per hostel.
  const dashboardSummary = '''
{
  "id": "95bb0f53-1423-4f15-b2f4-f0f916d761eb",
  "name": "Ganga Boys Hostel",
  "block": "B",
  "room": null,
  "students": 4,
  "window": "20:30–22:30"
}
''';

  group('WardenHostel parses GET /warden/hostels (hostel_id)', () {
    test('reads the id from hostel_id instead of throwing', () {
      final list = jsonDecode(geofencePayload) as List;
      final hostels = [
        for (final h in list) WardenHostel.fromJson(h as Map<String, dynamic>),
      ];

      expect(hostels, hasLength(1));
      expect(hostels.single.id, '95bb0f53-1423-4f15-b2f4-f0f916d761eb');
      expect(hostels.single.name, 'Ganga Boys Hostel');
      expect(hostels.single.block, 'B');
      expect(hostels.single.label, 'Ganga Boys Hostel · Block B');
    });

    test('keeps the geofence numbers the screens display', () {
      final h = WardenHostel.fromJson(
        (jsonDecode(geofencePayload) as List).first as Map<String, dynamic>,
      );
      expect(h.latitude, closeTo(12.9716, 1e-9));
      expect(h.longitude, closeTo(79.1585, 1e-9));
      expect(h.radiusM, 120.0);
      expect(h.windowStart, '20:30');
      expect(h.windowEnd, '22:30');
    });
  });

  group('WardenHostel parses the dashboard compact summary (id)', () {
    test('still reads the id from id', () {
      final h = WardenHostel.fromJson(
        jsonDecode(dashboardSummary) as Map<String, dynamic>,
      );
      expect(h.id, '95bb0f53-1423-4f15-b2f4-f0f916d761eb');
      expect(h.name, 'Ganga Boys Hostel');
      expect(h.block, 'B');
      // The summary carries a pre-joined window string, not the two halves.
      expect(h.windowStart, isNull);
      expect(h.windowEnd, isNull);
    });
  });

  group('WardenHostel fails soft on a malformed payload', () {
    test('a missing id becomes an empty string, never a TypeError', () {
      final h = WardenHostel.fromJson(const {'name': 'No Id Hostel'});
      expect(h.id, '');
      expect(h.name, 'No Id Hostel');
      expect(h.label, 'No Id Hostel');
    });

    test('a missing name becomes an empty string, never a TypeError', () {
      final h = WardenHostel.fromJson(const {
        'id': 'abc',
        'block': null,
      });
      expect(h.id, 'abc');
      expect(h.name, '');
    });
  });

  group('WardenDashboard embeds the compact summary safely', () {
    test('parses a dashboard payload carrying the id-keyed hostels', () {
      final dashboard = WardenDashboard.fromJson(const {
        'total_students': 4,
        'active_students': 2,
        'pending_enrollment': 2,
        'face_enrolled': 2,
        'suspended_students': 0,
        'hostels': [
          {
            'id': '95bb0f53-1423-4f15-b2f4-f0f916d761eb',
            'name': 'Ganga Boys Hostel',
            'block': 'B',
            'room': null,
            'students': 4,
            'window': '20:30–22:30',
          },
        ],
        'recent_activity': <Map<String, dynamic>>[],
        'attendance_today': <String, dynamic>{},
      });

      expect(dashboard.totalStudents, 4);
      expect(dashboard.hostels.single.id,
          '95bb0f53-1423-4f15-b2f4-f0f916d761eb');
      expect(dashboard.hostels.single.name, 'Ganga Boys Hostel');
    });
  });
}
