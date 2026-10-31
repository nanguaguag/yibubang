import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// 医考帮题目数据加解密工具。
///
/// 官方 App（2.8.5.4 逆向 + 2.8.6.5 实机抓包验证）：
/// - `allquestion/question/list`、`allquestion/question/info` 等接口的
///   `data` 字段为 Base64(DES/CBC/PKCS5Padding 密文)；
/// - 密钥 `DES_KEY_VERIFY = "de158b8749e6a2d0"`（Java `DESKeySpec`
///   只取前 8 字节 `de158b87`）；
/// - IV 为 `0x12 34 56 78 90 AB CD EF`。
///
/// pointycastle 3.x 移除了单 DES，这里用 3DES-EDE 等价实现：
/// K1=K2=K3 时 E(K)∘D(K)∘E(K) = E(K)，即单 DES。
class YkbCrypto {
  static const String _key = 'de158b8749e6a2d0'; // 取前 8 字节
  static final Uint8List _iv = Uint8List.fromList(const [
    0x12,
    0x34,
    0x56,
    0x78,
    0x90,
    0xAB,
    0xCD,
    0xEF,
  ]);

  /// 解密接口返回的 Base64 密文，得到 JSON 字符串。
  static String decrypt(String base64Cipher) {
    final key8 = Uint8List.fromList(utf8.encode(_key).sublist(0, 8));
    final key24 = Uint8List.fromList([...key8, ...key8, ...key8]);
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(DESedeEngine()),
    );
    cipher.init(
      false,
      PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(key24), _iv),
        null,
      ),
    );
    final raw = base64Decode(base64Cipher);
    final out = cipher.process(raw);
    return utf8.decode(out);
  }

  /// 解密并解析为 Map（接口返回的 JSON 对象）。
  static Map<String, dynamic> decryptJson(String base64Cipher) {
    return jsonDecode(decrypt(base64Cipher)) as Map<String, dynamic>;
  }
}
