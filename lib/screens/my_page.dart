import '../common/adaptive_route.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:yibubang/db/settings.dart';
import '../common/request.dart';
import '../services/note_service.dart';
import '../services/ykb_sync_service.dart';
import './settings_page.dart';
import '../widgets/common/info_card.dart';
import '../widgets/common/styled_tile.dart';
import '../widgets/common/app_network_image.dart';

/// **1. 入口页面：检查是否已登录**
class AuthCheckPage extends StatefulWidget {
  const AuthCheckPage({super.key});

  @override
  State<AuthCheckPage> createState() => _AuthCheckPageState();
}

class _AuthCheckPageState extends State<AuthCheckPage> {
  bool _loggedIn = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _refreshLoginStatus();
  }

  /// 读取本地登录状态，登录/退出后通过回调刷新整个页面
  Future<void> _refreshLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final logged = prefs.getBool('loggedin') ?? false;
    if (!mounted) return;
    setState(() {
      _loggedIn = logged;
      _checked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loggedIn) {
      return ProfilePage(onLoggedOut: _refreshLoginStatus);
    }
    return LoginPage(
      onLoggedIn: () => setState(() => _loggedIn = true),
    );
  }
}

/// **2. 登录页面**
class LoginPage extends StatefulWidget {
  final VoidCallback? onLoggedIn;

