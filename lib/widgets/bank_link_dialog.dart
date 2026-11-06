import 'package:flutter/material.dart';

import '../services/bank_subscription_service.dart';

class BankLinkDialog extends StatefulWidget {
  const BankLinkDialog({
    super.key,
    required this.title,
    this.initialValue = '',
  });
  final String title;
  final String initialValue;

  @override
  State<BankLinkDialog> createState() => _BankLinkDialogState();
}

class _BankLinkDialogState extends State<BankLinkDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(
        context,
        BankSubscriptionService.validateUrl(_controller.text),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        onFieldSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          labelText: 'HTTPS 订阅地址',
          hintText: 'ZIP、SQLite 或 JSON 链接',
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
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('确定')),
    ],
  );
}
