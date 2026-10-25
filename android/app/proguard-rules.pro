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
