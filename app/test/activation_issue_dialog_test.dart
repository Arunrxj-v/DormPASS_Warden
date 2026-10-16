import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostelpass_warden/features/warden/student_detail_screen.dart';
import 'package:hostelpass_warden/features/warden/warden_models.dart';

/// The mandated warden workflow: after issuing an activation key the warden
/// copies it with one tap and pastes it into WhatsApp for the student. These
/// tests drive exactly the dialog the warden sees: the key is displayed, the
/// Copy Key action puts the KEY on the clipboard and confirms with
/// "Activation key copied.", and the activation email stays a SECONDARY
/// delivery path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Representative shape of secrets.token_urlsafe(32): urlsafe base64, so
  // `-` and `_` are legitimate KEY characters and must survive verbatim.
  const key = 'aB3_-xY9_zQ1wS2kL4mN6pR8uV0-_TgH_JkLmnopQrstuvwxyz12';

  Future<void> pumpDialog(WidgetTester tester, ActivationIssue issue) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActivationIssueDialog(
            issue: issue,
            studentName: 'Rahul Kumar',
            studentEmail: 'rahul@ceconline.edu',
            verb: 'Activation key issued',
          ),
        ),
      ),
    );
  }

  group('ActivationIssueDialog (WhatsApp key hand-off)', () {
    testWidgets('shows student, key, Copy Key and the WhatsApp instruction',
        (tester) async {
      final issue = ActivationIssue(
        enrollmentStatus: 'account_provisioned',
        activationPending: true,
        delivered: false,
        emailStatus: 'not_configured',
        expiresAt: '2026-10-22T10:00:00Z',
        activationToken: key,
        setupUrl: 'hostelpass://activate?token=$key',
      );
      await pumpDialog(tester, issue);

      expect(find.text('Activation key issued'), findsOneWidget);
      expect(find.text('Rahul Kumar'), findsOneWidget);
      expect(find.text(key), findsOneWidget); // the raw key, selectable
      expect(find.text('Copy Key'), findsOneWidget);
      expect(
        find.text('Send this key to the student through WhatsApp.'),
        findsOneWidget,
      );
      // Email demoted to secondary — present, but below the key.
      expect(
        find.textContaining('not configured on this deployment'),
        findsOneWidget,
      );
    });

    testWidgets('Copy Key puts the KEY on the clipboard and confirms',
        (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final issue = ActivationIssue(
        enrollmentStatus: 'account_provisioned',
        activationPending: true,
        delivered: false,
        emailStatus: 'logged', // secondary path reported honestly
        activationToken: key,
      );
      await pumpDialog(tester, issue);

      await tester.tap(find.text('Copy Key'));
      await tester.pump(); // start the copy
      await tester.pump(const Duration(milliseconds: 750)); // snackbar show

      final setData =
          calls.where((c) => c.method == 'Clipboard.setData').toList();
      expect(setData, isNotEmpty);
      // The KEY itself is copied — not the deep link — so the student can
      // paste it straight into the app.
      expect((setData.first.arguments as Map)['text'], key);
      expect(find.text('Activation key copied.'), findsOneWidget);
    });

    testWidgets('without an inline key the email stays the only path',
        (tester) async {
      const issue = ActivationIssue(
        enrollmentStatus: 'account_provisioned',
        activationPending: true,
        delivered: false,
        emailStatus: 'not_configured',
      );
      await pumpDialog(tester, issue);

      expect(find.text('Copy Key'), findsNothing);
      expect(
        find.textContaining('not configured on this deployment'),
        findsOneWidget,
      );
      // No key section is rendered when the server withheld the key.
      expect(find.text('ACTIVATION KEY'), findsNothing);
      expect(find.text('Rahul Kumar'), findsNothing);
    });
  });
}
