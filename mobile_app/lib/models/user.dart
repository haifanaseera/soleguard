import 'package:flutter/material.dart';

class NurseUser {
  final String userId; // matches data contract "user_id", e.g. NURSE-A
  final String displayName;
  final String ward;
  final Color accentColor;
  final String sampleDataAsset;

  const NurseUser({
    required this.userId,
    required this.displayName,
    required this.ward,
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
