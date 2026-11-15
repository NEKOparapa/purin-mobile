import 'package:flutter/material.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 30});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(size * .28),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final height in [7, 14, 20, 12, 8])
            Container(
              margin: EdgeInsets.symmetric(horizontal: size * .029),
              width: size * .048,
              height: size * height / 34,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onPrimary,
                borderRadius: BorderRadius.circular(size),
              ),
            ),
        ],
      ),
    ),
  );
}

const wordmarkStyle = TextStyle(
  fontFamily: 'serif',
  fontSize: 25,
  height: 1.1,
  letterSpacing: -1.0,
  fontWeight: FontWeight.w500,
);
