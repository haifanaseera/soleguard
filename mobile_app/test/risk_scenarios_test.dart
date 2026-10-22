import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soleguard_mobile/models/alert.dart';
import 'package:soleguard_mobile/models/sensor_reading.dart';

/// Runs the app's risk rules against all 10 demo nurses and checks the
/// result for every reading. Run with:
///   flutter test test/risk_scenarios_test.dart
const expected = <String, List<String>>{
  'A': ['normal', 'normal', 'normal', 'normal', 'normal', 'normal'],
  'B': ['normal', 'normal', 'normal', 'normal', 'normal', 'normal'],
  'C': ['normal', 'normal', 'normal', 'normal', 'normal', 'normal'],
  'D': ['normal', 'normal', 'caution', 'caution', 'alert', 'alert'],
  'E': ['normal', 'normal', 'caution', 'caution', 'alert', 'alert'],
  'F': ['normal', 'normal', 'caution', 'caution', 'alert', 'alert'],
  'G': ['normal', 'normal', 'normal', 'caution', 'caution', 'alert', 'alert'],
  'H': ['normal', 'normal', 'normal', 'caution', 'caution', 'caution', 'alert', 'alert', 'alert', 'alert'],
  'I': ['normal', 'normal', 'caution', 'caution', 'alert', 'alert'],
  'J': ['alert', 'alert', 'caution', 'normal', 'normal', 'normal'],
};

const scenarios = <String, String>{
  'A': 'Normal – steady standing',
  'B': 'Normal – active walking',
  'C': 'Normal – borderline values',
  'D': 'Heel pressure rising',
  'E': 'Midfoot pressure rising',
  'F': 'Toe pressure rising',
  'G': 'Temperature rising only',
  'H': 'Prolonged standing (2h+)',
  'I': 'Heel pressure + temperature',
  'J': 'Alert, then recovery',
};

void main() {
  test('risk rules give the expected result for every demo nurse', () {
    final table = StringBuffer();
    for (final entry in expected.entries) {
      final letter = entry.key;
      final raw =
          File('assets/sample_shift_nurse$letter.json').readAsStringSync();
      final readings = (jsonDecode(raw) as List<dynamic>)
          .map((e) => SensorReading.fromJson(e as Map<String, dynamic>))
          .toList();

      final actual = List.generate(
        readings.length,
        (i) => riskLevelToString(RiskAlert.evaluate(readings, i).riskLevel),
      );

      table.writeln(
        'NURSE-$letter  ${scenarios[letter]!.padRight(30)} '
        '${actual.map((s) => s[0].toUpperCase()).join(' ')}',
      );
      expect(actual, entry.value, reason: 'NURSE-$letter ${scenarios[letter]}');
    }
    // ignore: avoid_print
    print('\n$table');
  });
}
