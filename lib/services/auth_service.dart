import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/request.dart';
import '../main.dart';
import '../screens/my_page.dart';

/// 账号自检结果
class AuthCheckResult {
  final bool isValid;
  final bool isLoggedOut;
  final String? code;
  final String? message;
  final String? nickname;
  final int elapsedMs;

  const AuthCheckResult({
    required this.isValid,
    this.isLoggedOut = false,
    this.code,
    this.message,
    this.nickname,
    required this.elapsedMs,
  });
}

/// 医考帮账号鉴权与登录状态守护服务
class AuthService {
  static final AuthService instance = AuthService._internal();
  AuthService._internal();

  bool _isPromptingRelogin = false;
  DateTime? _lastPromptTime;

  /// 检查当前账号 Token 有效性
  /// [promptRelogin]: 若发现 Token 过期是否自动弹窗提示用户重新登录
  Future<AuthCheckResult> checkTokenValidity({bool promptRelogin = true}) async {
    final sw = Stopwatch()..start();
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool('loggedin') ?? false;

    if (!loggedIn) {
      sw.stop();
      return AuthCheckResult(
        isValid: false,
        isLoggedOut: true,
        message: '用户尚未登录',
        elapsedMs: sw.elapsedMilliseconds,
      );
    }

    final userId = prefs.getString('user_id') ?? '';
    try {
      final params = <String, dynamic>{
        'app_id': '83',
        'is_vip': '0',
        'is_svip': '0',
      };
      if (userId.isNotEmpty) {
        params['target_user_id'] = userId;
      }

      final resp = await basicReq(
        '/User/Main/getUserInfo',
        params,
        method: 'GET',
      );
      sw.stop();

      final code = resp['code']?.toString() ?? 'unknown';
      final msg = resp['message']?.toString() ?? '';

      if (code == '200') {
        final data = resp['data'];
        String? nickname;
        if (data is Map) {
          nickname = data['nickname']?.toString();
          if (nickname != null && nickname.isNotEmpty) {
            await prefs.setString('nickname', nickname);
          }
          final avatar = data['avatar']?.toString();
          if (avatar != null && avatar.isNotEmpty) {
            await prefs.setString('avatar', avatar);
          }
        }
        return AuthCheckResult(
          isValid: true,
          code: code,
          message: msg.isNotEmpty ? msg : '登录状态正常',
          nickname: nickname,
          elapsedMs: sw.elapsedMilliseconds,
        );
      } else {
        // Token 过期或被顶掉 (如 309)
        if (code == '309' && promptRelogin) {
          notifyTokenExpired();
        }
        return AuthCheckResult(
          isValid: false,
          code: code,
          message: msg.isNotEmpty ? msg : 'Token 鉴权失败 ($code)',
          elapsedMs: sw.elapsedMilliseconds,
        );
      }
    } catch (e) {
      sw.stop();
      return AuthCheckResult(
        isValid: false,
        message: '自检网络异常: $e',
        elapsedMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// 当检测到 Token 失效 (309) 时触发弹窗提示，带防抖保护
  void notifyTokenExpired() {
    final now = DateTime.now();
    if (_lastPromptTime != null &&
        now.difference(_lastPromptTime!) < const Duration(seconds: 15)) {
      return;
    }
    if (_isPromptingRelogin) return;

    _lastPromptTime = now;
    _isPromptingRelogin = true;

    // 延迟到下一帧，确保 context 处于安全状态
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = rootNavigatorKey.currentContext;
      if (context == null) {
        _isPromptingRelogin = false;
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('登录已过期'),
            ],
          ),
          content: const Text(
            '检测到您的医考帮登录状态已失效（Token 过期），无法正常向云端同步做题记录与笔记。\n\n请重新登录以恢复完整同步。',
          ),
          actions: [
            TextButton(
              onPressed: () {
                _isPromptingRelogin = false;
                Navigator.of(ctx).pop();
              },
              child: const Text('稍后处理'),
            ),
            FilledButton(
              onPressed: () {
                _isPromptingRelogin = false;
                Navigator.of(ctx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LoginPage(
                      onLoggedIn: () {
                        // 登录成功后重新触发自检与队列
                        checkTokenValidity(promptRelogin: false);
                      },
                    ),
                  ),
                );
              },
              child: const Text('重新登录'),
            ),
          ],
        ),
      ).then((_) {
        _isPromptingRelogin = false;
      });
    });
  }
}
