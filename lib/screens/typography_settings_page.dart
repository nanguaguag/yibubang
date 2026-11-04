import 'package:flutter/material.dart';

import '../common/adaptive_route.dart';
import '../widgets/font_controller.dart';
import '../widgets/reading_layout.dart';
import 'font_settings_page.dart';

class TypographySettingsPage extends StatelessWidget {
  const TypographySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = ReadingLayoutController.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('排版')),
      body: ListenableBuilder(
        listenable: Listenable.merge([layout, FontController.instance]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              leading: const Icon(Icons.font_download_outlined),
              title: const Text('字体'),
              subtitle: Text(FontController.instance.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                adaptivePageRoute(builder: (_) => const FontSettingsPage()),
              ),
            ),
            const Divider(),
            const Text('题目与答案', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              '适用于题干、选项、答案、难度统计、来源和解析。导航、笔记及评论保持原布局。'
              '区域居中时，文字仍可保持左对齐。窄屏会自动缩小内容宽度和留白。',
            ),
            SwitchListTile(
              title: const Text('限制正文最大宽度'),
              subtitle: Text(
                layout.maxWidth == 0
                    ? '随窗口铺满'
                    : '${layout.maxWidth.round()} 逻辑像素',
              ),
              value: layout.maxWidth != 0,
              onChanged: (on) => layout.update(maxWidth: on ? 960 : 0),
            ),
            if (layout.maxWidth != 0)
              _slider(
                '最大宽度',
                layout.maxWidth,
                480,
                1440,
                24,
                '${layout.maxWidth.round()}',
                (v) => layout.update(maxWidth: v),
              ),
            _slider(
              '额外左右留白',
              layout.horizontalInset,
              0,
              80,
              20,
              '${layout.horizontalInset.round()}',
              (v) => layout.update(horizontalInset: v),
            ),
            _choice<ContentPosition>('正文区域位置', layout.position, const {
              ContentPosition.left: '靠左',
              ContentPosition.center: '居中',
              ContentPosition.right: '靠右',
            }, (v) => layout.update(position: v)),
            _choice<TextAlign>('正文文字对齐', layout.textAlign, const {
              TextAlign.left: '左对齐',
              TextAlign.center: '居中',
              TextAlign.right: '右对齐',
              TextAlign.justify: '两端对齐',
            }, (v) => layout.update(textAlign: v)),
            _slider(
              '行距',
              layout.lineHeight,
              1,
              2.2,
              12,
              '${layout.lineHeight.toStringAsFixed(1)} 倍',
              (v) => layout.update(lineHeight: v),
            ),
            _slider(
              '字距',
              layout.letterSpacing,
              0,
              3,
              12,
              layout.letterSpacing.toStringAsFixed(2),
              (v) => layout.update(letterSpacing: v),
            ),
            const Divider(),
            const Text('实时预览', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ReadingContent(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: const [
                      Text(
                        '下列哪项属于牙体硬组织？',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text('A. 牙釉质\nB. 牙髓\nC. 牙周膜'),
                      SizedBox(height: 12),
                      Text('正确答案：A'),
                      Text(
                        '解析：牙釉质覆盖于牙冠表面，是人体中矿化程度最高的组织。'
                        '调整正文宽度后，较长的内容会在限定区域内自动换行。',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: layout.reset,
              icon: const Icon(Icons.restart_alt),
              label: const Text('恢复默认正文排版'),
            ),
            const Text('设置自动保存。恢复正文排版不会更改字体选择或刷题字号。'),
          ],
        ),
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    int divisions,
    String display,
    ValueChanged<double> onChanged,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text('$label：$display'),
      ),
      Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: display,
        onChanged: onChanged,
      ),
    ],
  );

  Widget _choice<T>(
    String label,
    T value,
    Map<T, String> options,
    ValueChanged<T> onChanged,
  ) => ListTile(
    title: Text(label),
    trailing: DropdownButton<T>(
      value: value,
      underline: const SizedBox.shrink(),
      items: options.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    ),
  );
}
