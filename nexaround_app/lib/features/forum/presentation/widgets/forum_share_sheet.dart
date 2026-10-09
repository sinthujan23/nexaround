import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/utils/place_image_helper.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/forum_topic.dart';

/// The link for a shared forum topic. Opens the app directly when installed,
/// or a web preview page on nexaround.com/f/<id>.
String forumShareLink(ForumTopic topic) =>
    'https://nexaround.com/f/${topic.id}';

/// Opens the "Share this discussion" bottom sheet for [topic].
Future<void> showForumShareSheet(
  BuildContext context,
  ForumTopic topic,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _ForumShareSheet(
      topic: topic,
      messenger: ScaffoldMessenger.of(context),
    ),
  );
}

/// The formatted text shared to chats and copied to the clipboard.
String forumShareMessage(ForumTopic topic) {
  final category = topic.categoryName.trim();
  final author = topic.userDisplayName.trim();
  final details = [
    if (category.isNotEmpty) category,
    if (author.isNotEmpty) 'Asked by $author',
  ].join(' · ');

  final summary = topic.content.trim();
  final previewText = summary.length > 140 ? '${summary.substring(0, 139)}…' : summary;

  return [
    topic.title,
    if (details.isNotEmpty) details,
    if (previewText.isNotEmpty) previewText,
    '',
    'Join the discussion on nexARound: ${forumShareLink(topic)}',
  ].join('\n');
}

class _ForumShareSheet extends StatefulWidget {
  final ForumTopic topic;
  final ScaffoldMessengerState messenger;

  const _ForumShareSheet({required this.topic, required this.messenger});

  @override
  State<_ForumShareSheet> createState() => _ForumShareSheetState();
}

class _ForumShareSheetState extends State<_ForumShareSheet> {
  static const _shareChannel = MethodChannel('com.nexaround.app/share');

  String? _busy;

  ForumTopic get topic => widget.topic;

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
              'Share this discussion',
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

  Widget _buildPreview() {
    final firstImage = topic.imageUrls.isNotEmpty ? topic.imageUrls.first : null;
    final url = PlaceImageHelper.resolveUrl(firstImage);

    final stats = [
      if (topic.categoryName.isNotEmpty) topic.categoryName,
      '${topic.repliesCount} ${topic.repliesCount == 1 ? 'reply' : 'replies'}',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 56,
              height: 56,
              child: url == null
                  ? _placeholder()
                  : CachedNetworkImage(
                      imageUrl: url,
                      httpHeaders: PlaceImageHelper.headersFor(url),
                      fit: BoxFit.cover,
                      memCacheWidth: 168,
                      placeholder: (_, _) => _placeholder(),
                      errorWidget: (_, _, _) => _placeholder(),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  topic.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  stats,
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

  Widget _placeholder() {
    return Container(
      color: AppColors.brandGreen.withValues(alpha: 0.12),
      child: const Icon(
        Icons.forum_rounded,
        size: 26,
        color: AppColors.brandGreen,
      ),
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

  Future<void> _run(
    String label,
    BuildContext targetContext,
    Future<void> Function(Rect? origin) onShare,
  ) async {
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

  Future<void> _shareWhatsApp() {
    final text = forumShareMessage(topic);
    return _sendToChat(_ChatApp.whatsApp, text, compose: [
      Uri.parse('whatsapp://send?text=${Uri.encodeComponent(text)}'),
    ]);
  }

  Future<void> _shareInstagram() {
    final text = forumShareMessage(topic);
    return _sendToChat(_ChatApp.instagram, text, compose: [
      if (_isIOS) Uri.parse('instagram://sharesheet?text=${Uri.encodeComponent(text)}'),
    ], inbox: [
      Uri.parse('instagram://direct-inbox'),
      Uri.parse('https://www.instagram.com/direct/inbox/'),
    ]);
  }

  Future<void> _shareFacebook() {
    final link = forumShareLink(topic);
    return _sendToChat(_ChatApp.messenger, forumShareMessage(topic), compose: [
      Uri.parse('fb-messenger://share?link=${Uri.encodeComponent(link)}'),
    ]);
  }

  Future<void> _shareX() {
    final text =
        '${topic.title} · nexARound Travel Forum ${forumShareLink(topic)}';
    return _sendToChat(_ChatApp.x, text, compose: [
      Uri.parse('https://x.com/messages/compose?text=${Uri.encodeComponent(text)}'),
    ], inbox: [
      Uri.parse('twitter://messages'),
    ]);
  }

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

  Future<bool> _isInstalled(_ChatApp app) async {
    try {
      return await canLaunchUrl(Uri.parse('${app.iosScheme}://app'));
    } catch (e) {
      debugPrint('Checking for ${app.name} failed: $e');
      return false;
    }
  }

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

  Future<void> _shareMore(Rect? origin) async {
    final image = await _topicImage();
    if (!await _systemShare(image, forumShareMessage(topic), origin)) {
      _copy("Couldn't open sharing. Details copied instead.");
    }
  }

  Future<bool> _systemShare(_CoverImage? image, String? text, Rect? origin) async {
    try {
      await SharePlus.instance.share(ShareParams(
        text: text,
        subject: topic.title,
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

  Future<_CoverImage?> _topicImage() async {
    final firstImage = topic.imageUrls.isNotEmpty ? topic.imageUrls.first : null;
    final url = PlaceImageHelper.resolveUrl(firstImage);
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
    await Clipboard.setData(ClipboardData(text: forumShareMessage(topic)));
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

  bool get _isPng => bytes.length > 1 && bytes[0] == 0x89 && bytes[1] == 0x50;

  String get mimeType => _isPng ? 'image/png' : 'image/jpeg';

  String get extension => _isPng ? 'png' : 'jpg';
}

class _ChatApp {
  final String name;
  final List<String> androidPackages;
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
