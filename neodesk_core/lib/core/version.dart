/// The neodesk app version.
///
/// Keep in lock-step with `rustdesk/pubspec.yaml`'s `version:` (keep its `+build`
/// number monotonically increasing so installs never hit an Android
/// version-downgrade). This constant is the single source of truth shown in
/// Settings → About.
const String kNeodeskVersion = '1.11.0';
