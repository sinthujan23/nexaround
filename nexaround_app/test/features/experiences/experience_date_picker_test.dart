import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_date_picker.dart';

void main() {
  // October 2026, with the 16th–29th blocked by the vendor.
  bool blocked(DateTime d) =>
      d.year == 2026 && d.month == 10 && d.day >= 16 && d.day <= 29;

  Future<void> openPicker(
    WidgetTester tester, {
    void Function(DateTime?)? onPicked,
  }) async {
    // A phone screen; the default 800x600 test view is too short for the dialog.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final picked = await showExperienceDatePicker(
              context: context,
              initialDate: DateTime(2026, 10, 30),
              firstDate: DateTime(2026, 10, 15),
              lastDate: DateTime(2027, 10, 15),
              isUnavailable: blocked,
            );
            onPicked?.call(picked);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Color? dayColor(WidgetTester tester, String day) =>
      tester.widget<Text>(find.text(day)).style?.color;

  testWidgets('blocked days are red, past days are not', (tester) async {
    await openPicker(tester);

    expect(dayColor(tester, '20'), AppColors.error);
    expect(dayColor(tester, '10'), isNot(AppColors.error));
    expect(dayColor(tester, '31'), AppColors.textPrimary);
    expect(find.text('Not available'), findsOneWidget);
  });

  testWidgets('tapping a blocked day explains it and keeps the selection',
      (tester) async {
    await openPicker(tester);

    await tester.tap(find.text('20'));
    await tester.pump();

    expect(find.textContaining('is not available'), findsOneWidget);
    expect(find.text('Fri, Oct 30'), findsOneWidget);
  });

  testWidgets('OK returns the picked available day', (tester) async {
    DateTime? picked;
    await openPicker(tester, onPicked: (d) => picked = d);

    await tester.tap(find.text('31'));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(picked, DateTime(2026, 10, 31));
  });
}
