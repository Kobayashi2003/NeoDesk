import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'session_controller.dart';

/// Draws the local virtual cursor at [SessionController.cursorScreen] (computed
/// from the image-space cursor through the live canvas transform, so it rides
/// the zoomed/panned image correctly — DESIGN.md §3.1 / §6).
///
/// Shown always in Pointer mode; in Touch mode only on the FakeCore demo (the
/// real peer renders its own cursor). Gated by [SessionController.showLocalCursor].
class CursorLayer extends StatelessWidget {
  const CursorLayer({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (!controller.showLocalCursor || controller.viewport.isEmpty) {
            return const SizedBox.shrink();
          }
          final p = controller.cursorScreen;
          return Positioned(
            left: p.dx,
            top: p.dy,
            child:
                CustomPaint(size: const Size(26, 32), painter: _ArrowPainter()),
          );
        },
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, size.height * 0.78)
      ..lineTo(size.width * 0.28, size.height * 0.60)
      ..lineTo(size.width * 0.46, size.height)
      ..lineTo(size.width * 0.62, size.height * 0.92)
      ..lineTo(size.width * 0.44, size.height * 0.54)
      ..lineTo(size.width * 0.74, size.height * 0.54)
      ..close();

    canvas.drawShadow(path, Colors.black, 4, true);
    // White outline for contrast on any background, accent-green fill (on-brand).
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
    canvas.drawPath(path, Paint()..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
