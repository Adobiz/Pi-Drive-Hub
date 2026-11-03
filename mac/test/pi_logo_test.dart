import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_pan/ui/pi_logo.dart';

void main() {
  testWidgets('Logo stays square inside the stretched login layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [PiLogo(size: 64)],
            ),
          ),
        ),
      ),
    );
    final paint = find.descendant(
      of: find.byType(PiLogo),
      matching: find.byType(CustomPaint),
    );
    expect(tester.getSize(paint), const Size(64, 64));
    expect(find.bySemanticsLabel('PI 网盘'), findsOneWidget);
  });
}
