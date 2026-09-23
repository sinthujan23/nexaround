import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/utils/place_image_helper.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// The link for one package. It opens the app on that package when the app
/// is installed (Android App Links / iOS Universal Links), and otherwise a web
/// page with the package and the store buttons (nexaround_backend
/// app/api/share.py). The same page gives WhatsApp, Facebook and X their
/// link preview.
String experienceShareLink(ExperiencePackageEntity package) =>
    'https://nexaround.com/e/${package.id}';

/// Opens the "Share this experience" sheet for [package].
Future<void> showExperienceShareSheet(
  BuildContext context,
  ExperiencePackageEntity package,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _ExperienceShareSheet(
      package: package,
      // The page's messenger, not the sheet's: the sheet closes before the
      // confirmation is shown.
      messenger: ScaffoldMessenger.of(context),
    ),
  );
}

/// The message people receive, used for WhatsApp and for "Copy".
String experienceShareMessage(ExperiencePackageEntity package) {
  final details = [package.priceLabel, package.durationLabel]
      .where((s) => s.trim().isNotEmpty)
      .join(' · ');
  final summary = (package.summary ?? '').trim();

  return [
    'Check out "${package.title}" by ${package.vendorName} on nexARound',
    if (details.isNotEmpty) details,
    if (summary.isNotEmpty) summary,
    '',
    'See it on nexARound: ${experienceShareLink(package)}',
  ].join('\n');
}

class _ExperienceShareSheet extends StatelessWidget {
  final ExperiencePackageEntity package;
  final ScaffoldMessengerState messenger;

  const _ExperienceShareSheet({required this.package, required this.messenger});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Share this experience',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            _buildPreview(),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _target(context, 'WhatsApp', 'assets/images/social_whatsapp.png', _shareWhatsApp),
                _target(context, 'Instagram', 'assets/images/social_instagram.png', _shareInstagram),
                _target(context, 'Facebook', 'assets/images/social_facebook.png', _shareFacebook),
                _target(context, 'X', 'assets/images/social_x.png', _shareX),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _copy('Details copied. Paste them anywhere to share.');
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text(
                  'Copy details',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What is being shared, so the user knows before picking an app.
  Widget _buildPreview() {
    final url = PlaceImageHelper.resolveUrl(package.coverPhotoUrl);
    final details = [package.priceLabel, package.durationLabel]
        .where((s) => s.trim().isNotEmpty)
        .join(' · ');

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 56,
              height: 56,
              child: url == null
                  ? _thumbPlaceholder()
                  : CachedNetworkImage(
                      imageUrl: url,
                      httpHeaders: PlaceImageHelper.headersFor(url),
                      fit: BoxFit.cover,
                      memCacheWidth: 168,
                      placeholder: (_, __) => _thumbPlaceholder(),
                      errorWidget: (_, __, ___) => _thumbPlaceholder(),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  package.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  details.isEmpty ? package.vendorName : '${package.vendorName} · $details',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbPlaceholder() {
    return Container(
      color: AppColors.surfaceVariant,
      child: const Icon(Icons.kayaking_rounded, size: 22, color: AppColors.textMuted),
    );
  }

  Widget _target(
    BuildContext context,
    String label,
    String asset,
    Future<void> Function(Rect? origin) onShare,
  ) {
    return Builder(
      builder: (tileContext) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          // Read before the sheet closes: the iPad share popover anchors to it.
          final box = tileContext.findRenderObject() as RenderBox?;
          final origin =
              box == null ? null : box.localToGlobal(Offset.zero) & box.size;
          Navigator.pop(context);
          onShare(origin);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
                child: Image.asset(asset, fit: BoxFit.contain),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Targets --------------------------------------------------------------
  //
  // WhatsApp is the only one of the four with a public link that opens it
  // with a message ready (wa.me/?text=), so it gets that link. Facebook,
  // Instagram and X take a shared post only through the phone's own share
  // menu: picking them there opens their composer with the text and link in
  // it. Their web links (facebook.com/sharer, twitter.com/intent) just open
  // the app's feed on a phone, and Instagram has no link at all.

  Future<void> _shareWhatsApp(Rect? origin) async {
    // No number: WhatsApp asks which chat to send it to.
    final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(experienceShareMessage(package))}',
    );
    if (!await _open(uri)) _copy("Couldn't open WhatsApp. Details copied instead.");
  }

  /// Facebook shows the link as a card with the package photo and title
  /// (from the share page's Open Graph tags). It drops any text by policy.
  Future<void> _shareFacebook(Rect? origin) =>
      _shareWithSystemSheet(experienceShareMessage(package), origin);

  /// Instagram takes it as a message to send in a chat.
  Future<void> _shareInstagram(Rect? origin) =>
      _shareWithSystemSheet(experienceShareMessage(package), origin);

  /// A post has a length limit, so X gets the headline and the link only.
  Future<void> _shareX(Rect? origin) => _shareWithSystemSheet(
        'Check out "${package.title}" by ${package.vendorName} on nexARound '
        '${experienceShareLink(package)}',
        origin,
      );

  /// The phone's own share menu, with the chosen app in it.
  Future<void> _shareWithSystemSheet(String text, Rect? origin) async {
    try {
      await SharePlus.instance.share(ShareParams(
        text: text,
        subject: package.title,
        sharePositionOrigin: origin,
      ));
    } catch (e) {
      debugPrint('System share failed: $e');
      await _copy("Couldn't open sharing. Details copied instead.");
    }
  }

  Future<bool> _open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Share launch failed: $e');
      return false;
    }
  }

  Future<void> _copy(String message) async {
    await Clipboard.setData(ClipboardData(text: experienceShareMessage(package)));
    _toast(message);
  }

  void _toast(String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
