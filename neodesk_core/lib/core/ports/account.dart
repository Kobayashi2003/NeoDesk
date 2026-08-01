/// Signing in to a RustDesk account.
///
/// RustDesk's public infrastructure requires an account before ID-based
/// ("remote control code") connections are allowed, so the app needs to hold a
/// session token.
///
/// **Third-party sign-in only.** The public server has username/password login
/// switched off — it answers every attempt with *"Username/password login is not
/// available on this server. Please use the third-party login buttons"* — and it
/// serves no web console, so there is no registration to link to either: the
/// account simply *is* the Google / GitHub / Microsoft identity, created the
/// first time you sign in with it. Hence this port offers only the provider
/// flow. (A self-hosted server may well accept passwords; adding that back means
/// adding a method here, not reshaping the port.)
///
/// Direct-IP peers never needed an account, so being signed out blocks nothing.
abstract interface class AccountPort {
  /// The signed-in user, or null when signed out. Replays the current value to
  /// each new subscriber so a widget can build from it immediately.
  Stream<AccountUser?> get user;

  /// The current value of [user], for a synchronous first build.
  AccountUser? get current;

  /// The sign-in providers this server offers, in the order it lists them.
  /// Empty when the server is unreachable or offers none — the UI should then
  /// say so rather than show a dead button.
  Future<List<AuthProvider>> providers();

  /// Run the browser sign-in for [provider].
  ///
  /// This is a device-code style flow, not a redirect: the engine opens the
  /// provider's page in the system browser and polls the API server until the
  /// user finishes there. Nothing comes back through a deep link, so the app
  /// needs no custom URL scheme. [onStatus] receives the engine's progress text
  /// as it changes, for a live status line.
  ///
  /// Only one sign-in may be in flight; starting another cancels the first.
  Future<SignInOutcome> signInWith(
    AuthProvider provider, {
    void Function(String status)? onStatus,
  });

  /// Abandon a sign-in started by [signInWith]. Safe to call when none is
  /// running.
  Future<void> cancelSignIn();

  /// Drop the local session. Best-effort tells the server; the local token is
  /// cleared either way.
  Future<void> logout();
}

/// A sign-in provider as advertised by the server's login options.
class AuthProvider {
  const AuthProvider({required this.id, required this.label});

  /// The server's own key — `google`, `github`, `microsoft`, … Passed straight
  /// back to the engine to start the flow, and used to pick the button icon.
  final String id;

  /// Human-readable name for the button.
  final String label;

  @override
  bool operator ==(Object other) =>
      other is AuthProvider && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);
}

/// How a [AccountPort.signInWith] attempt ended.
sealed class SignInOutcome {
  const SignInOutcome();
}

/// Signed in; the engine has stored the session token.
class SignInSucceeded extends SignInOutcome {
  const SignInSucceeded(this.user);

  final AccountUser user;
}

/// The user backed out, or [AccountPort.cancelSignIn] was called.
class SignInCancelled extends SignInOutcome {
  const SignInCancelled();
}

/// The attempt failed. [message] is already human-readable — show it as-is.
class SignInFailed extends SignInOutcome {
  const SignInFailed(this.message);

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
