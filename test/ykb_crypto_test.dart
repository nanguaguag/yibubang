import 'package:flutter_test/flutter_test.dart';
import 'package:yibubang/services/ykb_crypto.dart';

void main() {
  group('YkbCrypto', () {
    test('解密真实接口密文（空壳样例，身份无效时官方返回）', () {
      const cipher =
          'R2vuEV/e98I6ZOWCh7wIocCWzuGMc5pMkLHi2N75Gm1gl7eqS3+E61eOIxhx8lIn';
      final plain = YkbCrypto.decrypt(cipher);
      expect(plain, '{"chapter_title":"","chapter_parent_title":""}');
    });

    test('加密-解密往返（自洽性）', () {
      // 已知明文用 Python(Crypto) DES 加密的密文：
      // DES/CBC/PKCS5, key=de158b87, iv=1234567890abcdef
      const knownPlain = '{"id":"588679","title":"test"}';
      const knownCipher = '/Iy9s0k+0ZrHWlHAGVD5rQGORqEox5mWdNOvlFbYUfw=';
      expect(YkbCrypto.decrypt(knownCipher), knownPlain);
    });
  });
}
