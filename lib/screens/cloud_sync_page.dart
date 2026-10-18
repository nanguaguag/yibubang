import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/cloud_sync_service.dart';
import '../widgets/common/info_card.dart';
import '../widgets/common/styled_tile.dart';

/// 云端做题记录多端同步配置页面 (符合 Material 3 规范)
class CloudSyncPage extends StatefulWidget {
  const CloudSyncPage({super.key});

  @override
  State<CloudSyncPage> createState() => _CloudSyncPageState();
}

class _CloudSyncPageState extends State<CloudSyncPage> {
  final _syncService = CloudSyncService.instance;
  PairingCodeInfo? _currentPairingCode;
  Timer? _countdownTimer;
  int _secondsRemaining = 0;

  bool _isGeneratingCode = false;

  // 健康检查状态
  HealthCheckResult? _healthResult;
  bool _isCheckingHealth = false;

  @override
  void initState() {
    super.initState();
    _syncService.addListener(_onServiceUpdate);
    _initData();
  }

  Future<void> _initData() async {
    await _syncService.init();
    _runHealthCheck();
    _restoreActivePairingCode();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _syncService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  /// 检查并恢复当前活跃的未过期配对码
  Future<void> _restoreActivePairingCode() async {
    final active = await _syncService.getActivePairingCode();
    if (active != null && !active.isExpired && mounted) {
      setState(() {
        _currentPairingCode = active;
        _secondsRemaining = active.expiresInSeconds;
      });
      _startCountdown();
    }
  }

  /// 执行健康检查
  Future<void> _runHealthCheck() async {
    if (_isCheckingHealth) return;
    setState(() => _isCheckingHealth = true);
    final res = await _syncService.checkHealth();
    if (mounted) {
      setState(() {
        _healthResult = res;
        _isCheckingHealth = false;
      });
    }
  }

  // ------------------------------------------------------------------
  // 业务动作
  // ------------------------------------------------------------------

  /// 首次开启：注册为首台设备
  Future<void> _handleRegisterFirstDevice() async {
    try {
      final success = await _syncService.registerCurrentDevice();
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已成功开启云同步！')),
        );
        // 注册成功后，立即静默触发一次初次数据推送
        _syncService.sync();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('开启失败：$e')),
      );
    }
  }

  /// 从设备：输入配对码兑换
  Future<void> _handleEnterPairingCode() async {
    final codeController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入配对码'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '在已开启同步的主设备上点击「生成配对码」，在此输入显示的 6 位数字：',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: codeController,
                keyboardType: TextInputType.number,
                autofocus: true,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
                decoration: const InputDecoration(
                  hintText: '000000',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                validator: (val) {
                  if (val == null || val.trim().length != 6) {
                    return '请输入 6 位数字配对码';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(ctx).pop(codeController.text.trim());
              }
            },
            child: const Text('配对并同步'),
          ),
        ],
      ),
    );

    if (code == null || code.isEmpty || !mounted) return;

    try {
      final success = await _syncService.claimPairingCode(code);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('设备配对成功！正在同步做题记录...')),
        );
        // 配对成功后触发拉取
        await _syncService.sync();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('做题记录同步完成！')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('配对失败：$e')),
      );
    }
  }

  /// 使用备份口令恢复
  Future<void> _handleRestoreWithPassphrase() async {
    final passController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final pass = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('使用备份恢复口令'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '输入曾经备份的 13 位云端恢复口令（如 AB12CD-EF34GH）：',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: passController,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  fontFamily: 'monospace',
                ),
                decoration: const InputDecoration(
                  hintText: 'XXXXXX-XXXXXX',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 6) {
                    return '请输入正确的备份口令';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(ctx).pop(passController.text.trim());
              }
            },
            child: const Text('恢复并同步'),
          ),
        ],
      ),
    );

    if (pass == null || pass.isEmpty || !mounted) return;

    try {
      final success = await _syncService.restoreWithPassphrase(pass);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('口令验证成功！正在拉取做题记录...')),
        );
        await _syncService.sync();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('历史做题记录恢复完成！')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('恢复失败：$e')),
      );
    }
  }

  /// 主设备：生成配对码 (带加载状态)
  Future<void> _handleGeneratePairingCode() async {
    if (_isGeneratingCode) return;
    setState(() => _isGeneratingCode = true);

    try {
      final info = await _syncService.createPairingCode();
      if (!mounted) return;

      setState(() {
        _currentPairingCode = info;
        _secondsRemaining = info.expiresInSeconds;
      });

      _startCountdown();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成配对码失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _isGeneratingCode = false);
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
        } else {
          _currentPairingCode = null;
          timer.cancel();
        }
      });
    });
  }

  /// 手动触发同步
  Future<void> _handleManualSync() async {
    final result = await _syncService.sync();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.toString()),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// 重命名设备
  Future<void> _handleRenameDevice() async {
    final controller = TextEditingController(text: _syncService.deviceName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改设备名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '如：我的 iPad、办公室电脑',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      await _syncService.setDeviceName(newName);
    }
  }

  /// 查看恢复口令
  void _handleShowPassphrase() {
    final pass = _syncService.passphrase;
    if (pass == null) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('备份恢复口令'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '请妥善保管此口令。若所有设备均丢失，可在任何设备凭此口令找回云端进度：',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                pass,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: pass));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制口令到剪贴板')),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('复制'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  /// 解除绑定确认
  Future<void> _handleUnbind() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解除云同步绑定'),
        content: const Text(
          '解除绑定将清除本机的云端授权凭证，不会删除本机的现有做题数据，也不会清空云端备份。确定继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('解除绑定'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _syncService.unbind();
      setState(() => _currentPairingCode = null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已解除云同步绑定')),
      );
    }
  }

  // ------------------------------------------------------------------
  // UI 构建
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isConfigured = _syncService.isConfigured;

    return Scaffold(
      appBar: AppBar(
        title: const Text('云端做题记录同步'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          _buildStatusBanner(colorScheme, isConfigured),
          const SizedBox(height: 20),
          if (!isConfigured) ...[
            _buildSetupGuide(colorScheme),
          ] else ...[
            _buildPairingSection(colorScheme),
            const SizedBox(height: 20),
            _buildSettingsSection(colorScheme),
            const SizedBox(height: 20),
            _buildDangerSection(colorScheme),
          ],
        ],
      ),
    );
  }

  /// 状态概览卡片 (Material 3 Elevated/Container Card)
  Widget _buildStatusBanner(ColorScheme colorScheme, bool isConfigured) {
    final isSyncing = _syncService.isSyncing;
    final lastSyncText = _formatTimeAgo(_syncService.lastSyncDateTime);

    return Container(
      decoration: BoxDecoration(
        color: isConfigured
            ? colorScheme.primaryContainer.withValues(alpha: 0.6)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConfigured
              ? colorScheme.primary.withValues(alpha: 0.2)
              : colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isConfigured
                      ? colorScheme.primary.withValues(alpha: 0.15)
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isConfigured ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                  color: isConfigured
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isConfigured ? '云端同步运行中' : '尚未开启云同步',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isConfigured
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isConfigured ? '上次同步：$lastSyncText' : '支持多设备无缝增量协同刷题',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isConfigured
                                ? colorScheme.onPrimaryContainer
                                    .withValues(alpha: 0.8)
                                : colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isConfigured) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '当前设备：${_syncService.deviceName}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: isSyncing ? null : _handleManualSync,
                  icon: isSyncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync, size: 18),
                  label: Text(isSyncing ? '同步中...' : '立即同步'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 未配置时的引导卡片 (包含“首台开启”、“输入配对码”、“口令恢复”)
  Widget _buildSetupGuide(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '开启方式',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        InfoCard(
          children: [
            BaseTile(
              onTap: _handleRegisterFirstDevice,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    TileIcon(
                      icon: Icons.add_to_home_screen_rounded,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '作为第一台设备开启',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '为此设备建立云同步并上传现有刷题进度',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
            BaseTile(
              onTap: _handleEnterPairingCode,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    TileIcon(
                      icon: Icons.qr_code_scanner_rounded,
                      color: colorScheme.secondary,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '输入配对码连接到其他设备',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '加入已有设备的同步网络，合并刷题记录',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
            BaseTile(
              onTap: _handleRestoreWithPassphrase,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    TileIcon(
                      icon: Icons.key_rounded,
                      color: colorScheme.tertiary,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '使用备份恢复口令导入',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '所有设备均遗失时，使用 13 位备份口令恢复',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 多设备配对卡片 (已开启同步状态)
  Widget _buildPairingSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '设备互联',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        InfoCard(
          children: [
            IconTile(
              icon: Icons.phonelink_ring_rounded,
              label: '生成设备配对码',
              trailing: _isGeneratingCode
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _isGeneratingCode ? null : _handleGeneratePairingCode,
            ),
            if (_currentPairingCode != null) _buildPairingCodeCard(colorScheme),
            IconTile(
              icon: Icons.key_rounded,
              label: '备份恢复口令',
              trailing: const Icon(Icons.chevron_right),
              onTap: _handleShowPassphrase,
            ),
          ],
        ),
      ],
    );
  }

  /// 展开展示的配对码组件 (自动记忆，不因切页面丢失)
  Widget _buildPairingCodeCard(ColorScheme colorScheme) {
    final code = _currentPairingCode!.code;
    final minutes = (_secondsRemaining / 60).floor();
    final seconds = (_secondsRemaining % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.all(16),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Column(
        children: [
          Text(
            '请在另一台设备输入以下 6 位配对码',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${code.substring(0, 3)}  ${code.substring(3)}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: colorScheme.primary,
                      ),
                ),
                const SizedBox(width: 14),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  tooltip: '复制配对码',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('配对码已复制')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.timer_outlined, size: 14, color: colorScheme.error),
              const SizedBox(width: 4),
              Text(
                '剩余有效时间：$minutes:$seconds (退出重进依然有效)',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 设置与选项
  Widget _buildSettingsSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '同步设置',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        InfoCard(
          children: [
            IconTile(
              icon: Icons.devices_rounded,
              label: '设备名称',
              value: _syncService.deviceName,
              onTap: _handleRenameDevice,
            ),
            IconTile(
              icon: Icons.autorenew_rounded,
              label: '应用启动时自动同步',
              trailing: Switch(
                value: _syncService.autoSync,
                onChanged: (v) => _syncService.setAutoSync(v),
              ),
            ),
            // 带有绿点/红点的健康检查卡片
            BaseTile(
              onTap: _runHealthCheck,
              child: Row(
                children: [
                  const TileIcon(icon: Icons.dns_outlined),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '云服务节点',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Cloudflare 边缘极速 (点击重新检测)',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  _buildHealthBadge(),
                ],
              ),
            ),
            IconTile(
              icon: Icons.sync_problem_rounded,
              label: '全量强制重新同步',
              value: '对齐历史数据',
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('全量强制重新同步'),
                    content: const Text(
                      '将重置同步时间游标，强制将本机所有历史作答与流水与云端双向完整对齐，用于修复历史日期格子墙或跨设备未同步的问题。确定执行吗？',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('开始全量对齐'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  final res = await _syncService.sync(force: true);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(res.toString())),
                  );
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  /// 健康检查状态指示器 (绿点 / 红点)
  Widget _buildHealthBadge() {
    if (_isCheckingHealth) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final isOk = _healthResult?.isHealthy ?? false;
    final color = _healthResult == null
        ? Colors.amber
        : (isOk ? Colors.green : Colors.red);
    final text = _healthResult == null
        ? '检测中'
        : (isOk ? '${_healthResult!.latencyMs}ms' : '异常');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  /// 危险操作区
  Widget _buildDangerSection(ColorScheme colorScheme) {
    return InfoCard(
      children: [
        IconTile(
          icon: Icons.link_off_rounded,
          label: '解除此设备的云同步绑定',
          iconColor: colorScheme.error,
          labelColor: colorScheme.error,
          onTap: _handleUnbind,
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // 辅助函数
  // ------------------------------------------------------------------
  String _formatTimeAgo(DateTime? time) {
    if (time == null) return '从未同步';
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${time.month}月${time.day}日 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
