/// The neodesk app version. Test phase, so it stays **below 1.0**.
///
/// Bump this on every change, in lock-step with `apps/neodesk/pubspec.yaml`'s
/// `version:` (keep its `+build` number monotonically increasing so installs
/// never hit an Android version-downgrade). This constant is the single source
/// of truth shown in Settings → About.
const String kNeodeskVersion = '1.0.0';
