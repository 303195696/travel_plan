import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:amap_flutter_base/amap_flutter_base.dart';
import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:travel_plan/config/amap_config.dart';
import 'package:travel_plan/services/amap_rest_client.dart';
import 'package:travel_plan/services/destination_history.dart';
import 'package:travel_plan/services/geo.dart';
import 'package:travel_plan/services/route_cache.dart';
import 'package:travel_plan/services/route_planner.dart';
import 'package:travel_plan/services/travel_links.dart';

class HomeMapPage extends StatefulWidget {
  const HomeMapPage({super.key});

  @override
  State<HomeMapPage> createState() => _HomeMapPageState();
}

class _HomeMapPageState extends State<HomeMapPage> {
  final AmapRestClient _rest = AmapRestClient();
  late final RoutePlanner _planner = RoutePlanner(_rest);

  AMapController? _mapController;

  LatLng? _myLocation;
  PoiSuggestion? _destination;
  WeatherBrief? _weather;

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<PoiSuggestion> _suggestions = [];
  List<PoiSuggestion> _recentDestinations = [];

  TripPlan? _trip;
  bool _loadingRoute = false;
  bool _loadingWx = false;
  String? _error;

  Polyline? _routePolyline;

  Marker? _destMarker;

  @override
  void initState() {
    super.initState();
    _refreshMyLocation();
    _loadRecentDestinations();
  }

  Future<void> _loadRecentDestinations() async {
    final list = await DestinationHistory.load();
    if (!mounted) return;
    setState(() => _recentDestinations = list);
  }

  /// 唤起第三方 App 时写入剪贴板：名称 + 地址。
  String? _destinationClipboardText() {
    final d = _destination;
    if (d == null) return null;
    return '${d.name} ${d.address}'.trim();
  }

