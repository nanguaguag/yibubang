import 'package:flutter/material.dart';

/// Gemini's four-point sparkle, drawn locally so it stays sharp at any size.
class GeminiMark extends StatelessWidget {
  final double size;
  final bool colorful;
  const GeminiMark({super.key, this.size = 24, this.colorful = true});
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _GeminiPainter(
        colorful
            ? null
            : IconTheme.of(context).color ??
                  Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _GeminiPainter extends CustomPainter {
  final Color? color;
  _GeminiPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w / 2, 0)
      ..cubicTo(w * .56, h * .32, w * .68, h * .44, w, h / 2)
      ..cubicTo(w * .68, h * .56, w * .56, h * .68, w / 2, h)
      ..cubicTo(w * .44, h * .68, w * .32, h * .56, 0, h / 2)
      ..cubicTo(w * .32, h * .44, w * .44, h * .32, w / 2, 0)
      ..close();
    final paint = Paint();
    if (color != null) {
      paint.color = color!;
    } else {
      paint.shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xff4285f4), Color(0xff8b72d8), Color(0xffd96570)],
      ).createShader(Offset.zero & size);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_GeminiPainter old) => old.color != color;
}
