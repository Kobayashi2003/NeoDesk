import 'package:flutter/material.dart';
import 'package:neodesk_core/neodesk_core.dart';

import 'ui/demo/fake_core.dart';
import 'ui/home/home_shell.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/app_typography.dart';

/// Standalone demo on [FakeCore]. The real app starts from
/// `overlay/lib/neodesk/launcher.dart` with the engine adapter.
void main() => runApp(NeodeskApp(core: FakeCore()));

class NeodeskApp extends StatelessWidget {
  const NeodeskApp({super.key, required this.core});

  final NeodeskCore core;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neodesk',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      // Mirrors NeodeskEntry: the Font-size setting scales the whole UI.
      builder: (context, child) => ValueListenableBuilder<double>(
        valueListenable: appTextScale,
        builder: (context, scale, __) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
      home: HomeShell(core: core),
    );
  }
}
