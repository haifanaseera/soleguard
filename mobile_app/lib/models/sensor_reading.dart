class PressureReading {
  final double heel;
  final double midfoot;
  final double toe;

  PressureReading({
    required this.heel,
    required this.midfoot,
    required this.toe,
  });

  factory PressureReading.fromJson(Map<String, dynamic> json) {
    return PressureReading(
      heel: (json['heel'] as num).toDouble(),
      midfoot: (json['midfoot'] as num).toDouble(),
      toe: (json['toe'] as num).toDouble(),
    );
  }
}

class SensorReading {
  final String deviceId;
  final String userId;
  final DateTime timestamp;
  final PressureReading pressure;
  final double temperatureCelsius;
  final String motionState;
  final int batteryPercent;

  SensorReading({
    required this.deviceId,
    required this.userId,
    required this.timestamp,
    required this.pressure,
    required this.temperatureCelsius,
    required this.motionState,
    required this.batteryPercent,
  });

  factory SensorReading.fromJson(Map<String, dynamic> json) {
    return SensorReading(
      deviceId: json['device_id'] as String,
      userId: json['user_id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      pressure: PressureReading.fromJson(
        json['pressure'] as Map<String, dynamic>,
      ),
      temperatureCelsius: (json['temperature_celsius'] as num).toDouble(),
      motionState: json['motion_state'] as String,
      batteryPercent: json['battery_percent'] as int,
    );
  }
}
