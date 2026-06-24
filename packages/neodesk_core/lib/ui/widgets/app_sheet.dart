import 'package:flutter/material.dart';

/// A modal bottom sheet that never overflows: [isScrollControlled] lets it grow
/// past half-height, and the content scrolls inside a [SingleChildScrollView]
/// (so long option lists stay usable in landscape). Pass the inner content via
/// [body] — it is wrapped in [SafeArea] + scroll automatically.
Future<T?> showAppSheet<T>(BuildContext context, WidgetBuilder body) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(child: body(ctx)),
      ),
    );
