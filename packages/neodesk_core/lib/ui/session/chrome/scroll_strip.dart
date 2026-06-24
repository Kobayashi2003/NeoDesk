import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/dimens.dart';
import '../session_controller.dart';

/// Auxiliary scroll control: a small thumb on the right edge that you pull up or
/// down to scroll. Drag distance accumulates into wheel notches (respecting the
/// scroll speed + invert settings); the thumb follows your finger within a short
/// track and springs back to centre on release. See DESIGN.md §4.5.
class ScrollStrip extends StatefulWidget {
  const ScrollStrip({super.key, required this.controller, required this.bounds});

  final SessionController controller;
  final Size bounds;

  @override
  State<ScrollStrip> createState() => _ScrollStripState();
}

class _ScrollStripState extends State<ScrollStrip> {
  static const double _trackW = 40;
  static const double _trackH = 132;
  static const double _thumbW = 30;
  static const double _thumbH = 52;
  static const double _range = (_trackH - _thumbH) / 2;

  double _accum = 0;
  double _offset = 0; // thumb displacement from centre
  bool _dragging = false;

  void _onUpdate(DragUpdateDetails d) {
    _accum += d.delta.dy;
    final step = widget.controller.scrollStep;
    while (_accum.abs() >= step) {
      widget.controller.scrollBy(_accum > 0 ? -1 : 1);
      _accum += _accum > 0 ? -step : step;
    }
    setState(() => _offset = (_offset + d.delta.dy).clamp(-_range, _range));
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final top = (widget.bounds.height - _trackH) / 2;
    final right = mq.padding.right + Dimens.s8;

    return Positioned(
      right: right,
      top: top,
      child: GestureDetector(
        onVerticalDragStart: (_) {
          _accum = 0;
          setState(() => _dragging = true);
        },
        onVerticalDragUpdate: _onUpdate,
        onVerticalDragEnd: (_) => setState(() {
          _dragging = false;
          _offset = 0; // spring back to centre
        }),
        child: Container(
          width: _trackW,
          height: _trackH,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.30),
            borderRadius: BorderRadius.circular(_trackW / 2),
            border: Border.all(color: AppColors.border),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration:
                    _dragging ? Duration.zero : const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                left: (_trackW - _thumbW) / 2,
                top: (_trackH - _thumbH) / 2 + _offset,
                child: Container(
                  width: _thumbW,
                  height: _thumbH,
                  decoration: BoxDecoration(
                    color: _dragging
                        ? AppColors.accent
                        : AppColors.bgElevated2.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(_thumbW / 2),
                    border: Border.all(
                        color: _dragging ? AppColors.accent : AppColors.border),
                  ),
                  child: Icon(Icons.unfold_more,
                      size: 20,
                      color: _dragging
                          ? AppColors.textOnAccent
                          : AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
