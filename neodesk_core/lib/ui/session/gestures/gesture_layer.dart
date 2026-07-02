import 'package:flutter/widgets.dart';

import 'gesture_pad.dart';
import '../session_controller.dart';

/// Hosts the in-session input surface and keeps the controller's viewport size
/// current. Both interaction modes share one raw-[Listener] state machine
/// ([GesturePad] → GestureEngine); the mode only changes how a gesture is
/// executed, not how it's recognised. See DESIGN.md §4.
class GestureLayer extends StatelessWidget {
  const GestureLayer({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      controller.bindViewport(constraints.biggest);
      return GesturePad(controller: controller);
    });
  }
}
