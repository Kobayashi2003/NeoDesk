import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/dimens.dart';

/// Fully-rounded Spotify-style action button. Green fill, black label, with a
/// subtle press-scale. See DESIGN.md §2.3 / §7.
class PillButton extends StatefulWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.filled = true,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Filled = green primary; otherwise outlined/ghost.
  final bool filled;
  final bool dense;

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final bg = widget.filled
        ? (_down ? AppColors.accentPressed : AppColors.accent)
        : Colors.transparent;
    final fg = widget.filled ? AppColors.textOnAccent : AppColors.textPrimary;

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.45,
          duration: const Duration(milliseconds: 120),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: widget.dense ? Dimens.s16 : Dimens.s24,
              vertical: widget.dense ? Dimens.s8 : Dimens.s12,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(Dimens.rPill),
              border: widget.filled
                  ? null
                  : Border.all(color: AppColors.border, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 18, color: fg),
                  const SizedBox(width: Dimens.s8),
                ],
                Text(widget.label,
                    style: AppTypography.button.copyWith(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
