import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:yibubang/db/settings.dart';
import 'package:yibubang/screens/home_page.dart';
import '../common/request.dart';

///// 我的页面，展示用户的收藏/评论/笔记
//class MyPage extends StatelessWidget {
//  const MyPage({super.key});

//  @override
//  Widget build(BuildContext context) {
//    return Scaffold(
//      appBar: AppBar(
//        title: const Text(AppStrings.myPageTitle),
//        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
//      ),
//      body: AuthCheckPage(),
//    );
//  }
//}

/// **1. 入口页面：检查是否已登录**
class AuthCheckPage extends StatefulWidget {
  const AuthCheckPage({super.key});

  @override
  State<AuthCheckPage> createState() => _AuthCheckPageState();
}

class _AuthCheckPageState extends State<AuthCheckPage> {
  Future<bool> checkLoginStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool('loggedin') ?? false;
  }

  /// 显示错误信息
  Widget _buildErrorMessage(Object? error) {
    return Center(child: Text('加载失败: $error'));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: checkLoginStatus(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return _buildErrorMessage(snapshot.error);
        } else if (snapshot.data!) {
          return ProfilePage();
        } else {
          return LoginPage();
        }
      },
    );
  }
}

/// **2. 登录页面**
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

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

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const HomePage(),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(resp['message'] ?? '登录失败'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('登录异常: $e'),
            duration: Duration(seconds: 1),
          ),
        );
      } finally {
        setState(() {
          _loading = false;
        });
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
        title: const Text("登录医考帮"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String mobile = "";
  String email = "";
  String avatar = "";
  String nickname = "";
  String strSex = "";
  String userType = "";
  String nowName = "";
  String nowMajorName = "";
  String educationName = "";
  String entranceTime = "";

  @override
  void initState() {
    super.initState();
    loadUserData();
  }

  Future<void> loadUserData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      mobile = prefs.getString('mobile') ?? "";
      email = prefs.getString('email') ?? "";
      avatar = prefs.getString('avatar') ?? "";
      nickname = prefs.getString('nickname') ?? "";
      strSex = prefs.getString('str_sex') ?? "";
      userType = prefs.getString('user_type') ?? "";
      nowName = prefs.getString('now_name') ?? "";
      nowMajorName = prefs.getString('now_major_name') ?? "";
      educationName = prefs.getString('education_name') ?? "";
      entranceTime = prefs.getString('entrance_time') ?? "";
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
      if (userType == "") {
        userType = "student";
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
      if (entranceTime == "") {
        entranceTime = "未知";
      }
    });
  }

  Future<void> logout() async {
    clearUserInfo(); // 清除登录数据
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("个人中心"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Column(
                          children: [
                            avatar.isNotEmpty
                                ? CircleAvatar(
                                    backgroundImage: NetworkImage(avatar),
                                    radius: 50,
                                  )
                                : const Icon(Icons.account_circle, size: 0),
                            const SizedBox(height: 12),
                            Text(
                              nickname,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(),
                      _buildInfoTile(Icons.phone, "手机号", mobile),
                      _buildInfoTile(Icons.email, "邮箱", email),
                      _buildInfoTile(Icons.person, "性别", strSex),
                      _buildInfoTile(
                        Icons.school,
                        "专业",
                        "$nowName $nowMajorName",
                      ),
                      _buildInfoTile(Icons.book, "学历", educationName),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: logout,
              child: const Text('退出登录'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.deepPurple),
          const SizedBox(width: 12),
          Text(
            "$title: ",
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
