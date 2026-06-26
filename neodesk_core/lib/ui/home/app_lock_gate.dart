import 'package:flutter/material.dart';
import 'package:neodesk_core/neodesk_core.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/dimens.dart';

/// Gates the whole app behind a device unlock (biometric / PIN / pattern) when
/// the app-lock setting is on. Locks on cold launch; if the prompt is dismissed
/// the user re-authenticates with the Unlock button. (Off by default; in the
/// demo [NeodeskCore.authenticateAppLock] returns true so this is a pass-through.)
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.core, required this.child});

  final NeodeskCore core;
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _authing = false;

  bool get _lockEnabled => widget.core.config.getBool(ConfigKeys.appLock);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!_lockEnabled) {
      _unlocked = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_lockEnabled || _authing) return;
    // Re-lock whenever we leave the foreground, then re-prompt on return — so a
    // once-unlocked app doesn't stay open across app switches. The auth prompt
    // itself backgrounds us, but [_authing] guards that above.
    if (state == AppLifecycleState.paused && _unlocked) {
      setState(() => _unlocked = false);
    } else if (state == AppLifecycleState.resumed && !_unlocked) {
      _authenticate();
    }
  }

  Future<void> _authenticate() async {
    if (_authing) return;
    setState(() => _authing = true);
    final ok = await widget.core.authenticateAppLock();
    if (!mounted) return;
    setState(() {
      _unlocked = ok;
      _authing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline,
                size: 56, color: AppColors.textSecondary),
            const SizedBox(height: Dimens.s16),
            Text(tr('NeoDesk is locked'), style: AppTypography.body),
            const SizedBox(height: Dimens.s24),
            if (_authing)
              const CircularProgressIndicator(color: AppColors.accent)
            else
              ElevatedButton.icon(
                onPressed: _authenticate,
                icon: const Icon(Icons.fingerprint),
                label: Text(tr('Unlock')),
              ),
          ],
        ),
      ),
    );
  }
}
