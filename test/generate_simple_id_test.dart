import 'package:flutter_test/flutter_test.dart';
import 'package:yibubang/db/database_helper.dart';

void main() {
  test('generateSimpleId generates unique IDs in tight loop without collision', () {
    const int count = 50000;
    final Set<String> idSet = <String>{};

    for (int i = 0; i < count; i++) {
      final id = generateSimpleId();
      expect(idSet.contains(id), isFalse, reason: 'Collision detected on ID: $id at index $i');
      idSet.add(id);
    }

    expect(idSet.length, count);
  });
}
