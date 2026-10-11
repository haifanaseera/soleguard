import 'package:flutter/material.dart';

class NurseUser {
  final String username; // short login name, e.g. n1
  final String userId; // matches data contract "user_id", e.g. NURSE-A
  final String deviceId; // matches data contract "device_id"
  final String displayName;
  final String ward;
  final String scenario; // what this demo account is meant to show
  final Color accentColor;
  final String sampleDataAsset;

  const NurseUser({
    required this.username,
    required this.userId,
    required this.deviceId,
    required this.displayName,
    required this.ward,
    required this.scenario,
    required this.accentColor,
    required this.sampleDataAsset,
  });

  String get initials {
    final parts = displayName.trim().split(' ');
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
