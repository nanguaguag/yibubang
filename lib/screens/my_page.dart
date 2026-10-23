import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yibubang/db/settings.dart';

import '../common/adaptive_route.dart';
import '../common/request.dart';
import '../repositories/question_search_repository.dart';
import '../services/note_service.dart';
import '../services/ykb_sync_service.dart';
import '../widgets/common/app_network_image.dart';
import '../widgets/common/info_card.dart';
import '../widgets/common/styled_tile.dart';
import './my_notes_page.dart';
import './settings_page.dart';
import './user_questions_list_page.dart';

/// 设置按钮，登录前/后及我的页共用
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

/// **我的页**
class MyPage extends StatefulWidget {
  const MyPage({super.key});

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  final QuestionSearchRepository _repository = QuestionSearchRepository();

  bool _loggedIn = false;
  String _nickname = '';

  int _collectionCount = 0;
  int _mistakeCount = 0;
  int _notesCount = 0;
  int _cutCount = 0;
  bool _loadingCounts = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    NoteService.instance.noteSyncEventNotifier.addListener(_onNoteEvent);
  }

  @override
  void dispose() {
    NoteService.instance.noteSyncEventNotifier.removeListener(_onNoteEvent);
    super.dispose();
  }

  void _onNoteEvent() {
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final logged = prefs.getBool('loggedin') ?? false;
    final nick = prefs.getString('nickname') ?? '';

    final counts = await _repository.getUserDataCounts();

    if (!mounted) return;
    setState(() {
      _loggedIn = logged;
      _nickname = nick;
      _collectionCount = counts['collection'] ?? 0;
      _mistakeCount = counts['mistake'] ?? 0;
      _notesCount = counts['notes'] ?? 0;
      _cutCount = counts['cut'] ?? 0;
      _loadingCounts = false;
    });
  }

  Future<void> _onAccountTap() async {
    if (_loggedIn) {
      await Navigator.push(
        context,
        adaptivePageRoute(
          builder: (context) => ProfilePage(onLoggedOut: _loadData),
        ),
      );
    } else {
      await Navigator.push(
        context,
        adaptivePageRoute(
          builder: (context) => LoginPage(onLoggedIn: _loadData),
        ),
      );
    }
    _loadData();
  }

  Widget _buildModuleCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required int count,
    required String unit,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _loadingCounts ? '...' : '$count $unit',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 220,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _onAccountTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _loggedIn
                      ? theme.colorScheme.primaryContainer.withValues(alpha: 0.65)
                      : theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _loggedIn ? Icons.verified_user : Icons.login,
                      size: 18,
                      color: _loggedIn
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _loggedIn
                            ? (_nickname.isNotEmpty ? _nickname : '医考帮用户')
                            : '登录医考帮',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _loggedIn
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          rebuildSettingsBtn(context),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _buildModuleCard(
            context: context,
            title: '我的收藏',
            subtitle: '常看常新，巩固重点考点',
            count: _collectionCount,
            unit: '道题',
            icon: Icons.favorite_rounded,
            iconColor: const Color(0xFFE53935),
            iconBgColor: const Color(0xFFFFEBEE),
            onTap: () async {
              await Navigator.push(
                context,
                adaptivePageRoute(
                  builder: (_) => const UserQuestionsListPage(
                    type: UserQuestionsType.collection,
                  ),
                ),
              );
              _loadData();
            },
          ),
          _buildModuleCard(
            context: context,
            title: '我的错题',
            subtitle: '查漏补缺，攻破知识盲区',
            count: _mistakeCount,
            unit: '道题',
            icon: Icons.cancel_rounded,
            iconColor: const Color(0xFFF57C00),
            iconBgColor: const Color(0xFFFFF3E0),
            onTap: () async {
              await Navigator.push(
                context,
                adaptivePageRoute(
                  builder: (_) => const UserQuestionsListPage(
                    type: UserQuestionsType.mistake,
                  ),
                ),
              );
              _loadData();
            },
          ),
          _buildModuleCard(
            context: context,
            title: '我的笔记',
            subtitle: '点滴积累，考点难点随笔',
            count: _notesCount,
            unit: '条笔记',
            icon: Icons.edit_note_rounded,
            iconColor: const Color(0xFF1E88E5),
            iconBgColor: const Color(0xFFE3F2FD),
            onTap: () async {
              await Navigator.push(
                context,
                adaptivePageRoute(
                  builder: (_) => const MyNotesPage(),
                ),
              );
              _loadData();
            },
          ),
          _buildModuleCard(
            context: context,
            title: '已斩的题',
            subtitle: '熟练掌握，斩除考题拦路虎',
            count: _cutCount,
            unit: '道题',
            icon: Icons.content_cut_rounded,
            iconColor: const Color(0xFF7E57C2),
            iconBgColor: const Color(0xFFEDE7F6),
            onTap: () async {
              await Navigator.push(
                context,
                adaptivePageRoute(
                  builder: (_) => const UserQuestionsListPage(
                    type: UserQuestionsType.cut,
                  ),
                ),
              );
              _loadData();
            },
          ),
        ],
      ),
    );
  }
}

/// 兼容旧代码路由的包装组件
class AuthCheckPage extends StatelessWidget {
  const AuthCheckPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const MyPage();
  }
}

/// **登录页面**
class LoginPage extends StatefulWidget {
  final VoidCallback? onLoggedIn;

  const LoginPage({super.key, this.onLoggedIn});

  @override
  State<LoginPage> createState() => _LoginPageState();
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
      String password = _passwordController.text;
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
          widget.onLoggedIn?.call();
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
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
    const double maxWidth = 400;

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.canPop(context) ? const BackButton() : null,
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

/// **个人中心页面**
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
    await clearUserInfo();
    widget.onLoggedOut?.call();
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
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
