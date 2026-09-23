import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexaround_app/features/experiences/data/models/experience_model.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/vendor_social_bar.dart';

void main() {
  group('Vendor social entities and models', () {
    test('ExperienceVendorEntity correctly detects presence of social channels', () {
      const vendorNone = ExperienceVendorEntity(
        id: 'v1',
        name: 'Test Vendor',
        latitude: 6.9,
        longitude: 79.8,
      );
      expect(vendorNone.hasPhone, false);
      expect(vendorNone.hasWhatsapp, false);
      expect(vendorNone.hasInstagram, false);
      expect(vendorNone.hasFacebook, false);
      expect(vendorNone.hasX, false);
      expect(vendorNone.hasSocials, false);

      const vendorSome = ExperienceVendorEntity(
        id: 'v2',
        name: 'Trinco Boat',
        latitude: 8.5,
        longitude: 81.2,
        contactWhatsapp: '+94771234567',
        contactInstagram: '@trincoboat',
      );
      expect(vendorSome.hasWhatsapp, true);
      expect(vendorSome.hasInstagram, true);
      expect(vendorSome.hasFacebook, false);
      expect(vendorSome.hasX, false);
      expect(vendorSome.hasSocials, true);
    });

    test('ExperiencePackageEntity correctly detects presence of vendor socials', () {
      const packageWithSocials = ExperiencePackageEntity(
        id: 'p1',
        title: 'Boat Safari',
        vendorId: 'v1',
        vendorName: 'Trinco Boat',
        vendorWhatsapp: '+94771234567',
        vendorInstagram: 'trincoboat',
        vendorFacebook: 'trincoboat.lk',
        vendorX: '@trincoboat',
        latitude: 8.5,
        longitude: 81.2,
      );
      expect(packageWithSocials.hasVendorWhatsapp, true);
      expect(packageWithSocials.hasVendorInstagram, true);
      expect(packageWithSocials.hasVendorFacebook, true);
      expect(packageWithSocials.hasVendorX, true);
      expect(packageWithSocials.hasSocials, true);

      const packageNoSocials = ExperiencePackageEntity(
        id: 'p2',
        title: 'City Walk',
        vendorId: 'v2',
        vendorName: 'Walk Tours',
        latitude: 6.9,
        longitude: 79.8,
      );
      expect(packageNoSocials.hasSocials, false);
    });

    test('ExperienceModel parses social fields from JSON', () {
      final vendorJson = {
        'id': 'v-100',
        'name': 'Lagoon Tours',
        'latitude': 8.58,
        'longitude': 81.21,
        'contact_phone': '+94770001111',
        'contact_whatsapp': '+94770001111',
        'contact_instagram': 'lagoontours_official',
        'contact_facebook': 'https://facebook.com/lagoontours',
        'contact_x': '@lagoontours',
      };
      final vendorModel = ExperienceVendorModel.fromJson(vendorJson);
      expect(vendorModel.contactInstagram, 'lagoontours_official');
      expect(vendorModel.contactFacebook, 'https://facebook.com/lagoontours');
      expect(vendorModel.contactX, '@lagoontours');
      expect(vendorModel.hasInstagram, true);
      expect(vendorModel.hasFacebook, true);
      expect(vendorModel.hasX, true);

      final packageJson = {
        'id': 'pkg-1',
        'title': 'Dolphin Watching',
        'vendor_id': 'v-100',
        'vendor_name': 'Lagoon Tours',
        'vendor_whatsapp': '+94770001111',
        'vendor_instagram': 'lagoontours_official',
        'vendor_facebook': null,
        'vendor_x': null,
        'latitude': 8.58,
        'longitude': 81.21,
      };
      final packageModel = ExperiencePackageModel.fromJson(packageJson);
      expect(packageModel.vendorWhatsapp, '+94770001111');
      expect(packageModel.vendorInstagram, 'lagoontours_official');
      expect(packageModel.vendorFacebook, null);
      expect(packageModel.vendorX, null);
      expect(packageModel.hasVendorWhatsapp, true);
      expect(packageModel.hasVendorInstagram, true);
      expect(packageModel.hasVendorFacebook, false);
      expect(packageModel.hasVendorX, false);
      expect(packageModel.hasSocials, true);
    });
  });

  group('VendorSocialBar widget', () {
    testWidgets('renders SizedBox.shrink when vendor has no social accounts', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VendorSocialBar(),
          ),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.byType(VendorSocialBar), findsOneWidget);
    });

    testWidgets('renders only provided social accounts (e.g. WhatsApp and Instagram only)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VendorSocialBar(
              whatsapp: '+94771234567',
              instagram: '@trincoboats',
              isCompact: true,
            ),
          ),
        ),
      );

      // Should find 2 images (WhatsApp and Instagram)
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.byTooltip('Chat on WhatsApp'), findsOneWidget);
      expect(find.byTooltip('View Instagram'), findsOneWidget);
      expect(find.byTooltip('View Facebook'), findsNothing);
      expect(find.byTooltip('View on X'), findsNothing);
    });

    testWidgets('renders all 4 social accounts when all are configured', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VendorSocialBar(
              whatsapp: '+94771234567',
              instagram: '@trincoboats',
              facebook: 'trincoboat',
              x: '@trincoboat',
              isCompact: true,
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsNWidgets(4));
      expect(find.byTooltip('Chat on WhatsApp'), findsOneWidget);
      expect(find.byTooltip('View Instagram'), findsOneWidget);
      expect(find.byTooltip('View Facebook'), findsOneWidget);
      expect(find.byTooltip('View on X'), findsOneWidget);
    });
  });
}
