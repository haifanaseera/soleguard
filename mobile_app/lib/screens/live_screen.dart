import 'dart:async';
import 'package:flutter/material.dart';

import '../models/alert.dart';
import '../models/sensor_reading.dart';
import '../models/user.dart';
import '../services/insole_source.dart';
import '../services/shift_repository.dart';
import '../widgets/ui_helpers.dart';

/// Shows readings arriving live from an [InsoleSource].
///
/// Today the source is a simulated insole. When the Bluetooth source is
/// switched on, this screen does not change.
class LiveScreen extends StatefulWidget {
  final NurseUser user;
  final ShiftData shift;
  final InsoleSource Function() sourceBuilder;

  const LiveScreen({
    super.key,
    required this.user,
    required this.shift,
    required this.sourceBuilder,
  });

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  // How long without a reading before we warn the user.
  static const Duration _staleAfter = Duration(seconds: 5);
  static const int _maxKept = 300;

  InsoleSource? _source;
  StreamSubscription<SensorReading>? _readingSub;
  StreamSubscription<LiveStatus>? _statusSub;
  Timer? _clock;

  LiveStatus _status = LiveStatus.idle;
  final List<SensorReading> _readings = [];
  RiskAlert? _alert;
  bool _alertFromMl = false;
  DateTime? _lastArrival;
  int _received = 0;

  /// ML alerts of this nurse's recorded shift, found by timestamp. When the
  /// insole replays the team's test data, its readings match these alerts.
  late final Map<DateTime, RiskAlert> _mlByTime;

  @override
  void initState() {
    super.initState();
    _mlByTime = {for (final a in widget.shift.alerts) a.timestamp: a};
    // Refresh once a second so the "no data" warning appears on time.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _status == LiveStatus.connected) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _readingSub?.cancel();
    _statusSub?.cancel();
    _source?.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    await _teardown();
    final source = widget.sourceBuilder();
    _source = source;

    _statusSub = source.status.listen((s) {
      if (mounted) setState(() => _status = s);
    });
    _readingSub = source.readings.listen(_onReading);

    setState(() {
      _status = LiveStatus.connecting;
      _readings.clear();
      _alert = null;
      _received = 0;
      _lastArrival = null;
    });
    await source.start();
  }

  Future<void> _disconnect() async {
    await _teardown();
    if (mounted) setState(() => _status = LiveStatus.idle);
  }

  Future<void> _teardown() async {
    await _readingSub?.cancel();
    await _statusSub?.cancel();
    _readingSub = null;
    _statusSub = null;
    final old = _source;
    _source = null;
    await old?.dispose();
  }

  void _onReading(SensorReading reading) {
    if (!mounted) return;
    _readings.add(reading);
    if (_readings.length > _maxKept) _readings.removeAt(0);

    final ml = _mlByTime[reading.timestamp];
    final RiskAlert alert;
    if (ml != null && ml.userId == reading.userId) {
      alert = ml;
      _alertFromMl = true;
    } else {
      // No ML alert exists for this reading: use the simple backup rules.
      alert = RiskAlert.evaluate(_readings, _readings.length - 1);
      _alertFromMl = false;
    }

    setState(() {
      _alert = alert;
      _lastArrival = DateTime.now();
      _received++;
    });
  }

  bool get _isStale =>
      _status == LiveStatus.connected &&
      _lastArrival != null &&
      DateTime.now().difference(_lastArrival!) > _staleAfter;

