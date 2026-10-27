import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'ykb_encrypt.dart';

import '../db/settings.dart';
import '../services/auth_service.dart';

/// 发起请求的基础函数，整合了请求头设置及全局登录状态的处理
Future<Map<String, dynamic>> basicReq(
  String url,
  Map<String, dynamic> params, {
  String channel = channelDefault,
  String method = "POST",
}) async {
  String timestamp = getTimestamp();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  bool loggedin = prefs.getBool('loggedin') ?? false;

  // 如果已登录则附加登录信息
  if (loggedin) {
    params['token'] = prefs.getString('token') ?? '';
    params['secret'] = prefs.getString('secret') ?? '';
    params['user_id'] = prefs.getString('user_id') ?? '';
  }
  if (!params.containsKey('app_id')) {
    params['app_id'] = '1';
  }

  Map<String, String> headers = {
    'User-Agent': 'Redmi_23078RKD5C',
    'Connection': 'Keep-Alive',
    'Content-Type': 'application/x-www-form-urlencoded',
    'timestamp': timestamp,
    'signature': getSignature(timestamp, params, loggedin),
    'client-type': 'android',
    'app-version': appVersionDefault,
    'uuid': imei,
    'channel': channel,
    'app-type': 'ykb',
  };

  Uri uri = Uri.parse(rootUrl + url);
  debugPrint('[API-REQ] >>> $method $url');
  debugPrint('[API-REQ] Params: $params');
  debugPrint('[API-REQ] Headers: $headers');

  http.Response response;
  try {
    if (method == "POST") {
      response = await http.post(uri, headers: headers, body: params);
    } else if (method == "GET") {
      uri = uri.replace(
        queryParameters: params.map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      );
      response = await http.get(uri, headers: headers);
    } else {
      debugPrint('[API-REQ] Unknown method: $method');
      return {"msg": "Unknown Method"};
    }
  } catch (e, stack) {
    debugPrint('[API-ERROR] <<< $method $url exception: $e');
    debugPrint('$stack');
    rethrow;
  }

  debugPrint('[API-RESP] <<< $method $url [${response.statusCode}]');
  debugPrint('[API-RESP] Body: ${response.body}');

  Map<String, dynamic> resp;
  try {
    resp = json.decode(response.body) as Map<String, dynamic>;
  } catch (e) {
    debugPrint('[API-RESP] JSON decode error: $e');
    return {'code': response.statusCode.toString(), 'message': response.body};
  }

  if (resp['code'] == '309' || resp['code'] == 309) {
    // 会话过期，请重新登录
    debugPrint('[API-RESP] Session expired (code 309), clearing user info');
    clearUserInfo();
    AuthService.instance.notifyTokenExpired();
  }

  return resp;
}

/// 登录函数，调用登录接口并将返回数据存储到 shared_preferences 中
Future<Map<String, dynamic>> login(
  String mobile,
  String password, {
  String betaVersion = '0',
  String appId = '1',
}) async {
  // 对密码进行加密
  String encryptedPassword = encryptPassword(password);

  // 调用登录接口
  Map<String, dynamic> loginResp = await basicReq('/User/Main/login', {
    'beta_version': betaVersion,
    'mobile': mobile,
    'password': encryptedPassword,
    'app_id': appId,
  });

  // 只有服务端明确返回成功且包含有效 token 时才持久化凭据并标记已登录
  if ((loginResp['code'] == '200' || loginResp['code'] == 200) &&
      loginResp['data'] is Map &&
      loginResp['data']['token'] != null) {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', loginResp['data']['token']);
    await prefs.setString('secret', loginResp['data']['secret']);
    await prefs.setString('user_id', loginResp['data']['user_id']);
    await prefs.setString('user_uuid', loginResp['data']['user_uuid']);
    await prefs.setBool('loggedin', true);
  }
  return loginResp;
}
