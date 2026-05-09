import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:amap_flutter_base/amap_flutter_base.dart';

/// 唤起第三方 App 或网页；失败时提示用户。
class TravelLinks {
  TravelLinks._();

  static Future<void> _copyBeforeLaunch(String? clipboardText) async {
    final t = clipboardText?.trim();
    if (t == null || t.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: t));
  }

  static Future<void> openDidi(
    LatLng from,
    LatLng to, {
    String? clipboardText,
  }) async {
    await _copyBeforeLaunch(clipboardText);
    final q =
        'slat=${from.latitude}&slon=${from.longitude}&dlat=${to.latitude}&dlon=${to.longitude}';
    final uris = <Uri>[
      Uri.parse('diditaxi://home?$q'),
      Uri.parse('onetravel://dache/sendorder?$q'),
      Uri.parse('https://m.didi.com/'),
    ];
    await _tryLaunchAny(uris);
  }

  static Future<void> openRail12306({String? clipboardText}) async {
    await _copyBeforeLaunch(clipboardText);
    await _tryLaunchAny(<Uri>[
      // 官方客户端常用 scheme（仅 https 会进 H5/浏览器，无法进 App）
      Uri.parse('cn.12306://'),
      Uri.parse('https://mobile.12306.cn/otsmobile/h5/ots/pages/home/index.html'),
      Uri.parse('https://www.12306.cn/'),
    ]);
  }

  static Future<void> openMeituanSearch(
    String keyword, {
    String? clipboardText,
  }) async {
    await _copyBeforeLaunch(clipboardText);
    final encoded = Uri.encodeComponent(keyword);
    await _tryLaunchAny(<Uri>[
      Uri.parse('imeituan://www.meituan.com/search?keyword=$encoded'),
      Uri.parse('https://i.meituan.com/s/$encoded'),
    ]);
  }

  /// 在高德地图 App 中打开路线规划（驾车）。无起点时由高德侧使用「我的位置」。
  static Future<void> openAmapRoute(
    LatLng? from,
    LatLng to,
    String destName, {
    String originLabel = '我的位置',
    int mode = 0,
    String? clipboardText,
  }) async {
    await _copyBeforeLaunch(clipboardText);
    final destLabel = destName.trim().isEmpty ? '目的地' : destName.trim();
    final candidates = <Uri>[];

    if (Platform.isIOS) {
      final q = <String, String>{
        'sourceApplication': 'travel_plan',
        'dlat': '${to.latitude}',
        'dlon': '${to.longitude}',
        'dname': destLabel,
        'dev': '0',
        't': '$mode',
      };
      if (from != null) {
        q['slat'] = '${from.latitude}';
        q['slon'] = '${from.longitude}';
        q['sname'] = originLabel;
      } else {
        q['sname'] = originLabel;
      }
      candidates.add(Uri(scheme: 'iosamap', host: 'path', queryParameters: q));
    } else if (Platform.isAndroid) {
      final q = <String, String>{
        'sourceApplication': 'travel_plan',
        'dlat': '${to.latitude}',
        'dlon': '${to.longitude}',
        'dname': destLabel,
        'dev': '0',
        't': '$mode',
      };
      if (from != null) {
        q['slat'] = '${from.latitude}';
        q['slon'] = '${from.longitude}';
        q['sname'] = originLabel;
      } else {
        q['sname'] = originLabel;
      }
      candidates.add(
        Uri(
          scheme: 'androidamap',
          host: 'route',
          pathSegments: const ['plan'],
          queryParameters: q,
        ),
      );
    }

    final toSeg = Uri.encodeComponent('${to.longitude},${to.latitude},$destLabel');
    candidates.add(
      Uri.parse(
        'https://uri.amap.com/navigation?to=$toSeg&mode=car&src=travel_plan&coordinate=gaode&callnative=1',
      ),
    );

    await _tryLaunchAny(candidates);
  }

  static Future<void> _tryLaunchAny(List<Uri> candidates) async {
    for (final u in candidates) {
      try {
        if (await canLaunchUrl(u) && await launchUrl(u, mode: LaunchMode.externalApplication)) {
          return;
        }
      } catch (_) {}
    }
    await launchUrl(candidates.last, mode: LaunchMode.externalApplication);
  }
}
