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

  static Future<void> _init() async {
    if (_ready) return;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      await GoogleSignIn.instance.initialize();
      _ready = true;
    } catch (e) {
      throw const GoogleLoginUnavailable(
        'इस बिल्ड में Google लॉगिन सेट नहीं है / Google login is not configured in this build',
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
      rethrow;
    }
    final gid = acc.authentication.idToken;
    if (gid == null) {
      throw const GoogleLoginUnavailable(
        'Google ने टोकन नहीं दिया / No Google token',
      );
    }
    final cred = await FirebaseAuth.instance.signInWithCredential(
      GoogleAuthProvider.credential(idToken: gid),
    );
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
