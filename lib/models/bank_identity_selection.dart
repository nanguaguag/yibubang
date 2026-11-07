import 'package:flutter/foundation.dart';
import '../services/bank_creation_service.dart';

/// Index once, then update the chosen subtree and its ancestors only. Counts
/// describe selectable leaves; a full parent still enters selectedRoots once.
class BankIdentitySelection {
  BankIdentitySelection(List<BankIdentityNode> roots, Set<String> selected) {
    _IdentitySelectionEntry index(
      BankIdentityNode node,
      _IdentitySelectionEntry? parent,
    ) {
      final entry = _IdentitySelectionEntry(node, parent);
      _entries[node.id] = entry;
      entry.children.addAll(node.children.map((child) => index(child, entry)));
      entry.total = entry.children.isEmpty
          ? 1
          : entry.children.fold(0, (sum, child) => sum + child.total);
      return entry;
    }

    _roots = roots.map((root) => index(root, null)).toList();
    replace(selected);
  }
  final _entries = <String, _IdentitySelectionEntry>{};
  late final List<_IdentitySelectionEntry> _roots;
  final _selected = <String>{};
  Set<String> get selected => Set.unmodifiable(_selected);
  bool get isEmpty => _selected.isEmpty;
  ValueListenable<bool?> value(String id) => _entries[id]!.value;

  void _publish(_IdentitySelectionEntry entry) {
    final bool? value = entry.count == entry.total
        ? true
        : entry.count == 0
        ? false
        : null;
    if (value == true) {
      _selected.add(entry.node.id);
    } else {
      _selected.remove(entry.node.id);
    }
    entry.value.value = value;
  }

  void toggle(String id) {
    final entry = _entries[id]!;
    final include = entry.value.value != true;
    final delta = (include ? entry.total : 0) - entry.count;
    void setSubtree(_IdentitySelectionEntry current) {
      current.count = include ? current.total : 0;
      _publish(current);
      current.children.forEach(setSubtree);
    }

    setSubtree(entry);
    for (var parent = entry.parent; parent != null; parent = parent.parent) {
      parent.count += delta;
      _publish(parent);
    }
  }

  void replace(Set<String> selected) {
    int apply(_IdentitySelectionEntry entry, bool inherited) {
      final include = inherited || selected.contains(entry.node.id);
      entry.count = entry.children.isEmpty
          ? (include ? 1 : 0)
          : entry.children.fold(0, (sum, child) => sum + apply(child, include));
      _publish(entry);
      return entry.count;
    }

    for (final root in _roots) {
      apply(root, false);
    }
  }

  void dispose() {
    for (final entry in _entries.values) {
      entry.value.dispose();
    }
  }
}

class _IdentitySelectionEntry {
  _IdentitySelectionEntry(this.node, this.parent);
  final BankIdentityNode node;
  final _IdentitySelectionEntry? parent;
  final children = <_IdentitySelectionEntry>[];
  final value = ValueNotifier<bool?>(false);
  int total = 0, count = 0;
}
