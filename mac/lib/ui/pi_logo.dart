import 'package:flutter/material.dart';
import '../core/constants.dart';

/// Rounded vector branding shared with the native app icon geometry.
class PiLogo extends StatelessWidget {
  final double size;
  final Color piColor;
  final Color cloudColor;
  const PiLogo({
    super.key,
    this.size = 64,
    this.piColor = kBrandColor,
    this.cloudColor = kBrandColor,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'PI 网盘',
    image: true,
    child: SizedBox(
      width: size,
      height: size,
      child: Center(
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(painter: _PiLogoPainter(cloudColor, piColor)),
        ),
      ),
    ),
  );
}

Path roundedCloud(Rect rect) {
  final path =
      Path()
        ..moveTo(28, 64)
        ..lineTo(76, 64)
        ..cubicTo(86, 64, 94, 56, 94, 46)
        ..cubicTo(94, 36, 88, 29, 81, 29)
        ..cubicTo(79, 29, 77.5, 27, 77, 25)
        ..cubicTo(74, 14, 66, 8, 54, 8)
        ..cubicTo(42, 8, 34, 14, 31, 25)
        ..cubicTo(30.5, 27, 29, 29, 27, 29)
        ..cubicTo(19, 29, 12, 36, 12, 46)
        ..cubicTo(12, 56, 18, 64, 28, 64)
        ..close();
  final transform = Matrix4.identity().storage;
  transform[0] = rect.width / 100;
  transform[5] = rect.height / 72;
  transform[12] = rect.left;
  transform[13] = rect.top;
  return path.transform(transform);
}

class _PiLogoPainter extends CustomPainter {
  final Color base;
  final Color pi;
  _PiLogoPainter(this.base, this.pi);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final background = RRect.fromRectAndRadius(
      const Rect.fromLTWH(6, 6, 88, 88),
      const Radius.circular(21),
    );
    canvas.drawRRect(
      background,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(base, Colors.white, .22)!,
            Color.lerp(base, const Color(0xFF123BB9), .4)!,
          ],
        ).createShader(const Rect.fromLTWH(6, 6, 88, 88)),
    );
    final cloud = roundedCloud(const Rect.fromLTWH(7, 23, 86, 58));
    canvas.drawShadow(cloud, const Color(0x55133C9E), 2, false);
    canvas.drawPath(cloud, Paint()..color = Colors.white);
    final mark =
        Path()
          ..moveTo(41, 48)
          ..lineTo(63, 48)
          ..moveTo(47, 49)
          ..cubicTo(47, 55, 46, 60, 44.5, 64)
          ..moveTo(58, 49)
          ..lineTo(58, 60)
          ..cubicTo(58, 64, 60, 65, 63, 63);
    canvas.drawPath(
      mark,
      Paint()
        ..color = pi
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PiLogoPainter oldDelegate) =>
      oldDelegate.base != base || oldDelegate.pi != pi;
}
