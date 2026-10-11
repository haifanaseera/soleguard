import 'sensor_reading.dart';

enum RiskLevel { normal, caution, alert }

RiskLevel riskLevelFromString(String value) {
  switch (value) {
    case 'caution':
      return RiskLevel.caution;
    case 'alert':
      return RiskLevel.alert;
    case 'normal':
    default:
      return RiskLevel.normal;
  }
}

String riskLevelToString(RiskLevel level) {
  switch (level) {
    case RiskLevel.caution:
      return 'caution';
    case RiskLevel.alert:
      return 'alert';
    case RiskLevel.normal:
      return 'normal';
  }
}

/// Placeholder thresholds standing in for Person C's ML module.
/// Pressure values are in kPa, temperature in °C, standing time in minutes.
class RiskThresholds {
  static const double heelCaution = 60, heelAlert = 80;
  static const double midfootCaution = 40, midfootAlert = 55;
  static const double toeCaution = 50, toeAlert = 65;
  static const double tempCaution = 36.5, tempAlert = 37.5;
  static const int standingCautionMin = 45, standingAlertMin = 90;

  static RiskLevel _level(double v, double caution, double alert) {
    if (v > alert) return RiskLevel.alert;
    if (v > caution) return RiskLevel.caution;
    return RiskLevel.normal;
  }

  static RiskLevel heel(double v) => _level(v, heelCaution, heelAlert);
  static RiskLevel midfoot(double v) => _level(v, midfootCaution, midfootAlert);
  static RiskLevel toe(double v) => _level(v, toeCaution, toeAlert);
  static RiskLevel temperature(double v) => _level(v, tempCaution, tempAlert);
}

class _Finding {
  final RiskLevel level;
  final String reason;
  const _Finding(this.level, this.reason);
}

class RiskAlert {
  final String userId;
  final DateTime timestamp;
  final RiskLevel riskLevel;
  final String? reason;

  RiskAlert({
    required this.userId,
    required this.timestamp,
    required this.riskLevel,
    this.reason,
  });

  /// Parses the alert format from the team data contract. Use this once
  /// Person C's ML module produces real alerts.
  factory RiskAlert.fromJson(Map<String, dynamic> json) {
    return RiskAlert(
      userId: json['user_id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      riskLevel: riskLevelFromString(json['risk_level'] as String),
      reason: json['reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'timestamp': timestamp.toIso8601String(),
      'risk_level': riskLevelToString(riskLevel),
      'reason': reason,
    };
  }

  /// How long (in minutes) the wearer has been continuously standing,
  /// counted back from [index] using the reading timestamps.
  static int standingMinutes(List<SensorReading> readings, int index) {
    if (readings[index].motionState != 'standing') return 0;
    var start = index;
    while (start > 0 && readings[start - 1].motionState == 'standing') {
      start--;
    }
    return readings[index]
        .timestamp
        .difference(readings[start].timestamp)
        .inMinutes;
  }

  static String _zoneText(String zone, RiskLevel level, double v) {
    final word = level == RiskLevel.alert ? 'critically high' : 'elevated';
    return '$zone pressure $word (${v.toStringAsFixed(1)})';
  }

  /// PLACEHOLDER risk logic, standing in for Person C's ML module.
  ///
  /// Looks at one reading (and the readings before it, for how long the
  /// nurse has been standing) and returns the worst level found. If several
  /// problems share the worst level, all their reasons are shown.
  /// When the ML module is ready, replace the calls to this method in
  /// dashboard_screen.dart and history_screen.dart.
  factory RiskAlert.evaluate(List<SensorReading> readings, int index) {
    final r = readings[index];
    final findings = <_Finding>[];

    void add(RiskLevel level, String reason) {
      if (level != RiskLevel.normal) findings.add(_Finding(level, reason));
    }

    final heel = RiskThresholds.heel(r.pressure.heel);
    add(heel, _zoneText('Heel', heel, r.pressure.heel));

    final mid = RiskThresholds.midfoot(r.pressure.midfoot);
    add(mid, _zoneText('Midfoot', mid, r.pressure.midfoot));

    final toe = RiskThresholds.toe(r.pressure.toe);
    add(toe, _zoneText('Toe', toe, r.pressure.toe));

    final temp = RiskThresholds.temperature(r.temperatureCelsius);
    final tempWord = temp == RiskLevel.alert ? 'elevated' : 'rising';
    add(
      temp,
      'Temperature $tempWord (${r.temperatureCelsius.toStringAsFixed(1)}°C)',
    );

    final minutes = standingMinutes(readings, index);
    final standing = minutes >= RiskThresholds.standingAlertMin
        ? RiskLevel.alert
        : minutes >= RiskThresholds.standingCautionMin
            ? RiskLevel.caution
            : RiskLevel.normal;
    add(standing, 'Standing continuously for $minutes min');

    if (findings.isEmpty) {
      return RiskAlert(
        userId: r.userId,
        timestamp: r.timestamp,
        riskLevel: RiskLevel.normal,
        reason: null,
      );
    }

    var top = RiskLevel.normal;
    for (final f in findings) {
      if (f.level.index > top.index) top = f.level;
    }

    return RiskAlert(
      userId: r.userId,
      timestamp: r.timestamp,
      riskLevel: top,
      reason: findings
          .where((f) => f.level == top)
          .map((f) => f.reason)
          .join(' • '),
    );
  }
}
