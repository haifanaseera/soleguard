import 'package:flutter/material.dart';

import '../models/alert.dart';
import '../models/sensor_reading.dart';
import '../models/user.dart';
import '../services/shift_repository.dart';
import '../widgets/ui_helpers.dart';

class HistoryScreen extends StatefulWidget {
  final NurseUser user;
  final ShiftData shift;
  const HistoryScreen({super.key, required this.user, required this.shift});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _zone = 0; // 0 heel, 1 midfoot, 2 toe, 3 temperature
  late bool _onlyFlagged;

  static const _zoneTitles = ['Heel', 'Midfoot', 'Toe', 'Temperature'];

  @override
  void initState() {
    super.initState();
    // Start with the interesting readings only, if there are any.
    _onlyFlagged = widget.shift.alerts.any((a) => a.isFlagged);
  }

  double _zoneValue(SensorReading r) {
    switch (_zone) {
      case 1:
        return r.pressure.midfoot;
      case 2:
        return r.pressure.toe;
      case 3:
        return r.temperatureCelsius;
      default:
        return r.pressure.heel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final readings = widget.shift.readings;
    final alerts = widget.shift.alerts;

    final values = readings.map(_zoneValue).toList();
    final levels = alerts.map((a) => a.riskLevel).toList();

    final normalCount = levels.where((l) => l == RiskLevel.normal).length;
    final cautionCount = levels.where((l) => l == RiskLevel.caution).length;
    final alertCount = levels.where((l) => l == RiskLevel.alert).length;

    final rows = <int>[
      for (var i = readings.length - 1; i >= 0; i--)
        if (!_onlyFlagged || alerts[i].isFlagged) i,
    ];

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
          '${widget.user.displayName} • ${readings.length} readings',
          style: const TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 16),
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
                '${_zoneTitles[_zone]} trend',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              SegmentedButton<int>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                segments: const [
                  ButtonSegment(value: 0, label: Text('Heel')),
                  ButtonSegment(value: 1, label: Text('Midfoot')),
                  ButtonSegment(value: 2, label: Text('Toe')),
                  ButtonSegment(value: 3, label: Text('Temp')),
                ],
                selected: {_zone},
                onSelectionChanged: (s) => setState(() => _zone = s.first),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 110,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _TrendPainter(values: values, levels: levels),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Shaded bands mark readings where the ML model raised '
                'a caution (orange) or alert (red).',
                style: TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CountChip(
              label: '$normalCount normal',
              color: riskColor(RiskLevel.normal),
            ),
            _CountChip(
              label: '$cautionCount caution',
              color: riskColor(RiskLevel.caution),
            ),
            _CountChip(
              label: '$alertCount alert',
              color: riskColor(RiskLevel.alert),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FilterChip(
          label: const Text('Caution & alert only'),
          selected: _onlyFlagged,
          onSelected: (v) => setState(() => _onlyFlagged = v),
        ),
        const SizedBox(height: 10),
      ],
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: 1 + (rows.isEmpty ? 1 : rows.length),
          itemBuilder: (context, k) {
            if (k == 0) return header;
            if (rows.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No readings to show.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              );
            }
            final i = rows[k - 1];
            return _HistoryTile(reading: readings[i], alert: alerts[i]);
          },
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final Color color;
  const _CountChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final SensorReading reading;
  final RiskAlert alert;
  const _HistoryTile({required this.reading, required this.alert});

  @override
  Widget build(BuildContext context) {
    final color = riskColor(alert.riskLevel);
    final lines = alert.reasonLines;
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
                  formatClock(reading.timestamp),
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
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      line,
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

/// Line chart of one zone over the whole shift, with a colored band behind
/// every reading where the ML model raised a caution or alert.
class _TrendPainter extends CustomPainter {
  final List<double> values;
  final List<RiskLevel> levels;
  _TrendPainter({required this.values, required this.levels});

  void _label(Canvas canvas, String text, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: 10, color: Colors.black45),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final double range = (maxV - minV).abs() < 0.001 ? 1.0 : (maxV - minV);

    const topPad = 12.0;
    const bottomPad = 12.0;
    final chartHeight = size.height - topPad - bottomPad;
    final n = values.length;
    final cell = size.width / n;

    // Colored bands behind the line.
    for (var i = 0; i < n; i++) {
      if (levels[i] == RiskLevel.normal) continue;
      canvas.drawRect(
        Rect.fromLTWH(i * cell, 0, cell + 0.6, size.height),
        Paint()..color = riskColor(levels[i]).withOpacity(0.18),
      );
    }

    final points = <Offset>[];
    for (var i = 0; i < n; i++) {
      final normalized = (values[i] - minV) / range;
      final y = topPad + chartHeight - normalized * chartHeight;
      points.add(Offset((i + 0.5) * cell, y));
    }

    final line = Paint()
      ..color = const Color(0xFF2E7D6B)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, line);

    _label(canvas, maxV.toStringAsFixed(1), const Offset(2, 0));
    _label(canvas, minV.toStringAsFixed(1), Offset(2, size.height - 11));
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.levels != levels;
}
