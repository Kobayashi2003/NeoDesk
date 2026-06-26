import 'package:flutter/material.dart';
import 'package:neodesk_core/neodesk_core.dart' show tr, trArg;

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../theme/dimens.dart';
import 'interaction_ui_mode.dart';

typedef _Row = ({IconData icon, String gesture, String result});

const Map<InteractionUiMode, List<_Row>> _help = {
  InteractionUiMode.touch: [
    (
      icon: Icons.touch_app,
      gesture: 'One-finger tap',
      result: 'Left click at point'
    ),
    (icon: Icons.touch_app, gesture: 'Double tap', result: 'Double click'),
    (icon: Icons.swipe, gesture: 'One-finger drag', result: 'Move cursor'),
    (
      icon: Icons.ads_click,
      gesture: 'Long press, then drag',
      result: 'Left-button drag (select / move)'
    ),
    (
      icon: Icons.swap_horiz,
      gesture: 'Two-finger horizontal drag',
      result: 'Pan the view'
    ),
    (
      icon: Icons.unfold_more,
      gesture: 'Two-finger vertical drag',
      result: 'Scroll wheel'
    ),
    (icon: Icons.pinch, gesture: 'Two-finger pinch', result: 'Zoom view'),
    (
      icon: Icons.menu,
      gesture: 'Three-finger tap',
      result: 'Custom (Settings → gestures)'
    ),
    (
      icon: Icons.keyboard,
      gesture: 'Four-finger tap',
      result: 'Custom (Settings → gestures)'
    ),
  ],
  InteractionUiMode.pointer: [
    (
      icon: Icons.swipe,
      gesture: 'One-finger drag',
      result: 'Move cursor (auto-pan at edges)'
    ),
    (icon: Icons.touch_app, gesture: 'One-finger tap', result: 'Left click'),
    (icon: Icons.touch_app, gesture: 'Double tap', result: 'Double click'),
    (
      icon: Icons.ads_click,
      gesture: 'Long press, then drag',
      result: 'Grab: hold left to drag / select'
    ),
    (icon: Icons.back_hand, gesture: 'Two-finger tap', result: 'Right click'),
    (
      icon: Icons.swap_horiz,
      gesture: 'Two-finger horizontal drag',
      result: 'Pan the view'
    ),
    (
      icon: Icons.unfold_more,
      gesture: 'Two-finger vertical drag',
      result: 'Scroll wheel'
    ),
    (icon: Icons.pinch, gesture: 'Two-finger pinch', result: 'Zoom view'),
    (
      icon: Icons.menu,
      gesture: 'Three-finger tap',
      result: 'Custom (Settings → gestures)'
    ),
    (
      icon: Icons.keyboard,
      gesture: 'Four-finger tap',
      result: 'Custom (Settings → gestures)'
    ),
  ],
};

/// Bottom sheet documenting the gestures for [mode] (DESIGN.md).
void showGestureHelp(BuildContext context, InteractionUiMode mode) {
  final rows = _help[mode] ?? const [];
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(Dimens.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.gesture, color: AppColors.accent),
                const SizedBox(width: Dimens.s8),
                Text(trArg('{} gestures', mode.label),
                    style: AppTypography.title),
              ]),
              const SizedBox(height: Dimens.s16),
              ...rows.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: Dimens.s8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(r.icon, size: 20, color: AppColors.textSecondary),
                      const SizedBox(width: Dimens.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr(r.gesture), style: AppTypography.body),
                            Text(tr(r.result), style: AppTypography.caption),
                          ],
                        ),
                      ),
                    ],
                  ),
                  )),
            ],
          ),
        ),
      ),
    ),
  );
}
