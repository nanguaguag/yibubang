import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../common/platform_adaptive.dart';
import '../common/request.dart';
import '../common/ykb_encrypt.dart';
import '../services/auth_service.dart';
import 'api_playground_page.dart';
import 'my_page.dart';
import '../db/database_helper.dart';
import '../services/cloud_backup_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/note_service.dart';
import '../services/ykb_sync_service.dart';
import 'cloud_sync_page.dart';

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
  int _ykbQueueTotalCount = 0;
  List<Map<String, dynamic>> _noteQueueItems = [];
  int _noteQueueTotalCount = 0;
  List<Map<String, dynamic>> _recentActivities = [];

  // Cloudflare 同步与冷备队列
  List<Map<String, dynamic>> _cloudOutboxItems = [];
  int _cloudOutboxTotalCount = 0;
  int? _cloudPullCursor;
  String? _cloudSyncOwner;
  bool _backupAutoEnabled = false;
  int _backupIntervalDays = 7;
  int _backupMaxRetained = 10;
  int _lastBackupTime = 0;
  bool _isSyncingCloud = false;
  bool _isBackingUpCloud = false;

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

  // 账号自检状态
  AuthCheckResult? _authCheckResult;
  bool _isCheckingAuth = false;

  Future<void> _checkAuthStatus() async {
    setState(() => _isCheckingAuth = true);
    final res = await AuthService.instance.checkTokenValidity(
      promptRelogin: false,
    );
    await _loadCredentials();
    if (mounted) {
      setState(() {
        _authCheckResult = res;
        _isCheckingAuth = false;
      });
    }
  }

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
    if (mounted) {
      setState(() => _loading = true);
    } else {
      _loading = true;
    }
    try {
      await _loadCredentials();
      await _loadPrefs();
      await _loadQueuesAndActivities();
      await _loadDatabaseStats();
    } catch (e, stack) {
      debugPrint('[DeveloperPage] _loadAllData error: $e\n$stack');
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @visibleForTesting
  Future<void> loadAllDataForTesting() => _loadAllData();
  @visibleForTesting
  List<Map<String, dynamic>> get cloudOutboxItemsForTesting =>
      _cloudOutboxItems;
  @visibleForTesting
  int get cloudOutboxTotalCountForTesting => _cloudOutboxTotalCount;

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
      final countRes = await db.rawQuery('SELECT COUNT(*) FROM YkbSyncQueue');
      _ykbQueueTotalCount = Sqflite.firstIntValue(countRes) ?? 0;
      final ykbRows = await db.query(
        'YkbSyncQueue',
        orderBy: 'created_at ASC',
        limit: 50,
      );
      _ykbQueueItems = List<Map<String, dynamic>>.from(ykbRows);
    } catch (_) {
      _ykbQueueTotalCount = 0;
      _ykbQueueItems = [];
    }

    try {
      final countRes = await db.rawQuery('SELECT COUNT(*) FROM NoteSyncQueue');
      _noteQueueTotalCount = Sqflite.firstIntValue(countRes) ?? 0;
      final noteRows = await db.query(
        'NoteSyncQueue',
        orderBy: 'created_at ASC',
        limit: 50,
      );
      _noteQueueItems = List<Map<String, dynamic>>.from(noteRows);
    } catch (_) {
      _noteQueueTotalCount = 0;
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

    try {
      final countRes = await db.rawQuery('SELECT COUNT(*) FROM CloudOutbox');
      _cloudOutboxTotalCount = Sqflite.firstIntValue(countRes) ?? 0;
      final outboxRows = await db.query(
        'CloudOutbox',
        orderBy: 'seq ASC',
        limit: 50,
      );
      _cloudOutboxItems = List<Map<String, dynamic>>.from(outboxRows);
    } catch (_) {
      _cloudOutboxTotalCount = 0;
      _cloudOutboxItems = [];
    }

    try {
      final cursorRows = await db.query('CloudPullCursor', limit: 1);
      if (cursorRows.isNotEmpty) {
        _cloudPullCursor = cursorRows.first['cursor'] as int?;
        _cloudSyncOwner = cursorRows.first['owner']?.toString();
      } else {
        _cloudPullCursor = 0;
        _cloudSyncOwner = null;
      }
    } catch (_) {
      _cloudPullCursor = 0;
      _cloudSyncOwner = null;
    }

    try {
      _backupAutoEnabled = await CloudBackupService.instance.getAutoEnabled();
      _backupIntervalDays = await CloudBackupService.instance.getIntervalDays();
      _backupMaxRetained = await CloudBackupService.instance.getMaxRetained();
      _lastBackupTime = await CloudBackupService.instance.getLastBackupTime();
    } catch (_) {
      _lastBackupTime = 0;
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
      'NoteTombstones',
      'CloudDeletedNotes',
      'Activities',
      'CloudDeletedActivities',
      'CustomFlashcards',
      'CloudDeletedFlashcards',
      'SpacedReviewItem',
      'ReviewPlans',
      'CloudOutbox',
      'CloudPullCursor',
      'YkbSyncQueue',
      'NoteSyncQueue',
      'QuestionRelations',
      'IdentitySubject',
      'IdentityChapter',
      'QuestionBank',
    ];

    final counts = <String, int>{};
    for (final table in tables) {
      try {
        final count =
            Sqflite.firstIntValue(
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('校验失败：$e')));
    }
  }

  Future<void> _runWalCheckpoint() async {
    final db = await UserDBHelper().database;
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE);');
      await _loadDatabaseStats();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('WAL 日志落盘与截断完成')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('执行失败：$e')));
    }
  }

  void _clearImageCache() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('内存图片缓存已清空')));
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

        // 账号状态自检与一键重新登录
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      '账号状态自检 (Token 诊断)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (_authCheckResult != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _authCheckResult!.isValid
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _authCheckResult!.isValid
                              ? 'Token 有效'
                              : 'Token 已失效/异常',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _authCheckResult!.isValid
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _authCheckResult != null
                      ? '结果: ${_authCheckResult!.message} (${_authCheckResult!.elapsedMs}ms)'
                      : '通过请求医考帮 getUserInfo 接口，自动验证当前本地 Token 是否有效或已在远端过期',
                  style: TextStyle(
                    fontSize: 12,
                    color: _authCheckResult?.isValid == false
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _isCheckingAuth ? null : _checkAuthStatus,
                      icon: _isCheckingAuth
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_lock, size: 16),
                      label: Text(_isCheckingAuth ? '正在检测...' : '立即自检 Token'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        pushAdaptiveModalPage(
                          context,
                          desktopConstraints: const BoxConstraints(
                            maxWidth: 480,
                            maxHeight: 560,
                          ),
                          builder: (_) => LoginPage(
                            onLoggedIn: () {
                              _loadCredentials();
                              _checkAuthStatus();
                            },
                          ),
                        );
                      },
                      icon: const Icon(Icons.login, size: 16),
                      label: const Text('重新登录'),
                    ),
                  ],
                ),
              ],
            ),
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
            onPressed: value.isEmpty
                ? null
                : () => _copyToClipboard(field, value),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: 云端同步、医考帮队列与本地数据上传/下载队列及流水
  // ---------------------------------------------------------------------------
  Widget _buildSyncQueuesTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Cloudflare D1 增量同步队列 (CloudOutbox)
        _buildCloudOutboxCard(theme),
        const SizedBox(height: 16),

        // Cloudflare R2 整库冷备快照
        _buildCloudBackupCard(theme),
        const SizedBox(height: 16),

        // 医考帮综合同步队列 (YkbSyncQueue)
        _buildQueueCard(
          theme: theme,
          title: '医考帮做题/斩题/重做同步队列',
          badgeText: _ykbQueueTotalCount > _ykbQueueItems.length
              ? '共 $_ykbQueueTotalCount 项 (展示前 ${_ykbQueueItems.length} 条)'
              : '$_ykbQueueTotalCount 项待处理',
          badgeColor: _ykbQueueTotalCount == 0
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
                  content: Text('已重置所有综合同步任务的重试计数与暂停状态'),
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
              for (final item in _ykbQueueItems)
                _buildYkbQueueTile(theme, item),
          ],
        ),
        const SizedBox(height: 16),

        // 医考帮笔记同步队列 (NoteSyncQueue)
        _buildQueueCard(
          theme: theme,
          title: '医考帮笔记上传/删除队列',
          badgeText: _noteQueueTotalCount > _noteQueueItems.length
              ? '共 $_noteQueueTotalCount 项 (展示前 ${_noteQueueItems.length} 条)'
              : '$_noteQueueTotalCount 项待处理',
          badgeColor: _noteQueueTotalCount == 0
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
                  content: Text('已重置所有笔记同步任务的重试计数与暂停状态'),
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
                      '流水',
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
                      icon: const Icon(
                        Icons.cleaning_services_outlined,
                        size: 16,
                      ),
                      label: const Text('清理', style: TextStyle(fontSize: 12)),
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
                    child: Text(
                      '暂无作答流水记录',
                      style: TextStyle(color: Colors.grey),
                    ),
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
                    final title = act['title']?.toString() ?? 'NewAnswer';
                    final qId = act['question_id']?.toString() ?? '';
                    final isRight = act['is_right']?.toString();
                    final duration = (act['duration'] as num?)?.toInt() ?? 0;
                    final ts = (act['timestamp'] as num?)?.toInt() ?? 0;

                    final cacheType = switch (title) {
                      'CutQuestion' => 'cut',
                      'RedoChapter' => 'redo_chapter',
                      'NoteUpload' => 'note_upload',
                      'NoteDelete' => 'note_delete',
                      'NewAnswer' || 'ReviewAnswer' => 'answer',
                      _ => null,
                    };
                    final lookupId = title == 'RedoChapter'
                        ? (act['chapter_id']?.toString() ?? qId)
                        : qId;
                    final cached = cacheType == null
                        ? null
                        : SyncResponseCache.instance.getByItemId(
                            lookupId,
                            type: cacheType,
                          );

                    String mainTitle;
                    String subTitle;
                    if (title == 'CutQuestion') {
                      mainTitle =
                          '斩题操作: 题目 $qId (${isRight == 'cut' ? '斩掉' : '恢复斩题'})';
                      subTitle =
                          '科目: ${act['subject_id'] ?? '-'}  |  时间: ${_formatTime(ts)}';
                    } else if (title == 'RedoChapter') {
                      mainTitle = '重做章节: ${act['chapter_id'] ?? '-'}';
                      subTitle =
                          '科目: ${act['subject_id'] ?? '-'}  |  时间: ${_formatTime(ts)}';
                    } else if (title == 'NoteUpload') {
                      mainTitle = '上传笔记: 题目 $qId';
                      subTitle =
                          '科目: ${act['subject_id'] ?? '-'}  |  时间: ${_formatTime(ts)}';
                    } else if (title == 'NoteDelete') {
                      mainTitle = '删除笔记: 题目 $qId';
                      subTitle =
                          '科目: ${act['subject_id'] ?? '-'}  |  时间: ${_formatTime(ts)}';
                    } else if (title == 'NotePull') {
                      mainTitle = '从医考帮拉取笔记: 题目 $qId';
                      subTitle =
                          '科目: ${act['subject_id'] ?? '-'}  |  时间: ${_formatTime(ts)}';
                    } else if (title == 'YkbPull') {
                      mainTitle = '从医考帮拉取做题: 题目 $qId';
                      subTitle =
                          '题库: ${act['bank_id'] ?? '-'}  |  时间: ${_formatTime(ts)}';
                    } else if (title == 'FlashcardReview') {
                      mainTitle =
                          '闪卡复习: 卡片 $qId  |  评级: ${isRight ?? '-'}  |  用时 ${(duration / 1000).toStringAsFixed(1)}s';
                      subTitle =
                          '科目/题库: ${act['subject_id'] ?? act['bank_id'] ?? '-'}  |  时间: ${_formatTime(ts)}';
                    } else if (title == 'ReviewMemory') {
                      mainTitle = '记忆曲线复习: $qId  |  评级: ${isRight ?? '-'}';
                      subTitle =
                          '科目/题库: ${act['subject_id'] ?? act['bank_id'] ?? '-'}  |  时间: ${_formatTime(ts)}';
                    } else if (title == 'ReviewAnswer') {
                      mainTitle =
                          '记忆曲线做题: 题目 $qId  |  用时 ${(duration / 1000).toStringAsFixed(1)}s';
                      subTitle =
                          '科目/题库: ${act['subject_id'] ?? act['bank_id'] ?? '-'}  |  时间: ${_formatTime(ts)}';
                    } else if (title == '熟练斩卡' || title == '熟练斩题') {
                      mainTitle = '$title: $qId';
                      subTitle =
                          '科目/题库: ${act['subject_id'] ?? act['bank_id'] ?? '-'}  |  时间: ${_formatTime(ts)}';
                    } else if (title == 'Backfill') {
                      mainTitle = '历史作答补记: 题目 $qId';
                      subTitle =
                          '题库: ${act['bank_id'] ?? '-'}  |  时间: ${_formatTime(ts)}';
                    } else {
                      mainTitle =
                          '做题提交: 题目 $qId  |  用时 ${(duration / 1000).toStringAsFixed(1)}s';
                      subTitle =
                          '题库: ${act['bank_id'] ?? '-'}  |  时间: ${_formatTime(ts)}';
                    }

                    return ListTile(
                      dense: true,
                      leading: _buildActivityTypeBadge(title, isRight),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              mainTitle,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildHttpCodeBadge(cached?.code),
                        ],
                      ),
                      subtitle: Text(
                        subTitle,
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.data_object, size: 18),
                            tooltip: '查看 Payload',
                            onPressed: () => _showRawJsonDialog(
                              '流水 Payload ($title)',
                              act['description']?.toString() ?? '{}',
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.reply_outlined, size: 18),
                            tooltip: '查看 respond',
                            onPressed: () {
                              final respJson =
                                  cached?.rawResponse ??
                                  const JsonEncoder.withIndent('  ').convert({
                                    'title': title,
                                    'question_id': qId,
                                    'status': '本地流水记录',
                                    'is_right': isRight,
                                    'timestamp': ts,
                                  });
                              _showRawJsonDialog(
                                '同步 Respond ($title)',
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

  Widget _buildCloudOutboxCard(ThemeData theme) {
    final hasMore = _cloudOutboxTotalCount > _cloudOutboxItems.length;
    return _buildQueueCard(
      theme: theme,
      title: 'Cloudflare D1 增量同步队列 (CloudOutbox)',
      badgeText: hasMore
          ? '共 $_cloudOutboxTotalCount 项 (展示前 ${_cloudOutboxItems.length} 条) · 游标 ${_cloudPullCursor ?? 0}'
          : '${_cloudOutboxItems.length} 项待推送 · 游标 ${_cloudPullCursor ?? 0}',
      badgeColor: _cloudOutboxTotalCount == 0
          ? Colors.green
          : theme.colorScheme.tertiary,
      onProcess: () async {
        if (_isSyncingCloud) return;
        setState(() => _isSyncingCloud = true);
        try {
          final report = await CloudSyncService.instance.sync();
          await _loadQueuesAndActivities();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(report.toString()),
                backgroundColor: report.success ? Colors.green : Colors.red,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Cloudflare 增量同步失败: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } finally {
          if (mounted) setState(() => _isSyncingCloud = false);
        }
      },
      onClear: () => _confirmClearQueue('CloudOutbox'),
      children: [
        if (_cloudOutboxItems.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                'CloudOutbox 为空，本地题目（含主观题自评）、笔记、卡片、记忆曲线、复习计划、做题流水均已同步到 D1 (Owner: ${_cloudSyncOwner ?? "未绑定"})',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          )
        else ...[
          for (final item in _cloudOutboxItems)
            _buildCloudOutboxTile(theme, item),
          if (hasMore)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Center(
                child: Text(
                  '还有 ${_cloudOutboxTotalCount - _cloudOutboxItems.length} 项待推送变动未在列表展开，点击“立即同步”推送到 D1',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildCloudBackupCard(ThemeData theme) {
    final enabled = _backupAutoEnabled;
    final interval = _backupIntervalDays;
    final retained = _backupMaxRetained;
    final lastTime = _lastBackupTime > 0
        ? _formatTime(_lastBackupTime)
        : '无本地快照记录';

    return Card(
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
                Icon(
                  Icons.cloud_done_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Cloudflare R2 整库冷备快照',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: (enabled ? Colors.green : Colors.grey).withValues(
                      alpha: 0.15,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    enabled ? '自动备份已开启 ($interval天/次)' : '自动备份未开启',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: enabled
                          ? Colors.green.shade700
                          : Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '配置保留: 最近 $retained 份快照  |  上次本地备份: $lastTime',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _isBackingUpCloud
                      ? null
                      : () async {
                          setState(() => _isBackingUpCloud = true);
                          try {
                            final res = await CloudBackupService.instance
                                .createBackup();
                            await _loadQueuesAndActivities();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(res.message),
                                  backgroundColor: res.success
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('冷备快照创建失败: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _isBackingUpCloud = false);
                            }
                          }
                        },
                  icon: _isBackingUpCloud
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.backup_outlined, size: 16),
                  label: const Text('立即创建冷备'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CloudSyncPage()),
                  ),
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text('云端设置'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudOutboxTile(ThemeData theme, Map<String, dynamic> item) {
    final seq = item['seq']?.toString() ?? '0';
    final kind = item['kind']?.toString() ?? '';
    final id = item['entity_id']?.toString() ?? item['id']?.toString() ?? '';
    final updatedAt = (item['updated_at'] as num?)?.toInt() ?? 0;

    String kindName;
    Color kindColor;
    switch (kind) {
      case 'question':
        kindName = '题目';
        kindColor = Colors.orange;
        break;
      case 'flashcard':
        kindName = '卡片';
        kindColor = Colors.purple;
        break;
      case 'flashcard_delete':
        kindName = '删卡';
        kindColor = Colors.red;
        break;
      case 'spaced_item':
        kindName = '记忆项';
        kindColor = Colors.blue;
        break;
      case 'review_plan':
        kindName = '计划';
        kindColor = Colors.indigo;
        break;
      case 'note':
        kindName = '笔记';
        kindColor = Colors.teal;
        break;
      case 'note_delete':
        kindName = '删笔记';
        kindColor = Colors.red;
        break;
      case 'activity_delete':
        kindName = '删流水';
        kindColor = Colors.redAccent;
        break;
      case 'activity':
        kindName = '流水';
        kindColor = Colors.green;
        break;
      default:
        kindName = kind;
        kindColor = Colors.grey;
    }

    return ListTile(
      dense: true,
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: kindColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: kindColor.withValues(alpha: 0.3)),
        ),
        child: Text(
          kindName,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: kindColor,
          ),
        ),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '#$seq',
              style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'ID: $id',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      subtitle: Text(
        '变动时间: ${_formatTime(updatedAt)}  |  Owner: ${item['owner'] ?? '-'}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.code, size: 18),
            tooltip: '查看实体当前状态',
            onPressed: () => _showOutboxEntityDialog(kind, id),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: '移出 Outbox',
            onPressed: () async {
              final db = await UserDBHelper().database;
              await db.delete(
                'CloudOutbox',
                where: 'seq = ?',
                whereArgs: [item['seq']],
              );
              await _loadQueuesAndActivities();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showOutboxEntityDialog(String kind, String id) async {
    final db = await UserDBHelper().database;
    Map<String, dynamic>? entity;
    try {
      if (kind == 'question') {
        final rows = await db.query(
          'Question',
          where: 'id = ?',
          whereArgs: [int.tryParse(id) ?? id],
        );
        if (rows.isNotEmpty) entity = rows.first;
      } else if (kind == 'flashcard') {
        final rows = await db.query(
          'CustomFlashcards',
          where: 'id = ?',
          whereArgs: [id],
        );
        if (rows.isNotEmpty) entity = rows.first;
      } else if (kind == 'flashcard_delete') {
        final rows = await db.query(
          'CloudDeletedFlashcards',
          where: 'id = ?',
          whereArgs: [id],
        );
        if (rows.isNotEmpty) entity = rows.first;
      } else if (kind == 'spaced_item') {
        final rows = await db.query(
          'SpacedReviewItem',
          where: 'item_id = ?',
          whereArgs: [id],
        );
        if (rows.isNotEmpty) entity = rows.first;
      } else if (kind == 'review_plan') {
        final rows = await db.query(
          'ReviewPlans',
          where: 'id = ?',
          whereArgs: [id],
        );
        if (rows.isNotEmpty) entity = rows.first;
      } else if (kind == 'note') {
        final rows = await db.query(
          'Notes',
          where: 'id = ?',
          whereArgs: [id],
        );
        if (rows.isNotEmpty) entity = rows.first;
      } else if (kind == 'note_delete') {
        final rows = await db.query(
          'CloudDeletedNotes',
          where: 'id = ?',
          whereArgs: [id],
        );
        if (rows.isNotEmpty) entity = rows.first;
      } else if (kind == 'activity_delete') {
        final rows = await db.query(
          'CloudDeletedActivities',
          where: 'id = ?',
          whereArgs: [id],
        );
        if (rows.isNotEmpty) entity = rows.first;
      } else if (kind == 'activity') {
        final rows = await db.query(
          'Activities',
          where: 'id = ?',
          whereArgs: [id],
        );
        if (rows.isNotEmpty) entity = rows.first;
      }
    } catch (e) {
      entity = {'error': e.toString()};
    }
    final content = entity != null
        ? const JsonEncoder.withIndent('  ').convert(entity)
        : '实体记录在本地库中不存在或已被物理清理';
    _showRawJsonDialog('变动实体详情: $kind #$id', content);
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
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
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

  /// 流水业务类型徽章（独立一列：表达业务动作及本地做题对错）
  Widget _buildActivityTypeBadge(String title, String? isRight) {
    String text;
    Color bg;
    Color fg;

    if (title == 'FlashcardReview' ||
        title == 'ReviewMemory' ||
        title == '熟练斩卡' ||
        title == '熟练斩题') {
      text = title == 'FlashcardReview'
          ? '闪卡自评'
          : title == 'ReviewMemory'
          ? '记忆自评'
          : title;
      bg = Colors.purple.withValues(alpha: 0.15);
      fg = Colors.purple.shade700;
    } else if (title == 'CutQuestion') {
      text = isRight == 'cut' ? '斩题' : '恢复';
      bg = Colors.purple.withValues(alpha: 0.15);
      fg = Colors.purple.shade700;
    } else if (title == 'RedoChapter') {
      text = '重做';
      bg = Colors.teal.withValues(alpha: 0.15);
      fg = Colors.teal.shade700;
    } else if (title == 'NoteUpload') {
      text = '笔记上传';
      bg = Colors.blue.withValues(alpha: 0.15);
      fg = Colors.blue.shade700;
    } else if (title == 'NoteDelete') {
      text = '笔记删除';
      bg = Colors.red.withValues(alpha: 0.15);
      fg = Colors.red.shade700;
    } else if (title == 'NotePull') {
      text = '笔记拉取';
      bg = Colors.indigo.withValues(alpha: 0.15);
      fg = Colors.indigo.shade700;
    } else if (title == 'YkbPull') {
      text = isRight == '1' ? '拉取·对' : '拉取·错';
      bg = Colors.indigo.withValues(alpha: 0.15);
      fg = Colors.indigo.shade700;
    } else if (title == 'ReviewAnswer') {
      text = isRight == '1' ? '复习·对' : '复习·错';
      bg = Colors.cyan.withValues(alpha: 0.15);
      fg = Colors.cyan.shade800;
    } else if (title == 'Backfill') {
      text = '补记';
      bg = Colors.brown.withValues(alpha: 0.15);
      fg = Colors.brown.shade700;
    } else {
      // NewAnswer
      if (isRight == '1') {
        text = '做题·对';
        bg = Colors.green.withValues(alpha: 0.15);
        fg = Colors.green.shade700;
      } else if (isRight == '0') {
        text = '做题·错';
        bg = Colors.orange.withValues(alpha: 0.15);
        fg = Colors.deepOrange;
      } else {
        text = '做题';
        bg = Colors.grey.withValues(alpha: 0.15);
        fg = Colors.grey.shade700;
      }
    }

    return Container(
      constraints: const BoxConstraints(minWidth: 46),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  /// 接口返回 Code 徽章（独立一列：真实展示网络返回码，绝不与做题对错混淆）
  Widget _buildHttpCodeBadge(String? code) {
    final effectiveCode = code?.trim();
    final bool hasCode = effectiveCode != null && effectiveCode.isNotEmpty;

    Color bg;
    Color fg;
    String display;

    if (!hasCode) {
      display = 'Code: --';
      bg = Colors.grey.withValues(alpha: 0.1);
      fg = Colors.grey.shade600;
    } else if (effectiveCode == '200') {
      display = 'Code 200';
      bg = Colors.green.withValues(alpha: 0.15);
      fg = Colors.green.shade700;
    } else if (effectiveCode == '309') {
      display = 'Code 309';
      bg = Colors.amber.withValues(alpha: 0.15);
      fg = Colors.brown;
    } else if (effectiveCode.startsWith('4')) {
      display = 'Code $effectiveCode';
      bg = Colors.orange.withValues(alpha: 0.15);
      fg = Colors.deepOrange;
    } else {
      display = 'Code $effectiveCode';
      bg = Colors.red.withValues(alpha: 0.15);
      fg = Colors.red.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Text(
        display,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
          color: fg,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String code, {double fontSize = 11}) {
    Color bg;
    Color fg;
    if (code == '200') {
      bg = Colors.green.withValues(alpha: 0.15);
      fg = Colors.green.shade700;
    } else if (code == '已暂停') {
      bg = Colors.red.withValues(alpha: 0.15);
      fg = Colors.red.shade700;
    } else if (code == '发包中') {
      bg = Colors.amber.withValues(alpha: 0.18);
      fg = Colors.brown.shade700;
    } else if (code == '退避中') {
      bg = Colors.orange.withValues(alpha: 0.15);
      fg = Colors.deepOrange;
    } else if (code.contains('斩') || code == 'cut') {
      bg = Colors.purple.withValues(alpha: 0.15);
      fg = Colors.purple.shade700;
    } else if (code.contains('重做') || code == 'redo') {
      bg = Colors.teal.withValues(alpha: 0.15);
      fg = Colors.teal.shade700;
    } else if (code.contains('笔记') ||
        code.contains('上传') ||
        code.contains('拉取')) {
      bg = Colors.blue.withValues(alpha: 0.15);
      fg = Colors.blue.shade700;
    } else if (code.startsWith('4') || code == '错题') {
      bg = Colors.orange.withValues(alpha: 0.15);
      fg = Colors.deepOrange;
    } else if (code.startsWith('5') || code == 'ERR' || code.contains('删除')) {
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

  String _resolveQueueStatusCode(
    Map<String, dynamic> item,
    SyncResponseRecord? cached,
  ) {
    if (cached != null && cached.code.isNotEmpty) return cached.code;
    final state = item['queue_state']?.toString() ?? 'pending';
    if (state == 'paused') return '已暂停';
    if (state == 'sending') return '发包中';
    final nextAt = (item['next_attempt_at'] as num?)?.toInt() ?? 0;
    if (nextAt > DateTime.now().millisecondsSinceEpoch) return '退避中';
    final retry = (item['retry_count'] as num?)?.toInt() ?? 0;
    return retry > 0 ? '重试' : '待同步';
  }

  String _formatQueueMetaLine(Map<String, dynamic> item) {
    final createdAt = (item['created_at'] as num?)?.toInt() ?? 0;
    final retry = (item['retry_count'] as num?)?.toInt() ?? 0;
    final state = item['queue_state']?.toString() ?? 'pending';
    final owner = item['owner_user_id']?.toString() ?? '';
    final nextAt = (item['next_attempt_at'] as num?)?.toInt() ?? 0;
    final parts = <String>[
      '状态: $state',
      '重试: $retry',
      if (owner.isNotEmpty) '账号: $owner' else '账号: 未认领',
      if (nextAt > DateTime.now().millisecondsSinceEpoch)
        '下次重试: ${_formatTime(nextAt)}'
      else
        '时间: ${_formatTime(createdAt)}',
    ];
    return parts.join('  |  ');
  }

  Widget _buildYkbQueueTile(ThemeData theme, Map<String, dynamic> item) {
    final type = item['type']?.toString() ?? '';
    final retry = (item['retry_count'] as num?)?.toInt() ?? 0;
    final lastError = item['last_error']?.toString();
    final queueId = item['id']?.toString() ?? '';
    final itemId = item['item_id']?.toString();

    final cached =
        SyncResponseCache.instance.getByQueueId(queueId) ??
        SyncResponseCache.instance.getByItemId(itemId, type: type);
    final String statusCode = _resolveQueueStatusCode(item, cached);

    final typeNames = {'cut': '斩题同步', 'answer': '做题提交', 'redo_chapter': '章节重做'};

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
            _formatQueueMetaLine(item),
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
              final respJson =
                  cached?.rawResponse ??
                  item['last_response']?.toString() ??
                  const JsonEncoder.withIndent('  ').convert({
                    'status': item['queue_state'] ?? 'pending',
                    'message': '队列项尚未向服务器请求或未生成响应',
                    'retry_count': retry,
                    'last_error': lastError,
                  });
              _showRawJsonDialog('YkbSyncQueue Respond', respJson);
            },
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: '删除该项',
            onPressed: () async {
              final db = await UserDBHelper().database;
              await db.delete(
                'YkbSyncQueue',
                where: 'id = ?',
                whereArgs: [item['id']],
              );
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
    final retry = (item['retry_count'] as num?)?.toInt() ?? 0;
    final lastError = item['last_error']?.toString();
    final queueId = item['id']?.toString() ?? '';
    final questionId = item['question_id']?.toString();
    final cacheType = action == 'upload' ? 'note_upload' : 'note_delete';

    final cached =
        SyncResponseCache.instance.getByQueueId(queueId) ??
        SyncResponseCache.instance.getByItemId(questionId, type: cacheType);
    final String statusCode = _resolveQueueStatusCode(item, cached);

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
            _formatQueueMetaLine(item),
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
              final respJson =
                  cached?.rawResponse ??
                  item['last_response']?.toString() ??
                  const JsonEncoder.withIndent('  ').convert({
                    'status': 'pending',
                    'message': '笔记队列项尚未向服务器请求或未生成响应',
                    'retry_count': retry,
                    'last_error': lastError,
                  });
              _showRawJsonDialog('NoteSyncQueue Respond', respJson);
            },
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: '删除该项',
            onPressed: () async {
              final db = await UserDBHelper().database;
              await db.delete(
                'NoteSyncQueue',
                where: 'id = ?',
                whereArgs: [item['id']],
              );
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
                    const Text(
                      'SQLite 数据库状态',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
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
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${entry.key}: ${entry.value}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
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
                    Text(
                      '网络 API 连通性测试 (Ping)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('医考帮 API 服务器 (getUserInfo 诊断)'),
                  subtitle: Text(
                    _ykbPingResult ?? '$rootUrl/User/Main/getUserInfo',
                    style: const TextStyle(fontSize: 12),
                  ),
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
              child: Icon(
                Icons.science_outlined,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            title: const Text(
              'API 调试台 (Playground)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('发送任意医考帮请求，自动生成加密签名与完整请求头'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              pushAdaptiveModalPage(
                context,
                desktopConstraints: const BoxConstraints(
                  maxWidth: 860,
                  maxHeight: 850,
                ),
                builder: (_) => const ApiPlaygroundPage(),
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
                    const Text(
                      'SharedPreferences 键值浏览器',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Text(
                      '${filteredPrefs.length} 个配置项',
                      style: const TextStyle(fontSize: 12),
                    ),
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
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          tooltip: '复制内容',
                          onPressed: () =>
                              _copyToClipboard(item.key, item.value.toString()),
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
