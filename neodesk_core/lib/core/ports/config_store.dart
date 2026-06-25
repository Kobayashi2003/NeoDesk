/// Persistent key/value configuration.
///
/// Wraps RustDesk's option storage exposed via the bridge:
///   - global:  `bind.mainGetLocalOption` / `bind.mainSetLocalOption`
///   - by-name: `ffiGetByName` / `ffiSetByName`
///     (`flutter/lib/models/platform_model.dart`)
///
/// This is where a future *user-customisable gesture map* would be persisted,
/// keeping it out of the speed-critical native path.
abstract interface class ConfigStore {
  String get(String key, {String defaultValue});
  Future<void> set(String key, String value);

  bool getBool(String key, {bool defaultValue});
  Future<void> setBool(String key, bool value);
}
