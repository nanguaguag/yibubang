import 'package:flutter/material.dart';
import '../services/bank_subscription_service.dart';

class BankLinkImportChoice {
  const BankLinkImportChoice(this.url, this.subscribe);
  final String url;
  final bool subscribe;
}

class BankLinkImportDialog extends StatefulWidget {
  const BankLinkImportDialog({super.key});
  @override
  State<BankLinkImportDialog> createState() => _BankLinkImportDialogState();
}

class _BankLinkImportDialogState extends State<BankLinkImportDialog> {
  final _controller = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _subscribe = true;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('从链接导入'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('下载 ZIP 或 SQLite 题库文件，校验后导入。'),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '题库文件链接',
                hintText: 'https://…',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                try {
                  BankSubscriptionService.validateUrl(value ?? '');
                  return null;
                } catch (_) {
                  return '请输入有效的 HTTPS 链接';
                }
              },
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _subscribe,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('订阅后续更新'),
              subtitle: const Text('复用本次下载，不重复添加已有来源'),
              onChanged: (value) => setState(() => _subscribe = value!),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(
              context,
              BankLinkImportChoice(
                BankSubscriptionService.validateUrl(_controller.text),
                _subscribe,
              ),
            );
          }
        },
        child: const Text('下载并导入'),
      ),
    ],
  );
}
