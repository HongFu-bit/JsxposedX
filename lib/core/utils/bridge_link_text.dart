/// 连接文本（电脑端复制 → 手机端粘贴）的生成与解析。
///
/// 格式说明见 docs/desktop_bridge_lan_CN.md §16：
///
/// ```
/// 192.168.1.9:27183 校验码 123456
/// ```
///
/// **两端共用这一份实现**，避免格式漂移：电脑端的复制按钮用 [format] 生成，
/// 手机端的地址输入框用 [parse] 解析。
///
/// 需要留意的是这行文本里两部分的时效完全不同（§10.2）：**地址稳定、可以提前传；
/// 6 位码每 15 秒就过期**。所以正常用法是把地址搬过去、再现场看着屏幕输码——
/// 行内带的码只有在"复制后几秒内就能粘贴"（电脑与手机有剪贴板同步）时才用得上。
abstract final class BridgeLinkText {
  /// 端口省略时的默认值，与 `BridgeProtocol.defaultPort` 保持一致。
  static const int defaultPort = 27183;

  /// 校验码前的固定标记，用来把码和地址里的端口区分开。
  static const String codeLabel = '校验码';

  /// 生成一行连接文本。地址总是带端口，避免歧义。
  static String format({
    required String host,
    required int port,
    String? code,
  }) {
    final buffer = StringBuffer('$host:$port');
    final normalized = normalizeCode(code);
    if (normalized != null) {
      buffer.write(' $codeLabel $normalized');
    }
    return buffer.toString();
  }

  /// 解析一行连接文本。
  ///
  /// 规则（与文档 §16 一一对应）：
  /// - **地址部分先解析**：取到第一个空白为止；其中最后一段若有 `:` 则当作端口，
  ///   否则用 [defaultPort]。**P0 不支持 IPv6**——`2001:db8::1` 这类字面量无法与
  ///   "主机 + 端口"用同一个冒号规则区分，硬支持只会让规则说不清。
  /// - **码部分尽力解析**：优先取 [codeLabel] 之后的 6 位数字；没有标记时，
  ///   取**剩余文本里唯一**的一段 6 位数字。出现多段则不猜，交给用户手输。
  /// - **地址解析失败就明确报错**，不静默退回默认值——用户抄错一位时，
  ///   一个"地址格式不对"的提示比一次 5 秒的连接超时有用得多。
  static BridgeLinkParseResult parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return const BridgeLinkInvalid('粘贴的内容是空的。');
    }

    // 地址 = 第一个空白之前的部分，其余部分用来找码。
    final firstSpace = text.indexOf(RegExp(r'\s'));
    final addressPart = firstSpace < 0 ? text : text.substring(0, firstSpace);
    final remainder = firstSpace < 0 ? '' : text.substring(firstSpace);

    final address = _parseAddress(addressPart);
    if (address == null) {
      return BridgeLinkInvalid('识别不出地址「$addressPart」。应该形如 192.168.1.9:27183。');
    }

    return BridgeLinkOk(
      host: address.$1,
      port: address.$2,
      code: _parseCode(remainder),
    );
  }

  /// 把 `123 456` / `123-456` / `123456` 归一成 `123456`；不是 6 位数字则返回 null。
  static String? normalizeCode(String? code) {
    if (code == null) {
      return null;
    }
    final digits = code.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 6) {
      return null;
    }
    return digits;
  }

  /// @return `(host, port)`；无法识别时返回 null。
  static (String, int)? _parseAddress(String addressPart) {
    if (addressPart.isEmpty) {
      return null;
    }

    final separator = addressPart.lastIndexOf(':');
    final String host;
    final int port;

    if (separator < 0) {
      host = addressPart;
      port = defaultPort;
    } else {
      host = addressPart.substring(0, separator);
      final portText = addressPart.substring(separator + 1);
      final parsed = int.tryParse(portText);
      if (parsed == null || parsed <= 0 || parsed > 65535) {
        return null;
      }
      port = parsed;
    }

    if (host.isEmpty) {
      return null;
    }
    // 主机部分不允许再出现冒号——那说明是 IPv6 或抄错了。
    if (host.contains(':')) {
      return null;
    }
    // 允许 IPv4 与主机名；挡住明显的粘贴事故（换行、路径、带协议的 URL）。
    if (RegExp(r'[^\w.\-]').hasMatch(host)) {
      return null;
    }

    return (host, port);
  }

  /// 从地址之后的文本里找 6 位码。找不到或无法确定时返回 null（不猜）。
  static String? _parseCode(String remainder) {
    if (remainder.trim().isEmpty) {
      return null;
    }

    final matches = _codePattern.allMatches(remainder).toList();
    if (matches.isEmpty) {
      return null;
    }

    // 有 校验码 标记时，取标记之后的第一个匹配，这是最可靠的一条路径。
    final labelIndex = remainder.indexOf(codeLabel);
    if (labelIndex >= 0) {
      for (final match in matches) {
        if (match.start > labelIndex) {
          return normalizeCode(match.group(0));
        }
      }
      return null;
    }

    // 没有标记时只在"唯一一段"的情况下采用——多段就交给用户手输，
    // 免得猜错一个数字、然后表现为"校验码不正确"。
    if (matches.length == 1) {
      return normalizeCode(matches.first.group(0));
    }
    return null;
  }

  /// 6 位数字，中间允许一个空格或连字符（`123 456` / `123-456`）。
  static final RegExp _codePattern = RegExp(r'\d{3}[ \-]?\d{3}');
}

/// 解析成功。
final class BridgeLinkOk extends BridgeLinkParseResult {
  const BridgeLinkOk({required this.host, required this.port, this.code});

  final String host;

  final int port;

  /// 行内带的 6 位码。**可能已经过期**——手机端不做新鲜度判断，
  /// 照原样提交给电脑，由电脑按 §9.3 给出准确原因（`code` 还是 `code-stale`）。
  final String? code;

  String get address => '$host:$port';

  @override
  String toString() =>
      'BridgeLinkOk($address${code == null ? '' : ', code=$code'})';
}

/// 解析失败，[message] 直接给用户看。
final class BridgeLinkInvalid extends BridgeLinkParseResult {
  const BridgeLinkInvalid(this.message);

  final String message;

  @override
  String toString() => 'BridgeLinkInvalid($message)';
}

sealed class BridgeLinkParseResult {
  const BridgeLinkParseResult();
}