  Future<void> _refreshMyLocation() async {
    if (!await _ensureLocationPermission()) {
      if (mounted) {
        setState(
          () => _error = '需要定位权限。请在弹窗中允许，或到系统设置为本应用开启「位置信息」。',
        );
      }
      return;
    }

    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      if (mounted) {
        setState(() => _error = '请打开系统「定位 / GPS」开关后再试。');
      }
      return;
    }

    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        try {
          await Geolocator.requestTemporaryFullAccuracy(
            purposeKey: 'TravelPlanPreciseLocation',
          );
        } catch (_) {}
      }
      final p = await _getCurrentPositionWithFallback();
      final here = LatLng(p.latitude, p.longitude);
      if (!mounted) return;
      setState(() {
        _myLocation = here;
        _error = null;
      });
      _mapController?.moveCamera(CameraUpdate.newLatLngZoom(here, 14));
    } catch (e) {
      if (mounted) {
        setState(() => _error = '定位失败：$e');
      }
    }
  }

  /// Android：先中等精度；失败则强制 LocationManager（无 GMS/融合定位异常时更稳）。iOS：中等精度即可。
  Future<Position> _getCurrentPositionWithFallback() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 22),
          ),
        );
      } catch (_) {
        return Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.low,
            forceLocationManager: true,
            timeLimit: const Duration(seconds: 28),
          ),
        );
      }
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: AppleSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 24),
            activityType: ActivityType.otherNavigation,
            pauseLocationUpdatesAutomatically: false,
          ),
        );
      } catch (_) {
        return Geolocator.getCurrentPosition(
          locationSettings: AppleSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 28),
            activityType: ActivityType.other,
          ),
        );
      }
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 22),
      ),
    );
  }

  Future<bool> _ensureLocationPermission() async {
    var gp = await Geolocator.checkPermission();
    if (gp == LocationPermission.denied) {
      gp = await Geolocator.requestPermission();
    }
    if (gp == LocationPermission.deniedForever) {
      await openAppSettings();
      return false;
    }
    if (gp == LocationPermission.denied) {
      return false;
    }
    return gp == LocationPermission.always || gp == LocationPermission.whileInUse;
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (!AmapConfig.keysConfigured) return;
    _debounce = Timer(const Duration(milliseconds: 380), () async {
      try {
        final list = await _rest.inputTips(q);
        if (!mounted) return;
        setState(() {
          _suggestions = list;
          _error = null;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _error = e.toString());
      }
    });
  }

  Future<void> _pickSuggestion(PoiSuggestion s) async {
    setState(() {
      _destination = s;
      _suggestions = [];
      _searchCtrl.text = s.name;
      _trip = null;
      _routePolyline = null;
      _weather = null;
      _destMarker = Marker(
        position: s.location,
        infoWindow: InfoWindow(title: s.name, snippet: s.address),
      );
    });
    await DestinationHistory.remember(s);
    await _loadRecentDestinations();
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    _mapController?.moveCamera(CameraUpdate.newLatLngZoom(s.location, 13));
    await _refreshWeatherForDestination();
  }

  Future<void> _refreshWeatherForDestination() async {
    final d = _destination;
    if (d == null || !AmapConfig.keysConfigured) return;

    setState(() => _loadingWx = true);
    try {
      String? adcode = d.adcode;
      adcode ??= await _rest.regeoAdcode(d.location);
      if (adcode == null || adcode.isEmpty) return;

      final cached = await RouteCache.getWeatherPayload(adcode);
      if (cached != null) {
        final m = json.decode(cached) as Map<String, dynamic>;
        final w = WeatherBrief(
          city: m['city'] as String? ?? '',
          weather: m['weather'] as String? ?? '',
          temperature: m['temperature'] as String? ?? '',
          windDirection: m['windDirection'] as String? ?? '',
          windPower: m['windPower'] as String? ?? '',
          humidity: m['humidity'] as String? ?? '',
          reportTime: m['reportTime'] as String? ?? '',
        );
        if (mounted) setState(() => _weather = w);
        return;
      }
      final live = await _rest.weatherLive(adcode);
      if (live != null) {
        await RouteCache.setWeatherPayload(
          adcode,
          json.encode(<String, String>{
            'city': live.city,
            'weather': live.weather,
            'temperature': live.temperature,
            'windDirection': live.windDirection,
            'windPower': live.windPower,
            'humidity': live.humidity,
            'reportTime': live.reportTime,
          }),
        );
        if (mounted) setState(() => _weather = live);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '天气/逆地理：$e');
      }
    } finally {
      if (mounted) setState(() => _loadingWx = false);
    }
  }

  Future<void> _planRoute() async {
    if (!AmapConfig.keysConfigured) {
      setState(
        () => _error = '请配置：① Web 服务 Key（路线/搜索/天气）② 本机平台地图 Key（Android 需 androidMapKey）。见 lib/config/amap_config.dart 顶部说明。',
      );
      return;
    }
    final from = _myLocation;
    final to = _destination;
    if (from == null) {
      setState(() => _error = '正在获取当前位置，请稍后再试或检查定位权限');
      _refreshMyLocation();
      return;
    }
    if (to == null) {
      setState(() => _error = '请先搜索并选择目的地');
      return;
    }
    setState(() {
      _loadingRoute = true;
      _error = null;
    });
    try {
      final trip = await _planner.plan(from, to.location);
      final pts = _decimate(trip.primary.points, 500);
      setState(() {
        _trip = trip;
        _routePolyline = Polyline(
          points: pts,
          color: const Color(0xFF1976D2),
          width: 8,
        );
      });
      await _fitCameraToRoute(from, to.location, pts);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  Future<void> _fitCameraToRoute(LatLng from, LatLng to, List<LatLng> pts) async {
    if (_mapController == null) return;
    if (pts.isEmpty) {
      await _mapController!.moveCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(
              math.min(from.latitude, to.latitude) - 0.01,
              math.min(from.longitude, to.longitude) - 0.01,
            ),
            northeast: LatLng(
              math.max(from.latitude, to.latitude) + 0.01,
              math.max(from.longitude, to.longitude) + 0.01,
            ),
          ),
          72,
        ),
      );
      return;
    }
    var minLat = pts.first.latitude;
    var maxLat = pts.first.latitude;
    var minLng = pts.first.longitude;
    var maxLng = pts.first.longitude;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    await _mapController!.moveCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  List<LatLng> _decimate(List<LatLng> pts, int maxCount) {
    if (pts.length <= maxCount) return pts;
    final step = pts.length / maxCount;
    final out = <LatLng>[];
    var i = 0.0;
    while (i < pts.length) {
      out.add(pts[i.floor()]);
      i += step;
    }
    if (out.last != pts.last) out.add(pts.last);
    return out;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _rest.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final destLabel = _destination == null
        ? '未选择'
        : '${_destination!.name}（${_destination!.address}）';

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: AMapWidget(
              apiKey: AmapConfig.mapApiKey,
              privacyStatement: AmapConfig.privacyStatement,
              initialCameraPosition: const CameraPosition(
                target: LatLng(39.909187, 116.397451),
                zoom: 11,
              ),
              myLocationStyleOptions: MyLocationStyleOptions(
                true,
                circleFillColor: Colors.blue.shade100,
                circleStrokeColor: Colors.blue,
                circleStrokeWidth: 1,
              ),
              markers: _destMarker == null ? {} : {_destMarker!},
              polylines: _routePolyline == null ? {} : {_routePolyline!},
              onMapCreated: (c) {
                _mapController = c;
                if (_myLocation != null) {
                  c.moveCamera(CameraUpdate.newLatLngZoom(_myLocation!, 14));
                }
              },
            ),
          ),
          if (!AmapConfig.keysConfigured)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 12,
              right: 12,
              child: Material(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Text(
                    '请配置高德 Key：① Web 服务 Key（_webLocal 或 AMAP_WEB_KEY）—路线/搜索/天气必填；'
                    '② 当前平台地图 Key（Android：_androidLocal / AMAP_ANDROID_KEY）。'
                    '仅填地图 Key、不填 Web Key 会在规划路线时报错。',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ),
          DraggableScrollableSheet(
            initialChildSize: 0.38,
            minChildSize: 0.22,
            maxChildSize: 0.88,
            builder: (ctx, scroll) {
              return Material(
                elevation: 12,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                color: Theme.of(ctx).colorScheme.surface,
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text('目的地', style: Theme.of(ctx).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: '输入景点、城市或地址',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: () => _onSearchChanged(_searchCtrl.text),
                        ),
                      ),
                      onChanged: (q) {
                        setState(() {});
                        _onSearchChanged(q);
                      },
                    ),
                    if (_searchCtrl.text.trim().isEmpty &&
                        _recentDestinations.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('最近', style: Theme.of(ctx).textTheme.titleSmall),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 200,
                        child: ListView.separated(
                          primary: false,
                          physics: const ClampingScrollPhysics(),
                          itemCount: _recentDestinations.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final s = _recentDestinations[i];
                            return ListTile(
                              dense: true,
                              title: Text(s.name),
                              subtitle: Text(
                                s.address.isEmpty ? '${s.location}' : s.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.close, size: 20),
                                tooltip: '从最近中移除',
                                onPressed: () async {
                                  await DestinationHistory.remove(s);
                                  await _loadRecentDestinations();
                                },
                              ),
                              onTap: () => _pickSuggestion(s),
                            );
                          },
                        ),
                      ),
                    ],
                    if (_suggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _suggestions.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final s = _suggestions[i];
                            return ListTile(
                              dense: true,
                              title: Text(s.name),
                              subtitle: Text(
                                s.address.isEmpty ? '${s.location}' : s.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _pickSuggestion(s),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _loadingRoute ? null : _planRoute,
                      icon: _loadingRoute
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.route),
                      label: Text(_loadingRoute ? '规划中…' : '规划路线'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                    ],
                    const Divider(height: 28),
                    Text('当前位置', style: Theme.of(ctx).textTheme.titleSmall),
                    Text(_myLocation == null ? '定位中…' : restLngLat(_myLocation!)),
                    const SizedBox(height: 8),
                    Text('已选目的地', style: Theme.of(ctx).textTheme.titleSmall),
                    Text(destLabel, maxLines: 3, overflow: TextOverflow.ellipsis),
                    if (_trip != null) ...[
                      const Divider(height: 24),
                      _routeSummary(ctx),
                    ],
                    if (_loadingWx) const LinearProgressIndicator(),
                    if (_weather != null) ...[
                      const SizedBox(height: 12),
                      Text('目的地天气', style: Theme.of(ctx).textTheme.titleSmall),
                      Text(
                        '${_weather!.city} ${_weather!.weather} ${_weather!.temperature}℃ '
                        '湿度${_weather!.humidity} ${_weather!.windDirection}${_weather!.windPower}级 '
                        '（${_weather!.reportTime}）',
                      ),
                    ],
                    if (_trip?.showThirdPartyLinks == true) ...[
                      const Divider(height: 24),
                      Text('距离较远，可跳转查看方案/费用', style: Theme.of(ctx).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: _myLocation != null && _destination != null
                                ? () => TravelLinks.openDidi(
                                      _myLocation!,
                                      _destination!.location,
                                      clipboardText: _destinationClipboardText(),
                                    )
                                : null,
                            child: const Text('滴滴出行'),
                          ),
                          OutlinedButton(
                            onPressed: () => TravelLinks.openRail12306(
                              clipboardText: _destinationClipboardText(),
                            ),
                            child: const Text('12306'),
                          ),
                          OutlinedButton(
                            onPressed: _destination == null
                                ? null
                                : () => TravelLinks.openMeituanSearch(
                                      _destination!.name,
                                      clipboardText: _destinationClipboardText(),
                                    ),
                            child: const Text('美团'),
                          ),
                        ],
                      ),
                    ],
                    const Divider(height: 24),
                    Text('更多路线', style: Theme.of(ctx).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: _destination == null
                          ? null
                          : () => TravelLinks.openAmapRoute(
                                _myLocation,
                                _destination!.location,
                                _destination!.name,
                                clipboardText: _destinationClipboardText(),
                              ),
                      child: const Text('去高德 App 查看路线规划'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _routeSummary(BuildContext ctx) {
    final trip = _trip!;
    final p = trip.primary;
    final dur = Duration(seconds: p.durationSeconds);
    final arrival = DateTime.now().add(dur);
    final timeStr = DateFormat('HH:mm').format(arrival);

    String fmtDur(Duration d) {
      if (d.inHours >= 1) {
        return '${d.inHours}小时${d.inMinutes.remainder(60)}分';
      }
      return '${d.inMinutes}分钟';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('推荐：${p.mode}', style: Theme.of(ctx).textTheme.titleMedium),
        Text('约 ${(p.distanceMeters / 1000).toStringAsFixed(1)} km · 预计 ${fmtDur(dur)}'),
        Text('预计到达时间约 $timeStr（按当前路况估算）'),
        if (trip.secondary != null) ...[
          const SizedBox(height: 10),
          Text(
            '备选（${trip.secondary!.mode}）：'
            '${(trip.secondary!.distanceMeters / 1000).toStringAsFixed(1)} km · '
            '${fmtDur(Duration(seconds: trip.secondary!.durationSeconds))}',
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
