import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:JsxposedX/generated/pinia.g.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pinia_provider.g.dart';

/// Pinia 存储服务 Provider
/// 使用 Android 原生 SharedPreferences 实现持久化存储
@riverpod
PiniaNative pinia(ref) {
  return NativeBridge.pinia;
}

/// Pinia 存储服务包装类
/// 提供类型安全的存储操作接口
class PiniaStorage {
  final PiniaNative _native;

  /// type=1: 传统本地 SharedPreferences
  /// type=2: RemotePreferences (新API, 默认)
  final int type;

  PiniaStorage(this._native, {this.type = 2});

  Future<void> setString(String key, String value, {String space = 'pinia'}) async {
    await _native.setString(key: key, value: value, space: space, type: type);
  }

  Future<void> setInt(String key, int value, {String space = 'pinia'}) async {
    await _native.setInt(key: key, value: value, space: space, type: type);
  }

  Future<void> setBool(String key, bool value, {String space = 'pinia'}) async {
    await _native.setBool(key: key, value: value, space: space, type: type);
  }

  Future<void> setDouble(String key, double value, {String space = 'pinia'}) async {
    await _native.setDouble(key: key, value: value, space: space, type: type);
  }

  Future<void> setLong(String key, int value, {String space = 'pinia'}) async {
    await _native.setLong(key: key, value: value, space: space, type: type);
  }

  Future<String> getString(String key, {String defaultValue = '', String space = 'pinia'}) async {
    return await _native.getString(key: key, defaultValue: defaultValue, space: space, type: type);
  }

  Future<int> getInt(String key, {int defaultValue = 0, String space = 'pinia'}) async {
    return await _native.getInt(key: key, defaultValue: defaultValue, space: space, type: type);
  }

  Future<bool> getBool(String key, {bool defaultValue = false, String space = 'pinia'}) async {
    return await _native.getBool(key: key, defaultValue: defaultValue, space: space, type: type);
  }

  Future<double> getDouble(String key, {double defaultValue = 0.0, String space = 'pinia'}) async {
    return await _native.getDouble(key: key, defaultValue: defaultValue, space: space, type: type);
  }

  Future<int> getLong(String key, {int defaultValue = 0, String space = 'pinia'}) async {
    return await _native.getLong(key: key, defaultValue: defaultValue, space: space, type: type);
  }

  Future<bool> contains(String key, {String space = 'pinia'}) async {
    return await _native.contains(key: key, space: space, type: type);
  }

  Future<void> remove(String key, {String space = 'pinia'}) async {
    await _native.remove(key: key, space: space, type: type);
  }

  Future<void> clear({String space = 'pinia'}) async {
    await _native.clear(space: space, type: type);
  }
}

/// 默认 Provider (type=2, RemotePreferences)
@riverpod
PiniaStorage piniaStorage(ref) {
  final native = ref.watch(piniaProvider);
  return PiniaStorage(native);
}

/// 传统本地存储 Provider (type=1)
@riverpod
PiniaStorage piniaStorageLocal(ref) {
  final native = ref.watch(piniaProvider);
  return PiniaStorage(native, type: 1);
}