  @override
  Widget build(BuildContext context) {
    final source = _source;
    final reading = _readings.isEmpty ? null : _readings.last;
    final busy = _status == LiveStatus.connecting;
    final connected = _status == LiveStatus.connected;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Live insole',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              source?.label ??
                  'Not connected. Press Connect to start receiving readings.',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _StatusChip(status: _status),
                const Spacer(),
                if (connected || busy)
                  OutlinedButton(
                    onPressed: _disconnect,
                    child: const Text('Disconnect'),
                  )
                else
                  FilledButton.icon(
                    onPressed: _connect,
                    icon: const Icon(Icons.sensors),
                    label: Text(
                      _status == LiveStatus.error ? 'Try again' : 'Connect',
                    ),
                  ),
              ],
            ),
            if (_status == LiveStatus.error)
              _Notice(
                icon: Icons.error_outline,
                color: Colors.red,
                text: source?.errorMessage ?? 'The connection failed.',
              ),
            if (_isStale)
              _Notice(
                icon: Icons.signal_wifi_statusbar_connected_no_internet_4,
                color: const Color(0xFFE08A1E),
                text: 'No data for '
                    '${DateTime.now().difference(_lastArrival!).inSeconds} '
                    'seconds. The insole may be out of range.',
              ),
            if (reading != null && reading.userId != widget.user.userId)
              _Notice(
                icon: Icons.person_search,
                color: Colors.blueGrey,
                text: 'This insole is sending data for ${reading.userId}, '
                    'but you are logged in as ${widget.user.userId}.',
              ),
            if (source is SimulatedInsoleSource)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Simulate an unplugged temperature sensor',
                  style: TextStyle(fontSize: 13),
                ),
                value: source.temperatureUnplugged,
                onChanged: (v) =>
                    setState(() => source.temperatureUnplugged = v),
              ),
            const SizedBox(height: 8),
            if (reading == null || _alert == null)
              _Placeholder(connecting: busy, connected: connected)
            else ...[
              _LiveBanner(alert: _alert!, fromMl: _alertFromMl),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Chip(
                    icon: motionIcon(reading.motionState),
                    label: reading.motionState,
                  ),
                  _Chip(
                    icon: Icons.battery_full,
                    label: '${reading.batteryPercent}%',
                  ),
                  _Chip(
                    icon: Icons.schedule,
                    label: formatClock(reading.timestamp),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Pressure (kPa)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ValueTile(
                      label: 'Heel',
                      value: reading.pressure.heel.toStringAsFixed(1),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ValueTile(
                      label: 'Midfoot',
                      value: reading.pressure.midfoot.toStringAsFixed(1),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ValueTile(
                      label: 'Toe',
                      value: reading.pressure.toe.toStringAsFixed(1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _TemperatureRow(temperature: reading.temperatureCelsius),
              const SizedBox(height: 14),
              Text(
                '$_received readings received'
                '${(source?.badLines ?? 0) > 0 ? '  •  ${source!.badLines} unreadable skipped' : ''}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final LiveStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (String text, Color color) = switch (status) {
      LiveStatus.idle => ('Not connected', Colors.blueGrey),
      LiveStatus.connecting => ('Connecting…', const Color(0xFFE08A1E)),
      LiveStatus.connected => ('Connected', const Color(0xFF2E9E6C)),
      LiveStatus.error => ('Connection problem', const Color(0xFFD93F3F)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Notice({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: color)),
          ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final bool connecting;
  final bool connected;
  const _Placeholder({required this.connecting, required this.connected});

  @override
  Widget build(BuildContext context) {
    final text = connecting
        ? 'Looking for the insole…'
        : connected
            ? 'Connected. Waiting for the first reading…'
            : 'Readings will appear here once you connect.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          if (connecting || connected)
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            )
          else
            const Icon(Icons.sensors_off, size: 30, color: Colors.black38),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _LiveBanner extends StatelessWidget {
  final RiskAlert alert;
  final bool fromMl;
  const _LiveBanner({required this.alert, required this.fromMl});

  @override
  Widget build(BuildContext context) {
    final color = riskColor(alert.riskLevel);
    final lines = alert.reasonLines;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(riskIcon(alert.riskLevel), color: Colors.white, size: 30),
              const SizedBox(width: 12),
              Text(
                riskLevelToString(alert.riskLevel).toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (lines.isEmpty)
            const Text(
              'No risk detected',
              style: TextStyle(color: Colors.white70),
            )
          else
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  line,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
          const SizedBox(height: 10),
          Text(
            fromMl
                ? 'ML alert (personal baseline)'
                : 'Backup rules: no ML alert exists for this reading',
            style: const TextStyle(color: Colors.white70, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip({required this.icon, required this.label});

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
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class _ValueTile extends StatelessWidget {
  final String label;
  final String value;
  const _ValueTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
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

class _TemperatureRow extends StatelessWidget {
  final double? temperature;
  const _TemperatureRow({required this.temperature});

  @override
  Widget build(BuildContext context) {
    final t = temperature;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            t == null ? Icons.sensors_off : Icons.thermostat,
            color: t == null ? Colors.black38 : Colors.deepOrange,
          ),
          const SizedBox(width: 12),
          Text(
            t == null ? 'Sensor unplugged' : '${t.toStringAsFixed(1)} °C',
            style: TextStyle(
              fontSize: t == null ? 16 : 20,
              fontWeight: FontWeight.bold,
              color: t == null ? Colors.black45 : const Color(0xFF1A1A2E),
            ),
          ),
          const Spacer(),
          const Text('Temperature', style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}
