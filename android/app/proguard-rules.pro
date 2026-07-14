# Flutter embedding & plugin glue
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugins.webviewflutter.** { *; }

# Firebase + AppCheck + Messaging
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Play Core (App Check play-integrity provider pulls this in)
-dontwarn com.google.android.play.core.**

# AppsFlyer SDK
-keep class com.appsflyer.** { *; }
-keep class com.appsflyer.internal.** { *; }
-dontwarn com.appsflyer.**

# Local notifications plugin pulls in Gson via reflection
-keep class com.google.gson.** { *; }
-keep class com.dexterous.** { *; }

# Keep native methods + Parcelable creators (R8 strips these otherwise)
-keepclasseswithmembernames class * {
    native <methods>;
}
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Strip verbose logging from release builds
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
