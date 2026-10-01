import 'dart:convert';
import 'package:crypto/crypto.dart';

/// 全局常量与初始值
const String imei = '4f07ccb6e858592c'; // uuid
const String rootUrl = 'https://api.yikaobang.com.cn/index.php';
const String channelDefault = '10000';

/// 获取当前秒级时间戳
String getTimestamp() {
  return (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
}

/// 对密码进行 MD5 加密，与 Python 中的 encrpyt_pswd 保持一致
String encryptPassword(String password) {
  return md5.convert(utf8.encode(password)).toString();
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