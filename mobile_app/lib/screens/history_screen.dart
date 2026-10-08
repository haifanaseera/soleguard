import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/sensor_reading.dart';
import '../models/alert.dart';
import '../models/user.dart';

class HistoryScreen extends StatefulWidget {
  final NurseUser user;
  const HistoryScreen({super.key, required this.user});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<SensorReading> _readings = [];
  bool _loading = true;

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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final heelValues = _readings.map((r) => r.pressure.heel).toList();

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
                  const Text(
                    'Heel pressure trend',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 80,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _SparklinePainter(values: heelValues),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ..._readings.reversed.map((reading) {
              final alert = RiskAlert.fromReading(reading);
              return _HistoryTile(reading: reading, alert: alert);
            }),
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

  Color _color() {
    switch (alert.riskLevel) {
      case RiskLevel.normal:
        return const Color(0xFF2E9E6C);
      case RiskLevel.caution:
        return const Color(0xFFE08A1E);
      case RiskLevel.alert:
        return const Color(0xFFD93F3F);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _color(),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${reading.timestamp.hour.toString().padLeft(2, '0')}:'
                  '${reading.timestamp.minute.toString().padLeft(2, '0')}:'
                  '${reading.timestamp.second.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  'Heel ${reading.pressure.heel.toStringAsFixed(1)} • '
                  '${reading.temperatureCelsius.toStringAsFixed(1)}°C • '
                  '${reading.motionState}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _color().withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              riskLevelToString(alert.riskLevel),
              style: TextStyle(
                color: _color(),
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
    final range = (maxV - minV).abs() < 0.001 ? 1 : (maxV - minV);

    final dx = size.width / (values.length - 1).clamp(1, 1000);
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
