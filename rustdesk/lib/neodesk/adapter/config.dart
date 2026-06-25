part of '../adapter.dart';

class _RustdeskConfigStore implements nd.ConfigStore {
  @override
  String get(String key, {String defaultValue = ''}) {
    final v = bind.mainGetLocalOption(key: key);
    return v.isEmpty ? defaultValue : v;
  }

  @override
  Future<void> set(String key, String value) =>
      bind.mainSetLocalOption(key: key, value: value);

  @override
  bool getBool(String key, {bool defaultValue = false}) {
    final v = bind.mainGetLocalOption(key: key);
    if (v.isEmpty) return defaultValue;
    return v == 'Y';
  }

  @override
  Future<void> setBool(String key, bool value) =>
      bind.mainSetLocalOption(key: key, value: value ? 'Y' : '');
}

