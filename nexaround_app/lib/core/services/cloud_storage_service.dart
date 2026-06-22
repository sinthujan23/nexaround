import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

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
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      drive.DriveApi.driveFileScope,
    ],
  );

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
      // 1. Force Sign Out before Signing In.
      // This is the CRITICAL line: it prevents the app from automatically using the Firebase email,
      // and forces the "Choose an Account" screen to appear every time!
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
      // Also disconnect to completely clear the cache
      try { await _googleSignIn.disconnect(); } catch (_) {}
      
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) {
        throw Exception("Google Sign-In was cancelled by the user.");
      }

      // 2. Get Authenticated Client for Google APIs
      final authClient = await _googleSignIn.authenticatedClient();
      if (authClient == null) {
        throw Exception("Failed to get authenticated client for Google APIs.");
      }

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
}
