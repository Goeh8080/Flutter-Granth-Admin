import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Google sign-in -> Firebase ID token for the panel's `POST /auth/firebase`.
/// Firebase is initialised lazily from android/app/google-services.json (injected by CI);
/// a build without it throws [GoogleLoginUnavailable] and password login still works.
class GoogleLoginUnavailable implements Exception {
  const GoogleLoginUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

class GoogleLogin {
  static bool _ready = false;

  /// OAuth web client (client_type 3) of Firebase project granth-management. Public id, not a
  /// secret. google_sign_in 7 (Credential Manager) needs it as serverClientId to mint an idToken.
  static const _webClientId =
      '386256348529-55gsprsn906i00e6726tu1gdo253kipv.apps.googleusercontent.com';

  static Future<void> _init() async {
    if (_ready) return;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      await GoogleSignIn.instance.initialize(serverClientId: _webClientId);
      _ready = true;
    } catch (e) {
      throw GoogleLoginUnavailable(
        'इस बिल्ड में Google लॉगिन सेट नहीं है / Google login is not configured in this build ($e)',
      );
    }
  }

  /// Returns a fresh Firebase ID token, or null when the user cancels.
  static Future<String?> idToken() async {
    await _init();
    final GoogleSignInAccount acc;
    try {
      acc = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw GoogleLoginUnavailable(
        'Google लॉगिन नहीं हो सका / Google sign-in failed: ${e.code.name}${e.description == null ? '' : ' (${e.description})'}',
      );
    }
    final gid = acc.authentication.idToken;
    if (gid == null) {
      throw const GoogleLoginUnavailable(
        'Google ने टोकन नहीं दिया / No Google token',
      );
    }
    final UserCredential cred;
    try {
      cred = await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(idToken: gid),
      );
    } on FirebaseAuthException catch (e) {
      throw GoogleLoginUnavailable('Firebase: ${e.code}');
    }
    return cred.user?.getIdToken(true);
  }

  static Future<void> signOut() async {
    if (!_ready) return;
    try {
      await FirebaseAuth.instance.signOut();
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }
}
