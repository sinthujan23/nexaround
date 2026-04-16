import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexaround_app/app/app.dart';

void main() {
  testWidgets('App should render', (WidgetTester tester) async {
    await tester.pumpWidget(const NexAroundApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
