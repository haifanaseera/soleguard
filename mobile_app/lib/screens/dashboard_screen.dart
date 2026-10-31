import 'dart:async';
import 'package:flutter/material.dart';

import '../models/alert.dart';
import '../models/sensor_reading.dart';
import '../models/user.dart';
import '../services/shift_repository.dart';
import '../widgets/ui_helpers.dart';

class DashboardScreen extends StatefulWidget {
  final NurseUser user;
  final ShiftData shift;
  const DashboardScreen({super.key, required this.user, required this.shift});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _index = 0;
  bool _playing = true;
  int _speed = 1; // 1x = one reading every 3 seconds
  Timer? _timer;
  late final List<int> _alertStarts;

  @override
  void initState() {
    super.initState();
    _alertStarts = RiskAlert.episodeStarts(widget.shift.alerts);
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (!_playing || widget.shift.readings.isEmpty) return;
    final ms = (3000 / _speed).round();
    _timer = Timer.periodic(Duration(milliseconds: ms), (_) {
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % widget.shift.readings.length;
      });
    });
  }

  void _togglePlay() {
    setState(() => _playing = !_playing);
    _restartTimer();
  }

  void _setSpeed(int speed) {
    setState(() => _speed = speed);
    _restartTimer();
  }

  void _seek(int i) {
    final last = widget.shift.readings.length - 1;
    setState(() => _index = i.clamp(0, last).toInt());
  }

  void _nextAlert() {
    if (_alertStarts.isEmpty) return;
    final next = _alertStarts.firstWhere(
      (s) => s > _index,
      orElse: () => _alertStarts.first,
    );
    setState(() => _index = next);
  }

  void _prevAlert() {
    if (_alertStarts.isEmpty) return;
    final prev = _alertStarts.lastWhere(
      (s) => s < _index,
      orElse: () => _alertStarts.last,
    );
    setState(() => _index = prev);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readings = widget.shift.readings;
    if (readings.isEmpty) {
      return const Scaffold(body: Center(child: Text('No readings found')));
    }

    final reading = readings[_index];
    final alert = widget.shift.alerts[_index];

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: const Color(0xFFF6F7FB),
              elevation: 0,
              title: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: widget.user.accentColor,
                    child: Text(
                      widget.user.initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.user.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                        Text(
                          widget.user.ward,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _RiskBanner(alert: alert),
                  const SizedBox(height: 16),
                  _MetaRow(reading: reading, usedFallback: widget.shift.usedFallback),
                  const SizedBox(height: 20),
                  const Text(
                    'Pressure (kPa)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _ZoneTile(
                          label: 'Heel',
                          value: reading.pressure.heel,
                          alert: alert,
                          zoneWord: 'heel',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ZoneTile(
                          label: 'Midfoot',
                          value: reading.pressure.midfoot,
                          alert: alert,
                          zoneWord: 'midfoot',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ZoneTile(
                          label: 'Toe',
                          value: reading.pressure.toe,
                          alert: alert,
                          zoneWord: 'toe',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _TemperatureCard(
                    temperature: reading.temperatureCelsius,
                    alert: alert,
                  ),
                  const SizedBox(height: 20),
                  _PlaybackCard(
                    alerts: widget.shift.alerts,
                    readings: readings,
                    index: _index,
                    playing: _playing,
                    speed: _speed,
                    hasAlerts: _alertStarts.isNotEmpty,
                    onSeek: _seek,
                    onTogglePlay: _togglePlay,
                    onSpeed: _setSpeed,
                    onNextAlert: _nextAlert,
                    onPrevAlert: _prevAlert,
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskBanner extends StatelessWidget {
  final RiskAlert alert;
  const _RiskBanner({required this.alert});

  @override
  Widget build(BuildContext context) {
    final color = riskColor(alert.riskLevel);
    final lines = alert.reasonLines;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: Icon(
              riskIcon(alert.riskLevel),
              key: ValueKey(alert.riskLevel),
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  riskLevelToString(alert.riskLevel).toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topLeft,
                    children: [...previous, if (current != null) current],
                  ),
                  child: Column(
                    key: ValueKey(alert.reason ?? ''),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: lines.isEmpty
                        ? const [
                            Text(
                              'No risk detected',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ]
                        : [
                            for (final line in lines)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  line,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                          ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final SensorReading reading;
  final bool usedFallback;
  const _MetaRow({required this.reading, required this.usedFallback});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _MetaChip(
          icon: motionIcon(reading.motionState),
          label: reading.motionState,
        ),
        _MetaChip(
          icon: Icons.battery_full,
          label: '${reading.batteryPercent}%',
        ),
        if (usedFallback)
          const _MetaChip(
            icon: Icons.info_outline,
            label: 'Backup rules in use',
          ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.black54),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ],
      ),
    );
  }
}

/// A pressure tile. It is highlighted only when the ML alert names this
/// zone in its reason, so the tiles always agree with the banner.
class _ZoneTile extends StatelessWidget {
  final String label;
  final double value;
  final RiskAlert alert;
  final String zoneWord;
  const _ZoneTile({
    required this.label,
    required this.value,
    required this.alert,
    required this.zoneWord,
  });

  @override
  Widget build(BuildContext context) {
    final flagged = alert.isFlagged && alert.mentions(zoneWord);
    final color = riskColor(alert.riskLevel);
    final sd = flagged ? alert.sdFor(zoneWord) : null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
      decoration: BoxDecoration(
        color: flagged ? color.withOpacity(0.10) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: flagged ? color : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            builder: (context, animatedValue, child) {
              return Text(
                animatedValue.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: flagged ? color : const Color(0xFF1A1A2E),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
          SizedBox(
            height: 18,
            child: sd == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '+${sd.toStringAsFixed(1)} SD',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TemperatureCard extends StatelessWidget {
  final double temperature;
  final RiskAlert alert;
  const _TemperatureCard({required this.temperature, required this.alert});

  @override
  Widget build(BuildContext context) {
    final flagged = alert.isFlagged && alert.mentions('temperature');
    final color = riskColor(alert.riskLevel);
    final sd = flagged ? alert.sdFor('temperature') : null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: flagged ? color.withOpacity(0.10) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: flagged ? color : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.deepOrange.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.thermostat, color: Colors.deepOrange),
          ),
          const SizedBox(width: 12),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: temperature),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            builder: (context, animatedValue, child) {
              return Text(
                '${animatedValue.toStringAsFixed(1)} °C',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: flagged ? color : const Color(0xFF1A1A2E),
                ),
              );
            },
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Temperature',
                style: TextStyle(color: Colors.black54),
              ),
              if (sd != null)
                Text(
                  '+${sd.toStringAsFixed(1)} SD',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Play/pause, speed, jump-to-alert buttons and a colored timeline you can
/// tap or drag to jump anywhere in the shift.
class _PlaybackCard extends StatelessWidget {
  final List<RiskAlert> alerts;
  final List<SensorReading> readings;
  final int index;
  final bool playing;
  final int speed;
  final bool hasAlerts;
  final ValueChanged<int> onSeek;
  final VoidCallback onTogglePlay;
  final ValueChanged<int> onSpeed;
  final VoidCallback onNextAlert;
  final VoidCallback onPrevAlert;

  const _PlaybackCard({
    required this.alerts,
    required this.readings,
    required this.index,
    required this.playing,
    required this.speed,
    required this.hasAlerts,
    required this.onSeek,
    required this.onTogglePlay,
    required this.onSpeed,
    required this.onNextAlert,
    required this.onPrevAlert,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Shift timeline',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '${formatClock(readings[index].timestamp)}  •  '
                '${index + 1}/${readings.length}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _Timeline(alerts: alerts, index: index, onSeek: onSeek),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatClock(readings.first.timestamp),
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
              Text(
                formatClock(readings.last.timestamp),
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: hasAlerts ? onPrevAlert : null,
                  icon: const Icon(Icons.skip_previous, size: 18),
                  label: const Text(
                    'Prev alert',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: onTogglePlay,
                tooltip: playing ? 'Pause' : 'Play',
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: hasAlerts ? onNextAlert : null,
                  icon: const Icon(Icons.skip_next, size: 18),
                  label: const Text(
                    'Next alert',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          if (!hasAlerts)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'No caution or alert readings in this shift.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Speed', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 12),
              Expanded(
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 1, label: Text('1×')),
                    ButtonSegment(value: 3, label: Text('3×')),
                    ButtonSegment(value: 10, label: Text('10×')),
                  ],
                  selected: {speed},
                  onSelectionChanged: (s) => onSpeed(s.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '1× shows one reading every 3 seconds. '
            'Each reading is 30 seconds of shift time.',
            style: TextStyle(fontSize: 11, color: Colors.black45),
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  final List<RiskAlert> alerts;
  final int index;
  final ValueChanged<int> onSeek;
  const _Timeline({
    required this.alerts,
    required this.index,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void seekTo(double dx) {
          final n = alerts.length;
          if (n == 0 || width <= 0) return;
          final i = ((dx / width) * n).floor().clamp(0, n - 1).toInt();
          onSeek(i);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seekTo(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => seekTo(d.localPosition.dx),
          child: SizedBox(
            height: 40,
            width: width,
            child: CustomPaint(
              painter: _TimelinePainter(alerts: alerts, index: index),
            ),
          ),
        );
      },
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final List<RiskAlert> alerts;
  final int index;
  _TimelinePainter({required this.alerts, required this.index});

  @override
  void paint(Canvas canvas, Size size) {
    final n = alerts.length;
    if (n == 0) return;

    const barTop = 12.0;
    const barHeight = 16.0;
    final cell = size.width / n;
    final barRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, barTop, size.width, barHeight),
      const Radius.circular(8),
    );

    canvas.drawRRect(barRect, Paint()..color = const Color(0xFFE3E7EE));

    canvas.save();
    canvas.clipRRect(barRect);
    for (var i = 0; i < n; i++) {
      final a = alerts[i];
      if (!a.isFlagged) continue;
      canvas.drawRect(
        Rect.fromLTWH(i * cell, barTop, cell + 0.6, barHeight),
        Paint()..color = riskColor(a.riskLevel),
      );
    }
    canvas.restore();

    final x = (index + 0.5) * cell;
    final marker = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x, barTop - 7), Offset(x, barTop + barHeight + 7), marker);
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) =>
      oldDelegate.index != index || oldDelegate.alerts != alerts;
}
