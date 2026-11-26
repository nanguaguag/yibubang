import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yibubang/common/request.dart';
import 'package:yibubang/main.dart' show rootNavigatorKey;
import 'package:yibubang/services/auth_service.dart';

Future<Map<String, dynamic>> _requestExpired({bool promptRelogin = true}) =>
    http.runWithClient(
      () => basicReq(
        '/User/Main/getUserInfo',
        <String, dynamic>{},
        promptRelogin: promptRelogin,
      ),
      () => MockClient((_) async => http.Response('{"code":309}', 200)),
    );

void main() {
  testWidgets('访客请求返回 309 时不提示重新登录', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(navigatorKey: rootNavigatorKey, home: const Scaffold()),
    );
    expect((await _requestExpired())['code'], 309);
    await tester.pumpAndSettle();
    expect(find.text('登录已过期'), findsNothing);
  });

  testWidgets('静默自检可清除失效会话而不提示', (tester) async {
    SharedPreferences.setMockInitialValues({
      'loggedin': true,
      'token': 'expired-test-token',
    });
    await tester.pumpWidget(
      MaterialApp(navigatorKey: rootNavigatorKey, home: const Scaffold()),
    );
    await _requestExpired(promptRelogin: false);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('loggedin'), isFalse);
    expect(find.text('登录已过期'), findsNothing);
  });

  testWidgets('旧会话的 309 不清除已重新登录的账号', (tester) async {
    SharedPreferences.setMockInitialValues({
      'loggedin': true,
      'token': 'current-test-token',
    });
    await AuthService.instance.handleExpiredSession('old-test-token');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('loggedin'), isTrue);
    expect(prefs.getString('token'), 'current-test-token');
  });

  testWidgets('启动时已关闭提醒的设备保持静默', (tester) async {
    SharedPreferences.setMockInitialValues({
      'loggedin': true,
      'token': 'expired-test-token',
      AuthService.showReloginPromptKey: false,
    });
    await tester.pumpWidget(
      MaterialApp(navigatorKey: rootNavigatorKey, home: const Scaffold()),
    );
    await _requestExpired();
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('loggedin'), isFalse);
    expect(find.text('登录已过期'), findsNothing);
  });

  testWidgets('不再提示保存在本机，之后仍会清除失效会话', (tester) async {
    SharedPreferences.setMockInitialValues({
      'loggedin': true,
      'token': 'expired-test-token',
    });
    await tester.pumpWidget(
      MaterialApp(navigatorKey: rootNavigatorKey, home: const Scaffold()),
    );
    await _requestExpired();
    await tester.pumpAndSettle();
    expect(find.text('登录已过期'), findsOneWidget);
    await tester.tap(find.text('不再提示'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AuthService.showReloginPromptKey), isFalse);
    await prefs.setBool('loggedin', true);
    await prefs.setString('token', 'second-expired-test-token');
    await _requestExpired();
    await tester.pumpAndSettle();
    expect(prefs.getBool('loggedin'), isFalse);
    expect(find.text('登录已过期'), findsNothing);
  });
}
