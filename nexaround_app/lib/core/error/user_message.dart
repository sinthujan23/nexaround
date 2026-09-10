import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Turns any thrown object into a sentence that is safe to put on screen.
///
/// Raw exception text is never part of the result. `e.toString()` on a
/// [DioException] names the HTTP library, the API hostname and the OS socket
/// error; a [TypeError] names Dart model fields; a backend 500 can carry
/// framework wording. None of that helps a user, and all of it helps someone
/// mapping the stack. The raw error still goes to the debug console.
///
/// [action] is what the user was trying to do, phrased as a verb phrase —
/// "delete the story", "open the link" — and produces "Couldn't delete the
/// story. Check your internet connection and try again." Without it the reason
/// alone is returned as a sentence.
String userMessageFor(Object? error, {String? action}) {
  if (kDebugMode) debugPrint('⚠️ ${action ?? 'error'}: $error');
  final reason = _reasonFor(error);
  if (action == null) return reason;
  return "Couldn't $action. $reason";
}

/// HTTP status behind [error], or null when it never got a response.
int? statusCodeOf(Object? error) =>
    error is DioException ? error.response?.statusCode : null;

/// True when the backend rejected the caller's session. Use this — not the
/// message text — to decide whether to send the user back to login.
bool isSessionExpired(Object? error) => statusCodeOf(error) == 401;

/// The server's own `detail` text, but only when it is safe to show.
///
/// The backend writes deliberate, user-facing messages for the conditions it
/// expects — "Invalid or expired OTP code", "Please wait 60 seconds before
/// requesting a new code" — and those are worth keeping. What it must not
/// pass through is validator output (422 lists pydantic field errors), server
/// faults (5xx), or anything that reads like a stack trace. Returns null when
/// the caller should fall back to a fixed message instead.
String? safeServerDetail(Response? response) {
  if (response == null) return null;
  final status = response.statusCode ?? 0;
  // Only statuses the backend answers with an intentional sentence.
  if (status < 400 || status >= 500 || status == 422) return null;
  final data = response.data;
  if (data is! Map) return null;
  final detail = data['detail'];
  if (detail is! String) return null;
  final text = detail.trim();
  if (text.isEmpty || text.length > 160 || text.contains('\n')) return null;
  if (_technical.hasMatch(text)) return null;
  return text;
}

// Wording that marks a message as machine output rather than a sentence
// written for a person.
final RegExp _technical = RegExp(
  r'(exception|traceback|error:|errno|sqlalchemy|psycopg|asyncpg|jwt|jose|'
  r'pydantic|nonetype|object has no attribute|line \d+|<[a-z]+ |\{|\}|\[|\]|'
  r'\.py\b|https?://|/api/|token payload)',
  caseSensitive: false,
);

String _reasonFor(Object? error) {
  if (error is DioException) return _dioReason(error);
  if (error is SocketException || error is HttpException) {
    return 'Check your internet connection and try again.';
  }
  if (error is TimeoutException) {
    return 'The server took too long to respond. Please try again.';
  }
  if (error is PlatformException) {
    final code = error.code.toUpperCase();
    if (code.contains('PERMISSION') || code.contains('DENIED')) {
      return 'A required permission was denied. You can enable it in Settings.';
    }
    if (code.contains('UNAVAILABLE') || code.contains('SERVICE')) {
      return 'That feature is not available on this device right now.';
    }
    return 'Something went wrong on this device. Please try again.';
  }
  if (error is FormatException || error is TypeError) {
    return 'We received an unexpected response. Please try again.';
  }
  return 'Something went wrong. Please try again.';
}

String _dioReason(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'The server took too long to respond. Please try again.';
    case DioExceptionType.connectionError:
      return 'Check your internet connection and try again.';
    case DioExceptionType.badCertificate:
      return 'A secure connection could not be established. Please try again later.';
    case DioExceptionType.cancel:
      return 'The request was cancelled.';
    case DioExceptionType.badResponse:
      return _statusReason(e.response);
    case DioExceptionType.unknown:
      if (e.error is SocketException || e.error is HttpException) {
        return 'Check your internet connection and try again.';
      }
      return 'Something went wrong. Please try again.';
  }
}

String _statusReason(Response? response) {
  final status = response?.statusCode ?? 0;
  // An intentional message from the backend beats a generic one.
  final detail = safeServerDetail(response);
  if (detail != null) return detail;
  if (status == 401) return 'Your session has expired. Please sign in again.';
  if (status == 403) return "You don't have permission to do that.";
  if (status == 404) return 'That could not be found.';
  if (status == 409) return 'That already exists.';
  if (status == 429) return 'Too many attempts. Please wait a moment and try again.';
  if (status == 400 || status == 422) {
    return 'Some of the details look invalid. Please check them and try again.';
  }
  if (status >= 500) {
    return 'Something went wrong on our side. Please try again later.';
  }
  return 'Something went wrong. Please try again.';
}
