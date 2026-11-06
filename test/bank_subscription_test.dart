import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yibubang/services/bank_subscription_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('subscription preferences survive reload and reject invalid URLs', () async {
    final service = BankSubscriptionService();
    await service.save(['https://example.org/manifest.json', 'https://example.org/manifest.json'], true);
    expect(await BankSubscriptionService().urls(), ['https://example.org/manifest.json']);
    expect(await BankSubscriptionService().automatic(), isTrue);
    expect(() => BankSubscriptionService.validateUrl('file:///tmp/bank'), throwsFormatException);
    expect(() => BankSubscriptionService.validateUrl('https://user:pass@example.org/'), throwsFormatException);
  });

  test('manifest preserves subscription origin and requires download integrity', () {
    final entry = {'bank_id': 'bank', 'url': 'https://example.org/bank.zip', 'sha256': 'a' * 64};
    final result = BankSubscriptionService.parseManifest({'question_banks': {'banks': [entry]}}, 'https://example.org/manifest.json');
    expect(result.single['subscription_url'], 'https://example.org/manifest.json');
    expect(() => BankSubscriptionService.parseManifest({'banks': [{...entry, 'sha256': ''}]}, ''), throwsFormatException);
    expect(() => BankSubscriptionService.parseManifest({'banks': [entry, entry]}, ''), throwsFormatException);
    expect(() => BankSubscriptionService.parseManifest({'banks': [{...entry, 'bank_id': '../bad'}]}, ''), throwsFormatException);
  });
}
