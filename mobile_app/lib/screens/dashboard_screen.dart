import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/sensor_reading.dart';
import '../models/alert.dart';
import '../models/user.dart';

class DashboardScreen extends StatefulWidget {
  final NurseUser user;
  const DashboardScreen({super.key, required this.user});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<SensorReading> _readings = [];
  int _currentIndex = 0;
  Timer? _timer;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSampleData();
  }

  Future<void> _loadSampleData() async {
    try {
      // Loads this nurse's own sample data — matches widget.user.userId.
      final raw = await rootBundle.loadString(widget.user.sampleDataAsset);
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      final readings = decoded
          .map((e) => SensorReading.fromJson(e as Map<String, dynamic>))
          .toList();

      setState(() {
        _readings = readings;
        _loading = false;
      });

      _startPlayback();
    } catch (e) {
      setState(() {
        _error = 'Failed to load sample data: $e';
        _loading = false;
      });
    }
  }

  void _startPlayback() {
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_readings.isEmpty) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % _readings.length;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (_readings.isEmpty) {
      return const Scaffold(body: Center(child: Text('No readings found')));
    }

    final reading = _readings[_currentIndex];
    // Placeholder local risk calc — swap for Person C's real ML output
    // once it's ready. Nothing else in this screen needs to change.
    final alert = RiskAlert.fromReading(reading);

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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.user.displayName,
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
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _RiskBanner(alert: alert),
                  const SizedBox(height: 20),
                  _MetaRow(reading: reading),
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
                  _PressureRow(pressure: reading.pressure),
                  const SizedBox(height: 20),
                  _TemperatureCard(temperature: reading.temperatureCelsius),
                  const SizedBox(height: 20),
                  _FooterInfo(
                    reading: reading,
                    index: _currentIndex,
                    total: _readings.length,
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

  Color _bgColor() {
    switch (alert.riskLevel) {
      case RiskLevel.normal:
        return const Color(0xFF2E9E6C);
      case RiskLevel.caution:
        return const Color(0xFFE08A1E);
      case RiskLevel.alert:
        return const Color(0xFFD93F3F);
    }
  }

  IconData _icon() {
    switch (alert.riskLevel) {
      case RiskLevel.normal:
        return Icons.check_circle;
      case RiskLevel.caution:
        return Icons.warning_amber_rounded;
      case RiskLevel.alert:
        return Icons.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
      decoration: BoxDecoration(
        color: _bgColor(),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _bgColor().withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: Icon(
              _icon(),
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
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: alert.reason == null
                      ? const SizedBox.shrink()
                      : Padding(
                          key: ValueKey(alert.reason),
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            alert.reason!,
                            style: const TextStyle(color: Colors.white70),
                          ),
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
  const _MetaRow({required this.reading});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _MetaChip(icon: Icons.directions_walk, label: reading.motionState),
        _MetaChip(
          icon: Icons.battery_full,
          label: '${reading.batteryPercent}%',
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

class _PressureRow extends StatelessWidget {
  final PressureReading pressure;
  const _PressureRow({required this.pressure});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _PressureTile(label: 'Heel', value: pressure.heel)),
        const SizedBox(width: 10),
        Expanded(
          child: _PressureTile(label: 'Midfoot', value: pressure.midfoot),
        ),
        const SizedBox(width: 10),
        Expanded(child: _PressureTile(label: 'Toe', value: pressure.toe)),
      ],
    );
  }
}

class _PressureTile extends StatelessWidget {
  final String label;
  final double value;
  const _PressureTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, animatedValue, child) {
              return Text(
                animatedValue.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _TemperatureCard extends StatelessWidget {
  final double temperature;
  const _TemperatureCard({required this.temperature});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, animatedValue, child) {
              return Text(
                '${animatedValue.toStringAsFixed(1)} °C',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
              );
            },
          ),
          const Spacer(),
          const Text('Temperature', style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

class _FooterInfo extends StatelessWidget {
  final SensorReading reading;
  final int index;
  final int total;
  const _FooterInfo({
    required this.reading,
    required this.index,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      'Reading ${index + 1}/$total • ${reading.timestamp}',
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 12, color: Colors.black38),
    );
  }
}
