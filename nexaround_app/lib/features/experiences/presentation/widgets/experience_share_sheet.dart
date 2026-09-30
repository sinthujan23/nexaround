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

/// The message people receive in a chat, also used for "Copy" and "More".
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

  /// The target being opened, shown as a spinner on that button so a second
  /// tap can't start another share.
  String? _busy;

  ExperiencePackageEntity get package => widget.package;

  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

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
            ..._buildTargets(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTargets() {
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _target('WhatsApp', 'assets/images/social_whatsapp.png', _shareWhatsApp),
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
    ];
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

  Widget _target(String label, String asset, Future<void> Function() onShare) {
    return Builder(
      builder: (targetContext) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _busy != null ? null : () => _run(label, targetContext, (_) => onShare()),
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
  /// a spinner on that target, until the other app has taken over.
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
  // Each button opens that app on its screen for sending a message, with no
  // share menu in between: not the phone's, and not the app's own choice of
  // feed, story or chat. Facebook's messages live in Messenger, so that is
  // where its button goes. An app that isn't installed opens its store page.

  Future<void> _shareWhatsApp() {
    final text = experienceShareMessage(package);
    return _sendToChat(_ChatApp.whatsApp, text, compose: [
      Uri.parse('whatsapp://send?text=${Uri.encodeComponent(text)}'),
    ]);
  }

  Future<void> _shareInstagram() {
    final text = experienceShareMessage(package);
    return _sendToChat(_ChatApp.instagram, text, compose: [
      // Instagram's own "send to" list, with the text as the message.
      if (_isIOS) Uri.parse('instagram://sharesheet?text=${Uri.encodeComponent(text)}'),
    ], inbox: [
      Uri.parse('instagram://direct-inbox'),
      Uri.parse('https://www.instagram.com/direct/inbox/'),
    ]);
  }

  /// Messenger turns the link into a card with the photo, title and summary.
  Future<void> _shareFacebook() {
    final link = experienceShareLink(package);
    return _sendToChat(_ChatApp.messenger, experienceShareMessage(package), compose: [
      Uri.parse('fb-messenger://share?link=${Uri.encodeComponent(link)}'),
    ]);
  }

  /// A message has no room for the whole summary, so X gets the headline and
  /// the link only.
  Future<void> _shareX() {
    final text =
        'Check out "${package.title}" by ${package.vendorName} on nexARound '
        '${experienceShareLink(package)}';
    return _sendToChat(_ChatApp.x, text, compose: [
      // X opens its own links (x.com claims every path), here a new Direct
      // Message; X asks who to send it to.
      Uri.parse('https://x.com/messages/compose?text=${Uri.encodeComponent(text)}'),
    ], inbox: [
      Uri.parse('twitter://messages'),
    ]);
  }

  /// Opens [app] on a new message with [text] in it, or its store page when
  /// it isn't installed.
  ///
  /// Android hands [text] to the app's chat screen (MainActivity.shareToChat).
  /// iOS, and an Android app without such a screen, open [compose], the app's
  /// own links to a new message, and failing those [inbox], its chat list,
  /// with [text] copied to paste.
  Future<void> _sendToChat(
    _ChatApp app,
    String text, {
    List<Uri> compose = const [],
    List<Uri> inbox = const [],
  }) async {
    if (_isIOS) {
      if (!await _isInstalled(app)) return _openStore(app);
    } else {
      switch (await _androidShareToChat(app, text)) {
        case 'sent':
          return;
        case 'missing':
          return _openStore(app);
      }
    }

    for (final link in compose) {
      if (await _openInApp(link)) return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    for (final link in inbox) {
      if (await _openInApp(link)) {
        _toast('Details copied. Pick a chat and paste them.');
        return;
      }
    }
    _toast("Couldn't open ${app.name}. Details copied instead.");
  }

  /// "sent", "missing" (not installed) or "no_chat", see
  /// MainActivity.shareToChat; null when the call itself failed.
  Future<String?> _androidShareToChat(_ChatApp app, String text) async {
    try {
      return await _shareChannel.invokeMethod<String>('shareToChat', {
        'packages': app.androidPackages,
        'text': text,
      });
    } catch (e) {
      debugPrint('Share to ${app.name} failed: $e');
      return null;
    }
  }

  /// iOS answers this only for the schemes in Info.plist's
  /// LSApplicationQueriesSchemes, which lists every [_ChatApp.iosScheme].
  Future<bool> _isInstalled(_ChatApp app) async {
    try {
      return await canLaunchUrl(Uri.parse('${app.iosScheme}://app'));
    } catch (e) {
      debugPrint('Checking for ${app.name} failed: $e');
      return false;
    }
  }

  /// The app's page in the App Store or Google Play, in the store app when
  /// there is one.
  Future<void> _openStore(_ChatApp app) async {
    final links = _isIOS
        ? [
            Uri.parse('itms-apps://apps.apple.com/app/id${app.appStoreId}'),
            Uri.parse('https://apps.apple.com/app/id${app.appStoreId}'),
          ]
        : [
            Uri.parse('market://details?id=${app.androidPackages.first}'),
            Uri.parse('https://play.google.com/store/apps/details?id=${app.androidPackages.first}'),
          ];
    for (final link in links) {
      if (await _open(link)) return;
    }
    _copy("Couldn't open the store. Details copied instead.");
  }

  /// Every app on the phone, through the system share sheet.
  Future<void> _shareMore(Rect? origin) async {
    final image = await _coverImage();
    if (!await _systemShare(image, experienceShareMessage(package), origin)) {
      _copy("Couldn't open sharing. Details copied instead.");
    }
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

  /// Like [_open], but an https link only opens in the app it belongs to,
  /// never the browser, and answers false when no app takes it.
  Future<bool> _openInApp(Uri uri) async {
    if (uri.scheme != 'https') return _open(uri);
    try {
      return await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
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

/// A chat app, as each store and platform knows it.
class _ChatApp {
  final String name;

  /// In order of preference; the first is the one whose Play Store page
  /// opens when none is installed.
  final List<String> androidPackages;

  /// The URL scheme that tells whether the app is installed on iOS.
  final String iosScheme;
  final String appStoreId;

  const _ChatApp(this.name, this.androidPackages, this.iosScheme, this.appStoreId);

  static const whatsApp =
      _ChatApp('WhatsApp', ['com.whatsapp', 'com.whatsapp.w4b'], 'whatsapp', '310633997');
  static const instagram =
      _ChatApp('Instagram', ['com.instagram.android'], 'instagram', '389801252');
  static const messenger =
      _ChatApp('Messenger', ['com.facebook.orca'], 'fb-messenger', '454638411');
  static const x = _ChatApp('X', ['com.twitter.android'], 'twitter', '333903271');
}

