import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../common/ykb_encrypt.dart';

/// 医考帮 API 调试台 (API Playground)
class ApiPlaygroundPage extends StatefulWidget {
  const ApiPlaygroundPage({super.key});

  @override
  State<ApiPlaygroundPage> createState() => _ApiPlaygroundPageState();
}

class _ApiTemplate {
  final String title;
  final String method;
  final String path;
  final Map<String, dynamic> defaultParams;

  const _ApiTemplate({
    required this.title,
    required this.method,
    required this.path,
    required this.defaultParams,
  });
}

class _ApiPlaygroundPageState extends State<ApiPlaygroundPage> {
  final TextEditingController _pathController = TextEditingController(
    text: '/User/Main/getUserInfo',
  );
  final TextEditingController _paramsController = TextEditingController();

  String _method = 'GET';
  bool _autoAttachAuth = true;
  bool _autoAttachDefaults = true;
  bool _isLoading = false;

  // 调试结果
  int? _statusCode;
  int? _elapsedMs;
  Map<String, String>? _actualHeaders;
  String? _actualUrl;
  String? _actualBody;
  String? _responseBody;
  String? _errorMessage;

  static final List<_ApiTemplate> _templates = [
    const _ApiTemplate(
      title: '用户信息 (getUserInfo)',
      method: 'GET',
      path: '/User/Main/getUserInfo',
      defaultParams: {
        'app_id': '83',
        'is_vip': '0',
        'is_svip': '0',
      },
    ),
    _ApiTemplate(
      title: '做题批量提交 (postBatchForAll)',
      method: 'POST',
      path: '/Question/Answer/postBatchForAll',
      defaultParams: {
        'answers': jsonEncode([
          {
            'question_id': '10001',
            'answer': '1',
            'is_right': '1',
            'duration': '10',
          }
        ]),
        'subject_id': '',
        'chapter_id': '',
        'identity_id': '',
        'app_id': '12',
      },
    ),
    const _ApiTemplate(
      title: '斩题/取消斩题 (cutQuestion/cut)',
      method: 'POST',
      path: '/allQuestion/cutQuestion/cut',
      defaultParams: {
        'question_id': '10001',
        'type': '1', // 1: 斩题, 2: 恢复
        'subject_id': '',
        'identity_id': '',
        'app_id': '12',
      },
    ),
    const _ApiTemplate(
      title: '获取题目笔记 (Note/getNote)',
      method: 'GET',
      path: '/allQuestion/Note/getNote',
      defaultParams: {
        'question_id': '10001',
        'subject_id': '',
        'identity_id': '',
        'app_id': '12',
        'module_type': '1',
        'page': '1',
        'size': '5',
        'is_vip': '0',
        'is_svip': '0',
      },
    ),
    const _ApiTemplate(
      title: '上传/编辑笔记 (Note/pushNote)',
      method: 'POST',
      path: '/allQuestion/Note/pushNote',
      defaultParams: {
        'question_id': '10001',
        'content': 'API 调试台测试笔记',
        'module_type': '1',
        'subject_id': '',
        'identity_id': '',
        'app_id': '12',
        'is_vip': '0',
        'is_svip': '0',
      },
    ),
    const _ApiTemplate(
      title: '删除笔记 (Note/cleanNote)',
      method: 'POST',
      path: '/allQuestion/Note/cleanNote',
      defaultParams: {
        'id': '',
        'question_id': '10001',
        'subject_id': '',
        'identity_id': '',
        'app_id': '12',
        'is_vip': '0',
        'is_svip': '0',
      },
    ),
    const _ApiTemplate(
      title: '章节重做 (redoAnswerWithWrong)',
      method: 'POST',
      path: '/allquestion/main/redoAnswerWithWrong',
      defaultParams: {
        'subject_id': '',
        'obj_id': '',
        'type': 'chapter',
        'category': 'chapter',
        'is_wrong': '0',
        'app_id': '12',
      },
    ),
  ];

  @override
  void initState() {
    super.initState();
    _applyTemplate(_templates.first);
  }