  const LoginPage({super.key, this.onLoggedIn});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

/// 设置按钮，登录前/后共用
Widget rebuildSettingsBtn(BuildContext context) {
  return IconButton(
    icon: const Icon(Icons.settings),
    tooltip: '设置',
    onPressed: () {
      Navigator.push(
        context,
        adaptivePageRoute(builder: (context) => const SettingsPage()),
      );
    },
  );
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _loading = false;

  void _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _loading = true;
      });
      String mobile = _accountController.text.trim();
      String password = _passwordController.text; // 假设此处需要加密
      try {
        Map<String, dynamic> resp = await login(mobile, password);
        if (resp['code'] == "200") {
          SharedPreferences prefs = await SharedPreferences.getInstance();
          Map<String, dynamic> userData = resp['data'];

          await prefs.setString('user_id', userData['user_id']);
          await prefs.setString('mobile', userData['mobile']);
          await prefs.setString('is_logout', userData['is_logout']);
          await prefs.setString('email', userData['email'] ?? '');
          await prefs.setString('avatar', userData['avatar']);
          await prefs.setString('nickname', userData['nickname']);
          await prefs.setString('user_uuid', userData['user_uuid']);
          await prefs.setString('sex', userData['sex']); // 0
          await prefs.setString('str_sex', userData['str_sex']); // 保密
          await prefs.setString('token', userData['token']);
          await prefs.setString('secret', userData['secret']);
          await prefs.setString('user_type', userData['user_type']);
          await prefs.setString('now_id', userData['now_id']); // 158
          await prefs.setString('now_name', userData['now_name']); // 四川大学
          await prefs.setString('now_major_id', userData['now_major_id']);
          await prefs.setString('now_major_name', userData['now_major_name']);
          await prefs.setString('education_id', userData['education_id']);
          await prefs.setString('education_name', userData['education_name']);
          await prefs.setString('entrance_time', userData['entrance_time']);

          await prefs.setBool('loggedin', true);

          // 登录成功后自动拉起离线同步队列
          YkbSyncService.instance.processQueue();
          NoteService.instance.processQueue();

          if (!mounted) return;
          // 登录成功后直接刷新为个人信息页，不再跳转到独立的“登录成功”页面
          widget.onLoggedIn?.call();
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(resp['message'] ?? '登录失败'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('登录异常: $e'),
            duration: const Duration(seconds: 1),
          ),
        );
      } finally {
        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 设置最大宽度常量，比如 400
    const double maxWidth = 400;

    return Scaffold(
      appBar: AppBar(
        actions: <Widget>[
          rebuildSettingsBtn(context),
        ],
        title: const Text("登录医考帮"),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 使用 ConstrainedBox 限制账号文本框的最大宽度
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: maxWidth),
                  child: TextFormField(
                    controller: _accountController,
                    decoration: const InputDecoration(
                      labelText: '医考帮账号(手机号)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请输入手机号';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 20),
                // 密码输入框同样添加最大宽度限制
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: maxWidth),
                  child: TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: '密码',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock),
                    ),
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请输入密码';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 20),
                // 添加 info 提示区域
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: maxWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: const [
                      Icon(Icons.info_outline, size: 16, color: Colors.grey),
                      SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          '登录医考帮账号能够让您看到所有的题目评论、题目的作答统计信息等。医不帮APP仅提供第三方登录，不会保存您的账号密码。',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // 登录按钮添加最大宽度限制
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: maxWidth),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _handleLogin,
                      child: _loading
                          ? const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            )
                          : const Text(
                              '登录',
                              style: TextStyle(fontSize: 18),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// **3. 个人中心页面**
class ProfilePage extends StatefulWidget {
  final VoidCallback? onLoggedOut;

  const ProfilePage({super.key, this.onLoggedOut});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String mobile = "";
  String email = "";
  String avatar = "";
  String nickname = "";
  String strSex = "";
  String nowName = "";
  String nowMajorName = "";
  String educationName = "";

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      mobile = prefs.getString('mobile') ?? "";
      email = prefs.getString('email') ?? "";
      avatar = prefs.getString('avatar') ?? "";
      nickname = prefs.getString('nickname') ?? "";
      strSex = prefs.getString('str_sex') ?? "";
      nowName = prefs.getString('now_name') ?? "";
      nowMajorName = prefs.getString('now_major_name') ?? "";
      educationName = prefs.getString('education_name') ?? "";
      if (mobile == "") {
        mobile = "未填写";
      }
      if (email == "") {
        email = "未填写";
      }
      if (avatar == "") {
        avatar =
            "https://img1.doubanio.com/view/group_topic/l/public/p560183288.jpg";
      }
      if (nickname == "") {
        nickname = "Anonymous";
      }
      if (strSex == "") {
        strSex = "未知";
      }
      if (nowName == "") {
        nowName = "未知";
      }
      if (nowMajorName == "") {
        nowMajorName = "未知";
      }
      if (educationName == "") {
        educationName = "未知";
      }
    });
  }

  Future<void> logout() async {
    await clearUserInfo(); // 清除登录数据
    widget.onLoggedOut?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Navigator.canPop(context) ? const BackButton() : null,
        actions: [
          rebuildSettingsBtn(context),
        ],
        title: const Text("个人中心"),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildHeaderCard(context),
          const SizedBox(height: 16),
          _buildInfoCard(context),
          const SizedBox(height: 24),
          _buildLogoutButton(context),
        ],
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasValidUrl =
        avatar.startsWith('http://') || avatar.startsWith('https://');

    if (!hasValidUrl) {
      // 头像未加载完或地址无效时，显示昵称首字作为占位
      return CircleAvatar(
        radius: 48,
        backgroundColor: colorScheme.primary,
        child: Text(
          nickname.isNotEmpty ? nickname.characters.first : '?',
          style: TextStyle(fontSize: 40, color: colorScheme.onPrimary),
        ),
      );
    }

    return CircleAvatar(
      radius: 48,
      backgroundColor: colorScheme.primaryContainer,
      // 使用 AppNetworkImage 提供磁盘与内存缓存，离线可用且异常兜底
      child: ClipOval(
        child: AppNetworkImage(
          imageUrl: avatar,
          width: 96,
          height: 96,
          fit: BoxFit.cover,
          errorWidget: (context, error, stackTrace) => Icon(
            Icons.person,
            size: 56,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final subtitle = [nowName, nowMajorName]
        .where((e) => e.isNotEmpty)
        .join(' · ');

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          children: [
            _buildAvatar(context),
            const SizedBox(height: 16),
            Text(
              nickname,
              style: textTheme.titleLarge?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    return InfoCard(
      children: [
        _buildInfoTile(Icons.phone, '手机号', mobile),
        _buildInfoTile(Icons.email_outlined, '邮箱', email),
        _buildInfoTile(Icons.person_outline, '性别', strSex),
        _buildInfoTile(Icons.school_outlined, '学校', nowName),
        _buildInfoTile(Icons.workspace_premium_outlined, '专业', nowMajorName),
        _buildInfoTile(Icons.menu_book_outlined, '学历', educationName),
      ],
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          TileIcon(icon: icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(value, style: textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FilledButton.tonalIcon(
      onPressed: logout,
      icon: const Icon(Icons.logout),
      label: const Text('退出登录'),
      style: FilledButton.styleFrom(
        foregroundColor: colorScheme.error,
        backgroundColor: colorScheme.errorContainer,
        minimumSize: const Size.fromHeight(52),
      ),
    );
  }
}
