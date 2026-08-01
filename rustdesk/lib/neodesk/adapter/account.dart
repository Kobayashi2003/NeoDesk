part of '../adapter.dart';

/// Binds [nd.AccountPort] to RustDesk's `UserModel` and its `/api/login`.
///
/// The engine already owns the whole account story — the HTTP calls, the token
/// in local options (which the Rust core reads when it talks to the rendezvous
/// server), and a `refreshCurrentUser()` that `runMobileApp()` already calls on
/// every start. So this adapter adds no session-restore logic of its own: it
/// observes `gFFI.userModel` and translates the two-step login into the port's
/// [nd.LoginOutcome].
class _RustdeskAccount implements nd.AccountPort {
  _RustdeskAccount() {
    // Any of the three can change on a refresh; re-publish the whole snapshot
    // rather than trying to track which field moved.
    final m = gFFI.userModel;
    m.userName.listen((_) => _emit());
    m.displayName.listen((_) => _emit());
    m.avatar.listen((_) => _emit());
  }

  final _users = StreamController<nd.AccountUser?>.broadcast();

  /// The engine's current user, or null when signed out. `UserModel` treats an
  /// empty `userName` as signed out (`bool get isLogin => userName.isNotEmpty`),
  /// so we do too.
  nd.AccountUser? _snapshot() {
    final m = gFFI.userModel;
    final name = m.userName.value.trim();
    if (name.isEmpty) return null;
    return nd.AccountUser(
      name: name,
      displayName: m.displayName.value,
      avatarUrl: m.avatar.value,
    );
  }

  void _emit() => _users.add(_snapshot());

  @override
  nd.AccountUser? get current => _snapshot();

  @override
  Stream<nd.AccountUser?> get user async* {
    yield _snapshot();
    yield* _users.stream;
  }

  @override
  Future<String> registrationUrl() async {
    // The client has no registration endpoint — RustDesk signs you up on the
    // web. The API server's own console is the right destination for both the
    // public service and a self-hosted one.
    try {
      return (await bind.mainGetApiServer()).trim();
    } catch (_) {
      return '';
    }
  }

  @override
  Future<nd.LoginOutcome> login(String username, String password) async {
    if (username.isEmpty) return const nd.LoginFailed('Username missed');
    if (password.isEmpty) return const nd.LoginFailed('Password missed');
    return _attempt(
      () async => LoginRequest(
        username: username,
        password: password,
        id: await bind.mainGetMyId(),
        uuid: await bind.mainGetUuid(),
        autoLogin: true,
        type: HttpType.kAuthReqTypeAccount,
      ),
      fallbackName: username,
    );
  }

  @override
  Future<nd.LoginOutcome> submitCode(
      nd.LoginNeedsCode pending, String code) async {
    if (code.isEmpty) return const nd.LoginFailed('Wrong verification code');
    return _attempt(
      () async => LoginRequest(
        // The server always reads `verificationCode`; `tfaCode` is set as well
        // only for an authenticator challenge. Both use the email-code request
        // type — that is the engine's own shape, not a guess.
        verificationCode: code,
        tfaCode: pending.byEmail ? null : code,
        secret: pending.secret,
        username: pending.username,
        id: await bind.mainGetMyId(),
        uuid: await bind.mainGetUuid(),
        autoLogin: true,
        type: HttpType.kAuthReqTypeEmailCode,
      ),
      fallbackName: pending.username,
    );
  }

  /// Runs one `/api/login` round-trip and maps whatever comes back. Both steps
  /// share this so an error can only be reported one way.
  Future<nd.LoginOutcome> _attempt(
    Future<LoginRequest> Function() build, {
    required String fallbackName,
  }) async {
    try {
      final resp = await gFFI.userModel.login(await build());
      return await _map(resp, fallbackName);
    } on RequestException catch (e) {
      // `cause` is a server-side key the engine's own bundle translates.
      return nd.LoginFailed(translate(e.cause));
    } catch (e) {
      return nd.LoginFailed('$e');
    }
  }

  Future<nd.LoginOutcome> _map(LoginResponse resp, String fallbackName) async {
    switch (resp.type) {
      case HttpType.kAuthResTypeToken:
        final token = resp.access_token;
        if (token == null) break;
        // `UserModel.login()` stores `user_info` but NOT the token — the
        // engine's own dialog does that itself. Miss this and the sign-in looks
        // fine yet nothing is persisted, so the next launch is signed out and
        // remote-code connections keep failing.
        await bind.mainSetLocalOption(key: 'access_token', value: token);
        _emit();
        return nd.LoginSucceeded(
            _snapshot() ?? nd.AccountUser(name: fallbackName));
      case HttpType.kAuthResTypeEmailCheck:
        return nd.LoginNeedsCode(
          secret: resp.secret ?? '',
          // No tfa_type, or an explicit email one, means a mailed code;
          // `tfa_check` means the authenticator app.
          byEmail: resp.tfa_type != HttpType.kAuthResTypeTfaCheck,
          username: resp.user?.name ?? fallbackName,
        );
    }
    return const nd.LoginFailed('Failed, bad response from server');
  }

  @override
  Future<void> logout() async {
    await gFFI.userModel.logOut();
    _emit();
  }
}
