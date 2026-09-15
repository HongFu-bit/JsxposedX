import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// 帧级加密：把每个 bridge 帧整体用 AES-256-GCM 封装。
///
/// ## 密钥从哪来
///
/// 用**电脑签发的会话令牌**当共享密钥——那个 32 字节的随机令牌在配对成功时
/// 已经通过 `token` 帧交给手机了，两端都持有，不需要额外的密钥交换。
/// 各自用 HKDF-SHA256 派生两条方向独立的密钥：
///
/// - 电脑 → 手机的密钥（本类在电脑侧是 `sendKey`）
/// - 手机 → 电脑的密钥（本类在电脑侧是 `receiveKey`）
///
/// 为什么必须分方向：GCM 的 nonce 一旦在同一把密钥下重复，安全性直接崩掉。
/// 两个方向各有自己的计数器、都从 1 开始，不分密钥就必然撞。
///
/// ## 局限（必须清楚）
///
/// **首次配对那一次是明文的**，包括会话令牌本身的传输。也就是说：
/// 一个正好在你配对时抓包的攻击者，能拿到令牌、进而解密之后的所有流量。
/// 本方案挡的是"长期同网段的旁观者"，不是"配对那一刻蹲守的人"。
/// 要做到后者需要密钥交换（X25519 + 用 6 位码做确认），那是独立的一步。
///
/// 见 docs/desktop_bridge_lan_CN.md §7.6。
class BridgeCipher {
  BridgeCipher._(this._sendKey, this._receiveKey);

  /// 从会话令牌派生密钥。
  ///
  /// 令牌是 hex 字符串，**电脑签发的实际是 16 字节 / 32 个字符（128 bit）**；
  /// 这里不假设长度，只校验它是合理的偶数长度 hex（见 [_decodeHex]）。
  ///
  /// **派生完立刻做一次自检**（[_verifySelfTest]），失败会抛 [StateError]。
  /// 调用方应当把它当作致命错误：加密实现坏了的话，最好的结果是当场报错，
  /// 最坏的结果是安静地连上又断开——而那正是最难查的一种故障。
  factory BridgeCipher.fromSessionToken(String sessionToken) {
    final ikm = _decodeHex(sessionToken);
    final cipher = BridgeCipher._(
      _hkdf(ikm, _utf8(_infoPc2Phone)),
      _hkdf(ikm, _utf8(_infoPhone2Pc)),
    );
    cipher._verifySelfTest();
    return cipher;
  }

  // ── 与手机侧 BridgeCipher.kt 必须逐字一致 ──
  static const String _salt = 'jsxposedx-bridge-v1-salt';
  static const String _infoPc2Phone = 'jsxposedx-bridge-v1/pc2phone';
  static const String _infoPhone2Pc = 'jsxposedx-bridge-v1/phone2pc';

  /// 认证但不加密的附加数据。它同时锁定了协议版本与算法套件——
  /// 两端如果不一致，解密会直接失败，而不是悄悄降级。
  static final Uint8List _aad = _utf8('JsxposedX-Bridge/v1/A256GCM');

  static const int _nonceBytes = 12;
  static const int _tagBits = 128;

  /// 会话令牌的 hex 长度范围，与手机侧 `BridgeCipher.kt` 保持一致。
  /// 电脑签发的会话令牌实际是 **16 字节（32 个字符，128 bit）**。
  static const int _minTokenHex = 32;
  static const int _maxTokenHex = 128;

  final Uint8List _sendKey;
  final Uint8List _receiveKey;

  /// 本端发出帧的计数器，从 1 开始（0 保留给"还没用过"）。
  int _sendSeq = 0;

  /// 对端发来帧的最大计数器，用来挡重放。
  int _lastReceiveSeq = 0;

