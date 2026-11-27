import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/font_controller.dart';

class FontSettingsPage extends StatefulWidget {
  const FontSettingsPage({super.key});

  @override
  State<FontSettingsPage> createState() => _FontSettingsPageState();
}

class _FontSettingsPageState extends State<FontSettingsPage> {
  final _familyInput = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final fonts = FontController.instance;
    _familyInput.text = fonts.isImported ? '' : fonts.family ?? '';
  }

  @override
  void dispose() {
    _familyInput.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ttf', 'otf'],
        withData: true,
      );
      if (result == null) return;
      final file = result.files.single;
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      await FontController.instance.importFont(file.name, bytes);
      if (mounted) _familyInput.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('字体导入失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fonts = FontController.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('字体')),
      body: ListenableBuilder(
        listenable: fonts,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('当前字体：${fonts.label}'),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('字体预览', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    const Text(
                      '医学生刷题：诊断、治疗与临床分析。\n'
                      'ABCDEFGHIJKLMNOPQRSTUVWXYZ\n'
                      'abcdefghijklmnopqrstuvwxyz 0123456789\n'
                      'α β γ μ ± × ÷ ≤ ≥ → Ⅰ Ⅱ Ⅲ',
                      style: TextStyle(fontSize: 18, height: 1.6),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '加粗预览：正确答案与重点解析',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _familyInput,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: '系统字体名称',
                hintText: '例如 Microsoft YaHei 或 Noto Sans CJK SC',
                helperText: '需已安装在当前设备；找不到时使用系统回退字体。',
                helperMaxLines: 3,
                border: OutlineInputBorder(),
              ),
              onSubmitted: _busy ? null : (value) => fonts.setSystemFont(value),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => fonts.setSystemFont(_familyInput.text),
                  child: const Text('应用系统字体'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || kIsWeb ? null : _import,
                  icon: const Icon(Icons.file_open_outlined),
                  label: Text(
                    kIsWeb
                        ? '网页版本不支持导入字体'
                        : (_busy ? '正在导入…' : '导入字体 TTF / OTF'),
                  ),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await fonts.setSystemFont(null);
                          if (mounted) _familyInput.clear();
                        },
                  child: const Text('恢复系统默认'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '字体应用于整个界面和题目，立即生效并自动保存。'
              '导入的字体会复制到应用目录，原文件移动后仍可使用。'
              '建议选择包含中文字形的字体；刷题字号仍可单独调整。',
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 8),
              const Text('网页版本仅支持选择设备已安装字体；导入字体文件需要桌面或移动应用。'),
            ],
          ],
        ),
      ),
    );
  }
}
