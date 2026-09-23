import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Opens Facebook's post screen, or a new Instagram Story, directly, without
/// the phone's share menu in between.
///
/// Native side: iOS in this package (Facebook's share kit, which comes in
/// through the same Swift package as facebook_app_events' SDK); Android in the
/// app's MainActivity.kt. Every call returns false instead of throwing, so the
/// caller can fall back to the share menu.
class NexaroundShare {
  const NexaroundShare._();

  static const MethodChannel _channel =
      MethodChannel('com.nexaround.app/social_share');

  /// Facebook's post screen with [url] as a link card. Facebook ignores any
  /// text from another app, so a link is all it takes.
  static Future<bool> facebookLink(String url) =>
      _call('facebookLink', {'url': url});

  /// A new Instagram Story with [image] as a sticker on a brand-colour
  /// background. Instagram takes no link from another app here.
  static Future<bool> instagramStory(Uint8List image) =>
      _call('instagramStory', {'image': image});

  static Future<bool> _call(String method, Map<String, Object> args) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } catch (e) {
      debugPrint('NexaroundShare.$method failed: $e');
      return false;
    }
  }
}
