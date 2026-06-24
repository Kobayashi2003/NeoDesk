import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'frame_override.dart';
import 'session_controller.dart';

/// Renders the remote frame. In the real app this is the [FrameSource]-backed
/// Texture/RGBA widget (the perf-critical path we must NOT rewrite — see
/// DESIGN.md §0). Here it's a placeholder "fake desktop" so the gesture /
/// transform plumbing is visible and testable.
class FrameLayer extends StatelessWidget {
  const FrameLayer({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    // Real-engine integration injects the actual render widget here.
    final override = neodeskFrameOverride;
    if (override != null) return override(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final t = controller.canvas;
        return ClipRect(
          child: Transform(
            transform: Matrix4.identity()
              ..translate(t.offsetX, t.offsetY)
              ..scale(t.scale),
            child: const _FakeDesktop(),
          ),
        );
      },
    );
  }
}

class _FakeDesktop extends StatelessWidget {
  const _FakeDesktop();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B3A5B), Color(0xFF2D2A55), Color(0xFF1B3A5B)],
        ),
      ),
      child: CustomPaint(
        painter: _GridPainter(),
        child: Stack(
          children: [
            // A couple of fake windows so pan/zoom is obvious.
            _window(const Offset(60, 120), const Size(220, 150), 'Explorer'),
            _window(const Offset(180, 320), const Size(260, 170), 'Terminal'),
            // Fake taskbar.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 40,
                color: Colors.black.withOpacity(0.55),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.window, color: Colors.white70, size: 20),
                    const SizedBox(width: 12),
                    Container(width: 36, height: 22, color: Colors.white12),
                    const SizedBox(width: 8),
                    Container(width: 36, height: 22, color: Colors.white12),
                    const Spacer(),
                    const Text('14:32',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _window(Offset pos, Size size, String title) => Positioned(
        left: pos.dx,
        top: pos.dy,
        child: Container(
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F3F3),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 16, spreadRadius: 2)
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.black87, fontSize: 12)),
                    const Spacer(),
                    const Icon(Icons.close, size: 14, color: Colors.black54),
                  ],
                ),
              ),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textPrimary.withOpacity(0.05)
      ..strokeWidth = 1;
    const step = 48.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
