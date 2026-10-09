/// Persistent key/value configuration.
///
/// Wraps RustDesk's option storage exposed via the bridge:
///   - global:  `bind.mainGetLocalOption` / `bind.mainSetLocalOption`
///   - by-name: `ffiGetByName` / `ffiSetByName`
///     (`flutter/lib/models/platform_model.dart`)
abstract interface class ConfigStore {
  String get(String key, {String defaultValue});
  Future<void> set(String key, String value);

  bool getBool(String key, {bool defaultValue});
  Future<void> setBool(String key, bool value);
}
