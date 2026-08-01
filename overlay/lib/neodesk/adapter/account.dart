part of '../adapter.dart';

/// Binds [nd.AccountPort] to RustDesk's `UserModel` and its OIDC plumbing.
///
/// The engine already owns the whole account story — the HTTP calls, the token
/// in local options (which the Rust core reads when it talks to the rendezvous
/// server), and a `refreshCurrentUser()` that `runMobileApp()` already calls on
/// every start. So this adapter adds no session-restore logic of its own: it
/// observes `gFFI.userModel` and drives the provider flow.
class _RustdeskAccount implements nd.AccountPort {
  _RustdeskAccount() {
    // Any of the three can change on a refresh; re-publish the whole snapshot
    // rather than trying to track which field moved.
    final m = gFFI.userModel;
    m.userName.listen((_) => _emit());
    m.displayName.listen((_) => _emit());
    m.avatar.listen((_) => _emit());
  }

  /// How often to ask the engine whether the browser round-trip has finished.
  /// Matches the engine's own dialog.
  static const _pollInterval = Duration(seconds: 1);

  /// Give up rather than poll forever if the user abandons the browser tab.
  static const _signInTimeout = Duration(minutes: 5);

  final _users = StreamController<nd.AccountUser?>.broadcast();

  /// The completer of the sign-in currently in flight, if any.
  Completer<nd.SignInOutcome>? _pending;
  Timer? _poll;

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
  Future<List<nd.AuthProvider>> providers() async {
    // `queryOidcLoginOptions` already unwraps the server's two shapes: a plain
    // `oidc/<name>` list, or a `common-oidc/[{name, icon}, …]` JSON blob.
    try {
      final raw = await UserModel.queryOidcLoginOptions();
      return raw
          .map((e) => (e is Map ? e['name'] : e)?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .map((name) => nd.AuthProvider(id: name, label: _label(name)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// The server sends lowercase keys; render the names people recognise.
  static String _label(String op) =>
      const {
        'github': 'GitHub',
        'gitlab': 'GitLab',
        'azure': 'Microsoft',
        'oidc': 'SSO',
      }[op.toLowerCase()] ??
      (op.isEmpty ? op : op[0].toUpperCase() + op.substring(1));

  @override
  Future<nd.SignInOutcome> signInWith(
    nd.AuthProvider provider, {
    void Function(String status)? onStatus,
  }) async {
    // Only one at a time — the engine keeps a single OIDC session, so starting
    // a second would silently hijack the first.
    await cancelSignIn();

    final done = Completer<nd.SignInOutcome>();
    _pending = done;

    var launched = false;
    var lastStatus = '';
    final deadline = DateTime.now().add(_signInTimeout);

    void finish(nd.SignInOutcome outcome) {
      if (done.isCompleted) return;
      _poll?.cancel();
      _poll = null;
      _pending = null;
      done.complete(outcome);
    }

    await bind.mainAccountAuth(op: provider.id, rememberMe: true);

    _poll = Timer.periodic(_pollInterval, (_) async {
      if (DateTime.now().isAfter(deadline)) {
        await bind.mainAccountAuthCancel();
        finish(const nd.SignInFailed('Timed out waiting for authorization'));
        return;
      }

      final raw = await bind.mainAccountAuthResult();
      if (raw.isEmpty) return;

      final Map<String, dynamic> result;
      try {
        result = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        return; // a partial result; the next tick will carry a whole one
      }

      final failed = (result['failed_msg'] ?? '').toString();
      if (failed.isNotEmpty) {
        finish(nd.SignInFailed(translate(failed)));
        return;
      }

      // The engine hands back the provider URL once it has one. On Android it
      // does not open it itself, so we must — `url_launched` says whether it
      // already did, and re-launching would spawn a second browser tab.
      final url = (result['url'] ?? '').toString();
      final alreadyLaunched = (result['url_launched'] as bool?) ?? false;
      if (!launched && !alreadyLaunched && url.isNotEmpty) {
        launched = true;
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }

      final status = (result['state_msg'] ?? '').toString();
      if (status.isNotEmpty && status != lastStatus) {
        lastStatus = status;
        onStatus?.call(translate(status));
      }

      final authBody = result['auth_body'];
      if (authBody is Map<String, dynamic>) {
        // Unlike the password flow, the **Rust side has already stored the
        // access token** by this point — parsing the body only updates the
        // user fields. Storing it again here would be harmless but is not ours
        // to do.
        try {
          gFFI.userModel.getLoginResponseFromAuthBody(authBody);
        } catch (e) {
          finish(nd.SignInFailed('$e'));
          return;
        }
        _emit();
        final u = _snapshot();
        finish(u == null
            ? const nd.SignInFailed('Failed, bad response from server')
            : nd.SignInSucceeded(u));
      }
    });

    return done.future;
  }

  @override
  Future<void> cancelSignIn() async {
    final pending = _pending;
    if (pending == null) return;
    _poll?.cancel();
    _poll = null;
    _pending = null;
    await bind.mainAccountAuthCancel();
    if (!pending.isCompleted) pending.complete(const nd.SignInCancelled());
  }

  @override
  Future<void> logout() async {
    await cancelSignIn();
    await gFFI.userModel.logOut();
    _emit();
  }
}
