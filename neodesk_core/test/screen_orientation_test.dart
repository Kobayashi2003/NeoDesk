import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neodesk_core/neodesk_core.dart';
import 'package:neodesk_core/ui/demo/fake_core.dart';
import 'package:neodesk_core/ui/session/gestures/interaction_ui_mode.dart';
import 'package:neodesk_core/ui/session/session_controller.dart';

/// A forced orientation outlives the page unless released, leaving the rest of
/// the app stuck sideways.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<List<String>> requests;

  setUp(() {
    requests = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        requests.add(List<String>.from(call.arguments as List));
      }
      return null;
    });
  });

  SessionController controller([String setting = '']) {
    final core = FakeCore();
    core.config.set(ConfigKeys.sessionOrientation, setting);
    return SessionController(
      core: core,
      session: core.sessions.create(),
      peerId: 'test',
      initialMode: InteractionUiMode.pointer,
    );
  }

  const landscape = [
    'DeviceOrientation.landscapeLeft',
    'DeviceOrientation.landscapeRight',
  ];
  const portrait = ['DeviceOrientation.portraitUp'];

  test('follow system: nothing is forced, nothing to release', () {
    final c = controller('system');
    expect(c.orientationLocked, isFalse);
    c.dispose();
    expect(requests, isEmpty);
  });

  test('the setting holds the orientation from session start', () {
    final c = controller('landscape');
    expect(c.orientationLocked, isTrue);
    expect(requests, [landscape]);
  });

  test('rotate goes to the other orientation', () {
    final c = controller();
    c.rotateScreen(landscape: false);
    c.rotateScreen(landscape: true);
    expect(requests, [landscape, portrait]);
  });

  test('follow system releases the hold', () {
    final c = controller('portrait');
    c.followSystemOrientation();
    expect(c.orientationLocked, isFalse);
    expect(requests.last, isEmpty);
  });

  test('leaving the session releases the hold', () {
    final c = controller();
    c.rotateScreen(landscape: false);
    c.dispose();
    expect(requests.last, isEmpty);
  });
}
