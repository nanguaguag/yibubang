import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FontController extends ChangeNotifier {
  FontController._();
  static final instance = FontController._();

  String? _family;
  String? _filePath;
  String _label = '系统默认';

  String? get family => _family;
  String get label => _label;
  bool get isImported => _filePath != null;

  List<String> get fallback => switch (defaultTargetPlatform) {
    TargetPlatform.windows => ['Microsoft YaHei UI', 'Microsoft YaHei'],
    TargetPlatform.macOS || TargetPlatform.iOS => ['PingFang SC'],
    _ => ['Noto Sans CJK SC', 'Noto Sans SC'],
  };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _family = prefs.getString('app_font_family');
    _filePath = prefs.getString('app_font_path');
    _label = prefs.getString('app_font_label') ?? _family ?? '系统默认';
    if (kIsWeb && _filePath != null) {
      await setSystemFont(null);
      return;
    }
    if (_filePath != null) {
      try {
        if (_family == null) throw const FormatException('缺少字体名称');
        await _loadFont(_family!, await File(_filePath!).readAsBytes());
      } catch (error) {
        debugPrint('自定义字体加载失败，恢复系统字体：$error');
        await setSystemFont(null);
        return;
      }
    }
    notifyListeners();
  }

  Future<void> setSystemFont(String? family) async {
    _family = family?.trim();
    if (_family?.isEmpty ?? false) _family = null;
    _filePath = null;
    _label = _family ?? '系统默认';
    await _save();
    notifyListeners();
  }

  Future<void> importFont(String name, Uint8List bytes) async {
    if (kIsWeb) {
      throw UnsupportedError('网页版本不支持导入字体文件');
    }
    final extension = p.extension(name).toLowerCase();
    if (!['.ttf', '.otf'].contains(extension) || bytes.length < 12) {
      throw const FormatException('请选择有效的 TTF 或 OTF 字体文件');
    }
    final signature = ByteData.sublistView(bytes).getUint32(0);
    if (![0x00010000, 0x4f54544f, 0x74727565].contains(signature)) {
      throw const FormatException('字体格式无效，请选择 TTF 或 OTF 文件');
    }
    // 字体引擎不会替换已加载的同名字体，每次导入使用独立名称。
    final family = 'UserFont_${DateTime.now().microsecondsSinceEpoch}';
    await _loadFont(family, bytes);
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'fonts'));
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, '$family$extension'));
    await file.writeAsBytes(bytes, flush: true);
    _family = family;
    _filePath = file.path;
    _label = p.basenameWithoutExtension(name);
    await _save();
    notifyListeners();
  }

  Future<void> _loadFont(String family, Uint8List bytes) async {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in {
      'app_font_family': _family,
      'app_font_path': _filePath,
      'app_font_label': _label,
    }.entries) {
      if (entry.value == null) {
        await prefs.remove(entry.key);
      } else {
        await prefs.setString(entry.key, entry.value!);
      }
    }
  }
}
