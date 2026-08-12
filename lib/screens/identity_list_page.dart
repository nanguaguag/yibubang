import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../models/identity.dart';
import '../common/app_strings.dart';
import '../models/question_bank.dart';
import '../repositories/question_bank_repository.dart';

class IdentityListPage extends StatefulWidget {
  final String parentId;
  final String title;

  const IdentityListPage({
    super.key,
    this.parentId = '-1',
    this.title = '选择题库',
  });

  @override
  State<IdentityListPage> createState() => _IdentityListPageState();
}

class _IdentityListPageState extends State<IdentityListPage> {
  late Future<List<Identity>> _identitiesFuture;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _loadSelectedId();
    _identitiesFuture = getChildrenIdentities(widget.parentId);
  }

  Future<void> _loadSelectedId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedId = prefs.getString('identityId') ?? '30401';
    });
  }

  Future<bool> _hasChildren(String identityId) async {
    final children = await getChildrenIdentities(identityId);
    return children.isNotEmpty;
  }

  Future<void> _onSelect(Identity identity) async {
    final choosable = AppStrings.choosableIdentities.contains(identity.id);
    final hasChildren = await _hasChildren(identity.id);
    if (choosable) {
      final prefs = await SharedPreferences.getInstance();
      QuestionBankSpec? bankSpec;
      for (final spec in QuestionBankDefaults.all) {
        if (spec.identityId == identity.id) {
          bankSpec = spec;
          break;
        }
      }
      final repository = QuestionBankRepository();
      final bank =
          bankSpec == null ? null : await repository.find(bankSpec.bankId);
      final activeBankId = await repository.activeBankId();
      if (bank != null && bank.isInstalled && bank.enabled) {
        if (activeBankId != bank.bankId) {
          await repository.selectBank(bank.bankId);
        }
        await prefs.setString('identityId', identity.id);
        setState(() {
          _selectedId = identity.id;
        });
        return;
      }

      // 新题库尚未安装时，旧版合并题库只作为一次性的兼容回退。
      // 如果已经在旧库中，不重复 selectBank，避免每次点击都提示“已切换”。
      final legacy = await repository.find('legacy_combined');
      if (legacy != null && legacy.isInstalled && legacy.enabled) {
        if (activeBankId != legacy.bankId) {
          await repository.selectBank(legacy.bankId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('当前使用旧版合并题库（兼容回退）')),
            );
          }
        }
        await prefs.setString('identityId', identity.id);
        setState(() {
          _selectedId = identity.id;
        });
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${identity.name}尚未安装或已禁用，请在题库管理中处理')),
        );
      }
      return;
    }
    if (hasChildren) {
      Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (_) => IdentityListPage(
            parentId: identity.id,
            title: '选择题库 - ${identity.name}',
          ),
        ),
      );
      return;
    }
    return;
  }

  Widget _buildOption(Identity item) {
    final choosable = AppStrings.choosableIdentities.contains(item.id);
    final choosabledir = AppStrings.choosableIdentiyDir.contains(item.id);
    final selected = item.id == _selectedId;
    return ElevatedButton(
      onPressed: (choosable || choosabledir) ? () => _onSelect(item) : null,
      style: ElevatedButton.styleFrom(
        backgroundColor:
            selected ? Theme.of(context).colorScheme.primary : Colors.white,
        foregroundColor: selected ? Colors.white : Colors.black87,
        elevation: selected ? 4 : 2,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(
                  AppStrings.identityIconMap[item.id] ?? Icons.book_outlined,
                  size: 20,
                  color: selected
                      ? Colors.white
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8), // 固定间距，避免挤压

          if (selected)
            const Icon(Icons.check_circle, color: Colors.white)
          else if (choosable)
            const Icon(Icons.radio_button_unchecked, color: Colors.black87)
          else if (choosabledir)
            const Icon(Icons.arrow_forward_ios, size: 16)
          else
            const Text(
              '（暂不提供）',
              style: TextStyle(fontSize: 12),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<List<Identity>>(
        future: _identitiesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const Center(child: Text('加载失败，请重试'));
          }
          final items = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Center(
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width * 0.8,
                    child: _buildOption(items[index]),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
