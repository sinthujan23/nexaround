import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_package_card.dart';

void main() {
  // "Price on request" keeps the price off the currency and auth blocs.
  ExperiencePackageEntity package({String? region = 'Doha'}) => ExperiencePackageEntity(
        id: '1',
        title: 'Doha City Tour',
        vendorId: 'v',
        vendorName: 'Desert Track Tourism',
        priceBasis: 'on_request',
        priceLabel: 'Price on request',
        latitude: 0,
        longitude: 0,
        regionLabel: region,
        countryCode: 'QA',
        countryName: 'Qatar',
      );

  Future<void> pumpCard(WidgetTester tester, ExperiencePackageEntity package,
      {required bool showCountry}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ExperiencePackageCard(
          package: package,
          index: 0,
          showCountry: showCountry,
          onTap: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The location line's text, whether plain or with the country in bold.
  String? locationText(WidgetTester tester) {
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final plain = text.textSpan?.toPlainText() ?? text.data;
      if (plain != null && plain.contains('Doha') && plain != 'Doha City Tour') return plain;
      if (plain == 'Qatar') return plain;
    }
    return null;
  }

  testWidgets('the "All countries" list leads the location with the country in bold',
      (tester) async {
    await pumpCard(tester, package(), showCountry: true);

    expect(locationText(tester), 'Qatar · Doha');
    expect(find.text('🇶🇦'), findsOneWidget);
    expect(find.byIcon(Icons.location_on_rounded), findsNothing);

    final rich = tester.widget<Text>(find.byWidgetPredicate(
        (w) => w is Text && w.textSpan?.toPlainText() == 'Qatar · Doha'));
    final country = (rich.textSpan! as TextSpan).children!.first as TextSpan;
    expect(country.text, 'Qatar');
    expect(country.style!.fontWeight, FontWeight.w800);
  });

  testWidgets('a list of one country shows only the region', (tester) async {
    await pumpCard(tester, package(), showCountry: false);

    expect(locationText(tester), 'Doha');
    expect(find.text('🇶🇦'), findsNothing);
    expect(find.byIcon(Icons.location_on_rounded), findsOneWidget);
  });

  testWidgets('the country shows even for a package with no region',
      (tester) async {
    await pumpCard(tester, package(region: null), showCountry: true);

    expect(locationText(tester), 'Qatar');
  });

  testWidgets('a region that only repeats the country is not shown twice',
      (tester) async {
    await pumpCard(tester, package(region: 'qatar'), showCountry: true);

    expect(locationText(tester), 'Qatar');
  });
}
