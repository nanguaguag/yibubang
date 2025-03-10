import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// 全局常量与初始值
const String imei = '4f07ccb6e858592c'; // uuid
const String rootUrl = 'https://api.yikaobang.com.cn/index.php';
const String channelDefault = '10000';

/// DES 解密配置
/// Python 中 iv 为 b'1234567890ABCDEF'[:8] -> '12345678'
/// Python 中 key 为 b'de158b8749e6a2d0'[:8] -> 'de158b87'
final Uint8List desKey = Uint8List.fromList(utf8.encode('de158b87'));
final Uint8List desIv = Uint8List.fromList(utf8.encode('12345678'));

/// 获取当前秒级时间戳
String getTimestamp() {
  return (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
}

/// 对密码进行 MD5 加密，与 Python 中的 encrpyt_pswd 保持一致
String encryptPassword(String password) {
  return md5.convert(utf8.encode(password)).toString();
}

/// DES 解密函数，参考 Python 中 DES_decode，使用 PointyCastle 实现
String desDecode(String encryptedData) {
  try {
    // 解码 Base64 编码的密文
    Uint8List dataBytes = base64.decode(encryptedData);
    // 创建 DES 解密器，使用 CBC 模式
    final cipher = CBCBlockCipher(DESedeEngine());
    cipher.init(false, ParametersWithIV(KeyParameter(desKey), desIv));

    // 分块解密
    Uint8List output = Uint8List(dataBytes.length);
    int offset = 0;
    while (offset < dataBytes.length) {
      cipher.processBlock(dataBytes, offset, output, offset);
      offset += cipher.blockSize;
    }

    // 移除 PKCS7 填充
    int pad = output[output.length - 1];
    final result = output.sublist(0, output.length - pad);
    return utf8.decode(result, allowMalformed: true);
  } catch (e) {
    throw Exception('解密失败: $e');
  }
}

/// 根据参数生成签名，与 Python 中 get_signature 实现一致
String getSignature(
    String timeStamp, Map<String, dynamic> ajaxParams, bool loggedin) {
  // 注意：此处忽略 loggedin 参数，实际业务中可根据需求调整
  String appId = ajaxParams['app_id'].toString();
  // 对所有参数按 key 进行排序，然后拼接成字符串
  List<MapEntry<String, dynamic>> sortedEntries = ajaxParams.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  String paramStr = sortedEntries.map((e) => '${e.key}=${e.value}').join('');
  String buildString = paramStr + appId + timeStamp;
  String md5Str = md5.convert(utf8.encode(buildString)).toString();
  md5Str += 'bfde83c3208f4bfe97a57765ee824e92';
  String signature = sha1.convert(utf8.encode(md5Str)).toString();
  return signature;
}
