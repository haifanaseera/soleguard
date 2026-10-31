import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

import '../models/alert.dart';
import '../models/sensor_reading.dart';
import '../models/user.dart';

/// One nurse's shift: the sensor readings and one alert per reading.
class ShiftData {
  final List<SensorReading> readings;
  final List<RiskAlert> alerts; // same length and order as [readings]

  /// Number of readings that had no ML alert and used the backup rules.
  final int fallbackCount;

  const ShiftData({
    required this.readings,
    required this.alerts,
    required this.fallbackCount,
  });

  bool get usedFallback => fallbackCount > 0;
}

class ShiftRepository {
  static const String nursesAsset = 'assets/app_demo/nurses.json';

  static Future<List<NurseUser>> loadNurses() async {
    final raw = await rootBundle.loadString(nursesAsset);
    final list = jsonDecode(raw) as List<dynamic>;
    return [
      for (var i = 0; i < list.length; i++)
        NurseUser.fromJson(list[i] as Map<String, dynamic>, i),
    ];
  }

  /// Loads the readings, then pairs each reading with the ML alert that has
  /// the same timestamp. If the alert file is missing or a timestamp has no
  /// alert, the backup fixed-limit rules are used for that reading.
  static Future<ShiftData> loadShift(NurseUser user) async {
    final rawReadings = await rootBundle.loadString(user.sampleDataAsset);
    final readings = (jsonDecode(rawReadings) as List<dynamic>)
        .map((e) => SensorReading.fromJson(e as Map<String, dynamic>))
        .toList();

    final byTimestamp = <DateTime, RiskAlert>{};
    try {
      final rawAlerts = await rootBundle.loadString(user.alertsAsset);
      for (final e in jsonDecode(rawAlerts) as List<dynamic>) {
        final alert = RiskAlert.fromJson(e as Map<String, dynamic>);
        byTimestamp[alert.timestamp] = alert;
      }
    } catch (_) {
      // Alert file missing or unreadable: every reading uses the backup rules.
    }

    var fallbackCount = 0;
    final alerts = <RiskAlert>[];
    for (var i = 0; i < readings.length; i++) {
      final ml = byTimestamp[readings[i].timestamp];
      if (ml != null) {
        alerts.add(ml);
      } else {
        fallbackCount++;
        alerts.add(RiskAlert.evaluate(readings, i));
      }
    }

    return ShiftData(
      readings: readings,
      alerts: alerts,
      fallbackCount: fallbackCount,
    );
  }
}
