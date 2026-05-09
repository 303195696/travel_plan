import 'dart:convert';

import 'package:amap_flutter_base/amap_flutter_base.dart';
import 'package:http/http.dart' as http;
import 'package:travel_plan/config/amap_config.dart';
import 'package:travel_plan/services/geo.dart';

class PoiSuggestion {
  PoiSuggestion({
    required this.name,
    required this.address,
    required this.location,
    this.adcode,
  });

  final String name;
  final String address;
  final LatLng location;
  final String? adcode;
}

class RoutePlanResult {
  RoutePlanResult({
    required this.mode,
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.rawTip,
  });

  final String mode;
  final List<LatLng> points;
  final int distanceMeters;
  final int durationSeconds;
  final String? rawTip;
}

/// 高德 Web 接口返回 status != 1 时抛出，便于界面展示 `info` / `infocode`。
class AmapRestException implements Exception {
  AmapRestException(this.api, this.message, {this.infocode});

  final String api;
  final String message;
  final String? infocode;

  @override
  String toString() => '高德$api: $message${infocode != null ? ' (infocode=$infocode)' : ''}';
}

class AmapRestClient {
  AmapRestClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  void _throwIfAmapError(String apiName, Map<String, dynamic> map) {
    if (map['status']?.toString() == '1') return;
    final info = map['info']?.toString() ?? '未知错误';
    final code = map['infocode']?.toString();
    throw AmapRestException(apiName, info, infocode: code);
  }

  Uri _u(String path, Map<String, String> q) {
    final m = Map<String, String>.from(q);
    m['key'] = AmapConfig.webServiceKey;
    return Uri.https('restapi.amap.com', path, m);
  }

  Future<List<PoiSuggestion>> inputTips(String keywords) async {
    if (keywords.trim().isEmpty) return [];
    final uri = _u('/v3/assistant/inputtips', {'keywords': keywords.trim()});
    final res = await _http.get(uri);
    if (res.statusCode != 200) {
      throw AmapRestException('inputtips', 'HTTP ${res.statusCode}');
    }
    final map = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    _throwIfAmapError('inputtips', map);
    final tips = map['tips'];
    if (tips is! List) return [];
    final list = <PoiSuggestion>[];
    for (final t in tips) {
      if (t is! Map) continue;
      final loc = t['location']?.toString();
      if (loc == null || loc.isEmpty) continue;
      final parts = loc.split(',');
      if (parts.length < 2) continue;
      final lng = double.tryParse(parts[0]);
      final lat = double.tryParse(parts[1]);
      if (lng == null || lat == null) continue;
      list.add(
        PoiSuggestion(
          name: t['name']?.toString() ?? '',
          address: t['address']?.toString() ?? '',
          location: LatLng(lat, lng),
          adcode: t['adcode']?.toString(),
        ),
      );
    }
    return list;
  }

  Future<RoutePlanResult?> driving(LatLng origin, LatLng dest) async {
    final uri = _u('/v3/direction/driving', {
      'origin': restLngLat(origin),
      'destination': restLngLat(dest),
      'extensions': 'base',
    });
    final res = await _http.get(uri);
    if (res.statusCode != 200) {
      throw AmapRestException('驾车规划', 'HTTP ${res.statusCode}');
    }
    return _parseRoute(res.bodyBytes, '驾车', _mergeDrivingPolylines);
  }

  Future<RoutePlanResult?> bicycling(LatLng origin, LatLng dest) async {
    final uri = _u('/v5/direction/bicycling', {
      'origin': restLngLat(origin),
      'destination': restLngLat(dest),
      'show_fields': 'polyline',
    });
    final res = await _http.get(uri);
    if (res.statusCode != 200) {
      throw AmapRestException('骑行规划', 'HTTP ${res.statusCode}');
    }
    final parsed = _parseRoute(res.bodyBytes, '骑行', _mergeDrivingPolylines);
    if (parsed != null) return parsed;
    return _bicyclingV4Fallback(origin, dest);
  }