  /// 派生出的**发送密钥**的指纹（SHA-256 前 8 个 hex 字符）。
  ///
  /// 纯粹是诊断用的：加密相关的故障大多是"两端密钥不一致"，而那种失败是静默的
  /// （GCM 校验不通过就返回 null），日志里只会看到"连上就断"。
  /// 两端各打一行指纹，相同则说明密钥派生没问题、问题在别处。
  ///
  /// 泄漏它无害——SHA-256 不可逆，这 8 个字符推不回密钥。
  String get sendKeyFingerprint =>
      sha256.convert(_sendKey).toString().substring(0, 8);

  /// 把一帧明文 JSON 封装成外层 `enc` 帧的 JSON 文本。
  String seal(String plaintextJson) {
    _sendSeq++;
    final seq = _sendSeq;
    final plain = Uint8List.fromList(utf8.encode(plaintextJson));
    final sealed = _gcm(true, _sendKey, _nonceFor(seq), plain);

    // 自检：GCM 的密文必须比明文正好多一个 tag。
    // 少了它说明底层没把 tag 附上——那不是"加密"，是"截断"，对端一定解不开。
    // 宁可在这里立刻炸掉，也不要等对端静默地解密失败。
    final expected = plain.length + (_tagBits ~/ 8);
    if (sealed.length != expected) {
      throw StateError(
        'GCM 输出长度异常：期望 $expected 字节，实际 ${sealed.length} 字节',
      );
    }

    return jsonEncode(<String, Object?>{
      't': 'enc',
      'n': seq,
      'd': base64Encode(sealed),
    });
  }

  /// 解开一个外层 `enc` 帧，返回内层明文 JSON 文本。
  ///
  /// 解密失败（被篡改、密钥不一致、计数器回退）时返回 null——调用方应当
  /// 把它当作协议违规直接断开，不要继续用这条连接。
  String? open(int seq, String base64Data) {
    if (seq <= _lastReceiveSeq) {
      // 重放或乱序。GCM 下乱序本身不至于致命，但正常的 TCP 流不会乱序，
      // 收到回退的计数器意味着有人在重放旧帧。
      return null;
    }

    final Uint8List sealed;
    try {
      sealed = base64Decode(base64Data);
    } on FormatException {
      return null;
    }

    final Uint8List plain;
    try {
      plain = _gcm(false, _receiveKey, _nonceFor(seq), sealed);
    } on InvalidCipherTextException {
      return null;
    } on Object {
      return null;
    }

    _lastReceiveSeq = seq;
    return utf8.decode(plain, allowMalformed: true);
  }

  /// 自检：用一把**一次性密钥**把一段探针加密再解回来，验证本端的 GCM 实现
  /// （尤其是输出缓冲里 tag 那 16 字节有没有算对）是自洽的。
  ///
  /// 为什么不直接用真实密钥：那样会占用一个 nonce，而 GCM 下 nonce 复用是灾难性的。
  /// 用一次性密钥既没有这个风险，也足以覆盖"实现是否自洽"——那才是这里要验的东西。
  ///
  /// 它**验不出**跨语言的差异（nonce 构造、AAD、HKDF 输入是否和 Kotlin 侧一致），
  /// 那要靠两端各打一行的密钥指纹去比对。
  void _verifySelfTest() {
    final probeKey = Uint8List(32)..fillRange(0, 32, 0x5A);
    final nonce = Uint8List(_nonceBytes)..fillRange(0, _nonceBytes, 0x5A);
    final probe = Uint8List.fromList(
      utf8.encode('jsxposedx-bridge-selftest'),
    );

    final sealed = _gcm(true, probeKey, nonce, probe);
    final expectedLength = probe.length + (_tagBits ~/ 8);
    if (sealed.length != expectedLength) {
      throw StateError(
        'GCM 自检失败：密文 ${sealed.length} 字节，期望 $expectedLength'
        '（密文应为「明文 + 16 字节 tag」）',
      );
    }

    final opened = _gcm(false, probeKey, nonce, sealed);
    if (opened.length != probe.length) {
      throw StateError('GCM 自检失败：解密结果 ${opened.length} 字节，期望 ${probe.length}');
    }
    for (var i = 0; i < probe.length; i++) {
      if (opened[i] != probe[i]) {
        throw StateError('GCM 自检失败：解密结果与明文不一致（第 $i 字节）');
      }
    }
  }

