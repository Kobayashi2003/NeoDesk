/// Signing in to a RustDesk account.
///
/// RustDesk's public infrastructure requires an account before ID-based
/// ("remote control code") connections are allowed, so the app needs to hold a
/// session token. The engine already implements the whole thing — this port is
/// only the contract the redesigned UI depends on; the adapter binds it to
/// RustDesk's `UserModel` and its `/api/login` endpoint.
///
/// Direct-IP peers and self-hosted servers do **not** need an account, so being
/// signed out never blocks anything in the UI.
abstract interface class AccountPort {
  /// The signed-in user, or null when signed out. Replays the current value to
  /// each new subscriber so a widget can build from it immediately.
  Stream<AccountUser?> get user;

  /// The current value of [user], for a synchronous first build.
  AccountUser? get current;

  /// Where to register or manage the account — the configured API server's web
  /// console (RustDesk's own for the public service, yours if self-hosted).
  /// There is no registration API in the client, so signing up always means
  /// opening this in a browser. Empty when no API server is configured.
  Future<String> registrationUrl();

  /// Step one: username + password.
  ///
  /// A brand-new device is normally challenged, so [LoginNeedsCode] is the
  /// expected outcome of a first sign-in on a phone — not an error path.
  Future<LoginOutcome> login(String username, String password);

  /// Step two, when [login] returned [LoginNeedsCode]: the six-digit code, sent
  /// back with the [LoginNeedsCode.secret] that identifies the challenge.
  Future<LoginOutcome> submitCode(LoginNeedsCode pending, String code);

  /// Drop the local session. Best-effort tells the server; the local token is
  /// cleared either way.
  Future<void> logout();
}

/// The result of a sign-in step.
sealed class LoginOutcome {
  const LoginOutcome();
}

/// Signed in; a token has been stored.
class LoginSucceeded extends LoginOutcome {
  const LoginSucceeded(this.user);

  final AccountUser user;
}

/// The server wants a six-digit code before it will issue a token — either
/// mailed out because it doesn't recognise this device, or from the user's
/// authenticator app when two-factor is on. Both are answered the same way, so
/// [byEmail] only changes the wording shown to the user.
class LoginNeedsCode extends LoginOutcome {
  const LoginNeedsCode({
    required this.secret,
    required this.byEmail,
    required this.username,
  });

  /// Opaque handle for this challenge; must be echoed back with the code.
  final String secret;

  /// True: emailed code. False: authenticator (TOTP) code.
  final bool byEmail;

  /// Who the challenge is for. Carried because completing it is a second
  /// request that has to name the same account, and because the UI can say
  /// whose inbox to check.
  final String username;
}

/// The attempt failed. [message] is already human-readable and localised where
/// the source allows it — show it as-is.
class LoginFailed extends LoginOutcome {
  const LoginFailed(this.message);

  final String message;
}

/// The signed-in account, reduced to what the UI shows.
class AccountUser {
  const AccountUser({
    required this.name,
    this.displayName = '',
    this.avatarUrl = '',
  });

  /// The login name / handle.
  final String name;

  /// Preferred display name; may be empty.
  final String displayName;

  /// Avatar image URL; may be empty.
  final String avatarUrl;

  /// What to show as the primary label.
  String get label => displayName.trim().isEmpty ? name : displayName.trim();

  /// `Display Name (@handle)` when the two differ, else just the handle — so the
  /// account row can always show which login is active.
  String get labelWithHandle {
    final handle = name.trim();
    if (handle.isEmpty) return '';
    final preferred = displayName.trim();
    if (preferred.isEmpty || preferred == handle) return handle;
    return '$preferred (@$handle)';
  }

  @override
  bool operator ==(Object other) =>
      other is AccountUser &&
      other.name == name &&
      other.displayName == displayName &&
      other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(name, displayName, avatarUrl);
}
