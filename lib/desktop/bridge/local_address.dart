import 'dart:io';

import 'package:flutter/foundation.dart';

/// 一个候选的本机地址，连同它来自哪块网卡。
///
/// 为什么要把 [interfaceName] 一起带上：Windows 上通常同时存在对外的网卡
/// 和虚拟网卡（WSL / Hyper-V / VPN），用户必须能分辨该选哪个——
/// 下拉里只显示 `192.168.1.50` 和 `192.168.137.1` 是没法选的。
@immutable
class LanAddress {
  const LanAddress({
    required this.address,
    required this.interfaceName,
    required this.isHotspot,
  });

  final String address;

  final String interfaceName;

  /// 是否判定为"电脑开热点"的那块网卡（见 [LocalAddress.candidates]）。
  final bool isHotspot;

  /// 下拉里显示的文字。地址放在前面，因为那是用户要抄走的东西。
  @override
  String toString() => '$address  ·  $interfaceName';
}

/// 本机地址的枚举与首选挑选。
///
/// 说明为什么不能只用"承载默认路由的那块"：**电脑开热点时，默认路由指向的是
/// 对外那块网卡，而手机只能连热点那块**（文档 §10.4、§14.1）。照默认路由取，
/// 结果一定错，而且错得很隐蔽——界面上看起来完全正常，只是手机永远连不上。
///
/// Dart 侧拿不到路由表，所以这里用两个启发式替代：
/// 1. 地址落在 `192.168.137.0/24` 就当作 Windows 移动热点接口（这是 ICS 的固定网段）；
/// 2. 名字里带 `vEthernet` / `WSL` / `Hyper-V` 等字样的判定为虚拟网卡，排在后面。
///
/// 启发式只用于**排序与默认选中**；界面上永远提供下拉让用户自己选，
/// 并且记住用户选过的那块。
abstract final class LocalAddress {
  /// Windows 移动热点 / ICS 的固定网段。
  static const String _hotspotPrefix = '192.168.137.';

  /// 虚拟网卡的常见名字片段。命中就排到最后，避免默认选中。
  static const List<String> _virtualHints = <String>[
    'vethernet',
    'wsl',
    'hyper-v',
    'virtualbox',
    'vmware',
    'docker',
    'loopback',
    'bluetooth',
  ];

  /// 枚举所有可作为监听地址的 IPv4，按"最可能是手机能连上的那块"排序。
  static Future<List<LanAddress>> candidates() async {
    final List<NetworkInterface> interfaces;
    try {
      interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
    } on Object catch (error) {
      debugPrint('[lan] 枚举网卡失败：$error');
      return const <LanAddress>[];
    }

    final result = <LanAddress>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final value = address.address;
        // 链路本地地址（169.254.x）说明这块网卡没拿到 DHCP，连不上任何东西。
        if (value.startsWith('169.254.')) {
          continue;
        }
        result.add(
          LanAddress(
            address: value,
            interfaceName: interface.name,
            isHotspot: value.startsWith(_hotspotPrefix),
          ),
        );
      }
    }

    result.sort((a, b) => _rank(a).compareTo(_rank(b)));
    return result;
  }

  /// 排序权重，越小越优先。
  static int _rank(LanAddress candidate) {
    // 热点网卡排第一：那是最可能被手机连上的那块。
    if (candidate.isHotspot) {
      return 0;
    }
    final name = candidate.interfaceName.toLowerCase();
    if (_virtualHints.any(name.contains)) {
      return 2;
    }
    return 1;
  }

  /// 挑一个默认选中项。没有候选时返回 null（例如完全没联网）。
  static LanAddress? preferred(List<LanAddress> list) {
    if (list.isEmpty) {
      return null;
    }
    return list.first;
  }

  /// 按地址字符串找回之前记住的那块网卡。
  static LanAddress? findByAddress(List<LanAddress> list, String? address) {
    if (address == null || address.isEmpty) {
      return null;
    }
    for (final candidate in list) {
      if (candidate.address == address) {
        return candidate;
      }
    }
    return null;
  }
}
