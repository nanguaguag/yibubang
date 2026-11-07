import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../models/question_bank.dart';
import '../services/bank_export_service.dart';
import 'bank_action_button.dart';

/// Shared export action for management cards and the detail page.
class BankExportButton extends StatefulWidget {
  const BankExportButton({
    super.key,
    required this.bank,
    this.enabled = true,
    this.onBusyChanged,
  });
  final QuestionBank bank;
  final bool enabled;
  final ValueChanged<bool>? onBusyChanged;

  @override
  State<BankExportButton> createState() => _BankExportButtonState();
}

class _BankExportButtonState extends State<BankExportButton> {
  bool _busy = false;
  bool _packing = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    widget.onBusyChanged?.call(true);
    try {
      var roots = <Map<String, dynamic>>[];
      if (widget.bank.bankId == 'legacy_combined') {
        // Old combined banks require choosing the subject to export.
        final db = await openDatabase(
          widget.bank.localPath,
          readOnly: true,
          singleInstance: false,
        );
        try {
          roots = await db.query(
            'Identity',
            where: 'parent_id = ?',
            whereArgs: ['-1'],
          );
        } finally {
          await db.close();
        }
      }
      if (!mounted) return;
      var rootId = roots.firstOrNull?['id']?.toString();
      final asZip = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
            title: const Text('导出题库'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('导出的题库可在其他设备导入，不包含个人做题记录。'),
                if (roots.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: rootId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '选择学科'),
                    items: roots
                        .map(
                          (r) => DropdownMenuItem(
                            value: r['id'].toString(),
                            child: Text('${r['name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => update(() => rootId = value),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('SQLite'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('ZIP'),
              ),
            ],
          ),
        ),
      );
      if (asZip == null || !mounted) return;
      setState(() => _packing = true);
      final path = await BankExportService.save(
        widget.bank,
        asZip: asZip,
        rootId: rootId,
      );
      if (path != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已导出：$path')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _packing = false;
        });
      }
      widget.onBusyChanged?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: _packing ? '正在打包题库' : '导出题库',
    onPressed: !widget.enabled || _busy || !widget.bank.isInstalled
        ? null
        : _export,
    icon: _packing
        ? const BankActionProgress(label: '正在打包题库')
        : const Icon(Icons.ios_share_rounded),
  );
}
