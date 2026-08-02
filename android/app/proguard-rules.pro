# Flutter rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase rules
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# AndroidX / Media3 / Desugaring rules
-keep class androidx.** { *; }
-dontwarn androidx.**

# Google Play Core rules (fixes R8 missing class errors)
-dontwarn com.google.android.play.core.**
