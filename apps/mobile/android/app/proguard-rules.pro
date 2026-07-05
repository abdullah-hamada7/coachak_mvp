# Keep ML Kit classes
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
-keep class com.google.android.gms.vision.** { *; }
-dontwarn com.google.mlkit.**

# Keep Hive
-keep class org.apache.hive.** { *; }
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }
-keepclassmembers class * extends org.apache.hive.** { *; }

# Keep secure storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Keep Flutter / plugin registrants
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Keep camera
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

# Keep permission handler
-keep class com.baseflow.permissionhandler.** { *; }

# Keep image picker
-keep class io.flutter.plugins.imagepicker.** { *; }

# Keep model classes used via reflection
-keepclassmembers class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-keepattributes Signature
-keepattributes *Annotation*
