import 'dart:io';

import 'package:path/path.dart' as p;

enum LocalTextbookOpenStatus { opened, notFound, unsupported, failed }

class LocalTextbookOpenResult {
  final LocalTextbookOpenStatus status;
  final String? path;
  final String? pageLabel;

  const LocalTextbookOpenResult({
    required this.status,
    this.path,
    this.pageLabel,
  });
}

typedef LocalTextbookProcessRunner =
    Future<int> Function(String executable, List<String> arguments);

/// Opens the user's local anatomy textbook at its printed PDF page label.
class LocalTextbookService {
  final String rootDirectory;
  final String? executablePath;
  final LocalTextbookProcessRunner _runProcess;
  final bool _windows;

  LocalTextbookService({
    String? rootDirectory,
    this.executablePath,
    LocalTextbookProcessRunner? runProcess,
    bool? windows,
  }) : rootDirectory = rootDirectory ?? r'E:\Documents\SYNC',
       _runProcess = runProcess ?? _startDetached,
       _windows = windows ?? Platform.isWindows;

  static final _referencePattern = RegExp(
    r'^(?:第?[0-9一二三四五六七八九十]+版)?系统解剖学\s*P(\d+)'
    r'(?:[-~～—–－]P?\d+)?$',
  );

  Future<LocalTextbookOpenResult> openReference(String reference) async {
    if (!_windows) {
      return const LocalTextbookOpenResult(
        status: LocalTextbookOpenStatus.unsupported,
      );
    }
    final match = _referencePattern.firstMatch(reference.trim());
    final page = int.tryParse(match?.group(1) ?? '');
    if (page == null || page < 1) {
      return const LocalTextbookOpenResult(
        status: LocalTextbookOpenStatus.unsupported,
      );
    }

    final pageLabel = page.toString();
    final pdfPath = p.join(rootDirectory, '系统解剖学(第10版).pdf');
    try {
      if (!await File(pdfPath).exists()) {
        return LocalTextbookOpenResult(
          status: LocalTextbookOpenStatus.notFound,
          path: pdfPath,
          pageLabel: pageLabel,
        );
      }
      final viewer = await _findExecutable();
      if (viewer == null) {
        return LocalTextbookOpenResult(
          status: LocalTextbookOpenStatus.failed,
          path: pdfPath,
          pageLabel: pageLabel,
        );
      }

      final pid = await _runProcess(viewer, [
        '-reuse-instance',
        '-named-dest',
        pageLabel,
        pdfPath,
      ]);
      return LocalTextbookOpenResult(
        status: pid > 0
            ? LocalTextbookOpenStatus.opened
            : LocalTextbookOpenStatus.failed,
        path: pdfPath,
        pageLabel: pageLabel,
      );
    } catch (_) {
      return LocalTextbookOpenResult(
        status: LocalTextbookOpenStatus.failed,
        path: pdfPath,
        pageLabel: pageLabel,
      );
    }
  }

  Future<String?> _findExecutable() async {
    if (executablePath != null) {
      return await File(executablePath!).exists() ? executablePath : null;
    }

    final environment = Platform.environment;
    final directories = [
      environment['LOCALAPPDATA'],
      environment['ProgramFiles'] ?? environment['PROGRAMFILES'],
      environment['ProgramFiles(x86)'] ?? environment['PROGRAMFILES(X86)'],
    ];
    for (final directory in directories) {
      if (directory == null || directory.isEmpty) continue;
      final candidate = p.join(directory, 'SumatraPDF', 'SumatraPDF.exe');
      if (await File(candidate).exists()) return candidate;
    }
    return null;
  }

  static Future<int> _startDetached(
    String executable,
    List<String> arguments,
  ) async {
    final process = await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.detached,
      runInShell: false,
    );
    return process.pid;
  }
}
