import 'package:amap_flutter_base/amap_flutter_base.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Android：`android/app/build.gradle.kts` 会从本文件 `_androidLocal` 解析并写入 Manifest
/// `com.amap.api.v2.apikey`，与下方常量保持一致即可。
///
/// iOS：在 Xcode 中确认 **Bundle Identifier** 与高德控制台 iOS 安全码（Bundle ID + 证书）一致；
/// Key 通过 Dart `mapApiKey` 传入，原生会在首帧地图创建时调用 `AMapServices`。
///
/// 需要 **两类** Key（在高德控制台分别创建、勾选对应服务）：
/// 1. **Android 平台 Key / iOS 平台 Key**：给原生地图 SDK（`mapApiKey`）。
/// 2. **Web 服务 Key**：给路线规划、inputtips、天气等 **HTTPS REST**（`webServiceKey`），与平台 Key 不是同一个字段，必须单独配置。
///
/// 填入方式二选一：改下面 `_webLocal` / `_androidLocal` / `_iosLocal`，或运行带参数，例如：
/// `flutter run --dart-define=AMAP_WEB_KEY=你的WebKey --dart-define=AMAP_ANDROID_KEY=你的AndroidKey`
/// （iOS 调试再加 `--dart-define=AMAP_IOS_KEY=...`）
///
class AmapConfig {
  AmapConfig._();

  static const String _iosFromEnv = String.fromEnvironment('AMAP_IOS_KEY');
  static const String _androidFromEnv = String.fromEnvironment('AMAP_ANDROID_KEY');
  static const String _webFromEnv = String.fromEnvironment('AMAP_WEB_KEY');

  /// 若未使用 dart-define，请修改下面常量为你的 Key（按调试平台填写即可）。
  static const String _iosLocal = 'bcdc712ea43f46ad4cd3223e7cb30e9f';
  static const String _androidLocal = '6ab419445f470d79a82a3af7e4a1e864';
  static const String _webLocal = '8fc0796f26fde5ae76df9b1629ed1f03';

  static String get iosMapKey =>
      (_iosFromEnv.isNotEmpty ? _iosFromEnv : _iosLocal).trim();

  static String get androidMapKey =>
      (_androidFromEnv.isNotEmpty ? _androidFromEnv : _androidLocal).trim();

  static String get webServiceKey =>
      (_webFromEnv.isNotEmpty ? _webFromEnv : _webLocal).trim();

  static AMapApiKey get mapApiKey =>
      AMapApiKey(iosKey: iosMapKey, androidKey: androidMapKey);

  static const AMapPrivacyStatement privacyStatement = AMapPrivacyStatement(
    hasContains: true,
    hasShow: true,
    hasAgree: true,
  );

  /// Web Key 必填；地图 SDK 至少填当前运行平台对应的 Key（Android 调试填 Android 即可）。
  static bool get keysConfigured {
    if (webServiceKey.isEmpty) return false;
    if (kIsWeb) return false;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return iosMapKey.isNotEmpty;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return androidMapKey.isNotEmpty;
    }
    return iosMapKey.isNotEmpty || androidMapKey.isNotEmpty;
  }
}
