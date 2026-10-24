import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../common/request.dart';
import '../common/ykb_encrypt.dart';
import 'api_playground_page.dart';
import '../db/database_helper.dart';
import '../services/cloud_sync_service.dart';
import '../services/note_service.dart';
import '../services/ykb_sync_service.dart';

/// 开发者调试页面
class DeveloperPage extends StatefulWidget {
  const DeveloperPage({super.key});

  @override
  State<DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends State<DeveloperPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // 账号凭据字段遮罩状态
  final Map<String, bool> _obscuredFields = {
    'uuid': true,
    'token': true,
    'secret': true,
    'user_id': true,
    'user_uuid': true,
  };

  // 凭据数据
  Map<String, String> _credentials = {};
  bool _isLoggedIn = false;

  // 队列数据
  List<Map<String, dynamic>> _ykbQueueItems = [];
  List<Map<String, dynamic>> _noteQueueItems = [];
  List<Map<String, dynamic>> _recentActivities = [];

  // 数据库统计
  Map<String, int> _tableCounts = {};
  String _databasePath = '';
  int _databaseSize = 0;

  // Preferences
  Map<String, Object> _allPrefs = {};
  String _prefSearchKeyword = '';

  // 网络诊断状态
  String? _ykbPingResult;
  bool _isPingingYkb = false;
  String? _cfPingResult;
  bool _isPingingCf = false;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _loading = true);
    await Future.wait([
      _loadCredentials(),
      _loadQueuesAndActivities(),
      _loadDatabaseStats(),
      _loadPrefs(),
    ]);
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getBool('loggedin') ?? false;
    _credentials = {
      'uuid': imei,
      'token': prefs.getString('token') ?? '',
      'secret': prefs.getString('secret') ?? '',
      'user_id': prefs.getString('user_id') ?? '',
      'user_uuid': prefs.getString('user_uuid') ?? '',
      'mobile': prefs.getString('mobile') ?? '',
      'nickname': prefs.getString('nickname') ?? '',
    };
  }

  Future<void> _loadQueuesAndActivities() async {
    final db = await UserDBHelper().database;
    try {
      final ykbRows = await db.query('YkbSyncQueue', orderBy: 'created_at ASC');
      _ykbQueueItems = List<Map<String, dynamic>>.from(ykbRows);
    } catch (_) {
      _ykbQueueItems = [];
    }

    try {
      final noteRows =
          await db.query('NoteSyncQueue', orderBy: 'created_at ASC');
      _noteQueueItems = List<Map<String, dynamic>>.from(noteRows);
    } catch (_) {
      _noteQueueItems = [];
    }

    try {
      final actRows = await db.query(
        'Activities',
        orderBy: 'timestamp DESC',
        limit: 50,
      );
      _recentActivities = List<Map<String, dynamic>>.from(actRows);
    } catch (_) {
      _recentActivities = [];
    }
  }

  Future<void> _loadDatabaseStats() async {
    final db = await UserDBHelper().database;
    final dbDir = await getDatabasesPath();
    _databasePath = p.join(dbDir, 'user_data.sqlite');
    final file = File(_databasePath);
    if (await file.exists()) {
      _databaseSize = await file.length();
    }

    final tables = [
      'Question',
      'Notes',
      'Activities',
      'YkbSyncQueue',
      'NoteSyncQueue',
      'Cards',
      'IdentitySubject',
      'IdentityChapter',
      'QuestionBank',
    ];

    final counts = <String, int>{};
    for (final table in tables) {
      try {
        final count = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM $table'),
            ) ??
            0;
        counts[table] = count;
      } catch (_) {
        counts[table] = 0;
      }
    }
    _tableCounts = counts;
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final map = <String, Object>{};
    for (final key in keys) {
      map[key] = prefs.get(key) ?? '';
    }
    _allPrefs = map;
  }

  void _copyToClipboard(String label, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 $label 到剪贴板'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _pingYkb() async {
    setState(() {
      _isPingingYkb = true;
      _ykbPingResult = null;
    });
    final sw = Stopwatch()..start();
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '';
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
      String extra = '';
      if (code == '200') {
        final data = resp['data'];
        final nickname = (data is Map) ? data['nickname'] : '';
        extra = (nickname != null && nickname.toString().isNotEmpty)
            ? ' (用户: $nickname)'
            : ' (成功)';
      }
      setState(() {
        _ykbPingResult = '[$code] $msg$extra (${sw.elapsedMilliseconds}ms)';
        _isPingingYkb = false;
      });
    } catch (e) {
      sw.stop();
      setState(() {
        _ykbPingResult = '请求失败 (${sw.elapsedMilliseconds}ms): $e';
        _isPingingYkb = false;
      });
    }
  }

  Future<void> _pingCf() async {
    setState(() {
      _isPingingCf = true;
      _cfPingResult = null;
    });
    final syncService = CloudSyncService.instance;
    if (!syncService.isConfigured) {
      setState(() {
        _cfPingResult = '未配置 Cloudflare Workers 凭证';
        _isPingingCf = false;
      });
      return;
    }
    try {
      final res = await CloudSyncService.instance.checkHealth();
      setState(() {
        _cfPingResult = res.isHealthy
            ? '健康 (${res.latencyMs}ms): ${res.message}'
            : '异常 (${res.latencyMs}ms): ${res.message}';
        _isPingingCf = false;
      });
    } catch (e) {
      setState(() {
        _cfPingResult = '探测失败: $e';
        _isPingingCf = false;
      });
    }
  }

  Future<void> _runIntegrityCheck() async {
    final db = await UserDBHelper().database;
    try {
      final res = await db.rawQuery('PRAGMA integrity_check;');
      final status = res.first.values.first?.toString() ?? 'unknown';
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('完整性校验结果'),
          content: Text(status == 'ok' ? '✅ 数据库完整性良好 (ok)' : '⚠️ 异常: $status'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('校验失败：$e')),
      );
    }
  }

  Future<void> _runWalCheckpoint() async {
    final db = await UserDBHelper().database;
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE);');
      await _loadDatabaseStats();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WAL 日志落盘与截断完成')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('执行失败：$e')),
      );
    }
  }

  void _clearImageCache() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('内存图片缓存已清空')),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _formatTime(int ms) {
    if (ms <= 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('开发者模式'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新全部数据',
            onPressed: _loadAllData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.key), text: '账号凭据'),
            Tab(icon: Icon(Icons.sync_alt), text: '同步队列'),
            Tab(icon: Icon(Icons.build_circle_outlined), text: '系统诊断'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCredentialsTab(theme),
                _buildSyncQueuesTab(theme),
                _buildDiagnosticsTab(theme),
              ],
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: 账号凭据 (uuid, token, secret, user_id, user_uuid)
  // ---------------------------------------------------------------------------
  Widget _buildCredentialsTab(ThemeData theme) {
    final fields = ['uuid', 'token', 'secret', 'user_id', 'user_uuid'];
    final allObscured = fields.every((f) => _obscuredFields[f] == true);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _isLoggedIn
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                : theme.colorScheme.errorContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isLoggedIn
                  ? theme.colorScheme.primary.withValues(alpha: 0.3)
                  : theme.colorScheme.error.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _isLoggedIn ? Icons.check_circle_outline : Icons.error_outline,
                color: _isLoggedIn
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isLoggedIn ? '已登录医考帮账号' : '未登录医考帮账号',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (_isLoggedIn)
                      Text(
                        '昵称: ${_credentials['nickname']}  |  手机: ${_credentials['mobile']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    for (final f in fields) {
                      _obscuredFields[f] = !allObscured;
                    }
                  });
                },
                icon: Icon(
                  allObscured ? Icons.visibility : Icons.visibility_off,
                  size: 16,
                ),
                label: Text(allObscured ? '全部显示' : '全部隐藏'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            children: [
              for (int i = 0; i < fields.length; i++) ...[
                _buildCredentialTile(theme, fields[i]),
                if (i < fields.length - 1)
                  const Divider(height: 1, indent: 16, endIndent: 16),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCredentialTile(ThemeData theme, String field) {
    final value = _credentials[field] ?? '';
    final isObscured = _obscuredFields[field] ?? true;
    final displayValue = value.isEmpty
        ? '（未设置/空）'
        : (isObscured ? '••••••••••••••••••••••••' : value);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        field,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
          color: theme.colorScheme.primary,
        ),
      ),
      subtitle: SelectableText(
        displayValue,
        style: TextStyle(
          fontSize: 13,
          fontFamily: isObscured ? null : 'monospace',
          color: value.isEmpty
              ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
              : theme.colorScheme.onSurface,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              isObscured ? Icons.visibility : Icons.visibility_off,
              size: 20,
            ),
            tooltip: isObscured ? '显示明文' : '遮罩隐藏',
            onPressed: () {
              setState(() {
                _obscuredFields[field] = !isObscured;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            tooltip: '复制',
            onPressed:
                value.isEmpty ? null : () => _copyToClipboard(field, value),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: 医考帮与本地数据上传/下载队列及同步历史
  // ---------------------------------------------------------------------------
  Widget _buildSyncQueuesTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 医考帮综合同步队列 (YkbSyncQueue)
        _buildQueueCard(
          theme: theme,
          title: '医考帮做题/斩题/重做同步队列',
          badgeText: '${_ykbQueueItems.length} 项待处理',
          badgeColor: _ykbQueueItems.isEmpty
              ? Colors.green
              : theme.colorScheme.primary,
          onProcess: () async {
            await YkbSyncService.instance.processQueue();
            await _loadQueuesAndActivities();
            if (mounted) setState(() {});
          },
          onResetAllRetries: () async {
            await YkbSyncService.instance.resetAllRetries();
            await _loadQueuesAndActivities();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已重置所有综合同步任务的重试计数为 0'),
                  duration: Duration(milliseconds: 800),
                ),
              );
              setState(() {});
            }
          },
          onClear: () => _confirmClearQueue('YkbSyncQueue'),
          children: [
            if (_ykbQueueItems.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    '队列为空，所有斩题/做题/章节重做均已同步',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
              )
            else
              for (final item in _ykbQueueItems) _buildYkbQueueTile(theme, item),
          ],
        ),
        const SizedBox(height: 16),

        // 医考帮笔记同步队列 (NoteSyncQueue)
        _buildQueueCard(
          theme: theme,
          title: '医考帮笔记上传/删除队列',
          badgeText: '${_noteQueueItems.length} 项待处理',
          badgeColor: _noteQueueItems.isEmpty
              ? Colors.green
              : theme.colorScheme.secondary,
          onProcess: () async {
            await NoteService.instance.processQueue();
            await _loadQueuesAndActivities();
            if (mounted) setState(() {});
          },
          onResetAllRetries: () async {
            await NoteService.instance.resetAllRetries();
            await _loadQueuesAndActivities();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已重置所有笔记同步任务的重试计数为 0'),
                  duration: Duration(milliseconds: 800),
                ),
              );
              setState(() {});
            }
          },
          onClear: () => _confirmClearQueue('NoteSyncQueue'),
          children: [
            if (_noteQueueItems.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    '笔记队列为空，所有笔记均已同步',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
              )
            else
              for (final item in _noteQueueItems)
                _buildNoteQueueTile(theme, item),
          ],
        ),
        const SizedBox(height: 16),

        // 最近作答流水历史 (Activities)
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.history, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      '本地作答与同步流水 (最近 50 条)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        SyncResponseCache.instance.clear();
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已清空同步响应缓存')),
                        );
                      },
                      icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                      label: const Text('清理响应缓存', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '共 ${_recentActivities.length} 条',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (_recentActivities.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: Text('暂无作答流水记录',
                        style: TextStyle(color: Colors.grey)),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _recentActivities.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (ctx, index) {
                    final act = _recentActivities[index];
                    final qId = act['question_id']?.toString() ?? '';
                    final isRight = act['is_right']?.toString();
                    final duration = (act['duration'] as num?)?.toInt() ?? 0;
                    final ts = (act['timestamp'] as num?)?.toInt() ?? 0;

                    final cached = SyncResponseCache.instance.getByItemId(qId);
                    final String displayCode = cached?.code ??
                        (isRight == '1'
                            ? '200'
                            : (isRight == '0' ? '错题' : '--'));

                    return ListTile(
                      dense: true,
                      leading: _buildStatusBadge(displayCode),
                      title: Text(
                        '题目 $qId  |  用时 ${(duration / 1000).toStringAsFixed(1)}s',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '题库: ${act['bank_id'] ?? '-'}  |  时间: ${_formatTime(ts)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.data_object, size: 18),
                            tooltip: '查看 Payload',
                            onPressed: () => _showRawJsonDialog(
                              '作答 Payload (题目 $qId)',
                              act['description']?.toString() ?? '{}',
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.reply_outlined, size: 18),
                            tooltip: '查看 respond',
                            onPressed: () {
                              final respJson = cached?.rawResponse ??
                                  const JsonEncoder.withIndent('  ').convert({
                                    'status': isRight == '1' ? 200 : 400,
                                    'msg': '本地流水记录（未命中响应缓存或已清理）',
                                    'question_id': qId,
                                    'is_right': isRight,
                                  });
                              _showRawJsonDialog(
                                '同步 Respond (题目 $qId)',
                                respJson,
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQueueCard({
    required ThemeData theme,
    required String title,
    required String badgeText,
    required Color badgeColor,
    required VoidCallback onProcess,
    VoidCallback? onResetAllRetries,
    required VoidCallback onClear,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: onProcess,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('立即同步'),
                ),
                if (onResetAllRetries != null)
                  IconButton(
                    icon: const Icon(Icons.restart_alt, size: 20),
                    tooltip: '重置所有任务的重试计数为 0',
                    onPressed: onResetAllRetries,
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_sweep, size: 20),
                  tooltip: '清空队列',
                  onPressed: onClear,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String code, {double fontSize = 11}) {
    Color bg;
    Color fg;
    if (code == '200') {
      bg = Colors.green.withValues(alpha: 0.15);
      fg = Colors.green.shade700;
    } else if (code.startsWith('4')) {
      bg = Colors.orange.withValues(alpha: 0.15);
      fg = Colors.deepOrange;
    } else if (code.startsWith('5') || code == 'ERR') {
      bg = Colors.red.withValues(alpha: 0.15);
      fg = Colors.red;
    } else {
      bg = Colors.grey.withValues(alpha: 0.15);
      fg = Colors.grey.shade700;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 38),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: fg.withValues(alpha: 0.3)),
          ),
          child: Text(
            code,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: fg,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildYkbQueueTile(ThemeData theme, Map<String, dynamic> item) {
    final type = item['type']?.toString() ?? '';
    final createdAt = (item['created_at'] as num?)?.toInt() ?? 0;
    final retry = (item['retry_count'] as num?)?.toInt() ?? 0;
    final lastError = item['last_error']?.toString();
    final queueId = item['id']?.toString() ?? '';
    final itemId = item['item_id']?.toString();

    final cached = SyncResponseCache.instance.getByQueueId(queueId) ??
        SyncResponseCache.instance.getByItemId(itemId);
    final String statusCode = cached?.code ?? (retry > 0 ? '重试' : '待同步');

    final typeNames = {
      'cut': '斩题同步',
      'answer': '做题提交',
      'redo_chapter': '章节重做',
    };

    return ListTile(
      dense: true,
      leading: _buildStatusBadge(statusCode),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              typeNames[type] ?? type,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'ID: ${item['item_id'] ?? '-'}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '时间: ${_formatTime(createdAt)}  |  重试次数: $retry',
            style: const TextStyle(fontSize: 11),
          ),
          if (lastError != null && lastError.isNotEmpty)
            Text(
              '错误: $lastError',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.error),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: '单项手动重试 (重置计数并立即执行)',
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('正在单项重试...'),
                  duration: Duration(milliseconds: 600),
                ),
              );
              final ok = await YkbSyncService.instance.retryItem(queueId);
              await _loadQueuesAndActivities();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? '单项重试成功并已移出队列' : '单项重试未成功，请查看最新报错'),
                    backgroundColor: ok ? Colors.green : Colors.red,
                  ),
                );
                setState(() {});
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.history, size: 18),
            tooltip: '仅重置重试计数为 0',
            onPressed: () async {
              await YkbSyncService.instance.resetItemRetry(queueId);
              await _loadQueuesAndActivities();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已重置该项重试计数为 0'),
                    duration: Duration(milliseconds: 600),
                  ),
                );
                setState(() {});
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.code, size: 18),
            tooltip: '查看 Payload',
            onPressed: () => _showRawJsonDialog(
              'YkbSyncQueue Payload',
              item['payload']?.toString() ?? '{}',
            ),
          ),
          IconButton(
            icon: const Icon(Icons.reply_outlined, size: 18),
            tooltip: '查看 respond',
            onPressed: () {
              final respJson = cached?.rawResponse ??
                  item['last_response']?.toString() ??
                  const JsonEncoder.withIndent('  ').convert({
                    'status': 'pending',
                    'message': '队列项尚未向服务器请求或未生成响应',
                    'retry_count': retry,
                    'last_error': lastError,
                  });
              _showRawJsonDialog(
                'YkbSyncQueue Respond',
                respJson,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: '删除该项',
            onPressed: () async {
              final db = await UserDBHelper().database;
              await db.delete('YkbSyncQueue',
                  where: 'id = ?', whereArgs: [item['id']]);
              await _loadQueuesAndActivities();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNoteQueueTile(ThemeData theme, Map<String, dynamic> item) {
    final action = item['action']?.toString() ?? '';
    final createdAt = (item['created_at'] as num?)?.toInt() ?? 0;
    final retry = (item['retry_count'] as num?)?.toInt() ?? 0;
    final lastError = item['last_error']?.toString();
    final queueId = item['id']?.toString() ?? '';
    final questionId = item['question_id']?.toString();

    final cached = SyncResponseCache.instance.getByQueueId(queueId) ??
        SyncResponseCache.instance.getByItemId(questionId);
    final String statusCode = cached?.code ?? (retry > 0 ? '重试' : '待同步');

    return ListTile(
      dense: true,
      leading: _buildStatusBadge(statusCode),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: action == 'upload'
                  ? Colors.blue.withValues(alpha: 0.2)
                  : Colors.red.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              action == 'upload' ? '上传笔记' : '删除笔记',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: action == 'upload' ? Colors.blue : Colors.red,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '题号: ${item['question_id'] ?? '-'}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '时间: ${_formatTime(createdAt)}  |  重试次数: $retry',
            style: const TextStyle(fontSize: 11),
          ),
          if (lastError != null && lastError.isNotEmpty)
            Text(
              '错误: $lastError',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.error),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: '单项手动重试 (重置计数并立即执行)',
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('正在单项重试笔记任务...'),
                  duration: Duration(milliseconds: 600),
                ),
              );
              final ok = await NoteService.instance.retryItem(queueId);
              await _loadQueuesAndActivities();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? '单项重试成功并已移出队列' : '单项重试未成功，请查看最新报错'),
                    backgroundColor: ok ? Colors.green : Colors.red,
                  ),
                );
                setState(() {});
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.history, size: 18),
            tooltip: '仅重置重试计数为 0',
            onPressed: () async {
              await NoteService.instance.resetItemRetry(queueId);
              await _loadQueuesAndActivities();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已重置该项重试计数为 0'),
                    duration: Duration(milliseconds: 600),
                  ),
                );
                setState(() {});
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.code, size: 18),
            tooltip: '查看 Payload',
          onPressed: () => _showRawJsonDialog(
            'NoteSyncQueue Payload',
            item['payload']?.toString() ?? '{}',
          ),
        ),
        IconButton(
          icon: const Icon(Icons.reply_outlined, size: 18),
          tooltip: '查看 respond',
          onPressed: () {
            final respJson = cached?.rawResponse ??
                item['last_response']?.toString() ??
                const JsonEncoder.withIndent('  ').convert({
                  'status': 'pending',
                  'message': '笔记队列项尚未向服务器请求或未生成响应',
                  'retry_count': retry,
                  'last_error': lastError,
                });
            _showRawJsonDialog(
              'NoteSyncQueue Respond',
              respJson,
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          tooltip: '删除该项',
          onPressed: () async {
            final db = await UserDBHelper().database;
            await db.delete('NoteSyncQueue',
                where: 'id = ?', whereArgs: [item['id']]);
            await _loadQueuesAndActivities();
            if (mounted) setState(() {});
          },
        ),
      ],
    ),
  );
}

  Future<void> _confirmClearQueue(String table) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('清空 $table'),
        content: const Text('确定要清空该同步队列中的所有未决项吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final db = await UserDBHelper().database;
      await db.delete(table);
      await _loadQueuesAndActivities();
      if (mounted) setState(() {});
    }
  }

  void _showRawJsonDialog(String title, String raw) {
    String pretty = raw;
    try {
      final decoded = jsonDecode(raw);
      pretty = const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {}

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              pretty,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _copyToClipboard(title, pretty),
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: 系统与诊断工具 (DB / Ping / Preferences / Cache)
  // ---------------------------------------------------------------------------
  Widget _buildDiagnosticsTab(ThemeData theme) {
    final filteredPrefs = _allPrefs.entries.where((e) {
      if (_prefSearchKeyword.isEmpty) return true;
      final k = e.key.toLowerCase();
      final v = e.value.toString().toLowerCase();
      final q = _prefSearchKeyword.toLowerCase();
      return k.contains(q) || v.contains(q);
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 数据库诊断
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.storage, size: 20),
                    const SizedBox(width: 8),
                    const Text('SQLite 数据库状态',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text(
                      _formatBytes(_databaseSize),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _databasePath,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in _tableCounts.entries)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${entry.key}: ${entry.value}',
                          style: const TextStyle(
                              fontSize: 12, fontFamily: 'monospace'),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _runIntegrityCheck,
                      icon: const Icon(Icons.verified_outlined, size: 16),
                      label: const Text('完整性检查'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _runWalCheckpoint,
                      icon: const Icon(Icons.save_outlined, size: 16),
                      label: const Text('WAL 落盘'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 网络诊断与 Ping
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.network_check, size: 20),
                    SizedBox(width: 8),
                    Text('网络 API 连通性测试 (Ping)',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('医考帮 API 服务器 (getUserInfo 诊断)'),
                  subtitle: Text(
                      _ykbPingResult ?? '$rootUrl/User/Main/getUserInfo',
                      style: const TextStyle(fontSize: 12)),
                  trailing: ElevatedButton(
                    onPressed: _isPingingYkb ? null : _pingYkb,
                    child: _isPingingYkb
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Ping 测试'),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('多端同步 (Cloudflare Workers)'),
                  subtitle: Text(
                    _cfPingResult ??
                        (CloudSyncService.instance.isConfigured
                            ? '已配置 (${CloudSyncService.primaryEndpoint})'
                            : '未配置 (${CloudSyncService.primaryEndpoint})'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: ElevatedButton(
                    onPressed: _isPingingCf ? null : _pingCf,
                    child: _isPingingCf
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Ping 测试'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // API 调试台入口
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.science_outlined,
                  color: theme.colorScheme.onPrimaryContainer),
            ),
            title: const Text('API 调试台 (Playground)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('发送任意医考帮请求，自动生成加密签名与完整请求头'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ApiPlaygroundPage()),
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        // 缓存清理
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: ListTile(
            leading: const Icon(Icons.cleaning_services),
            title: const Text('内存图片缓存清理'),
            subtitle: const Text('立即释放 Flutter 内存中缓存的解码位图'),
            trailing: OutlinedButton(
              onPressed: _clearImageCache,
              child: const Text('清空缓存'),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // SharedPreferences 浏览器
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune, size: 20),
                    const SizedBox(width: 8),
                    const Text('SharedPreferences 键值浏览器',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text('${filteredPrefs.length} 个配置项',
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  decoration: InputDecoration(
                    hintText: '搜索配置项 key 或 value...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (v) {
                    setState(() => _prefSearchKeyword = v);
                  },
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: filteredPrefs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, index) {
                      final item = filteredPrefs[index];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: SelectableText(
                          item.key,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        subtitle: SelectableText(
                          item.value.toString(),
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 11),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          tooltip: '复制内容',
                          onPressed: () => _copyToClipboard(
                              item.key, item.value.toString()),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
