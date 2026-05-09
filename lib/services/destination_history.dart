import 'dart:convert';

import 'package:amap_flutter_base/amap_flutter_base.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:travel_plan/services/amap_rest_client.dart';

/// 本地持久化的最近目的地（无账号、仅本机）。
class DestinationHistory {
  DestinationHistory._();

  static const _prefsKey = 'destination_history_v1';
  static const maxItems = 20;

  static String _dedupeKey(PoiSuggestion s) =>
      '${s.name}|${s.location.latitude.toStringAsFixed(5)}|${s.location.longitude.toStringAsFixed(5)}';

  static Map<String, dynamic> _toMap(PoiSuggestion s) => <String, dynamic>{
        'name': s.name,
        'address': s.address,
        'lat': s.location.latitude,
        'lng': s.location.longitude,
        if (s.adcode != null && s.adcode!.isNotEmpty) 'adcode': s.adcode,
      };

  static PoiSuggestion? _fromMap(Map<String, dynamic> m) {
    final lat = m['lat'];
    final lng = m['lng'];
    if (lat is! num || lng is! num) return null;
    return PoiSuggestion(
      name: m['name'] as String? ?? '',
      address: m['address'] as String? ?? '',
      location: LatLng(lat.toDouble(), lng.toDouble()),
      adcode: m['adcode'] as String?,
    );
  }

  static Future<List<PoiSuggestion>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return [];
      final out = <PoiSuggestion>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final s = _fromMap(Map<String, dynamic>.from(e));
        if (s != null) out.add(s);
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// 将 [s] 提到最前；与已有项按名称+坐标去重。
  static Future<void> remember(PoiSuggestion s) async {
    final p = await SharedPreferences.getInstance();
    final k = _dedupeKey(s);
    final existing = await load();
    final rest = existing.where((e) => _dedupeKey(e) != k).toList();
    final next = [s, ...rest].take(maxItems).toList();
    await p.setString(
      _prefsKey,
      json.encode(next.map(_toMap).toList()),
    );
  }

  static Future<void> remove(PoiSuggestion s) async {
    final p = await SharedPreferences.getInstance();
    final k = _dedupeKey(s);
    final existing = await load();
    final next = existing.where((e) => _dedupeKey(e) != k).toList();
    if (next.isEmpty) {
      await p.remove(_prefsKey);
    } else {
      await p.setString(
        _prefsKey,
        json.encode(next.map(_toMap).toList()),
      );
    }
  }
}
