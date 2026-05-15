import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class SocialAuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  Future<GoogleSignInAccount?> signInWithGoogle() async {
    try {
      return await _googleSignIn.signIn();
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
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
  }
}
