import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/sensor_reading.dart';
import '../models/alert.dart';
import '../models/user.dart';
import 'dashboard_screen.dart' show riskColor;

class HistoryScreen extends StatefulWidget {
  final NurseUser user;
  const HistoryScreen({super.key, required this.user});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<SensorReading> _readings = [];
  bool _loading = true;
  int _zone = 0; // 0 = heel, 1 = midfoot, 2 = toe

  static const _zoneNames = ['Heel', 'Midfoot', 'Toe'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = await rootBundle.loadString(widget.user.sampleDataAsset);
    final decoded = jsonDecode(raw) as List<dynamic>;
    setState(() {
      _readings = decoded
          .map((e) => SensorReading.fromJson(e as Map<String, dynamic>))
          .toList();
      _loading = false;
    });
  }

  double _zoneValue(SensorReading r) {
    switch (_zone) {
      case 1:
        return r.pressure.midfoot;
      case 2:
        return r.pressure.toe;
      default:
        return r.pressure.heel;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final values = _readings.map(_zoneValue).toList();
    final alerts = List.generate(
      _readings.length,
      (i) => RiskAlert.evaluate(_readings, i),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Shift history',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.user.displayName} • ${_readings.length} readings',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_zoneNames[_zone]} pressure trend',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Heel')),
                      ButtonSegment(value: 1, label: Text('Midfoot')),
                      ButtonSegment(value: 2, label: Text('Toe')),
                    ],
                    selected: {_zone},
                    onSelectionChanged: (s) => setState(() => _zone = s.first),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 80,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _SparklinePainter(values: values),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            for (int i = _readings.length - 1; i >= 0; i--)
              _HistoryTile(reading: _readings[i], alert: alerts[i]),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final SensorReading reading;
  final RiskAlert alert;
  const _HistoryTile({required this.reading, required this.alert});

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final color = riskColor(alert.riskLevel);
    final t = reading.timestamp;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'H ${reading.pressure.heel.toStringAsFixed(1)} • '
                  'M ${reading.pressure.midfoot.toStringAsFixed(1)} • '
                  'T ${reading.pressure.toe.toStringAsFixed(1)} • '
                  '${reading.temperatureCelsius.toStringAsFixed(1)}°C • '
                  '${reading.motionState}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                if (alert.reason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      alert.reason!,
                      style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              riskLevelToString(alert.riskLevel),
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  _SparklinePainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final double range = (maxV - minV).abs() < 0.001 ? 1.0 : (maxV - minV);

    final double dx =
        values.length > 1 ? size.width / (values.length - 1) : size.width;
    final points = <Offset>[];
    for (int i = 0; i < values.length; i++) {
      final normalized = (values[i] - minV) / range;
      final y = size.height - (normalized * size.height);
      points.add(Offset(dx * i, y));
    }

    final linePaint = Paint()
      ..color = const Color(0xFF2E7D6B)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = const Color(0xFF2E7D6B);
    for (final p in points) {
      canvas.drawCircle(p, 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values;
}
