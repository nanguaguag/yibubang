import 'package:flutter/material.dart';
import '../common/app_shapes.dart';
import '../widgets/theme_controller.dart';

class SetDurationPage extends StatefulWidget {
  const SetDurationPage({super.key});

  @override
  State<SetDurationPage> createState() => _SetDurationPageState();
}

class _SetDurationPageState extends State<SetDurationPage> {
  late int _tempAnimationTime;
  bool _isAnimating = false;
  bool _shouldAnimate = true;

  @override
  void initState() {
    super.initState();
    _tempAnimationTime =
        ThemeController.instance.animationDuration.inMilliseconds;
    _startAnimation();
  }

  @override
  void dispose() {
    _shouldAnimate = false;
    super.dispose();
  }

  Future<void> _startAnimation() async {
    while (_shouldAnimate && mounted) {
      await Future.delayed(Duration(milliseconds: _tempAnimationTime + 100));

      if (!_shouldAnimate || !mounted) break;

      setState(() {
        _isAnimating = true;
      });

      await Future.delayed(Duration(milliseconds: _tempAnimationTime + 100));

      if (!_shouldAnimate || !mounted) break;

      setState(() {
        _isAnimating = false;
      });
    }
  }

  void _updateAnimationTime(double value) {
    setState(() {
      _tempAnimationTime = value.round();
    });
  }

  void _confirmChanges() {
    ThemeController.instance.setAnimationDuration(
      Duration(milliseconds: _tempAnimationTime),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text('动画时长'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              onPressed: _confirmChanges,
              child: const Text('确认'),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Text(
                '当前动画时长：$_tempAnimationTime 毫秒',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ),

            Slider(
              value: _tempAnimationTime.toDouble(),
              min: 0,
              max: 1000,
              divisions: 20,
              label: '$_tempAnimationTime ms',
              onChanged: _updateAnimationTime,
              activeColor: colorScheme.primary,
              inactiveColor: colorScheme.surfaceContainerHighest,
            ),

            const SizedBox(height: 20),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppShapes.medium),
                ),
                child: Center(
                  child: AnimatedContainer(
                    width: _isAnimating ? 150 : 100,
                    height: _isAnimating ? 150 : 100,
                    decoration: BoxDecoration(
                      color: _isAnimating
                          ? colorScheme.primary
                          : colorScheme.secondary,
                      borderRadius: BorderRadius.circular(
                        _isAnimating ? 30 : 10,
                      ),
                    ),
                    duration: Duration(milliseconds: _tempAnimationTime),
                    curve: Curves.easeInOut,
                    child: const Icon(
                      Icons.flutter_dash,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),
            //SizedBox(
            //  width: double.infinity,
            //  child: FilledButton(
            //    style: FilledButton.styleFrom(
            //      padding: const EdgeInsets.symmetric(vertical: 14),
            //      shape: RoundedRectangleBorder(
            //        borderRadius: BorderRadius.circular(AppShapes.large),
            //      ),
            //    ),
            //    onPressed: _confirmChanges,
            //    child: const Text('确认保存设置', style: TextStyle(fontSize: 16)),
            //  ),
            //),

            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Text(
                '调整应用内各项动画的持续时长。设置为 0 毫秒可关闭动画，获得最迅捷的响应。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
