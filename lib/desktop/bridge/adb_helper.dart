import 'dart:async';
import 'dart:io';

import 'package:JsxposedX/desktop/bridge/bridge_protocol.dart';

/// adb 操作失败。[message] 给用户看结论，[hint] 给下一步怎么做。
///
/// [technical] 为 true 表示 message 是 adb 的原始报错（英文诊断信息），
/// 界面应该加一层双语说明再展示，而不是直接甩给用户。
class AdbException implements Exception {
  const AdbException(this.message, {this.hint, this.technical = false});

  final String message;

  final String? hint;

  final bool technical;

  @override
  String toString() => message;
}

/// `adb devices` 里的一台设备。
class AdbDevice {
  const AdbDevice({required this.serial, required this.state});

  final String serial;

  /// `device` / `unauthorized` / `offline` / ...
  final String state;

  bool get isReady => state == 'device';
}

/// 桌面端自带的 adb 连接能力。
///
/// 目标：**双击 exe 就能连上手机**，不需要仓库里的 PowerShell 脚本、也不需要用户手抄令牌。
/// 完整链路是：找到 adb → 找到设备 → 拉起手机上的 JsxposedX → 建立端口转发 → 从 logcat 读令牌。
///
/// adb 查找顺序：
/// 1. exe 同级的 `platform-tools/adb.exe`（打包脚本会把 adb 放进去，见 build_desktop_exe.ps1）
/// 2. `ANDROID_HOME` / `ANDROID_SDK_ROOT` / 默认 SDK 路径
/// 3. 系统 PATH
class AdbHelper {
  AdbHelper({String? adbPath}) : _adbPath = adbPath;

  static const Duration _commandTimeout = Duration(seconds: 20);
  static const Duration _logcatTimeout = Duration(seconds: 15);
  static const int _logcatTailLines = 3000;

  /// 手机端 bridge 服务在 logcat 里打印的 tag（LogX 会拼成 JsxposedX-<tag>）。
  static const String _logTag = 'JsxposedX-DesktopBridge';

  static final RegExp _tokenPattern = RegExp(r'token=([0-9a-fA-F]{32})');

  /// `adb devices` 里可能出现的状态字段。
  static const Set<String> _knownDeviceStates = <String>{
    'device',
    'offline',
    'unauthorized',
    'bootloader',
    'recovery',
    'sideload',
    'rescue',
    'connecting',
    'authorizing',
  };

  String? _adbPath;

  String? get adbPath => _adbPath;

  bool get hasAdb => _adbPath != null;

  String get _adbName => Platform.isWindows ? 'adb.exe' : 'adb';

