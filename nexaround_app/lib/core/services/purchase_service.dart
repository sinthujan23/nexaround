import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/services/plan_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// What a purchase attempt came to.
enum PurchaseOutcome { purchased, cancelled, failed, unavailable }

/// Apple / Google in-app purchase through RevenueCat.
///
/// RevenueCat's customer id is our user id ([logIn] after every sign-in), so
/// its webhook and `/billing/sync` both know whose plan changed. The public SDK
/// keys come from `/config/keys`; until they arrive, or on a platform without
/// a store, everything here reports [PurchaseOutcome.unavailable] instead of
/// throwing.
///
/// RevenueCat setup this expects: offering "default" (the current one) with
/// two packages identified `voyager_monthly` and `globetrotter_monthly`.
/// Monthly plans only since 2026-11-11 (the TL dropped annual plans).
class PurchaseService {
  PurchaseService._();

  static bool _configured = false;
  static String? _pendingUserId;

  static bool get _supported => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  static String get _apiKey => !_supported
      ? ''
      : (Platform.isIOS ? ApiConstants.revenueCatAppleKey : ApiConstants.revenueCatGoogleKey);

  /// Set up the SDK once the keys are known. Safe to call repeatedly.
  static Future<void> init() async {
    if (_configured || !_supported || _apiKey.isEmpty) return;
    try {
      await Purchases.configure(PurchasesConfiguration(_apiKey));
      _configured = true;
      final pending = _pendingUserId;
      _pendingUserId = null;
      if (pending != null) await logIn(pending);
    } catch (e) {
      debugPrint('PurchaseService.init failed: $e');
    }
  }

  static Future<void> logIn(String userId) async {
    if (!_configured) {
      _pendingUserId = userId; // applied as soon as init() runs
      return;
    }
    try {
      await Purchases.logIn(userId);
    } catch (e) {
      debugPrint('PurchaseService.logIn failed: $e');
    }
  }

  static Future<void> logOut() async {
    _pendingUserId = null;
    if (!_configured) return;
    try {
      final info = await Purchases.getCustomerInfo();
      // logOut throws for an anonymous customer; only a logged-in one has
      // anything to sign out of.
      if (!info.originalAppUserId.startsWith(r'$RCAnonymousID')) {
        await Purchases.logOut();
      }
    } catch (e) {
      debugPrint('PurchaseService.logOut failed: $e');
    }
  }

  /// The four packages by id (`voyager_monthly` …), with the store's localised
  /// price on each. Empty when the store cannot be reached.
  static Future<Map<String, Package>> packages() async {
    await init();
    if (!_configured) return const {};
    try {
      final offerings = await Purchases.getOfferings();
      final offering = offerings.current ?? offerings.getOffering('default');
      if (offering == null) return const {};
      final out = <String, Package>{};
      for (final p in offering.availablePackages) {
        out[_keyFor(p)] = p;
      }
      return out;
    } catch (e) {
      debugPrint('PurchaseService.packages failed: $e');
      return const {};
    }
  }

  /// `voyager_monthly` etc. from the package id, or from the product id when
  /// the package was named differently in the dashboard.
  static String _keyFor(Package p) {
    final ids = '${p.identifier} ${p.storeProduct.identifier}'.toLowerCase();
    final plan = ids.contains('globetrotter') ? 'globetrotter' : (ids.contains('voyager') ? 'voyager' : '');
    final period = (ids.contains('year') || ids.contains('annual') || p.packageType == PackageType.annual)
        ? 'yearly'
        : 'monthly';
    return plan.isEmpty ? p.identifier : '${plan}_$period';
  }

  static Future<PurchaseOutcome> buy(Package package) async {
    await init();
    if (!_configured) return PurchaseOutcome.unavailable;
    try {
      await Purchases.purchase(PurchaseParams.package(
        package,
        productChangeInfo: await _changeFrom(package),
      ));
      await PlanService.sync();
      return PurchaseOutcome.purchased;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) return PurchaseOutcome.cancelled;
      debugPrint('PurchaseService.buy failed: $code $e');
      return PurchaseOutcome.failed;
    } catch (e) {
      debugPrint('PurchaseService.buy failed: $e');
      return PurchaseOutcome.failed;
    }
  }

  /// On Google Play a second plan is a second subscription unless the purchase
  /// replaces the current one; the App Store does this by itself because all
  /// four products sit in one subscription group.
  static Future<StoreProductChangeInfo?> _changeFrom(Package package) async {
    if (!Platform.isAndroid) return null;
    try {
      final active = (await Purchases.getCustomerInfo()).activeSubscriptions;
      final newId = package.storeProduct.identifier;
      for (final id in active) {
        final lower = id.toLowerCase();
        if ((lower.contains('voyager') || lower.contains('globetrotter')) && id != newId) {
          // Upgrade now with the unused time credited; downgrade at renewal.
          final upgrading = package.storeProduct.identifier.toLowerCase().contains('globetrotter') &&
              lower.contains('voyager');
          return StoreProductChangeInfo(
            id,
            replacementMode: upgrading
                ? StoreReplacementMode.withTimeProration
                : StoreReplacementMode.deferred,
          );
        }
      }
    } catch (e) {
      debugPrint('PurchaseService: could not read the current subscription: $e');
    }
    return null;
  }

  /// "Restore purchases" (Apple requires the button): re-links a plan bought
  /// on another device or before a reinstall.
  static Future<bool> restore() async {
    await init();
    if (!_configured) return false;
    try {
      await Purchases.restorePurchases();
      await PlanService.sync();
      return true;
    } catch (e) {
      debugPrint('PurchaseService.restore failed: $e');
      return false;
    }
  }

  /// Opens the store's subscription settings, where the user cancels or
  /// changes their plan.
  static Future<void> manage() async {
    String? url;
    if (_configured) {
      try {
        url = (await Purchases.getCustomerInfo()).managementURL;
      } catch (_) {}
    }
    url ??= (_supported && Platform.isIOS)
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
