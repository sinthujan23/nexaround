import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_package_card.dart';

void main() {
  // "Price on request" keeps the price off the currency and auth blocs.
  ExperiencePackageEntity package({
    String? region = 'Doha',
    String countryCode = 'QA',
    String countryName = 'Qatar',
  }) =>
      ExperiencePackageEntity(
        id: '1',
        title: 'Doha City Tour',
        vendorId: 'v',
        vendorName: 'Desert Track Tourism',
        priceBasis: 'on_request',
        priceLabel: 'Price on request',
        latitude: 0,
        longitude: 0,
        regionLabel: region,
        countryCode: countryCode,
        countryName: countryName,
      );

  Future<void> pumpCard(WidgetTester tester, ExperiencePackageEntity package,
      {required bool showCountry, double? width}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: ExperiencePackageCard(
              package: package,
              index: 0,
              showCountry: showCountry,
              onTap: () {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the "All countries" list shows the country as a bold badge, then the region',
      (tester) async {
    await pumpCard(tester, package(), showCountry: true);

    expect(find.text('🇶🇦'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Qatar')).style!.fontWeight, FontWeight.w800);
    expect(find.text('Doha'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
    expect(find.byIcon(Icons.location_on_rounded), findsNothing);
    // The region sits after the badge, not inside it.
    expect(tester.getTopLeft(find.text('Doha')).dx,
        greaterThan(tester.getTopRight(find.text('Qatar')).dx));
  });

  testWidgets('a list of one country shows only the region', (tester) async {
    await pumpCard(tester, package(), showCountry: false);

    expect(find.text('Doha'), findsOneWidget);
    expect(find.text('Qatar'), findsNothing);
    expect(find.text('🇶🇦'), findsNothing);
    expect(find.byIcon(Icons.location_on_rounded), findsOneWidget);
  });

  testWidgets('the country shows even for a package with no region',
      (tester) async {
    await pumpCard(tester, package(region: null), showCountry: true);

    expect(find.text('Qatar'), findsOneWidget);
  });

  testWidgets('a region that only repeats the country is not shown twice',
      (tester) async {
    await pumpCard(tester, package(region: 'qatar'), showCountry: true);

    expect(find.text('Qatar'), findsOneWidget);
    expect(find.text('qatar'), findsNothing);
  });

  testWidgets('a long country name on a narrow phone stays inside the card',
      (tester) async {
    await pumpCard(
      tester,
      package(region: 'Dubai · Marina', countryCode: 'AE', countryName: 'United Arab Emirates'),
      showCountry: true,
      width: 360,
    );

    expect(tester.takeException(), isNull);
    // The test font draws every letter as a full square: the name cannot fit,
    // so it is cut short inside the badge rather than overflowing the card.
    final country = find.text('United Arab Emirates');
    expect(country, findsOneWidget);
    expect(tester.getTopRight(country).dx,
        lessThanOrEqualTo(tester.getTopRight(find.byType(ExperiencePackageCard)).dx));
  });
}
