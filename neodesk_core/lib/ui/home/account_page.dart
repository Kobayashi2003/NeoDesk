import 'package:flutter/material.dart';
import 'package:neodesk_core/neodesk_core.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/dimens.dart';

/// Sign in to a RustDesk account.
///
/// RustDesk's public servers require an account before ID ("remote code")
/// connections are allowed, and they accept **only third-party sign-in** — see
/// [AccountPort]. So this page is a list of whatever providers the server
/// advertises, plus the signed-in state. Direct-IP peers don't need any of it,
/// which is why nothing here gates the rest of the app.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.core});

  final NeodeskCore core;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  AccountUser? _user;

  List<AuthProvider>? _providers; // null = still loading
  AuthProvider? _busyWith; // non-null while a sign-in runs
  String _status = '';
  String? _error;
  bool _leaving = false; // signing out

  AccountPort get _account => widget.core.account;

  @override
  void initState() {
    super.initState();
    _user = _account.current;
    if (_user == null) _loadProviders();
  }

  Future<void> _loadProviders() async {
    final list = await _account.providers();
    if (!mounted) return;
    setState(() => _providers = list);
  }

  Future<void> _signIn(AuthProvider provider) async {
    if (_busyWith != null) return;
    setState(() {
      _busyWith = provider;
      _status = '';
      _error = null;
    });

    final outcome = await _account.signInWith(
      provider,
      onStatus: (s) {
        if (mounted && _busyWith != null) setState(() => _status = s);
      },
    );
    if (!mounted) return;

    setState(() {
      _busyWith = null;
      _status = '';
      switch (outcome) {
        case SignInSucceeded(:final user):
          _user = user;
        case SignInFailed(:final message):
          _error = message;
        case SignInCancelled():
          break; // the user backed out; say nothing
      }
    });
  }

  Future<void> _cancel() async {
    await _account.cancelSignIn();
    if (!mounted) return;
    setState(() {
      _busyWith = null;
      _status = '';
    });
  }

  Future<void> _signOut() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await _account.logout();
    if (!mounted) return;
    setState(() {
      _leaving = false;
      _user = null;
      _error = null;
    });
    _loadProviders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Account'), style: AppTypography.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Dimens.pageInset),
          children: _user != null ? _signedIn(_user!) : _signIn_(),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- signed in

  List<Widget> _signedIn(AccountUser user) => [
        const SizedBox(height: Dimens.s16),
        Center(child: _Avatar(user: user)),
        const SizedBox(height: Dimens.s16),
        Center(
          child: Text(user.label,
              style: AppTypography.title, textAlign: TextAlign.center),
        ),
        if (user.labelWithHandle != user.label) ...[
          const SizedBox(height: Dimens.s4),
          Center(child: Text('@${user.name}', style: AppTypography.caption)),
        ],
        const SizedBox(height: Dimens.s32),
        _note(tr('Signed in — remote-code connections are available.')),
        const SizedBox(height: Dimens.s24),
        _wideButton(
          label: tr('Sign out'),
          onPressed: _signOut,
          busy: _leaving,
          color: AppColors.danger,
        ),
      ];

  // --------------------------------------------------------------- signing in

  List<Widget> _signIn_() {
    final providers = _providers;
    return [
      const SizedBox(height: Dimens.s8),
      _note(tr('RustDesk requires an account before connecting by remote code. '
          'Direct IP connections work without one.')),
      const SizedBox(height: Dimens.s24),
      if (providers == null)
        const Center(child: Padding(
          padding: EdgeInsets.all(Dimens.s24),
          child: SizedBox(
              width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        ))
      else if (providers.isEmpty)
        _note(tr('This server offers no sign-in providers, or it could not be '
            'reached.'))
      else
        for (final p in providers) ...[
          _ProviderButton(
            provider: p,
            busy: _busyWith == p,
            enabled: _busyWith == null,
            onPressed: () => _signIn(p),
          ),
          const SizedBox(height: Dimens.s12),
        ],
      if (_busyWith != null) ...[
        const SizedBox(height: Dimens.s8),
        _note(_status.isEmpty ? tr('Waiting for the browser…') : tr(_status)),
        const SizedBox(height: Dimens.s8),
        Center(
          child: TextButton(onPressed: _cancel, child: Text(tr('Cancel'))),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: Dimens.s12),
        Text(
          tr(_error!),
          style: AppTypography.caption.copyWith(color: AppColors.danger),
          textAlign: TextAlign.center,
        ),
      ],
      const SizedBox(height: Dimens.s24),
      _note(tr('Your account is your provider identity — signing in the first '
          'time creates it. There is nothing to register.')),
    ];
  }

  // ------------------------------------------------------------------- pieces

  Widget _note(String text) => Text(
        text,
        style: AppTypography.caption,
        textAlign: TextAlign.center,
      );

  Widget _wideButton({
    required String label,
    required VoidCallback onPressed,
    required bool busy,
    required Color color,
  }) =>
      SizedBox(
        height: 48,
        child: ElevatedButton(
          onPressed: busy ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: AppColors.textOnAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Dimens.rPill),
            ),
          ),
          child: busy
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.textOnAccent),
                )
              : Text(label, style: AppTypography.body),
        ),
      );
}

/// One "Continue with X" button.
///
/// The icon is picked from the engine's bundled `auth-*.svg` set by provider id;
/// an unknown id falls back to a generic key icon rather than a broken asset.
class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.provider,
    required this.busy,
    required this.enabled,
    required this.onPressed,
  });

  final AuthProvider provider;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;

  static const _icons = <String, IconData>{
    'google': Icons.g_mobiledata,
    'github': Icons.code,
    'microsoft': Icons.window,
    'apple': Icons.apple,
    'gitlab': Icons.merge_type,
    'facebook': Icons.facebook,
    'okta': Icons.shield_outlined,
    'auth0': Icons.shield_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.accent),
              )
            : Icon(_icons[provider.id.toLowerCase()] ?? Icons.vpn_key_outlined,
                size: 20),
        label: Text(
          trArg('Continue with {}', provider.label),
          style: AppTypography.body,
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Dimens.rPill),
          ),
        ),
      ),
    );
  }
}

/// The account's initial in an accent circle.
///
/// Deliberately not a network image: the engine hands back avatar URLs that may
/// need auth headers, and a letter never fails to load or leaks a request.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});

  final AccountUser user;

  @override
  Widget build(BuildContext context) {
    final label = user.label;
    final initial = label.isEmpty ? '?' : label.characters.first.toUpperCase();
    return Container(
      width: 72,
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.accentMuted,
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: AppTypography.display.copyWith(color: AppColors.accent),
      ),
    );
  }
}
