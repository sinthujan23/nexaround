import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';

class SocialAuthService {
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

  Future<GoogleSignInAccount?> signInWithGoogle() async {
    try {
      await _ensureInitialized();
      await _googleSignIn.signOut();
      return await _googleSignIn.authenticate();
    } catch (e) {
      rethrow;
    }
  }

  Future<AuthorizationCredentialAppleID> signInWithApple() async {
    try {
      return await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        webAuthenticationOptions: WebAuthenticationOptions(
          clientId: 'com.nexaround.nexaround_app.service',
          redirectUri: Uri.parse('https://api.nexaround.com/api/v1/auth/apple/callback'),
        ),
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _ensureInitialized();
    await _googleSignIn.signOut();
  }
}
