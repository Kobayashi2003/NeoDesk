import 'package:flutter/widgets.dart';

import 'interaction_ui_mode.dart';
import 'pointer_pad.dart';
import '../session_controller.dart';
import 'touch_pad.dart';

/// Dispatches the active input surface by mode and keeps the controller's
/// viewport size current.
///
/// Both surfaces are raw-[Listener] state machines (no recognizer-arena delays):
/// **Pointer** mode uses [PointerPad] (relative trackpad), **Touch** mode uses
/// [TouchPad] (absolute "tap where you touch"). See DESIGN.md §4.
class GestureLayer extends StatelessWidget {
  const GestureLayer({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      controller.bindViewport(constraints.biggest);
      return controller.mode == InteractionUiMode.pointer
          ? PointerPad(controller: controller)
          : TouchPad(controller: controller);
    });
  }
}
