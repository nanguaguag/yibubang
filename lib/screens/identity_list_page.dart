import '../common/adaptive_route.dart';
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
  final Set<String> _choosableIdentityIds = <String>{};
  final Set<String> _directoryIdentityIds = <String>{};
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _identitiesFuture = getChildrenIdentities(widget.parentId);
    _loadIdentityOptions();
    _loadSelectedId();
  }

  Future<void> _loadIdentityOptions() async {
    final identities = await _identitiesFuture;
    final repository = QuestionBankRepository();
    final banks = await repository.listBanks();
    final choosableIds = banks
        .map((bank) => bank.identityId)
        .where((identityId) => identityId.isNotEmpty)
        .toSet();
    final directoryIds = <String>{};
    for (final identity in identities) {
      if (await _hasChildren(identity.id)) {
        directoryIds.add(identity.id);
      }
    }
    if (!mounted) return;
    setState(() {
      _choosableIdentityIds
        ..clear()
        ..addAll(choosableIds);
      _directoryIdentityIds
        ..clear()
        ..addAll(directoryIds);
    });
  }

  Future<void> _loadSelectedId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedId = prefs.getString('identityId');
    });
  }

  Future<bool> _hasChildren(String identityId) async {
    final children = await getChildrenIdentities(identityId);
    return children.isNotEmpty;
  }

  Future<void> _onSelect(Identity identity) async {
    final hasChildren = await _hasChildren(identity.id);
    final repository = QuestionBankRepository();
    final banks = await repository.listBanks();
    final prefs = await SharedPreferences.getInstance();
    final activeBankId = await repository.activeBankId();

    QuestionBank? bank;
    for (final candidate in banks) {
      if (candidate.bankId != 'legacy_combined' &&
          candidate.identityId == identity.id) {
        bank = candidate;
        break;
      }
    }

    if (bank != null) {
      if (bank.isInstalled && bank.enabled) {
        if (activeBankId != bank.bankId) {
          await repository.selectBank(bank.bankId);
        }
        await prefs.setString('identityId', identity.id);
        if (!mounted) return;
        setState(() {
          _selectedId = identity.id;
        });
        return;
      }

      // 新题库尚未安装时，旧版合并题库只作为一次性的兼容回退。
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
        if (!mounted) return;
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
      if (!mounted) return;
      Navigator.of(context).push(
        adaptivePageRoute(
          builder: (_) => IdentityListPage(
            parentId: identity.id,
            title: '选择题库 - ${identity.name}',
          ),
        ),
      );
    }
  }

  Widget _buildOption(Identity item) {
    final choosable = _choosableIdentityIds.contains(item.id);
    final choosabledir = _directoryIdentityIds.contains(item.id);
    final selected = item.id == _selectedId;
    return ElevatedButton(
      onPressed: (choosable || choosabledir) ? () => _onSelect(item) : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surface,
        foregroundColor: selected
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.onSurface,
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
                      ? Theme.of(context).colorScheme.onPrimary
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
