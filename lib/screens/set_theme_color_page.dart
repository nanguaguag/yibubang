import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:system_theme/system_theme.dart';
import '../common/app_shapes.dart';
import '../widgets/theme_controller.dart';

class SetThemeColorPage extends StatefulWidget {
  const SetThemeColorPage({super.key});

  @override
  State<SetThemeColorPage> createState() => _SetThemeColorPageState();
}

class _SetThemeColorPageState extends State<SetThemeColorPage> {
  late Color pickerColor;
  late ThemeColorMode _selectedMode;
  ColorScheme? colorScheme;

  @override
  void initState() {
    super.initState();
    _selectedMode = ThemeController.instance.themeColorMode;
    if (_selectedMode == ThemeColorMode.system) {
      pickerColor = ThemeController.instance.effectiveSeedColor;
    } else {
      pickerColor = ThemeController.instance.themeColor;
    }
  }

  void changeColor(Color color) {
    setState(() {
      pickerColor = color;
      colorScheme = ColorScheme.fromSeed(
        seedColor: pickerColor,
        brightness: Theme.of(context).brightness,
      );
    });
    if (_selectedMode != ThemeColorMode.custom) {
      setState(() {
        _selectedMode = ThemeColorMode.custom;
      });
    }
  }

  void _onModeChanged(ThemeColorMode? mode) async {
    if (mode == null) return;
    setState(() {
      _selectedMode = mode;
    });
    switch (mode) {
      case ThemeColorMode.system:
        await _handleSystemMode();
        break;
      case ThemeColorMode.custom:
        setState(() {
          pickerColor = ThemeController.instance.themeColor;
          colorScheme = ColorScheme.fromSeed(
            seedColor: pickerColor,
            brightness: Theme.of(context).brightness,
          );
        });
        break;
    }
  }

  Future<void> _handleSystemMode() async {
    try {
      await SystemTheme.accentColor.load();
      final color = SystemTheme.accentColor.accent;
      if (!mounted) return;
      setState(() {
        pickerColor = color;
        colorScheme = ColorScheme.fromSeed(
          seedColor: pickerColor,
          brightness: Theme.of(context).brightness,
        );
      });
    } catch (e) {
      debugPrint('获取系统色彩失败: $e');
    }
  }

  void _confirmChanges() {
    ThemeController.instance.setThemeColor(pickerColor);
    ThemeController.instance.setThemeColorMode(_selectedMode);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    colorScheme ??= ColorScheme.fromSeed(
      seedColor: pickerColor,
      brightness: Theme.of(context).brightness,
    );
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        brightness: Theme.of(context).brightness,
      ),
      child: Builder(
        builder: (context) {
          final currentTheme = Theme.of(context);
          return Scaffold(
            appBar: AppBar(
              title: const Text('主题颜色'),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: currentTheme.colorScheme.primary,
                      foregroundColor: currentTheme.colorScheme.onPrimary,
                    ),
                    onPressed: _confirmChanges,
                    child: const Text('确认'),
                  ),
                ),
              ],
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  const _HintCard(
                    title: '提示',
                    child: Text('自定义主题色将影响应用内的主要色调，包括按钮、高亮以及底栏图标。'),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: SegmentedButton<ThemeColorMode>(
                      segments: const [
                        ButtonSegment<ThemeColorMode>(
                          value: ThemeColorMode.system,
                          label: Text('跟随系统'),
                          icon: Icon(Icons.settings_suggest),
                        ),
                        ButtonSegment<ThemeColorMode>(
                          value: ThemeColorMode.custom,
                          label: Text('自定义'),
                          icon: Icon(Icons.palette),
                        ),
                      ],
                      selected: {_selectedMode},
                      onSelectionChanged: (selected) {
                        _onModeChanged(selected.first);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: BlockPicker(
                      useInShowDialog: false,
                      pickerColor: pickerColor,
                      onColorChanged: changeColor,
                    ),
                  ),
                  const SizedBox(height: 24),
                  //Padding(
                  //  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  //  child: SizedBox(
                  //    width: double.infinity,
                  //    child: FilledButton(
                  //      style: FilledButton.styleFrom(
                  //        padding: const EdgeInsets.symmetric(vertical: 14),
                  //        shape: RoundedRectangleBorder(
                  //          borderRadius: BorderRadius.circular(AppShapes.large),
                  //        ),
                  //      ),
                  //      onPressed: _confirmChanges,
                  //      child: const Text('确认保存设置', style: TextStyle(fontSize: 16)),
                  //    ),
                  //  ),
                  //),
                  //const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _HintCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.topLeft,
      decoration: ShapeDecoration(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadiusDirectional.circular(
            AppShapes.largeIncreased,
          ),
        ),
        color: Theme.of(context).colorScheme.secondaryContainer,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 0.1,
            blurRadius: 10,
          ),
        ],
      ),
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ],
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }
}
