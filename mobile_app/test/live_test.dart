import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:soleguard_mobile/models/sensor_reading.dart';
import 'package:soleguard_mobile/services/insole_source.dart';
import 'package:soleguard_mobile/services/line_assembler.dart';

/// Tests for receiving live readings: no hardware or Bluetooth needed.
/// Run with:  flutter test test/live_test.dart

/// One reading exactly as the firmware sent it (sample from Person A).
const sample =
    '{"device_id":"INSOLE-001","user_id":"NURSE-01",'
    '"timestamp":"2026-10-08T07:55:30","pressure":{"heel":35.8,'
    '"midfoot":18.5,"toe":34.9},"temperature_celsius":34.0,'
    '"motion_state":"walking","battery_percent":78}';

/// Splits bytes into chunks, like a phone that did not agree to a bigger packet.
List<List<int>> chunked(List<int> bytes, int size) => [
      for (var i = 0; i < bytes.length; i += size)
        bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size),
    ];

/// A source we can feed bytes to by hand.
class _FeedSource extends ChunkedInsoleSource {
  @override
  String get label => 'test';
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  void feed(List<int> bytes) => handleBytes(bytes);
}

SensorReading _reading(int heel, String motion, {double? temp = 34.0}) =>
    SensorReading.fromJson({
      'device_id': 'INSOLE-001',
      'user_id': 'NURSE-01',
      'timestamp': '2026-10-08T07:00:00',
      'pressure': {'heel': heel, 'midfoot': 18.0, 'toe': 30.0},
      'temperature_celsius': temp,
      'motion_state': motion,
      'battery_percent': 80,
    });

void main() {
  group('LineAssembler', () {
    test('a whole reading in one packet (MTU 247) gives one line', () {
      final a = LineAssembler();
      final lines = a.add(utf8.encode('$sample\n'));
      expect(lines, [sample]);
      expect(a.pendingBytes, 0);
    });

    test('20-byte chunks are put back together at the newline', () {
      final a = LineAssembler();
      final lines = <String>[];
      for (final chunk in chunked(utf8.encode('$sample\n'), 20)) {
        lines.addAll(a.add(chunk));
      }
      expect(lines, [sample]);
    });

    test('a line that is not finished yet is kept, not returned', () {
      final a = LineAssembler();
      expect(a.add(utf8.encode(sample.substring(0, 50))), isEmpty);
      expect(a.pendingBytes, 50);
      expect(a.add(utf8.encode('${sample.substring(50)}\n')), [sample]);
    });

    test('two readings in one packet give two lines', () {
      final a = LineAssembler();
      expect(a.add(utf8.encode('$sample\n$sample\n')), [sample, sample]);
    });

    test('a carriage return before the newline is ignored', () {
      final a = LineAssembler();
      expect(a.add(utf8.encode('$sample\r\n')), [sample]);
    });

    test('an overlong line is thrown away, and the next reading is fine', () {
      final a = LineAssembler();
      a.add(List<int>.filled(LineAssembler.maxLineBytes + 10, 65));
      expect(a.overflowCount, 1);
      // The newline ends the garbage line. Nothing is returned for it.
      expect(a.add(utf8.encode('\n')), isEmpty);
      // The next reading arrives clean, with no garbage glued to it.
      expect(a.add(utf8.encode('$sample\n')), [sample]);
    });
  });

  group('parsing the insole sample', () {
    test('the sample from Person A parses correctly', () {
      final r = SensorReading.fromJson(
        jsonDecode(sample) as Map<String, dynamic>,
      );
      expect(r.deviceId, 'INSOLE-001');
      expect(r.userId, 'NURSE-01');
      expect(r.timestamp, DateTime(2026, 10, 8, 7, 55, 30));
      expect(r.pressure.heel, 35.8);
      expect(r.pressure.midfoot, 18.5);
      expect(r.pressure.toe, 34.9);
      expect(r.temperatureCelsius, 34.0);
      expect(r.motionState, 'walking');
      expect(r.batteryPercent, 78);
    });

    test('toJson gives the same text the firmware sends', () {
      final r = SensorReading.fromJson(
        jsonDecode(sample) as Map<String, dynamic>,
      );
      expect(jsonEncode(r.toJson()), sample);
    });

    test('a null temperature (sensor unplugged) parses', () {
      final unplugged = sample.replaceFirst(
        '"temperature_celsius":34.0',
        '"temperature_celsius":null',
      );
      final r = SensorReading.fromJson(
        jsonDecode(unplugged) as Map<String, dynamic>,
      );
      expect(r.temperatureCelsius, isNull);
    });
  });

  group('ChunkedInsoleSource', () {
    test('turns chunks into readings and skips unreadable lines', () async {
      final source = _FeedSource();
      final got = <SensorReading>[];
      source.readings.listen(got.add);

      source.feed(utf8.encode('this is not json\n'));
      for (final chunk in chunked(utf8.encode('$sample\n'), 20)) {
        source.feed(chunk);
      }
      source.feed(utf8.encode('{"broken": \n'));
      for (final chunk in chunked(utf8.encode('$sample\n'), 20)) {
        source.feed(chunk);
      }
      await Future<void>.delayed(Duration.zero);

      expect(got.length, 2); // both good readings arrived
      expect(source.badLines, 2); // the two bad lines were skipped
      await source.dispose();
    });
  });

  group('SimulatedInsoleSource', () {
    test('delivers the recorded readings through 20-byte chunks', () async {
      final recorded = [
        _reading(40, 'standing'),
        _reading(55, 'walking'),
        _reading(70, 'sitting'),
      ];
      final source = SimulatedInsoleSource(
        recorded: recorded,
        interval: const Duration(milliseconds: 5),
        connectDelay: Duration.zero,
      );

      final future = source.readings.take(4).toList();
      await source.start();
      final got = await future.timeout(const Duration(seconds: 5));

      expect(got.map((r) => r.pressure.heel), [40, 55, 70, 40]); // loops
      expect(got.map((r) => r.motionState), [
        'standing',
        'walking',
        'sitting',
        'standing',
      ]);
      expect(source.badLines, 0);
      await source.dispose();
    });

    test('an unplugged temperature is sent as null', () async {
      final source = SimulatedInsoleSource(
        recorded: [_reading(40, 'standing')],
        interval: const Duration(milliseconds: 5),
        connectDelay: Duration.zero,
      )..temperatureUnplugged = true;

      final future = source.readings.take(2).toList();
      await source.start();
      final got = await future.timeout(const Duration(seconds: 5));

      expect(got.every((r) => r.temperatureCelsius == null), isTrue);
      await source.dispose();
    });

    test('status goes connecting, connected, then idle', () async {
      final source = SimulatedInsoleSource(
        recorded: [_reading(40, 'standing')],
        interval: const Duration(milliseconds: 5),
        connectDelay: Duration.zero,
      );
      final seen = <LiveStatus>[];
      source.status.listen(seen.add);

      await source.start();
      await source.stop();
      await Future<void>.delayed(Duration.zero);

      expect(seen, [
        LiveStatus.connecting,
        LiveStatus.connected,
        LiveStatus.idle,
      ]);
      await source.dispose();
    });

    test('stopping while still connecting never connects', () async {
      final source = SimulatedInsoleSource(
        recorded: [_reading(40, 'standing')],
        connectDelay: const Duration(milliseconds: 50),
      );
      final seen = <LiveStatus>[];
      source.status.listen(seen.add);

      final starting = source.start();
      await source.stop();
      await starting;
      await Future<void>.delayed(Duration.zero);

      expect(seen.contains(LiveStatus.connected), isFalse);
      await source.dispose();
    });
  });
}
