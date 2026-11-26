import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/platform_adaptive.dart';
import '../common/request.dart';
import '../db/settings.dart';
import '../main.dart';
import '../screens/my_page.dart';
import 'note_service.dart';
import 'ykb_sync_service.dart';

enum _ReloginChoice { mute, signIn }

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
  static const showReloginPromptKey = 'ykb_show_relogin_prompt';
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
        promptRelogin: promptRelogin,
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

  /// 只处理本机当前会话的失效响应。
  Future<void> handleExpiredSession(
    String? requestToken, {
    bool promptRelogin = true,
  }) async {
    if (requestToken == null || requestToken.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('loggedin') != true ||
        prefs.getString('token') != requestToken) {
      return;
    }
    await clearUserInfo();
    if (promptRelogin) unawaited(_showReloginPrompt(prefs));
  }

  Future<void> _showReloginPrompt(SharedPreferences prefs) async {
    if (prefs.getBool(showReloginPromptKey) == false) return;
    final now = DateTime.now();
    if (_lastPromptTime != null &&
        now.difference(_lastPromptTime!) < const Duration(seconds: 15)) {
      return;
    }
    if (_isPromptingRelogin) return;

    _isPromptingRelogin = true;
    try {
      await WidgetsBinding.instance.endOfFrame;
      final context = rootNavigatorKey.currentContext;
      if (context == null ||
          !context.mounted ||
          prefs.getBool(showReloginPromptKey) == false ||
          prefs.getBool('loggedin') == true) {
        return;
      }
      _lastPromptTime = DateTime.now();
      final choice = await showDialog<_ReloginChoice>(
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
            '医考帮登录已失效。重新登录可恢复医考帮的记录与笔记同步。本地刷题和医不帮多端同步仍可使用。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('稍后处理'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_ReloginChoice.mute),
              child: const Text('不再提示'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(_ReloginChoice.signIn),
              child: const Text('重新登录'),
            ),
          ],
        ),
      );
      if (choice == _ReloginChoice.mute) {
        await prefs.setBool(showReloginPromptKey, false);
      } else if (choice == _ReloginChoice.signIn && context.mounted) {
        pushAdaptiveModalPage(
          context,
          desktopConstraints: const BoxConstraints(
            maxWidth: 480,
            maxHeight: 560,
          ),
          builder: (_) => LoginPage(
            onLoggedIn: () {
              unawaited(checkTokenValidity(promptRelogin: false));
              unawaited(YkbSyncService.instance.processQueue());
              unawaited(NoteService.instance.processQueue());
            },
          ),
        );
      }
    } finally {
      _isPromptingRelogin = false;
    }
  }
}
