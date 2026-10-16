import 'package:flutter_test/flutter_test.dart';
import 'package:hostelpass_warden/core/validation/college_email.dart';

/// Requirement: the create-student form validates the college email against
/// the EXACT @ceconline.edu domain — no substring matching on either side.
///
/// This rule applies to STUDENT emails only; warden sign-in deliberately
/// accepts any staff username (see login_payload_test.dart).
void main() {
  group('isCollegeEmail — exact domain match', () {
    const valid = <String>[
      'student@ceconline.edu',
      'Student@ceconline.edu',
      '  padded@ceconline.edu  ',
      'f.l.dash+tag@ceconline.edu',
      'a@ceconline.edu',
    ];
    const invalid = <String>[
      'student@gmail.com',
      'student@ceconline.com',
      'student@ceconline.edu.example.com',
      'student@xceconline.edu',
      'student@sub.ceconline.edu',
      'student@CECONLINE.EDU.example.com',
      'student@host.ceconline.edu',
      'plainaddress',
      'student@',
      '@ceconline.edu',
      'student @ceconline.edu',
      'two@at@ceconline.edu',
    ];

    for (final email in valid) {
      test('accepts "$email"', () {
        expect(isCollegeEmail(email), isTrue);
      });
    }

    for (final email in invalid) {
      test('rejects "$email"', () {
        expect(isCollegeEmail(email), isFalse);
      });
    }

    test('rejects a lookalike whose hostname merely CONTAINS the domain', () {
      // A substring check would wrongly accept all of these.
      expect(isCollegeEmail('x@ceconline.edu.attacker.com'), isFalse);
      expect(isCollegeEmail('x@notceconline.edu'), isFalse);
      expect(isCollegeEmail('x@ceconline.edu.evil.io'), isFalse);
    });

    test('rejects the x@sub.ceconline.edu subdomain case explicitly', () {
      expect(isCollegeEmail('x@sub.ceconline.edu'), isFalse);
      expect(isCollegeEmail('x@ceconline.edu'), isTrue);
    });
  });

  group('collegeEmailDomain constant', () {
    test('is exactly ceconline.edu', () {
      expect(collegeEmailDomain, 'ceconline.edu');
    });
  });
}
