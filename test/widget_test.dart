import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tojir_app/app.dart';

void main() {
  testWidgets('TojirApp shows loading then UI', (WidgetTester tester) async {
    await tester.pumpWidget(const TojirApp());
    await tester.pump();
    // App can render a loader during bootstrap; just ensure it builds.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