  Future<RoutePlanResult?> _bicyclingV4Fallback(LatLng origin, LatLng dest) async {
    final uri = _u('/v4/direction/bicycling', {
      'origin': restLngLat(origin),
      'destination': restLngLat(dest),
    });
    final res = await _http.get(uri);
    if (res.statusCode != 200) {
      throw AmapRestException('骑行规划(v4)', 'HTTP ${res.statusCode}');
    }
    final map = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final err = map['errcode'];
    if (err != null && err != 0) {
      final msg = map['errmsg']?.toString() ?? 'errcode=$err';
      throw AmapRestException('骑行规划(v4)', msg);
    }
    final data = map['data'];
    if (data is! Map<String, dynamic>) return null;
    final pathsRaw = data['paths'];
    Map<String, dynamic>? routeObj;
    if (pathsRaw is List && pathsRaw.isNotEmpty && pathsRaw.first is Map) {
      routeObj = Map<String, dynamic>.from(pathsRaw.first as Map);
    } else if (pathsRaw is Map<String, dynamic>) {
      routeObj = pathsRaw;
    }
    if (routeObj == null) return null;
    final dist = int.tryParse(routeObj['distance']?.toString() ?? '') ?? 0;
    final dur = int.tryParse(routeObj['duration']?.toString() ?? '') ?? 0;
    final pts = _mergeDrivingPolylines(routeObj);
    if (pts.isEmpty) return null;
    return RoutePlanResult(
      mode: '骑行',
      points: pts,
      distanceMeters: dist,
      durationSeconds: dur,
      rawTip: map['errmsg']?.toString(),
    );
  }

  RoutePlanResult? _parseRoute(
    List<int> bytes,
    String mode,
    List<LatLng> Function(Map<String, dynamic> route) pickPoints,
  ) {
    final map = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    _throwIfAmapError('$mode规划', map);
    Map<String, dynamic>? routeObj;
    if (map['route'] is Map<String, dynamic>) {
      final paths = (map['route'] as Map)['paths'];
      if (paths is List && paths.isNotEmpty && paths.first is Map) {
        routeObj = Map<String, dynamic>.from(paths.first as Map);
      } else if (paths is Map<String, dynamic>) {
        routeObj = paths;
      }
    }
    if (routeObj == null) return null;
    final dist = int.tryParse(routeObj['distance']?.toString() ?? '') ?? 0;
    final dur = int.tryParse(routeObj['duration']?.toString() ?? '') ?? 0;
    final pts = pickPoints(routeObj);
    if (pts.isEmpty) {
      throw AmapRestException('$mode规划', '路线坐标为空（检查 Key 是否开通路径规划权限）');
    }
    return RoutePlanResult(
      mode: mode,
      points: pts,
      distanceMeters: dist,
      durationSeconds: dur,
      rawTip: map['info']?.toString(),
    );
  }

  List<LatLng> _mergeDrivingPolylines(Map<String, dynamic> route) {
    final steps = route['steps'];
    if (steps is! List) return [];
    final buf = <LatLng>[];
    for (final s in steps) {
      if (s is! Map) continue;
      final pl = s['polyline']?.toString();
      if (pl == null) continue;
      buf.addAll(decodeAmapPolyline(pl));
    }
    return buf;
  }

  /// [city] 为城市名或 adcode，与 inputtips 一致时可提高准确度。
  Future<String?> regeoAdcode(LatLng p) async {
    final uri = _u('/v3/geocode/regeo', {
      'location': restLngLat(p),
      'extensions': 'base',
    });
    final res = await _http.get(uri);
    if (res.statusCode != 200) {
      throw AmapRestException('逆地理', 'HTTP ${res.statusCode}');
    }
    final map = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    _throwIfAmapError('逆地理', map);
    final re = map['regeocode'];
    if (re is! Map) return null;
    final ac = re['addressComponent'];
    if (ac is! Map) return null;
    return ac['adcode']?.toString();
  }

  Future<WeatherBrief?> weatherLive(String cityAdcode) async {
    final uri = _u('/v3/weather/weatherInfo', {
      'city': cityAdcode,
      'extensions': 'base',
    });
    final res = await _http.get(uri);
    if (res.statusCode != 200) {
      throw AmapRestException('天气', 'HTTP ${res.statusCode}');
    }
    final map = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    _throwIfAmapError('天气', map);
    final lives = map['lives'];
    if (lives is! List || lives.isEmpty) return null;
    final w = lives.first;
    if (w is! Map) return null;
    return WeatherBrief(
      city: w['city']?.toString() ?? '',
      weather: w['weather']?.toString() ?? '',
      temperature: w['temperature']?.toString() ?? '',
      windDirection: w['wind_direction']?.toString() ?? '',
      windPower: w['wind_power']?.toString() ?? '',
      humidity: w['humidity']?.toString() ?? '',
      reportTime: w['report_time']?.toString() ?? '',
    );
  }

  void close() {
    _http.close();
  }
}

class WeatherBrief {
  WeatherBrief({
    required this.city,
    required this.weather,
    required this.temperature,
    required this.windDirection,
    required this.windPower,
    required this.humidity,
    required this.reportTime,
  });

  final String city;
  final String weather;
  final String temperature;
  final String windDirection;
  final String windPower;
  final String humidity;
  final String reportTime;
}
