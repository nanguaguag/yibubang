import 'package:flutter/material.dart';

import '../models/bank_progress.dart';
import '../models/bank_creation_report.dart';
import '../widgets/bank_creation_dialogs.dart';
import '../widgets/bank_identity_tree.dart';
import '../services/bank_creation_service.dart';
import '../widgets/bank_progress_view.dart';
import '../widgets/bank_action_button.dart';

class BankCreationPage extends StatefulWidget {
  const BankCreationPage({super.key, this.service});
  final BankCreationService? service;

  @override
  State<BankCreationPage> createState() => _BankCreationPageState();
}

class _BankCreationPageState extends State<BankCreationPage> {
  late final _service = widget.service ?? BankCreationService();
  late Future<List<BankIdentityNode>> _identities;
  final _selected = <String>{};
  BankTaskCancellation? _cancellation;
  BankProgress? _progress;
  bool _busy = false;
  bool _confirming = false;
  BankCreationReport? _report;
  bool _terminated = false;

  @override
  void initState() {
    super.initState();
    _identities = _service.identities();
  }

  @override
  void dispose() {
    _cancellation?.cancelled = true;
    super.dispose();
  }

  Future<BankCreationErrorAction> _onError(BankCreationIssue issue) async {
    if (!mounted || (_cancellation?.cancelled ?? false)) {
      return BankCreationErrorAction.terminate;
    }
    return showBankCreationIssue(context, issue);
  }

  Future<void> _showReport() => showDialog<void>(
    context: context,
    builder: (_) =>
        BankCreationReportDialog(report: _report!, terminated: _terminated),
  );

  Future<void> _create(List<BankIdentityNode> nodes) async {
    if (_busy || _confirming) return;
    final roots = nodes.expand((n) => n.selectedRoots(_selected)).toList();
    if (roots.isEmpty) return;
    setState(() => _confirming = true);
    bool confirmed;
    try {
      confirmed = await showBankCreationConfirmation(
        context,
        bankCount: roots.length,
      );
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
    if (!confirmed || !mounted) return;
    final cancellation = BankTaskCancellation();
    final report = BankCreationReport();
    setState(() {
      _busy = true;
      _progress = null;
      _cancellation = cancellation;
      _report = report;
      _terminated = false;
    });
    try {
      for (final root in roots) {
        cancellation.check();
        try {
          await _service.create(
            root,
            cancellation: cancellation,
            report: report,
            onError: _onError,
            onProgress: (progress) {
              if (mounted) setState(() => _progress = progress);
            },
          );
        } on BankTaskCancelled {
          rethrow;
        } on BankCreationTerminated {
          rethrow;
        } catch (error) {
          // A validation/installation failure cannot produce a usable bank.
          // Ignoring it continues with the next selected subject.
          await report.handle(
            BankCreationIssue(
              bankName: root.name,
              stage: '保存题库',
              item: root.name,
              message: bankCreationErrorMessage(error),
            ),
            error,
            _onError,
          );
        }
      }
    } on BankTaskCancelled {
      _terminated = true;
    } on BankCreationTerminated {
      _terminated = true;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = BankProgress(
            stage: _terminated ? '已终止创建' : '创建完成',
            finished: true,
            questions: report.savedQuestionCount,
          );
        });
      }
    }
    if (!mounted) return;
    await _showReport();
    if (mounted && !_terminated && report.savedBanks.isNotEmpty) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('创建题库')),
      body: FutureBuilder<List<BankIdentityNode>>(
        future: _identities,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${snapshot.error}'),
                  TextButton(
                    onPressed: () => setState(() {
                      _identities = _service.identities();
                    }),
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: BankActionProgress(label: '正在加载题库'));
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          '选择学科后，抓取全部课程与章节并保存为独立题库。选择上级学科会包含下级；重复选择只制作一次。',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        BankIdentityTree(
                          nodes: snapshot.data!,
                          selected: _selected,
                          enabled: !_busy && !_confirming,
                          onChanged: (selection) => setState(() {
                            _selected
                              ..clear()
                              ..addAll(selection);
                          }),
                        ),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_progress != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: BankProgressView(
                                progress: _progress!,
                                showIndicator: false,
                              ),
                            ),
                          FilledButton.icon(
                            onPressed: _busy || _confirming || _selected.isEmpty
                                ? null
                                : () => _create(snapshot.data!),
                            icon: _busy
                                ? BankActionProgress(
                                    value: _progress?.fraction,
                                    label: _progress?.stage,
                                  )
                                : const Icon(Icons.add_rounded),
                            label: Text(_busy ? '正在创建' : '开始创建'),
                          ),
                          if (_busy)
                            TextButton(
                              onPressed: (_cancellation?.cancelled ?? false)
                                  ? null
                                  : () => setState(() {
                                      _cancellation?.cancelled = true;
                                    }),
                              child: Text(
                                (_cancellation?.cancelled ?? false)
                                    ? '正在终止…'
                                    : '终止创建',
                              ),
                            ),
                          if (!_busy && _report != null)
                            TextButton(
                              onPressed: _showReport,
                              child: const Text('查看创建报告'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
