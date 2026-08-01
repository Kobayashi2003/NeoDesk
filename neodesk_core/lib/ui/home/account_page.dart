import 'package:flutter/material.dart';
import 'package:neodesk_core/neodesk_core.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/dimens.dart';

/// Sign in to a RustDesk account.
///
/// RustDesk's public servers require an account before ID ("remote code")
/// connections are allowed. Direct-IP peers don't, so nothing here gates the
/// rest of the app — this page is reachable from Settings and that's all.
///
/// Three states, one page: credentials → (optional) six-digit code → signed in.
/// The code step is the *normal* path on a device the server hasn't seen, not an
/// error, so it gets a first-class screen rather than a dialog.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.core});

  final NeodeskCore core;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  AccountUser? _user;
  LoginNeedsCode? _pending;
  String? _error;
  bool _busy = false;
  bool _obscure = true;

  AccountPort get _account => widget.core.account;

  @override
  void initState() {
    super.initState();
    _user = _account.current;
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  /// Runs [step] with the button spinner on, and routes the outcome. Every
  /// sign-in path funnels through here so the busy flag and the error text can
  /// never drift out of sync with what actually happened.
  Future<void> _run(Future<LoginOutcome> Function() step) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await step();
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (outcome) {
        case LoginSucceeded(:final user):
          _user = user;
          _pending = null;
          _passCtrl.clear();
          _codeCtrl.clear();
        case LoginNeedsCode():
          _pending = outcome;
          _codeCtrl.clear();
        case LoginFailed(:final message):
          _error = message;
      }
    });
  }

  Future<void> _signOut() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _account.logout();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _user = null;
      _pending = null;
      _error = null;
    });
  }

  Future<void> _openRegistration() async {
    final url = await _account.registrationUrl();
    if (url.isEmpty) return;
    await widget.core.openExternalUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Account'), style: AppTypography.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Dimens.pageInset),
          children: [
            if (_user != null)
              ..._signedIn(_user!)
            else if (_pending != null)
              ..._codeStep(_pending!)
            else
              ..._credentialsStep(),
          ],
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
          Center(
            child: Text('@${user.name}', style: AppTypography.caption),
          ),
        ],
        const SizedBox(height: Dimens.s32),
        _note(tr('Signed in — remote-code connections are available.')),
        const SizedBox(height: Dimens.s24),
        _button(tr('Sign out'), _signOut, danger: true),
      ];

  // -------------------------------------------------------------- credentials

  List<Widget> _credentialsStep() => [
        const SizedBox(height: Dimens.s8),
        _note(tr(
            'RustDesk requires an account before connecting by remote code. '
            'Direct IP connections work without one.')),
        const SizedBox(height: Dimens.s24),
        _field(
          controller: _userCtrl,
          label: tr('Username'),
          icon: Icons.person_outline,
          keyboardType: TextInputType.emailAddress,
          onSubmitted: (_) => _submitCredentials(),
        ),
        const SizedBox(height: Dimens.s12),
        _field(
          controller: _passCtrl,
          label: tr('Password'),
          icon: Icons.lock_outline,
          obscure: _obscure,
          trailing: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                color: AppColors.textDisabled, size: 20),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
          onSubmitted: (_) => _submitCredentials(),
        ),
        _errorText(),
        const SizedBox(height: Dimens.s24),
        _button(tr('Sign in'), _submitCredentials),
        const SizedBox(height: Dimens.s16),
        Center(
          child: TextButton.icon(
            onPressed: _busy ? null : _openRegistration,
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(tr('Create an account on the web')),
          ),
        ),
      ];

  void _submitCredentials() =>
      _run(() => _account.login(_userCtrl.text.trim(), _passCtrl.text));

  // ---------------------------------------------------------------- code step

  List<Widget> _codeStep(LoginNeedsCode pending) => [
        const SizedBox(height: Dimens.s8),
        _note(pending.byEmail
            ? trArg('A verification code was sent to the email for {}.',
                pending.username)
            : tr('Enter the code from your authenticator app.')),
        const SizedBox(height: Dimens.s24),
        _field(
          controller: _codeCtrl,
          label: tr('Verification code'),
          icon: Icons.pin_outlined,
          keyboardType: TextInputType.number,
          autofocus: true,
          onSubmitted: (_) => _submitCode(pending),
        ),
        _errorText(),
        const SizedBox(height: Dimens.s24),
        _button(tr('Verify'), () => _submitCode(pending)),
        const SizedBox(height: Dimens.s8),
        Center(
          child: TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _pending = null;
                      _error = null;
                    }),
            child: Text(tr('Back')),
          ),
        ),
      ];

  void _submitCode(LoginNeedsCode pending) =>
      _run(() => _account.submitCode(pending, _codeCtrl.text.trim()));

  // ------------------------------------------------------------------- pieces

  Widget _note(String text) => Text(
        text,
        style: AppTypography.caption,
        textAlign: TextAlign.center,
      );

  Widget _errorText() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: Dimens.s12),
          child: Text(
            tr(_error!),
            style: AppTypography.caption.copyWith(color: AppColors.danger),
            textAlign: TextAlign.center,
          ),
        );

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    bool autofocus = false,
    TextInputType? keyboardType,
    Widget? trailing,
    ValueChanged<String>? onSubmitted,
  }) =>
      TextField(
        controller: controller,
        obscureText: obscure,
        autofocus: autofocus,
        enabled: !_busy,
        keyboardType: keyboardType,
        textInputAction: TextInputAction.done,
        onSubmitted: onSubmitted,
        style: AppTypography.body,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
          suffixIcon: trailing,
          filled: true,
          fillColor: AppColors.bgInput,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Dimens.rCard),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Dimens.rCard),
            borderSide: BorderSide(color: AppColors.border),
          ),
        ),
      );

  Widget _button(String label, VoidCallback onPressed, {bool danger = false}) =>
      SizedBox(
        height: 48,
        child: ElevatedButton(
          onPressed: _busy ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: danger ? AppColors.danger : AppColors.accent,
            foregroundColor: AppColors.textOnAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Dimens.rPill),
            ),
          ),
          child: _busy
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
