import 'dart:async';

import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:JsxposedX/generated/status_management.g.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'status_management_provider.g.dart';

/// 状态管理原生接口 Provider
@riverpod
StatusManagementNative statusManagementNative(Ref ref) {
  return NativeBridge.statusManagement;
}

/// Hook 状态 Provider
@Riverpod(keepAlive: true)
Future<bool> isHook(Ref ref) async {
  final native = ref.read(statusManagementNativeProvider);
  for (var i = 0; i < 18; i++) {
    try {
      final hooked = await native.isHook();
      if (hooked) return true;
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 350));
  }
  return false;
}

/// Root 状态 Provider（轮询检测）
@Riverpod(keepAlive: true)
class IsRoot extends _$IsRoot {
  Timer? _timer;

  @override
  Future<bool> build() async {
    ref.onDispose(() => _timer?.cancel());
    _checkInitialStatus();
    return false;
  }

  bool _isChecking = false;
  bool _hasFoundRoot = false;

  void _checkInitialStatus() {
    _performCheck();
    _startPolling();
  }

  Future<void> _performCheck() async {
    if (_isChecking || _hasFoundRoot) return;
    _isChecking = true;

    try {
      final native = ref.read(statusManagementNativeProvider);
      final result = await native.isRoot();
      if (result) {
        _hasFoundRoot = true;
        _timer?.cancel();
        state = const AsyncData(true);
      }
    } catch (_) {
    } finally {
      _isChecking = false;
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _performCheck());
  }
}

/// Frida 状态 Provider（异步检测，不轮询）
@Riverpod(keepAlive: true)
class IsFrida extends _$IsFrida {
  @override
  Future<FridaStatusData> build() async {
    _performCheck();
    return FridaStatusData(
      status: false,
      type: -1,
    );
  }

  bool _isChecking = false;

  Future<void> _performCheck() async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      final native = ref.read(statusManagementNativeProvider);
      final result = await native.isFrida();
      state = AsyncData(result);
    } catch (_) {
      state = AsyncData(
        FridaStatusData(
          status: false,
          type: -1,
        ),
      );
    } finally {
      _isChecking = false;
    }
  }

  Future<void> refresh() => _performCheck();
}

