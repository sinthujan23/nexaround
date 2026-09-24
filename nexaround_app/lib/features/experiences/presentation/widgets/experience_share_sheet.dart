import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
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

class _ExperienceShareSheet extends StatefulWidget {
  final ExperiencePackageEntity package;
  final ScaffoldMessengerState messenger;

  const _ExperienceShareSheet({required this.package, required this.messenger});

  @override
  State<_ExperienceShareSheet> createState() => _ExperienceShareSheetState();
}

class _ExperienceShareSheetState extends State<_ExperienceShareSheet> {
  static const _shareChannel = MethodChannel('com.nexaround.app/share');

  /// The target being prepared (its cover photo downloading), shown as a
  /// spinner on that button so a second tap can't start another share.
  String? _busy;

  ExperiencePackageEntity get package => widget.package;

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
                _target('WhatsApp', 'assets/images/social_whatsapp.png', (_) => _shareWhatsApp()),
                _target('Instagram', 'assets/images/social_instagram.png', _shareInstagram),
                _target('Facebook', 'assets/images/social_facebook.png', _shareFacebook),
                _target('X', 'assets/images/social_x.png', _shareX),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _outlinedAction(
                    icon: Icons.copy_rounded,
                    label: 'Copy details',
                    onPressed: () {
                      Navigator.pop(context);
                      _copy('Details copied. Paste them anywhere to share.');
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Builder(
                    builder: (buttonContext) => _outlinedAction(
                      icon: Icons.ios_share_rounded,
                      label: 'More',
                      onPressed: _busy != null
                          ? null
                          : () => _run('More', buttonContext, _shareMore),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _outlinedAction({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                      placeholder: (_, _) => _thumbPlaceholder(),
                      errorWidget: (_, _, _) => _thumbPlaceholder(),
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
    String label,
    String asset,
    Future<void> Function(Rect? origin) onShare,
  ) {
    return Builder(
      builder: (targetContext) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _busy != null ? null : () => _run(label, targetContext, onShare),
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
                child: _busy == label
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      )
                    : Image.asset(asset, fit: BoxFit.contain),
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

  /// Runs [onShare] for the target called [label]. The sheet stays open, with
  /// a spinner on that target, while the cover photo downloads, and closes
  /// once the other app has taken over.
  Future<void> _run(
    String label,
    BuildContext targetContext,
    Future<void> Function(Rect? origin) onShare,
  ) async {
    // iPad anchors the system share popover to the tapped button, so its
    // position is read now, while the sheet is still on screen.
    final box = targetContext.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;

    setState(() => _busy = label);
    try {
      await onShare(origin);
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  // --- Targets --------------------------------------------------------------
  //
  // Instagram, Facebook and X get the cover photo the same way the system
  // share sheet passes it, so each app asks where it goes: Instagram offers
  // Feed, Story or a chat, Facebook a post or a story, X a post or a Direct
  // Message. On Android the photo goes straight to that app
  // (MainActivity.shareToApp). iOS doesn't let an app pick the receiver, so
  // there the system share sheet opens with the photo attached. The web links
  // are the fallback when the app isn't installed; they go through https,
  // which the Android manifest and iOS LSApplicationQueriesSchemes already
  // allow.

  Future<void> _shareWhatsApp() async {
    // No number: WhatsApp asks which chat to send it to.
    final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(experienceShareMessage(package))}',
    );
    if (!await _open(uri)) _copy("Couldn't open WhatsApp. Details copied instead.");
  }

  /// Instagram drops any text it is given, so the details go on the
  /// clipboard for the caption or the message.
  Future<void> _shareInstagram(Rect? origin) async {
    await Clipboard.setData(ClipboardData(text: experienceShareMessage(package)));
    final shared = await _shareToApp(
      androidPackage: 'com.instagram.android',
      appName: 'Instagram',
      origin: origin,
    );
    if (shared) {
      _toast('Details copied. Paste them into your post, story or message.');
      return;
    }
    final opened = await _open(Uri.parse('https://www.instagram.com/'));
    _toast(opened
        ? 'Details copied. Paste them in an Instagram chat or story.'
        : "Couldn't open Instagram. Details copied instead.");
  }

  /// Facebook ignores prefilled text, so the details are copied for the post.
  Future<void> _shareFacebook(Rect? origin) async {
    await Clipboard.setData(ClipboardData(text: experienceShareMessage(package)));
    final shared = await _shareToApp(
      androidPackage: 'com.facebook.katana',
      appName: 'Facebook',
      text: experienceShareLink(package),
      origin: origin,
    );
    if (shared) {
      _toast('Details copied. Paste them into your post or story.');
      return;
    }
    final uri = Uri.parse(
      'https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(experienceShareLink(package))}',
    );
    final opened = await _open(uri);
    _toast(opened
        ? 'Details copied. Paste them into your post.'
        : "Couldn't open Facebook. Details copied instead.");
  }

  /// A post has a length limit, so X gets the headline and the link only.
  Future<void> _shareX(Rect? origin) async {
    final text = 'Check out "${package.title}" by ${package.vendorName} on nexARound';
    final shared = await _shareToApp(
      androidPackage: 'com.twitter.android',
      appName: 'X',
      text: '$text ${experienceShareLink(package)}',
      origin: origin,
    );
    if (shared) return;

    final uri = Uri.parse(
      'https://twitter.com/intent/tweet'
      '?text=${Uri.encodeComponent(text)}'
      '&url=${Uri.encodeComponent(experienceShareLink(package))}',
    );
    if (!await _open(uri)) _copy("Couldn't open X. Details copied instead.");
  }

  /// Every app on the phone, through the system share sheet.
  Future<void> _shareMore(Rect? origin) async {
    final image = await _coverImage();
    if (!await _systemShare(image, experienceShareMessage(package), origin)) {
      _copy("Couldn't open sharing. Details copied instead.");
    }
  }

  /// Hands the cover photo (and [text], for apps that use it) to one app.
  /// Returns false when that can't happen, so the caller falls back to the
  /// app's website.
  Future<bool> _shareToApp({
    required String androidPackage,
    required String appName,
    String? text,
    Rect? origin,
  }) async {
    final image = await _coverImage();
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final shared = await _shareChannel.invokeMethod<bool>('shareToApp', {
          'package': androidPackage,
          'image': image?.bytes,
          'mimeType': image?.mimeType,
          'text': text,
          'title': 'Share to $appName',
        });
        return shared ?? false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return await _systemShare(image, text, origin);
      }
    } catch (e) {
      debugPrint('Share to $appName failed: $e');
    }
    return false;
  }

  Future<bool> _systemShare(_CoverImage? image, String? text, Rect? origin) async {
    try {
      await SharePlus.instance.share(ShareParams(
        text: text,
        subject: package.title,
        files: image == null ? null : [XFile.fromData(image.bytes, mimeType: image.mimeType)],
        fileNameOverrides: image == null ? null : ['nexaround_share.${image.extension}'],
        sharePositionOrigin: origin,
      ));
      return true;
    } catch (e) {
      debugPrint('System share failed: $e');
      return false;
    }
  }

  /// The package's cover photo, or null when there is none or it can't be
  /// fetched in time, in which case only text is shared.
  Future<_CoverImage?> _coverImage() async {
    final url = PlaceImageHelper.resolveUrl(package.coverPhotoUrl);
    if (url == null) return null;
    try {
      final response = await http
          .get(Uri.parse(url), headers: PlaceImageHelper.headersFor(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      return _CoverImage(response.bodyBytes);
    } catch (e) {
      debugPrint('Share image download failed: $e');
      return null;
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
    widget.messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CoverImage {
  final Uint8List bytes;

  const _CoverImage(this.bytes);

  /// PNG files start with 0x89 'P'; anything else is sent as JPEG, which is
  /// what cover photos are.
  bool get _isPng => bytes.length > 1 && bytes[0] == 0x89 && bytes[1] == 0x50;

  String get mimeType => _isPng ? 'image/png' : 'image/jpeg';

  String get extension => _isPng ? 'png' : 'jpg';
}
