import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Outbound contact channels for vendor experiences.
///
/// The phone path is the same logic the Emergency tab has used for years
/// (`discover_page.dart`'s `_makePhoneCall`), lifted here so the Experiences
/// screens do not grow a second copy of it.
class ContactLauncher {
  const ContactLauncher._();

  /// Opens the dialler. Keeps a leading `+` — `tel:` accepts it and it is what
  /// makes an international number dial correctly from abroad.
  static Future<bool> call(String? rawNumber) async {
    final number = _telNumber(rawNumber);
    if (number == null) return false;
    try {
      return await launchUrl(
        Uri(scheme: 'tel', path: number),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('Phone launch failed: $e');
      return false;
    }
  }

  /// Opens a WhatsApp chat, optionally prefilled.
  ///
  /// Uses the `https://wa.me/` form rather than the `whatsapp://` scheme: the
  /// Android manifest already declares an intent query for https VIEW, so this
  /// needs no manifest change, and it degrades to the web client when WhatsApp
  /// is not installed instead of failing silently.
  static Future<bool> whatsApp(String? rawNumber, {String? message}) async {
    final digits = whatsAppDigits(rawNumber);
    if (digits == null) return false;

    final query = (message == null || message.isEmpty)
        ? ''
        : '?text=${Uri.encodeComponent(message)}';
    try {
      return await launchUrl(
        Uri.parse('https://wa.me/$digits$query'),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('WhatsApp launch failed: $e');
      return false;
    }
  }

  /// Opens an external website.
  static Future<bool> website(String? url) async {
    if (url == null || url.trim().isEmpty) return false;
    var target = url.trim();
    if (!target.startsWith('http://') && !target.startsWith('https://')) {
      target = 'https://$target';
    }
    try {
      return await launchUrl(
        Uri.parse(target),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('Website launch failed: $e');
      return false;
    }
  }

  /// Digits only — `wa.me` rejects a leading `+`.
  ///
  /// Mirrors `whatsapp_number()` on the backend; the two must agree or a
  /// number the server accepts will produce a dead link in the app.
  static String? whatsAppDigits(String? raw) {
    if (raw == null) return null;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length < 7 ? null : digits;
  }

  static String? _telNumber(String? raw) {
    if (raw == null) return null;
    final hadPlus = raw.trim().startsWith('+');
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 7) return null;
    return hadPlus ? '+$digits' : digits;
  }
}
