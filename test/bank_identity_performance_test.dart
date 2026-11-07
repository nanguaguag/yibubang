import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yibubang/services/bank_creation_service.dart';
import 'package:yibubang/screens/bank_creation_page.dart';
import 'package:yibubang/models/bank_identity_selection.dart';

class _LargeCatalogService extends BankCreationService {
  @override
  Future<List<BankIdentityNode>> identities() async => largeCatalog();
}

List<BankIdentityNode> largeCatalog() => [
  for (var root = 0; root < 60; root++)
    BankIdentityNode(
      {'identity_id': '$root', 'title': '学科 $root'},
      [
        for (var branch = 0; branch < 8; branch++)
          BankIdentityNode(
            {'identity_id': '$root-$branch', 'title': '学年 $branch'},
            [
              for (var leaf = 0; leaf < 8; leaf++)
                BankIdentityNode({
                  'identity_id': '$root-$branch-$leaf',
                  'title': '学期 $leaf',
                }, []),
            ],
          ),
      ],
    ),
];

void main() {
  testWidgets('large catalog selection benchmark', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final load = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(home: BankCreationPage(service: _LargeCatalogService())),
    );
    await tester.pump();
    load.stop();
    final toggle = Stopwatch()..start();
    await tester.tap(find.byKey(const ValueKey('bank-identity-0')));
    await tester.pump();
    toggle.stop();
    final mounted = find
        .byType(CheckboxListTile, skipOffstage: false)
        .evaluate()
        .length;
    debugPrint(
      'BANK_TREE_OPTIMIZED nodes=4380 mounted=$mounted loadMs=${load.elapsedMilliseconds} toggleMs=${toggle.elapsedMilliseconds}',
    );
    expect(
      mounted,
      lessThan(40),
      reason: 'mount viewport rows only, even for a large collapsed catalog',
    );
    expect(toggle.elapsedMilliseconds, lessThan(300));
    expect(load.elapsedMilliseconds, lessThan(1000));
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('bank-identity-0')),
          )
          .value,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('bank-identity-expand-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bank-identity-expand-0-0')));
    await tester.pump();
    final unrelated = tester.widget<CheckboxListTile>(
      find.byKey(const ValueKey('bank-identity-0-1')),
    );
    final leafToggle = Stopwatch()..start();
    await tester.tap(find.byKey(const ValueKey('bank-identity-0-0-0')));
    await tester.pump();
    leafToggle.stop();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('bank-identity-0')),
          )
          .value,
      isNull,
    );
    expect(
      tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('bank-identity-0-1')),
      ),
      same(unrelated),
      reason: 'unaffected sibling row is not rebuilt',
    );
    expect(leafToggle.elapsedMilliseconds, lessThan(300));
    debugPrint('BANK_TREE_LEAF toggleMs=${leafToggle.elapsedMilliseconds}');
    await tester.drag(find.byType(ListView), const Offset(0, -1800));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bank-identity-0')), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, 2400));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('bank-identity-0')),
          )
          .value,
      isNull,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('bank-identity-0-0-0')),
          )
          .value,
      isFalse,
    );
    final afterScroll = Stopwatch()..start();
    await tester.tap(find.byKey(const ValueKey('bank-identity-0-0-0')));
    await tester.pump();
    afterScroll.stop();
    expect(afterScroll.elapsedMilliseconds, lessThan(300));
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('bank-identity-0')),
          )
          .value,
      isTrue,
    );
    debugPrint(
      'BANK_TREE_AFTER_SCROLL toggleMs=${afterScroll.elapsedMilliseconds}',
    );
    expect(tester.takeException(), isNull);
  });

  test(
    'leaf selection updates only its path and preserves subtree root contract',
    () {
      final nodes = largeCatalog();
      final model = BankIdentitySelection(nodes, {});
      addTearDown(model.dispose);
      var unrelatedUpdates = 0;
      model.value('1').addListener(() => unrelatedUpdates++);
      model.toggle('0');
      expect(model.selected.length, 73);
      expect(nodes.first.selectedRoots(model.selected).map((node) => node.id), [
        '0',
      ]);
      model.toggle('0-0-0');
      expect(model.value('0').value, isNull);
      expect(model.value('0-0').value, isNull);
      expect(model.value('0-0-0').value, isFalse);
      expect(model.selected.contains('0-0-0'), isFalse);
      expect(unrelatedUpdates, 0);
      model.toggle('0-0');
      expect(model.value('0').value, isTrue);
      model.toggle('0');
      expect(model.isEmpty, isTrue);
    },
  );
}
