import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app_theme.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.fromUser, required this.child});

  final bool fromUser;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final atmosphere = AppAtmosphere.of(context);
    final colors = Theme.of(context).colorScheme;
    final fill = fromUser
        ? atmosphere.userBubbleFill
        : atmosphere.assistantBubbleFill;
    final edge = fromUser
        ? Color.lerp(fill, colors.primary, 0.20)!
        : atmosphere.cardBorder;
    const inset = 14.0;
    const tail = _BubblePainter.tail;
    return CustomPaint(
      painter: _BubblePainter(fromUser, fill, edge),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          fromUser ? inset : inset + tail,
          9,
          fromUser ? inset + tail : inset,
          9,
        ),
        child: child,
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter(this.fromUser, this.fill, this.edge);

  static const tail = 6.0;
  final bool fromUser;
  final Color fill, edge;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 0.85;
    final w = size.width - stroke, h = size.height - stroke;
    if (w <= tail || h <= 0) return;
    final r = math.min(16.0, math.min((w - tail) / 2, h / 2));
    final corner = Radius.circular(r);
    final path = Path()
      ..moveTo(tail, h - r)
      ..lineTo(tail, r)
      ..arcToPoint(Offset(tail + r, 0), radius: corner)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: corner)
      ..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: corner)
      ..lineTo(tail + r, h)
      ..quadraticBezierTo(tail + r * .64, h, tail + r * .40, h - r * .20)
      ..quadraticBezierTo(tail * .96, h, .8, h)
      ..quadraticBezierTo(-.2, h, .5, h - .8)
      ..quadraticBezierTo(tail, h - r * .45, tail, h - r)
      ..close();

    canvas.save();
    canvas.translate(
      fromUser ? size.width - stroke / 2 : stroke / 2,
      stroke / 2,
    );
    if (fromUser) canvas.scale(-1, 1);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = stroke,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.fromUser != fromUser || old.fill != fill || old.edge != edge;
}
