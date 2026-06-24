# =============================================================================
# Mesh Messenger — ProGuard / R8 rules
# =============================================================================
# Applied only to release builds (isMinifyEnabled = true in build.gradle.kts).
# Debug builds skip R8 entirely, so these rules have no effect in debug mode.

# ── PointyCastle (RSA + AES crypto) ──────────────────────────────────────────
# PointyCastle uses a string-keyed registry to look up algorithm
# implementations at runtime via Class.forName(). R8 would otherwise strip or
# rename these classes, causing "Algorithm not found" exceptions in release.
-keep class org.bouncycastle.** { *; }
-keep class org.spongycastle.** { *; }

# The Dart/Flutter bridge for pointycastle uses these JVM classes:
-keepnames class com.pointycastle.** { *; }

# ── Hive (local database) ─────────────────────────────────────────────────────
# Hive accesses box adapters and generated code via reflection in some paths.
-keep class com.hive.** { *; }
-keep @com.hive.** class * { *; }
-keepclassmembers class * {
    @com.hive.* <fields>;
}
# Hive Flutter uses dart:mirrors equivalent patterns — keep all Hive boxes.
-keep class ** extends com.hive.flutter.** { *; }

# ── Flutter Secure Storage ────────────────────────────────────────────────────
# Stores RSA key material — must not be obfuscated.
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# ── Google Nearby Connections ─────────────────────────────────────────────────
-keep class com.google.android.gms.nearby.** { *; }
-keep class com.google.android.gms.common.** { *; }
-dontwarn com.google.android.gms.**

# ── Flutter Foreground Task ───────────────────────────────────────────────────
-keep class com.pravera.flutter_foreground_task.** { *; }

# ── Flutter engine & plugin registry ─────────────────────────────────────────
# The Flutter embedding uses reflection to locate and register plugins.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# ── Mobile Scanner (QR camera) ───────────────────────────────────────────────
-keep class dev.zxing.** { *; }
-keep class com.google.zxing.** { *; }
-dontwarn com.google.zxing.**

# ── General Android safety rules ─────────────────────────────────────────────
# Preserve Parcelable implementations (used internally by Nearby Connections).
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator CREATOR;
}

# Preserve enums (used in MeshMessage type/status serialisation).
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Preserve all native method signatures.
-keepclasseswithmembernames class * {
    native <methods>;
}

# Suppress warnings for optional dependencies that may not be present.
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
