import 'package:flutter/material.dart';
import 'package:neodesk_core/neodesk_core.dart';

import '../theme/app_colors.dart';
import 'devices_page.dart';
import 'settings_page.dart';

/// Bottom-tab shell: Devices / Settings. The app is a remote-control **client**
/// only (no hosting / be-controlled mode).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.core});

  final NeodeskCore core;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      DevicesPage(core: widget.core),
      SettingsPage(core: widget.core),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          items: [
            BottomNavigationBarItem(
                icon: const Icon(Icons.devices_outlined),
                activeIcon: const Icon(Icons.devices),
                label: tr('Devices')),
            BottomNavigationBarItem(
                icon: const Icon(Icons.settings_outlined),
                activeIcon: const Icon(Icons.settings),
                label: tr('Settings')),
          ],
        ),
      ),
    );
  }
}
