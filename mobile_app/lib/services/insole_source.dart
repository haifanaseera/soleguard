import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/sensor_reading.dart';
import 'line_assembler.dart';

enum LiveStatus { idle, connecting, connected, error }

/// Anything that can deliver live insole readings: a simulated insole today,
/// the real Bluetooth insole later. The Live screen only knows this class.
abstract class InsoleSource {
  Stream<SensorReading> get readings;
  Stream<LiveStatus> get status;

  /// Short text shown on screen, e.g. "Bluetooth: SoleGuard-001".
  String get label;

  /// Set when [status] is [LiveStatus.error].
  String? get errorMessage;

  /// Readings that arrived but could not be understood.
  int get badLines;

  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}

/// Shared code for sources that receive text in chunks of bytes.
///
/// A subclass only has to call [handleBytes] for every chunk it receives.
/// This class puts the chunks back together at each "\n", parses the JSON
/// with the same parser as the recorded data, and publishes the readings.
abstract class ChunkedInsoleSource implements InsoleSource {
  final StreamController<SensorReading> _readings =
      StreamController<SensorReading>.broadcast();
  final StreamController<LiveStatus> _status =
      StreamController<LiveStatus>.broadcast();
  final LineAssembler _assembler = LineAssembler();

  String? _errorMessage;
  int _badLines = 0;

  @override
  Stream<SensorReading> get readings => _readings.stream;

  @override
  Stream<LiveStatus> get status => _status.stream;

  @override
  String? get errorMessage => _errorMessage;

  @override
  int get badLines => _badLines + _assembler.overflowCount;

  @protected
  void setStatus(LiveStatus s) {
    if (!_status.isClosed) _status.add(s);
  }

  @protected
  void setError(String message) {
    _errorMessage = message;
    setStatus(LiveStatus.error);
  }

  @protected
  void resetBuffer() {
    _assembler.clear();
    _errorMessage = null;
  }

  @protected
  void handleBytes(List<int> bytes) {
    for (final line in _assembler.add(bytes)) {
      try {
        final map = jsonDecode(line) as Map<String, dynamic>;
        if (!_readings.isClosed) _readings.add(SensorReading.fromJson(map));
      } catch (_) {
        // One unreadable line must never stop the stream.
        _badLines++;
      }
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _readings.close();
    await _status.close();
  }
}

/// A fake insole for testing without hardware. It sends the recorded readings
/// as text in small chunks, exactly like the real insole would, so the whole
/// receiving code is exercised.
class SimulatedInsoleSource extends ChunkedInsoleSource {
  SimulatedInsoleSource({
    required this.recorded,
    this.chunkSize = 20,
    this.interval = const Duration(seconds: 1),
    this.connectDelay = const Duration(milliseconds: 700),
  });

  final List<SensorReading> recorded;

  /// 20 mimics a phone that did not agree to a bigger packet size.
  /// Use 244 to mimic MTU 247, where a whole reading arrives at once.
  final int chunkSize;
  final Duration interval;
  final Duration connectDelay;

  /// When true, the temperature is sent as null (sensor unplugged).
  bool temperatureUnplugged = false;

  Timer? _timer;
  int _next = 0;
  bool _active = false;

  @override
  String get label => 'Simulated insole (replays the recorded shift)';

  @override
  Future<void> start() async {
    if (recorded.isEmpty) {
      setError('There are no recorded readings to replay.');
      return;
    }
    _active = true;
    resetBuffer();
    setStatus(LiveStatus.connecting);
    await Future<void>.delayed(connectDelay);
    if (!_active) return; // stop() was called while "connecting"
    setStatus(LiveStatus.connected);
    _emit();
    _timer = Timer.periodic(interval, (_) => _emit());
  }

  void _emit() {
    final reading = recorded[_next];
    _next = (_next + 1) % recorded.length;

    final map = reading.toJson();
    if (temperatureUnplugged) map['temperature_celsius'] = null;

    final bytes = utf8.encode('${jsonEncode(map)}\n');
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = offset + chunkSize > bytes.length
          ? bytes.length
          : offset + chunkSize;
      handleBytes(bytes.sublist(offset, end));
    }
  }

  @override
  Future<void> stop() async {
    _active = false;
    _timer?.cancel();
    _timer = null;
    setStatus(LiveStatus.idle);
  }
}
