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

  /// Placeholder risk logic, standing in for Person C's real ML module.
  /// Swap this out once ml_personalization/ produces real alerts — this is
  /// the ONLY line downstream code needs to change (see dashboard_screen.dart).
  factory RiskAlert.fromReading(SensorReading reading) {
    final heel = reading.pressure.heel;
    final temp = reading.temperatureCelsius;

    RiskLevel level = RiskLevel.normal;
    String? reason;

    if (heel > 80 || temp > 37.5) {
      level = RiskLevel.alert;
      reason = heel > 80
          ? 'Heel pressure critically high (${heel.toStringAsFixed(1)})'
          : 'Temperature elevated (${temp.toStringAsFixed(1)}°C)';
    } else if (heel > 60 || temp > 36.5) {
      level = RiskLevel.caution;
      reason = heel > 60
          ? 'Heel pressure elevated (${heel.toStringAsFixed(1)})'
          : 'Temperature rising (${temp.toStringAsFixed(1)}°C)';
    }

    return RiskAlert(
      userId: reading.userId,
      timestamp: reading.timestamp,
      riskLevel: level,
      reason: reason,
    );
  }
}
