# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.editing.** { *; }

# Play Core 是 Flutter 用于动态特性模块 (deferred components) 的可选依赖，
# 本项目没用到，R8 看到引用会抓狂，全部忽略。
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# just_audio / ExoPlayer
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**
-keep class com.ryanheise.just_audio.** { *; }
-dontwarn com.ryanheise.just_audio.**

# audio_service / just_audio_background
-keep class com.ryanheise.audioservice.** { *; }
-dontwarn com.ryanheise.audioservice.**

# OkHttp / Okio（ExoPlayer 间接依赖）
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.conscrypt.**

# Kotlin reflection
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**

# 保留 JSON 解析涉及的反射类（如有 Gson/Moshi 后续再细化）
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
