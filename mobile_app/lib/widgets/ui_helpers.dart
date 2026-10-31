import 'package:flutter/material.dart';
import '../models/alert.dart';

Color riskColor(RiskLevel level) {
  switch (level) {
    case RiskLevel.normal:
      return const Color(0xFF2E9E6C);
    case RiskLevel.caution:
      return const Color(0xFFE08A1E);
    case RiskLevel.alert:
      return const Color(0xFFD93F3F);
  }
}

IconData riskIcon(RiskLevel level) {
  switch (level) {
    case RiskLevel.normal:
      return Icons.check_circle;
    case RiskLevel.caution:
      return Icons.warning_amber_rounded;
    case RiskLevel.alert:
      return Icons.error;
  }
}

IconData motionIcon(String motionState) {
  switch (motionState) {
    case 'walking':
      return Icons.directions_walk;
    case 'sitting':
      return Icons.event_seat;
    case 'standing':
    default:
      return Icons.accessibility_new;
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 07:32:30
String formatClock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
