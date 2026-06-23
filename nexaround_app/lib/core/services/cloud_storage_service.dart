import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';

enum CloudProvider {
  dropbox,
  googleDrive,
}

class CloudStorageService {
  final FlutterAppAuth appAuth = const FlutterAppAuth();
  
  // Paste your Dropbox "Generated access token" here to bypass the OAuth redirect if it gets stuck.
  // Note: Dropbox generated access tokens expire after 4 hours. Leave empty/null to use regular OAuth.
  final String clientId = '4f169mxmupvg6q1';
  final String redirectUrl = 'nexaround://oauth2redirect';
  final String? dropboxAccessToken = '';

  // We configure Google Sign In to ask for the Drive permission.
  GoogleSignIn get _googleSignIn => GoogleSignIn.instance;

  bool _initialized = false;
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await _googleSignIn.initialize(
        clientId: ApiConstants.googleClientId.isNotEmpty ? ApiConstants.googleClientId : null,
        serverClientId: ApiConstants.googleServerClientId.isNotEmpty ? ApiConstants.googleServerClientId : null,
      );
      _initialized = true;
    }
  }

  Future<String?> connectAndUpload(CloudProvider provider, List<String> localImagePaths) async {
    if (provider == CloudProvider.dropbox) {
      return _uploadToDropbox(localImagePaths);
    } else if (provider == CloudProvider.googleDrive) {
      return _uploadToGoogleDrive(localImagePaths);
    }
    return null;
  }

  Future<String?> _uploadToGoogleDrive(List<String> localImagePaths) async {
    try {
      await _ensureInitialized();

      // 1. Force Sign Out before Signing In.
      // This is the CRITICAL line: it prevents the app from automatically using the Firebase email,
      // and forces the "Choose an Account" screen to appear every time!
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
      
      // Also disconnect to completely clear the cache
      try { await _googleSignIn.disconnect(); } catch (_) {}
      
      final GoogleSignInAccount account = await _googleSignIn.authenticate();

      // 2. Get Authenticated Client for Google APIs
      final scopes = [drive.DriveApi.driveFileScope];
      final clientAuth = await account.authorizationClient.authorizeScopes(scopes);
      final authClient = clientAuth.authClient(scopes: scopes);

      final driveApi = drive.DriveApi(authClient);

      // 3. Create a Folder
      final folderName = 'Trip_${DateTime.now().millisecondsSinceEpoch}';
      final folder = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder';

      final createdFolder = await driveApi.files.create(folder);
      final folderId = createdFolder.id;

      if (folderId == null) {
        throw Exception("Failed to create Google Drive folder");
      }

      // 4. Upload Images
      for (final path in localImagePaths) {
        final fileToUpload = File(path);
        final fileName = path.split('/').last;

        final driveFile = drive.File()
          ..name = fileName
          ..parents = [folderId];

        await driveApi.files.create(
          driveFile,
          uploadMedia: drive.Media(fileToUpload.openRead(), fileToUpload.lengthSync()),
        );
      }

      // 5. Create Web Shareable Link
      final permission = drive.Permission()
        ..type = 'anyone'
        ..role = 'reader';

      await driveApi.permissions.create(permission, folderId);
      final updatedFolder = await driveApi.files.get(folderId, $fields: 'webViewLink');

      return (updatedFolder as drive.File).webViewLink;

    } catch (e) {
      print("Google Drive Integration Error: $e");
      rethrow;
    }
  }

  Future<String?> _uploadToDropbox(List<String> localImagePaths) async {
    try {
      String token;
      
      if (dropboxAccessToken != null && dropboxAccessToken!.isNotEmpty) {
        token = dropboxAccessToken!;
      } else {
        // 1. Authenticate using PKCE flow
        final AuthorizationTokenResponse? result = await appAuth.authorizeAndExchangeCode(
          AuthorizationTokenRequest(
            clientId,
            redirectUrl,
            serviceConfiguration: const AuthorizationServiceConfiguration(
              authorizationEndpoint: 'https://www.dropbox.com/oauth2/authorize',
              tokenEndpoint: 'https://api.dropboxapi.com/oauth2/token',
            ),
            // With PKCE, code verifier is generated automatically.
          ),
        );

        if (result == null || result.accessToken == null) {
          throw Exception("Failed to login to Dropbox");
        }

        token = result.accessToken!;
      }

      final folderName = '/Trip_${DateTime.now().millisecondsSinceEpoch}';

      // 2. Upload Files
      for (final path in localImagePaths) {
        final file = File(path);
        final fileName = path.split('/').last;
        
        final arg = jsonEncode({
          "path": "$folderName/$fileName",
          "mode": "add",
          "autorename": true,
          "mute": false,
          "strict_conflict": false
        });

        final request = http.Request('POST', Uri.parse('https://content.dropboxapi.com/2/files/upload'));
        request.headers.addAll({
          'Authorization': 'Bearer $token',
          'Dropbox-API-Arg': arg,
          'Content-Type': 'application/octet-stream',
        });
        request.bodyBytes = await file.readAsBytes();
        
        final response = await request.send();
        if (response.statusCode != 200) {
          final resBody = await response.stream.bytesToString();
          print("Dropbox upload failed: $resBody");
        }
      }

      // 3. Create Shared Link for the folder
      final shareRes = await http.post(
        Uri.parse('https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "path": folderName,
          "settings": {
            "requested_visibility": "public"
          }
        }),
      );

      if (shareRes.statusCode == 200) {
        final data = jsonDecode(shareRes.body);
        return data['url'] as String;
      } else {
        print("Dropbox share failed: ${shareRes.body}");
        return 'https://www.dropbox.com/home$folderName'; // Fallback to personal home link
      }
    } catch (e) {
      print("Dropbox Integration Error: $e");
      rethrow;
    }
  }

  Future<void> deleteFromCloud(CloudProvider provider, String folderUrl) async {
    if (provider == CloudProvider.googleDrive) {
      await _deleteFromGoogleDrive(folderUrl);
    } else if (provider == CloudProvider.dropbox) {
      await _deleteFromDropbox(folderUrl);
    }
  }

  Future<void> _deleteFromGoogleDrive(String webViewLink) async {
    try {
      final regExp = RegExp(r'folders/([a-zA-Z0-9_-]+)|d/([a-zA-Z0-9_-]+)');
      final match = regExp.firstMatch(webViewLink);
      String? folderId;
      if (match != null) {
        folderId = match.group(1) ?? match.group(2);
      }
      
      if (folderId == null || folderId.isEmpty) {
        throw Exception("Could not extract Google Drive folder ID from link");
      }

      await _ensureInitialized();
      GoogleSignInAccount? account;
      try {
        account = await _googleSignIn.authenticate();
      } catch (e) {
        throw Exception("Failed to authenticate with Google: $e");
      }
      if (account == null) throw Exception("User not signed in to Google.");

      final scopes = [drive.DriveApi.driveFileScope];
      final clientAuth = await account.authorizationClient.authorizeScopes(scopes);
      final authClient = clientAuth.authClient(scopes: scopes);

      final driveApi = drive.DriveApi(authClient);
      await driveApi.files.delete(folderId);

    } catch (e) {
      print("Google Drive Deletion Error: $e");
      rethrow;
    }
  }

  Future<void> _deleteFromDropbox(String webUrl) async {
    // Note: Dropbox deletion using only a shared web link is not natively supported
    // without the internal file path. Since the backend schema doesn't store the path,
    // we bypass cloud deletion for Dropbox here. The post will still be deleted in the app.
    print("Dropbox cloud deletion skipped: path unavailable from shared link.");
  }
}
