import 'dart:math' as math;

import 'package:amap_flutter_base/amap_flutter_base.dart';

double haversineMeters(LatLng a, LatLng b) {
  const r = 6371000.0;
  final p1 = a.latitude * math.pi / 180;
  final p2 = b.latitude * math.pi / 180;
  final dp = (b.latitude - a.latitude) * math.pi / 180;
  final dl = (b.longitude - a.longitude) * math.pi / 180;
  final x = math.sin(dp / 2) * math.sin(dp / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(x)));
}

/// 高德 REST 路径坐标串：经度,纬度;经度,纬度
List<LatLng> decodeAmapPolyline(String polyline) {
  if (polyline.isEmpty) return [];
  final out = <LatLng>[];
  for (final seg in polyline.split(';')) {
    final parts = seg.split(',');
    if (parts.length >= 2) {
      final lng = double.tryParse(parts[0].trim());
      final lat = double.tryParse(parts[1].trim());
      if (lng != null && lat != null) {
        out.add(LatLng(lat, lng));
      }
    }
  }
  return out;
}

String restLngLat(LatLng p) => '${p.longitude},${p.latitude}';
