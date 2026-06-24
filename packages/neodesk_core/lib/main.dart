import 'package:flutter/material.dart';
import 'package:neodesk_core/neodesk_core.dart';

import 'ui/demo/fake_core.dart';
import 'ui/home/home_shell.dart';
import 'ui/theme/app_theme.dart';

void main() {
  // Stage 1 runs on the in-memory FakeCore so the UI/gesture layer works with
  // no native engine. Swap in the real RustDesk adapter here later (docs §8).
  final NeodeskCore core = FakeCore();
  runApp(NeodeskApp(core: core));
}

class NeodeskApp extends StatelessWidget {
  const NeodeskApp({super.key, required this.core});

  final NeodeskCore core;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neodesk',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: HomeShell(core: core),
    );
  }
}
