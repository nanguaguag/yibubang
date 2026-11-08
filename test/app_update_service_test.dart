import 'dart:ffi';
import 'package:flutter_test/flutter_test.dart';
import 'package:yibubang/services/app_update_service.dart';

void main() {
  group('AppUpdateService ABI and Download URL Resolution Tests', () {
    test('detectAndroidAbi correctly maps Abi enum values', () {
      expect(
        AppUpdateService.detectAndroidAbi(currentAbi: Abi.androidArm64),
        'arm64-v8a',
      );
      expect(
        AppUpdateService.detectAndroidAbi(currentAbi: Abi.androidArm),
        'armeabi-v7a',
      );
      expect(
        AppUpdateService.detectAndroidAbi(currentAbi: Abi.androidX64),
        'x86_64',
      );
      expect(
        AppUpdateService.detectAndroidAbi(currentAbi: Abi.macosArm64),
        isNull,
      );
      expect(
        AppUpdateService.detectAndroidAbi(currentAbi: Abi.windowsX64),
        isNull,
      );
    });

    test('detectAndroidAbi infers architecture from split-per-abi build numbers', () {
      // 2000+ -> arm64-v8a
      expect(
        AppUpdateService.detectAndroidAbi(
          currentAbi: Abi.macosArm64,
          buildNumber: 2205,
        ),
        'arm64-v8a',
      );
      // 1000+ -> armeabi-v7a
      expect(
        AppUpdateService.detectAndroidAbi(
          currentAbi: Abi.macosArm64,
          buildNumber: 1205,
        ),
        'armeabi-v7a',
      );
      // 3000+ -> x86_64
      expect(
        AppUpdateService.detectAndroidAbi(
          currentAbi: Abi.macosArm64,
          buildNumber: 3205,
        ),
        'x86_64',
      );
      // Universal build number < 1000
      expect(
        AppUpdateService.detectAndroidAbi(
          currentAbi: Abi.macosArm64,
          buildNumber: 212,
        ),
        isNull,
      );
    });

    final mockManifest = {
      'latest_app': '2.2.2',
      'latest_app_url': 'https://github.com/nanguaguag/yibubang/releases/tag/v2.2.2',
      'assets': {
        'android':
            'https://github.com/nanguaguag/yibubang/releases/download/v2.2.2/yibubang-v2.2.2-android.apk',
        'android_arm64':
            'https://github.com/nanguaguag/yibubang/releases/download/v2.2.2/yibubang-v2.2.2-android-arm64-v8a.apk',
        'android_armv7':
            'https://github.com/nanguaguag/yibubang/releases/download/v2.2.2/yibubang-v2.2.2-android-armeabi-v7a.apk',
        'android_x86_64':
            'https://github.com/nanguaguag/yibubang/releases/download/v2.2.2/yibubang-v2.2.2-android-x86_64.apk',
        'windows':
            'https://github.com/nanguaguag/yibubang/releases/download/v2.2.2/yibubang-v2.2.2-windows-x64.zip',
        'macos':
            'https://github.com/nanguaguag/yibubang/releases/download/v2.2.2/yibubang-v2.2.2-macos.zip',
        'linux':
            'https://github.com/nanguaguag/yibubang/releases/download/v2.2.2/yibubang-v2.2.2-linux-x64.tar.gz',
      },
    };

    test('resolvePlatformDownloadUrl selects android_arm64 for arm64-v8a', () {
      final url = AppUpdateService.resolvePlatformDownloadUrl(
        mockManifest,
        isAndroidOverride: true,
        androidAbiOverride: 'arm64-v8a',
      );
      expect(
        url,
        'https://github.com/nanguaguag/yibubang/releases/download/v2.2.2/yibubang-v2.2.2-android-arm64-v8a.apk',
      );
    });

    test('resolvePlatformDownloadUrl selects android_armv7 for armeabi-v7a', () {
      final url = AppUpdateService.resolvePlatformDownloadUrl(
        mockManifest,
        isAndroidOverride: true,
        androidAbiOverride: 'armeabi-v7a',
      );
      expect(
        url,
        'https://github.com/nanguaguag/yibubang/releases/download/v2.2.2/yibubang-v2.2.2-android-armeabi-v7a.apk',
      );
    });

    test('resolvePlatformDownloadUrl selects android_x86_64 for x86_64', () {
      final url = AppUpdateService.resolvePlatformDownloadUrl(
        mockManifest,
        isAndroidOverride: true,
        androidAbiOverride: 'x86_64',
      );
      expect(
        url,
        'https://github.com/nanguaguag/yibubang/releases/download/v2.2.2/yibubang-v2.2.2-android-x86_64.apk',
      );
    });

    test('resolvePlatformDownloadUrl falls back to universal if ABI is unknown', () {
      final url = AppUpdateService.resolvePlatformDownloadUrl(
        mockManifest,
        isAndroidOverride: true,
        androidAbiOverride: null,
        buildNumber: 212,
      );
      expect(
        url,
        'https://github.com/nanguaguag/yibubang/releases/download/v2.2.2/yibubang-v2.2.2-android.apk',
      );
    });

    test('resolvePlatformDownloadUrl falls back to universal if specific ABI asset missing', () {
      final manifestWithoutArm64 = {
        'latest_app': '2.2.2',
        'assets': {
          'android':
              'https://github.com/nanguaguag/yibubang/releases/download/v2.2.2/yibubang-v2.2.2-android.apk',
        },
      };
      final url = AppUpdateService.resolvePlatformDownloadUrl(
        manifestWithoutArm64,
        isAndroidOverride: true,
        androidAbiOverride: 'arm64-v8a',
      );
      expect(
        url,
        'https://github.com/nanguaguag/yibubang/releases/download/v2.2.2/yibubang-v2.2.2-android.apk',
      );
    });

    test('resolvePlatformDownloadUrl supports desktop platforms', () {
      expect(
        AppUpdateService.resolvePlatformDownloadUrl(
          mockManifest,
          isAndroidOverride: false,
          isWindowsOverride: true,
        ),
        'https://github.com/nanguaguag/yibubang/releases/download/v2.2.2/yibubang-v2.2.2-windows-x64.zip',
      );

      expect(
        AppUpdateService.resolvePlatformDownloadUrl(
          mockManifest,
          isAndroidOverride: false,
          isMacOSOverride: true,
        ),
        'https://github.com/nanguaguag/yibubang/releases/download/v2.2.2/yibubang-v2.2.2-macos.zip',
      );

      expect(
        AppUpdateService.resolvePlatformDownloadUrl(
          mockManifest,
          isAndroidOverride: false,
          isLinuxOverride: true,
        ),
        'https://github.com/nanguaguag/yibubang/releases/download/v2.2.2/yibubang-v2.2.2-linux-x64.tar.gz',
      );
    });
  });
}
