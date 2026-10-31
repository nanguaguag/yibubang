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
  if (!params.containsKey('app_id') ||
      params['app_id'] == null ||
      params['app_id'].toString().isEmpty) {
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

  http.Response response;
  try {
    if (method == "POST") {
      response = await http.post(uri, headers: headers, body: params);
    } else if (method == "GET") {
      uri = uri.replace(
        queryParameters: params.map(
          (k, v) => MapEntry(k, v?.toString() ?? ''),
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

  if (response.statusCode != 200) {
    debugPrint(
      '[API-RESP] <<< $method $url [${response.statusCode}], raw body: ${response.body.isEmpty ? "<EMPTY>" : response.body}',
    );
  } else {
    debugPrint('[API-RESP] <<< $method $url [${response.statusCode}]');
  }

  if (response.body.trim().isEmpty) {
    debugPrint('[API-RESP] <<< $method $url returned empty response body (HTTP ${response.statusCode})');
    return {
      'code': response.statusCode.toString(),
      'message': 'HTTP ${response.statusCode}: Empty response body',
      'data': null,
    };
  }

  Map<String, dynamic> resp;
  try {
    resp = json.decode(response.body) as Map<String, dynamic>;
  } catch (e) {
    debugPrint('[API-RESP] JSON decode error: $e, raw response body: ${response.body}');
    return {
      'code': response.statusCode.toString(),
      'message': response.body,
      'data': null,
    };
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

  // 只要求鉴权必需的字段；个人资料可能为空或缺失。
  if (loginResp['code'].toString() == '200') {
    final data = loginResp['data'];
    if (data is! Map ||
        ['token', 'secret', 'user_id'].any(
          (key) => data[key] == null || data[key].toString().isEmpty,
        )) {
      return {'code': 'login_invalid_response', 'message': '登录响应缺少必要的鉴权信息'};
    }
    final prefs = await SharedPreferences.getInstance();
    for (final key in ['token', 'secret', 'user_id']) {
      await prefs.setString(key, data[key].toString());
    }
    if (data['user_uuid'] != null && data['user_uuid'].toString().isNotEmpty) {
      await prefs.setString('user_uuid', data['user_uuid'].toString());
    }
    await prefs.setBool('loggedin', true);
  }
  return loginResp;
}
