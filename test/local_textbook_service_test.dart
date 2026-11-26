import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yibubang/services/local_textbook_service.dart';

void main() {
  late Directory directory;
  late String pdfPath;
  late String executable;
  late List<(String, List<String>)> calls;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('local_textbook_');
    final bookDirectory = Directory(p.join(directory.path, '教材 PDF 文件'));
    await bookDirectory.create();
    pdfPath = p.join(bookDirectory.path, '系统解剖学(第10版).pdf');
    await File(pdfPath).writeAsBytes([]);
    executable = p.join(directory.path, 'Sumatra PDF.exe');
    await File(executable).writeAsBytes([]);
    calls = [];
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  LocalTextbookService service({
    bool windows = true,
    String? viewer,
    LocalTextbookProcessRunner? runProcess,
  }) {
    return LocalTextbookService(
      rootDirectory: p.dirname(pdfPath),
      executablePath: viewer ?? executable,
      windows: windows,
      runProcess:
          runProcess ??
          (exe, arguments) async {
            calls.add((exe, List.of(arguments)));
            return 123;
          },
    );
  }

  test(
    'opens the printed label with intact Chinese and spaced paths',
    () async {
      final result = await service().openReference('系统解剖学P87');

      expect(result.status, LocalTextbookOpenStatus.opened);
      expect(result.path, pdfPath);
      expect(result.pageLabel, '87');
      expect(calls, hasLength(1));
      expect(calls.single.$1, executable);
      expect(calls.single.$2, [
        '-reuse-instance',
        '-named-dest',
        '87',
        pdfPath,
      ]);
    },
  );

  test(
    'page ranges and edition prefixes use their first printed label',
    () async {
      final loader = service();
      for (final reference in [
        '系统解剖学P172～173',
        '10版系统解剖学P172-P173',
        '第10版系统解剖学P172-173',
        '第十版系统解剖学P172',
      ]) {
        final result = await loader.openReference(reference);
        expect(result.status, LocalTextbookOpenStatus.opened);
        expect(result.pageLabel, '172');
        expect(calls.last.$2, [
          '-reuse-instance',
          '-named-dest',
          '172',
          pdfPath,
        ]);
      }
    },
  );

  test('a missing PDF does not launch the viewer', () async {
    await File(pdfPath).delete();

    final result = await service().openReference('系统解剖学P87');

    expect(result.status, LocalTextbookOpenStatus.notFound);
    expect(result.path, pdfPath);
    expect(calls, isEmpty);
  });

  test(
    'a missing explicit viewer fails without launching another app',
    () async {
      final result = await service(
        viewer: p.join(directory.path, 'missing.exe'),
      ).openReference('系统解剖学P87');

      expect(result.status, LocalTextbookOpenStatus.failed);
      expect(result.path, pdfPath);
      expect(calls, isEmpty);
    },
  );

  test(
    'process errors are reported while retaining the textbook path',
    () async {
      final result = await service(
        runProcess: (exe, arguments) async {
          throw ProcessException(exe, arguments, 'Cannot start');
        },
      ).openReference('系统解剖学P87');

      expect(result.status, LocalTextbookOpenStatus.failed);
      expect(result.path, pdfPath);
      expect(result.pageLabel, '87');
    },
  );

  test('a nonpositive process ID does not report a successful open', () async {
    final result = await service(
      runProcess: (exe, arguments) async => 0,
    ).openReference('系统解剖学P87');

    expect(result.status, LocalTextbookOpenStatus.failed);
  });

  test('non-Windows platforms do not launch a process', () async {
    final result = await service(windows: false).openReference('系统解剖学P87');

    expect(result.status, LocalTextbookOpenStatus.unsupported);
    expect(calls, isEmpty);
  });

  test(
    'other textbooks and malformed page references remain unsupported',
    () async {
      final loader = service();
      for (final reference in [
        '生理学P87',
        '系统解剖学P0',
        '系统解剖学P',
        'P87',
        '系统解剖学P87 trailing',
        '系统解剖学P87;command',
      ]) {
        expect(
          (await loader.openReference(reference)).status,
          LocalTextbookOpenStatus.unsupported,
        );
      }
      expect(calls, isEmpty);
    },
  );
}
