import 'package:flutter/material.dart';

import '../theme/app_typography.dart';
import '../theme/dimens.dart';

/// Bold section title with optional trailing action. See DESIGN.md §4.1.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Dimens.pageInset, Dimens.s24, Dimens.pageInset, Dimens.s12),
      child: Row(
        children: [
          Expanded(child: Text(title, style: AppTypography.title)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
