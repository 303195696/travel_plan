import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 简单 TTL 缓存（路线与天气），无用户体系。
class RouteCache {
  RouteCache._();
  static const _prefixRoute = 'cache_route_v1_';
  static const _prefixWeather = 'cache_wx_v1_';
  static const routeTtl = Duration(minutes: 30);
  static const weatherTtl = Duration(minutes: 45);

  static String _routeKey(String k) => '$_prefixRoute$k';
  static String _wxKey(String adcode) => '$_prefixWeather$adcode';

  static Future<String?> getJson(String logicalKey) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_routeKey(logicalKey));
    if (raw == null) return null;
    try {
      final m = json.decode(raw) as Map<String, dynamic>;
      final exp = DateTime.tryParse(m['exp'] as String? ?? '');
      if (exp == null || DateTime.now().isAfter(exp)) {
        await p.remove(_routeKey(logicalKey));
        return null;
      }
      return m['payload'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setJson(
    String logicalKey,
    String payloadJson, {
    Duration ttl = routeTtl,
  }) async {
    final p = await SharedPreferences.getInstance();
    final exp = DateTime.now().add(ttl).toIso8601String();
    await p.setString(
      _routeKey(logicalKey),
      json.encode(<String, dynamic>{'exp': exp, 'payload': payloadJson}),
    );
  }

  static Future<String?> getWeatherPayload(String adcode) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_wxKey(adcode));
    if (raw == null) return null;
    try {
      final m = json.decode(raw) as Map<String, dynamic>;
      final exp = DateTime.tryParse(m['exp'] as String? ?? '');
      if (exp == null || DateTime.now().isAfter(exp)) {
        await p.remove(_wxKey(adcode));
        return null;
      }
      return m['payload'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setWeatherPayload(String adcode, String payloadJson) async {
    final p = await SharedPreferences.getInstance();
    final exp = DateTime.now().add(weatherTtl).toIso8601String();
    await p.setString(
      _wxKey(adcode),
      json.encode(<String, dynamic>{'exp': exp, 'payload': payloadJson}),
    );
  }
}
