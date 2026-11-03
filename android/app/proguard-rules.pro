# Plugins called from Dart via JNI (jnigen) look up methods by name at runtime;
# R8 must not rename/strip them (caused NoSuchMethodError in SharedPreferencesApiRegistrar.getAll).
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
-keep class com.github.dart_lang.jni_flutter.** { *; }
-keep class androidx.datastore.** { *; }
# Native classes started by name (copied unmodified from the user app).
-keep class com.wnm.granthprabandhan.PdfService { *; }
-keep class com.wnm.granthprabandhan.MainActivity { *; }
-keep class com.wnm.granthprabandhan.PageSyncService { *; }
-keep class com.wnm.granthprabandhan.HlFileProvider { *; }
# Production R8 (Round-2): keep every Flutter plugin + Firebase/Google sign-in entry point, strip logs.
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keepattributes Signature,*Annotation*,InnerClasses,EnclosingMethod
-dontwarn com.google.android.play.core.**
-dontwarn org.conscrypt.**
-assumenosideeffects class android.util.Log { public static int v(...); public static int d(...); public static int i(...); }
