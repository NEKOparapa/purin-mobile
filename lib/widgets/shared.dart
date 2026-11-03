import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../main.dart';
import '../data/demo_data.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: accent,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(
      Icons.graphic_eq_rounded,
      color: const Color(0xFF19382A),
      size: size * .65,
    ),
  );
}

class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key, this.label = 'DEMO'});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFF455A49)),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 9, color: accent, letterSpacing: 1),
    ),
  );
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.onTap, this.padding = 18});
  final Widget child;
  final VoidCallback? onTap;
  final double padding;
  @override
  Widget build(BuildContext context) => Material(
    color: surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15),
      side: const BorderSide(color: Color(0xFF304034)),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: EdgeInsets.all(padding), child: child),
    ),
  );
}

class SignalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .78, size.height * .48);
    final rings = Paint()
      ..color = accent.withValues(alpha: .08)
      ..style = PaintingStyle.stroke;
    for (final radius in [55.0, 83.0, 112.0]) {
      canvas.drawCircle(center, radius, rings);
    }
    final paint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 40; i++) {
      final x = center.dx - 72 + i * 4;
      final height = 5 + (math.sin(i * 1.9) * math.cos(i * .19)).abs() * 38;
      paint.color = accent.withValues(
        alpha: .18 + math.sin(i * .13).abs() * .6,
      );
      canvas.drawLine(
        Offset(x, center.dy - height),
        Offset(x, center.dy + height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SignalPainter oldDelegate) => false;
}

class MemoryCard extends StatelessWidget {
  const MemoryCard({super.key, required this.memory, required this.onTap});
  final Memory memory;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Panel(
    onTap: onTap,
    padding: 16,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: memory.isVoice
                ? const Color(0xFF283E30)
                : const Color(0xFF3B382A),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            memory.isVoice ? Icons.graphic_eq : Icons.chat_bubble_outline,
            size: 19,
            color: memory.isVoice ? accent : const Color(0xFFCABD98),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${memory.time}  ·  ${memory.source}',
                style: const TextStyle(color: muted, fontSize: 10, height: 1.5),
              ),
              const SizedBox(height: 7),
              Text(
                memory.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                memory.summary,
                style: const TextStyle(color: muted, fontSize: 12, height: 1.8),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 5,
                children: memory.tags
                    .map(
                      (tag) => Text(
                        '# $tag',
                        style: const TextStyle(
                          color: Color(0xFFABC2A8),
                          fontSize: 10,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

void showDetail(BuildContext context, String title, String body) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: .65,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DemoBadge(label: '示例内容'),
            const SizedBox(height: 18),
            Text(title, style: const TextStyle(fontSize: 22, height: 1.5)),
            const SizedBox(height: 18),
            Text(
              body,
              style: const TextStyle(color: muted, height: 2, fontSize: 14),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      ),
    ),
  );
}
