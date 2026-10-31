import 'package:flutter/material.dart';

/// One nurse, built from an entry in assets/app_demo/nurses.json.
class NurseUser {
  final String username; // short login name: n1 ... n10
  final String userId; // data contract "user_id", e.g. NURSE-01
  final String deviceId; // data contract "device_id", e.g. INSOLE-001
  final String displayName;
  final int age;
  final String gender;
  final String ward;
  final int yearsInNursing;
  final String diabetesType;
  final int yearsWithDiabetes;
  final String footSensation;
  final String otherConditions;
  final String scenario; // what this demo nurse is meant to show
  final Color accentColor;
  final String sampleDataAsset; // sensor readings
  final String alertsAsset; // ML alerts in the alert contract format

  const NurseUser({
    required this.username,
    required this.userId,
    required this.deviceId,
    required this.displayName,
    required this.age,
    required this.gender,
    required this.ward,
    required this.yearsInNursing,
    required this.diabetesType,
    required this.yearsWithDiabetes,
    required this.footSensation,
    required this.otherConditions,
    required this.scenario,
    required this.accentColor,
    required this.sampleDataAsset,
    required this.alertsAsset,
  });

  static const List<Color> _palette = [
    Color(0xFF2E7D6B),
    Color(0xFF3B5BDB),
    Color(0xFF7048E8),
    Color(0xFFB4530A),
    Color(0xFF0C8599),
    Color(0xFFC2255C),
    Color(0xFFE8590C),
    Color(0xFF5F3DC4),
    Color(0xFFA61E4D),
    Color(0xFF2B8A3E),
  ];

  /// [index] is the position in nurses.json (0 for the first nurse).
  factory NurseUser.fromJson(Map<String, dynamic> json, int index) {
    final userId = json['user_id'] as String;
    final number = userId.split('-').last; // NURSE-07 -> 07
    return NurseUser(
      username: 'n${index + 1}',
      userId: userId,
      deviceId: json['device_id'] as String,
      displayName: json['name'] as String,
      age: (json['age'] as num).toInt(),
      gender: json['gender'] as String,
      ward: json['ward'] as String,
      yearsInNursing: (json['years_in_nursing'] as num).toInt(),
      diabetesType: json['diabetes_type'] as String,
      yearsWithDiabetes: (json['years_with_diabetes'] as num).toInt(),
      footSensation: json['foot_sensation'] as String,
      otherConditions: json['other_conditions'] as String,
      scenario: json['scenario'] as String,
      accentColor: _palette[index % _palette.length],
      sampleDataAsset: 'assets/app_demo/sample_shift_nurse$number.json',
      alertsAsset: 'assets/app_demo/alerts_nurse$number.json',
    );
  }

  String get initials {
    final parts = displayName.trim().split(' ');
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