  void _applyTemplate(_ApiTemplate t) {
    setState(() {
      _method = t.method;
      _pathController.text = t.path;
      _paramsController.text =
          const JsonEncoder.withIndent('  ').convert(t.defaultParams);
    });
  }

  Future<void> _sendRequest() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusCode = null;
      _responseBody = null;
    });

    final sw = Stopwatch()..start();
    try {
      final prefs = await SharedPreferences.getInstance();
      final loggedIn = prefs.getBool('loggedin') ?? false;

      // 解析用户输入的 JSON 参数
      Map<String, dynamic> params = {};
      final rawText = _paramsController.text.trim();
      if (rawText.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawText);
          if (decoded is Map<String, dynamic>) {
            params = decoded;
          } else {
            throw const FormatException('参数根对象必须为 JSON Object (Map)');
          }
        } catch (e) {
          setState(() {
            _errorMessage = '参数解析错误: $e';
            _isLoading = false;
          });
          return;
        }
      }

      // 自动附加登录凭据
      if (_autoAttachAuth && loggedIn) {
        params.putIfAbsent('token', () => prefs.getString('token') ?? '');
        params.putIfAbsent('secret', () => prefs.getString('secret') ?? '');
        params.putIfAbsent('user_id', () => prefs.getString('user_id') ?? '');
        if (_pathController.text.contains('getUserInfo')) {
          params.putIfAbsent(
              'target_user_id', () => prefs.getString('user_id') ?? '');
        }
      }

      // 自动附加默认通用字段
      if (_autoAttachDefaults) {
        if (!params.containsKey('app_id')) {
          params['app_id'] =
              _pathController.text.contains('getUserInfo') ? '83' : '12';
        }
        params.putIfAbsent('is_vip', () => '0');
        params.putIfAbsent('is_svip', () => '0');
      }

      final timestamp = getTimestamp();
      final signature = getSignature(timestamp, params, loggedIn);

      final headers = <String, String>{
        'User-Agent': 'Redmi_23078RKD5C',
        'Connection': 'Keep-Alive',
        'Content-Type': 'application/x-www-form-urlencoded',
        'timestamp': timestamp,
        'signature': signature,
        'client-type': 'android',
        'app-version': appVersionDefault,
        'uuid': imei,
        'channel': channelDefault,
        'app-type': 'ykb',
      };

      String cleanPath = _pathController.text.trim();
      if (!cleanPath.startsWith('/')) {
        cleanPath = '/$cleanPath';
      }
      Uri uri = Uri.parse('$rootUrl$cleanPath');

      http.Response response;
      if (_method == 'POST') {
        final bodyData = params.map((k, v) => MapEntry(k, v.toString()));
        _actualUrl = uri.toString();
        _actualBody = jsonEncode(bodyData);
        response = await http
            .post(uri, headers: headers, body: bodyData)
            .timeout(const Duration(seconds: 15));
      } else {
        uri = uri.replace(
          queryParameters: params.map((k, v) => MapEntry(k, v.toString())),
        );
        _actualUrl = uri.toString();
        _actualBody = null;
        response = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 15));
      }

      sw.stop();

      // 格式化响应
      String formattedResp;
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        formattedResp = const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {
        formattedResp = utf8.decode(response.bodyBytes);
      }

      setState(() {
        _statusCode = response.statusCode;
        _elapsedMs = sw.elapsedMilliseconds;
        _actualHeaders = headers;
        _responseBody = formattedResp;
        _isLoading = false;
      });
    } catch (e) {
      sw.stop();
      setState(() {
        _isLoading = false;
        _errorMessage = '请求异常 (${sw.elapsedMilliseconds}ms): $e';
      });
    }
  }

  void _copyToClipboard(String content, String message) {
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  String _generateCurl() {
    if (_actualUrl == null) return '';
    final buffer = StringBuffer('curl -X $_method \'$_actualUrl\'');
    if (_actualHeaders != null) {
      for (final entry in _actualHeaders!.entries) {
        buffer.write(' \\\n  -H \'${entry.key}: ${entry.value}\'');
      }
    }
    if (_method == 'POST' && _actualBody != null) {
      buffer.write(' \\\n  -d \'$_actualBody\'');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('API 调试台 (Playground)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined),
            tooltip: '清空结果',
            onPressed: () {
              setState(() {
                _statusCode = null;
                _responseBody = null;
                _errorMessage = null;
                _actualHeaders = null;
                _actualUrl = null;
              });
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 预设模板选择
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<_ApiTemplate>(
                  isExpanded: true,
                  hint: const Text('选择常用 API 模板...'),
                  items: _templates.map((t) {
                    return DropdownMenuItem<_ApiTemplate>(
                      value: t,
                      child: Text(
                        '[${t.method}] ${t.title}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) _applyTemplate(val);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Method & Path
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color:
                        theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _method,
                    items: const [
                      DropdownMenuItem(
                        value: 'GET',
                        child: Text(
                          'GET',
                          style: TextStyle(
                              color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'POST',
                        child: Text(
                          'POST',
                          style: TextStyle(
                              color: Colors.blue, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _method = val);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _pathController,
                  decoration: const InputDecoration(
                    labelText: '接口相对路径',
                    hintText: '/User/Main/getUserInfo',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 参数控制开关
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              FilterChip(
                label: const Text('自动注入登录凭证 (token/secret)'),
                selected: _autoAttachAuth,
                onSelected: (val) => setState(() => _autoAttachAuth = val),
              ),
              FilterChip(
                label: const Text('自动补充默认参数 (app_id/vip)'),
                selected: _autoAttachDefaults,
                onSelected: (val) => setState(() => _autoAttachDefaults = val),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 参数 JSON 输入区
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '请求参数 (JSON Object):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                icon: const Icon(Icons.format_align_left, size: 16),
                label: const Text('格式化 JSON'),
                onPressed: () {
                  try {
                    final obj = jsonDecode(_paramsController.text.trim());
                    setState(() {
                      _paramsController.text =
                          const JsonEncoder.withIndent('  ').convert(obj);
                    });
                  } catch (_) {}
                },
              ),
            ],
          ),
          TextField(
            controller: _paramsController,
            maxLines: 6,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(
              hintText: '{\n  "app_id": "12"\n}',
              border: const OutlineInputBorder(),
              fillColor: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.3),
              filled: true,
            ),
          ),
          const SizedBox(height: 16),

          // 发送按钮
          FilledButton.icon(
            onPressed: _isLoading ? null : _sendRequest,
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send),
            label: Text(_isLoading ? '正在请求并计算签名...' : '发送请求 (自动签名)'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 20),

          // 结果展示区域
          if (_errorMessage != null)
            Card(
              color: Colors.red.withValues(alpha: 0.1),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.red.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade900),
                ),
              ),
            ),

          if (_statusCode != null || _responseBody != null) ...[
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 状态栏
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _statusCode == 200
                                ? Colors.green.withValues(alpha: 0.15)
                                : Colors.red.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'HTTP $_statusCode',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _statusCode == 200
                                  ? Colors.green.shade800
                                  : Colors.red.shade800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '耗时: ${_elapsedMs ?? 0} ms',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          tooltip: '复制响应 JSON',
                          onPressed: () => _copyToClipboard(
                              _responseBody ?? '', '已复制响应内容'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.terminal, size: 18),
                          tooltip: '复制 cURL',
                          onPressed: () =>
                              _copyToClipboard(_generateCurl(), '已复制 cURL 命令行'),
                        ),
                      ],
                    ),
                    const Divider(height: 16),

                    // 实际发包详情
                    ExpansionTile(
                      dense: true,
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        '查看实际发出的 Request 详情 (包含签名)',
                        style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                      ),
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SelectableText(
                            'URL:\n$_actualUrl\n\n'
                            'Headers:\n${const JsonEncoder.withIndent('  ').convert(_actualHeaders ?? {})}\n\n'
                            'Body:\n${_actualBody ?? '(None)'}',
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 响应体
                    const Text(
                      'Response Body:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        _responseBody ?? '',
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