  /// 查找 adb；找到返回 true。
  Future<bool> resolveAdb() async {
    if (_adbPath != null) {
      return true;
    }

    final separator = Platform.pathSeparator;

    // 1) 与 exe 同级目录（打包分发时的首选位置）
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final bundled = [
      '$exeDir${separator}platform-tools$separator$_adbName',
      // 也允许直接放在 exe 旁边
      '$exeDir$separator$_adbName',
    ];
    for (final candidate in bundled) {
      if (File(candidate).existsSync()) {
        _adbPath = candidate;
        return true;
      }
    }

    // 2) 常见 Android SDK 位置
    final environment = Platform.environment;
    final candidates = <String>[];
    for (final key in const ['ANDROID_HOME', 'ANDROID_SDK_ROOT']) {
      final value = environment[key];
      if (value != null && value.isNotEmpty) {
        candidates.add('$value${separator}platform-tools$separator$_adbName');
      }
    }
    final localAppData = environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      candidates.add(
        '$localAppData${separator}Android${separator}Sdk${separator}platform-tools$separator$_adbName',
      );
    }
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        _adbPath = candidate;
        return true;
      }
    }

    // 3) 系统 PATH
    try {
      final locator = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(
        locator,
        ['adb'],
        runInShell: true,
      ).timeout(_commandTimeout);
      if (result.exitCode == 0) {
        final first = (result.stdout as String)
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .firstWhere((line) => line.isNotEmpty, orElse: () => '');
        if (first.isNotEmpty && File(first).existsSync()) {
          _adbPath = first;
          return true;
        }
      }
    } catch (_) {
      // 落到"没找到 adb"
    }

    return false;
  }

  /// 列出设备（会顺带触发 adb server 启动）。
  Future<List<AdbDevice>> listDevices() async {
    final output = await _run(const ['devices']);
    final devices = <AdbDevice>[];

    for (final rawLine in output.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty ||
          line.startsWith('List of devices') ||
          line.startsWith('*')) {
        continue;
      }

      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2) {
        continue;
      }

      // adb 的报错行（如 "adb: failed to check server version"）也会混进来，
      // 只接受「制表符分隔」或「状态字段是已知状态」的行。
      final looksLikeDeviceRow =
          rawLine.contains('\t') || _knownDeviceStates.contains(parts[1]);
      if (!looksLikeDeviceRow) {
        continue;
      }

      devices.add(AdbDevice(serial: parts[0], state: parts[1]));
    }

    return devices;
  }

  /// 让手机把 JsxposedX 拉到前台——bridge 服务随 Flutter 引擎创建，App 不在前台就用不了。
  Future<void> startPhoneApp({String? serial}) async {
    await _run(
      <String>[
        'shell',
        'am',
        'start',
        '-n',
        '${BridgeProtocol.androidPackageName}/${BridgeProtocol.androidMainActivity}',
      ],
      serial: serial,
    );
  }

  /// 强制结束手机上的 JsxposedX。
  ///
  /// 用途：令牌是 bridge 服务启动时打印的。如果 App 早就在运行（引擎里没有新的启动），
  /// logcat 里可能已经没有那行令牌，这时需要冷启动一次让它重新生成。
  Future<void> forceStopPhoneApp({String? serial}) async {
    await _run(
      <String>['shell', 'am', 'force-stop', BridgeProtocol.androidPackageName],
      serial: serial,
      allowFailure: true,
    );
  }

  /// 建立端口转发：本机 tcp:<port> → 手机上的抽象命名空间 socket。
  Future<void> forward({required int port, String? serial}) async {
    // 旧规则先删掉，避免端口被上一次运行占用（删不掉属于正常情况）
    await _run(
      <String>['forward', '--remove', 'tcp:$port'],
      serial: serial,
      allowFailure: true,
    );
    await _run(
      <String>[
        'forward',
        'tcp:$port',
        'localabstract:${BridgeProtocol.socketName}',
      ],
      serial: serial,
    );
  }

  /// 从 logcat 读连接令牌。
  ///
  /// 令牌在手机端每次启动 bridge 时打印一行；只有持有 adb 的人能读到，
  /// 也就是说"能拿到令牌"与"能建立转发"是同一个信任边界。
  Future<String?> readToken({String? serial}) async {
    final output = await _run(
      <String>[
        'logcat',
        '-d',
        '-t',
        '$_logcatTailLines',
        '-s',
        _logTag,
      ],
      serial: serial,
      timeout: _logcatTimeout,
      allowFailure: true,
    );

    String? token;
    for (final match in _tokenPattern.allMatches(output)) {
      token = match.group(1);
    }
    return token;
  }

  /// 反复尝试读取令牌（用于"刚把 App 拉起来，日志还没出来"的场景）。
  Future<String?> waitForToken({
    String? serial,
    int attempts = 12,
    Duration interval = const Duration(milliseconds: 700),
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      final token = await readToken(serial: serial);
      if (token != null) {
        return token;
      }
      await Future<void>.delayed(interval);
    }
    return null;
  }

  Future<String> _run(
    List<String> arguments, {
    String? serial,
    Duration timeout = _commandTimeout,
    bool allowFailure = false,
  }) async {
    if (!await resolveAdb()) {
      throw const AdbException(
        'adb not found.',
        hint: 'Bundle platform-tools next to the exe, or add adb to PATH.',
        technical: true,
      );
    }

    final fullArguments = <String>[
      if (serial != null && serial.isNotEmpty) ...<String>['-s', serial],
      ...arguments,
    ];

    ProcessResult result;
    try {
      result = await Process.run(
        _adbPath!,
        fullArguments,
        stdoutEncoding: const SystemEncoding(),
        stderrEncoding: const SystemEncoding(),
      ).timeout(timeout);
    } on TimeoutException {
      throw AdbException(
        'adb command timed out: adb ${fullArguments.join(' ')}',
        hint: 'Check the phone is still connected; reproduce with "adb devices".',
        technical: true,
      );
    } catch (error) {
      throw AdbException('Failed to run adb: $error', technical: true);
    }

    final stdout = result.stdout as String;
    final stderr = result.stderr as String;

    if (result.exitCode != 0 && !allowFailure) {
      final detail = stderr.trim().isNotEmpty ? stderr.trim() : stdout.trim();
      throw AdbException(
        'adb ${arguments.join(' ')} failed (exit ${result.exitCode})${detail.isEmpty ? '' : ': $detail'}',
        technical: true,
      );
    }

    return '$stdout\n$stderr';
  }
}
