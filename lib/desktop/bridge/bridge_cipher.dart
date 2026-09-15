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

  /// 从会话令牌派生密钥。令牌是 64 个 hex 字符（32 字节）。
  factory BridgeCipher.fromSessionToken(String sessionToken) {
    final ikm = _decodeHex(sessionToken);
    return BridgeCipher._(
      _hkdf(ikm, _utf8(_infoPc2Phone)),
      _hkdf(ikm, _utf8(_infoPhone2Pc)),
    );
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

  final Uint8List _sendKey;
  final Uint8List _receiveKey;

  /// 本端发出帧的计数器，从 1 开始（0 保留给"还没用过"）。
  int _sendSeq = 0;

  /// 对端发来帧的最大计数器，用来挡重放。
  int _lastReceiveSeq = 0;

  /// 把一帧明文 JSON 封装成外层 `enc` 帧的 JSON 文本。
  String seal(String plaintextJson) {
    _sendSeq++;
    final seq = _sendSeq;
    final sealed = _gcm(true, _sendKey, _nonceFor(seq), _utf8(plaintextJson));
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
    // 加密时返回 密文||tag；解密时同样需要 密文||tag 作为输入。
    // 这与 Kotlin 侧 `Cipher("AES/GCM/NoPadding")` 的输出格式一致。
    return cipher.process(input);
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

  /// 会话令牌是 hex 字符串。长度不对时抛——那说明握手阶段出了问题，
  /// 不该带着一个残缺的密钥继续跑。
  static Uint8List _decodeHex(String hex) {
    final clean = hex.trim();
    if (clean.length != 64) {
      throw ArgumentError('会话令牌应是 64 个 hex 字符，实际 ${clean.length} 个');
    }
    final out = Uint8List(32);
    for (var i = 0; i < 32; i++) {
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
