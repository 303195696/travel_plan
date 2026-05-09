import 'package:amap_flutter_base/amap_flutter_base.dart';
import 'package:travel_plan/services/amap_rest_client.dart';
import 'package:travel_plan/services/geo.dart';

class TripPlan {
  TripPlan({
    required this.straightMeters,
    required this.primary,
    this.secondary,
    required this.showThirdPartyLinks,
  });

  final double straightMeters;
  final RoutePlanResult primary;
  final RoutePlanResult? secondary;
  final bool showThirdPartyLinks;
}

/// 直线距离阈值：近程优先尝试骑行，远程展示第三方出行入口。
class RoutePlanner {
  RoutePlanner(this._client);

  final AmapRestClient _client;

  static const double bikePreferMax = 4000;
  static const double thirdPartyMin = 15000;

  Future<TripPlan> plan(LatLng origin, LatLng dest) async {
    final straight = haversineMeters(origin, dest);
    final showThird = straight >= thirdPartyMin;

    if (straight < bikePreferMax) {
      final bike = await _client.bicycling(origin, dest);
      if (bike != null) {
        final drive = await _client.driving(origin, dest);
        return TripPlan(
          straightMeters: straight,
          primary: bike,
          secondary: drive,
          showThirdPartyLinks: showThird,
        );
      }
      final driveOnly = await _client.driving(origin, dest);
      if (driveOnly == null) {
        throw StateError('驾车路线规划失败');
      }
      return TripPlan(
        straightMeters: straight,
        primary: driveOnly,
        showThirdPartyLinks: showThird,
      );
    }

    final drive = await _client.driving(origin, dest);
    if (drive == null) {
      throw StateError('驾车路线规划失败');
    }
    RoutePlanResult? bike;
    if (straight < thirdPartyMin) {
      bike = await _client.bicycling(origin, dest);
    }
    return TripPlan(
      straightMeters: straight,
      primary: drive,
      secondary: bike,
      showThirdPartyLinks: showThird,
    );
  }
}