  /// 12 字节 nonce = 4 字节 0 前缀 + 8 字节大端计数器。
  ///
  /// GCM 的 nonce 不需要保密，只要在**同一把密钥下不重复**；用计数器而不是
  /// 随机数，就不会有"随机撞车"的理论风险。
  static Uint8List _nonceFor(int seq) {
    final nonce = Uint8List(_nonceBytes);
    final view = ByteData.view(nonce.buffer);
    // 前 4 字节保持 0，后 8 字节写计数器。
    view.setUint64(4, seq, Endian.big);
    return nonce;
  }

  /// AES-256-GCM。
  ///
  /// **刻意不用 `GCMBlockCipher.process()`**：那个方法自己分配输出缓冲，而它的
  /// 尺寸是否包含 tag 属于实现细节。加密时如果它按输入长度分配，`doFinal` 写
  /// 那 16 字节 tag 就会越界——异常被上层 `_send` 的 catch 吞掉，表现为
  /// "帧根本没发出去、对端等不到响应然后断开"，安静得完全看不出原因。
  ///
  /// 显式分配 + `processBytes`/`doFinal` 就没这个问题，也和 Kotlin 侧
  /// `Cipher("AES/GCM/NoPadding")` 的行为一一对应（密文后紧跟 tag）。
  static Uint8List _gcm(
    bool forEncryption,
    Uint8List key,
    Uint8List nonce,
    Uint8List input,
  ) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        forEncryption,
        AEADParameters(KeyParameter(key), _tagBits, nonce, _aad),
      );

    final tagBytes = _tagBits ~/ 8;
    // 加密：明文 + tag；解密：密文 - tag。
    final outLength = forEncryption
        ? input.length + tagBytes
        : input.length - tagBytes;
    if (outLength < 0) {
      throw ArgumentError('密文短于 tag，输入不合法');
    }

    final out = Uint8List(outLength);
    final written = cipher.processBytes(input, 0, input.length, out, 0);
    final total = written + cipher.doFinal(out, written);
    return total == out.length ? out : Uint8List.fromList(out.sublist(0, total));
  }

  /// HKDF-SHA256（RFC 5869）。输出长度固定 32 字节，因此 expand 只跑一轮。
  static Uint8List _hkdf(Uint8List ikm, Uint8List info) {
    final salt = _utf8(_salt);
    // extract
    final prk = Hmac(sha256, salt).convert(ikm).bytes;
    // expand：T(1) = HMAC(PRK, info || 0x01)
    final block = Hmac(sha256, prk).convert(<int>[...info, 0x01]).bytes;
    return Uint8List.fromList(block.sublist(0, 32));
  }

  /// 会话令牌是 hex 字符串。
  ///
  /// **长度取实际值，不假设固定长度**——这一点曾经被我写死成"必须 64 个字符"
  /// （以为令牌是 32 字节），而电脑签发的是 **16 字节 / 32 个字符**，
  /// 结果两端都建不出密钥，表现为"连上就断"。HKDF 的 IKM 可以是任意长度，
  /// 这里只需要校验它是个合理偶数长度的 hex。
  static Uint8List _decodeHex(String hex) {
    final clean = hex.trim();
    if (clean.length < _minTokenHex ||
        clean.length > _maxTokenHex ||
        clean.length.isOdd) {
      throw ArgumentError(
        '会话令牌应是 $_minTokenHex~$_maxTokenHex 个 hex 字符（偶数），实际 ${clean.length} 个',
      );
    }

    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final byte = int.tryParse(clean.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) {
        throw ArgumentError('会话令牌不是合法的 hex');
      }
      out[i] = byte;
    }
    return out;
  }

  static Uint8List _utf8(String value) =>
      Uint8List.fromList(utf8.encode(value));
}
