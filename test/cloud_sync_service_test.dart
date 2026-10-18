import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yibubang/services/cloud_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('CloudSyncService initial state is unconfigured', () async {
    final service = CloudSyncService.instance;
    await service.init();
    expect(service.isConfigured, isFalse);
    expect(service.enabled, isFalse);
    expect(service.userId, isNull);
    expect(service.lastSyncTime, 0);
  });

  test('PairingCodeInfo models properly', () {
    final info = PairingCodeInfo(
      code: '839201',
      expiresAt: 1729000600000,
      expiresInSeconds: 600,
    );
    expect(info.code, '839201');
    expect(info.expiresInSeconds, 600);
  });

  test('SyncResult format and message', () {
    final result = SyncResult(
      success: true,
      pushedActivities: 5,
      pushedQuestions: 3,
      pulledActivities: 2,
      pulledQuestions: 1,
    );
    expect(result.success, isTrue);
    expect(result.toString(), contains('上传流水 5 条'));
    expect(result.toString(), contains('拉取流水 2 条'));
  });
}
