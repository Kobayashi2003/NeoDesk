import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neodesk_core/neodesk_core.dart';
import 'package:neodesk_core/ui/demo/fake_core.dart';
import 'package:neodesk_core/ui/session/chrome/overlay_chrome.dart';
import 'package:neodesk_core/ui/session/gestures/interaction_ui_mode.dart';
import 'package:neodesk_core/ui/session/session_controller.dart';

/// Both bars hold rows of fixed-width buttons, which overflowed on a narrow
/// portrait screen with large text.
void main() {
  testWidgets('both bars fit a narrow portrait screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final core = FakeCore();
    final c = SessionController(
      core: core,
      session: core.sessions.create(),
      peerId: 'test',
      initialMode: InteractionUiMode.pointer,
    )..peer = const PeerRuntimeInfo(
        platform: 'Windows',
        isAndroid: false,
        currentDisplay: 0,
        displayCount: 2,
      );

    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
            size: Size(320, 640), textScaler: TextScaler.linear(1.6)),
        child: Scaffold(
          body: OverlayChrome(
              controller: c, peerName: 'Office Desktop', onClose: () {}),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.screen_rotation), findsOneWidget);

    // Cancels the demo session's periodic stats before the timer check.
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
