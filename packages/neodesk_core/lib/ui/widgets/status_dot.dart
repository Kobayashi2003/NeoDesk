import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Small online/offline indicator dot. See DESIGN.md §4.1.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.online, this.size = 9});

  final bool online;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = online ? AppColors.online : AppColors.offline;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: online
            ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 6)]
            : null,
      ),
    );
  }
}
