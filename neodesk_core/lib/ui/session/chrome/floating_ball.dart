import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/dimens.dart';

/// Draggable handle that restores the hidden toolbar.
///
/// Shown only while the toolbar (chrome) is hidden — **tap** reveals the toolbar,
/// **drag** moves it. It snaps to the nearest side edge and keeps clear of the
/// notch, the system bars and the on-screen keyboard, re-snapping itself when the
/// screen rotates or those insets change. See DESIGN.md §4.5.
class FloatingBall extends StatefulWidget {
  const FloatingBall({
    super.key,
    required this.bounds,
    required this.onTap,
    this.visible = true,
  });

  /// The full layer size (from the session's LayoutBuilder).
  final Size bounds;

  /// Reveal-toolbar callback (tap).
  final VoidCallback onTap;

  /// Hidden (but kept mounted, so position survives) while the toolbar is shown.
  final bool visible;

  @override
  State<FloatingBall> createState() => _FloatingBallState();
}

class _FloatingBallState extends State<FloatingBall> {
  static const double _margin = 8.0;

  Offset _pos = Offset.zero;
  bool _ready = false;
  bool _dragging = false;

  double get _size => Dimens.ballSize;

  /// Horizontal travel limits, inset past side cutouts / system bars.
  (double, double) _xRange() {
    final mq = MediaQuery.of(context);
    final minX = mq.padding.left + _margin;
    final maxX = widget.bounds.width - mq.padding.right - _size - _margin;
    return (minX, math.max(minX, maxX));
  }

  /// Vertical travel limits, kept clear of the status bar, nav bar and keyboard.
  (double, double) _yRange() {
    final mq = MediaQuery.of(context);
    final minY = mq.padding.top + _margin;
    final reserveBottom = math.max(mq.padding.bottom, mq.viewInsets.bottom);
    final maxY = widget.bounds.height - reserveBottom - _size - _margin;
    return (minY, math.max(minY, maxY));
  }

  Offset _clamp(Offset p) {
    final (minX, maxX) = _xRange();
    final (minY, maxY) = _yRange();
    return Offset(p.dx.clamp(minX, maxX), p.dy.clamp(minY, maxY));
  }

  /// Clamp into the safe rect and snap x to whichever side edge is nearer.
  void _snap() {
    final (minX, maxX) = _xRange();
    final p = _clamp(_pos);
    _pos = Offset(p.dx < (minX + maxX) / 2 ? minX : maxX, p.dy);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_ready) {
      final (_, maxX) = _xRange();
      final (minY, maxY) = _yRange();
      _pos = Offset(maxX, minY + (maxY - minY) * 0.18); // start: upper-right edge
      _ready = true;
    } else {
      _snap(); // MediaQuery changed (rotation / inset change)
    }
  }

  @override
  void didUpdateWidget(FloatingBall old) {
    super.didUpdateWidget(old);
    if (old.bounds != widget.bounds) _snap();
  }

  @override
  Widget build(BuildContext context) {
    final pos = _clamp(_pos);
    return AnimatedPositioned(
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      left: pos.dx,
      top: pos.dy,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: IgnorePointer(
          ignoring: !widget.visible,
          child: GestureDetector(
            onTap: widget.onTap,
            onPanStart: (_) => setState(() => _dragging = true),
            onPanUpdate: (d) => setState(() => _pos = _clamp(_pos + d.delta)),
            onPanEnd: (_) => setState(() {
              _dragging = false;
              _snap();
            }),
            child: Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                color: AppColors.bgElevated2.withOpacity(0.9),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accent.withOpacity(0.7)),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
                ],
              ),
              child: Icon(Icons.drag_indicator, color: AppColors.accent),
            ),
          ),
        ),
      ),
    );
  }
}
