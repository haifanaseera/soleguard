import 'package:flutter_test/flutter_test.dart';
import 'package:soleguard_mobile/models/alert.dart';
import 'package:soleguard_mobile/services/auth_service.dart';
import 'package:soleguard_mobile/services/shift_repository.dart';

/// Checks the app against the ML output in assets/app_demo.
/// Run with:  flutter test test/risk_scenarios_test.dart
///
/// For each nurse number: [normal, caution, alert, reading indexes where a
/// new caution/alert episode begins]. These come from alerts_nurseNN.json.
const expected = <int, List<Object>>{
  1: [200, 0, 0, <int>[]],
  2: [180, 17, 3, <int>[73, 110, 163]],
  3: [185, 15, 0, <int>[70, 72, 118, 173]],
  4: [177, 3, 20, <int>[68, 115, 165]],
  5: [200, 0, 0, <int>[]],
  6: [182, 15, 3, <int>[81, 130, 176]],
  7: [153, 3, 44, <int>[64, 98, 132, 138, 154, 178]],
  8: [200, 0, 0, <int>[]],
  9: [145, 55, 0, <int>[116, 122, 126, 131, 133, 140, 142, 144, 147, 150, 155, 159]],
  10: [182, 7, 11, <int>[75, 140, 147, 185]],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('nurses.json gives 10 nurses with logins n1 to n10', () async {
    final nurses = await ShiftRepository.loadNurses();
    expect(nurses.length, 10);
    expect(nurses.first.username, 'n1');
    expect(nurses.first.userId, 'NURSE-01');
    expect(nurses.last.username, 'n10');
    expect(nurses.last.userId, 'NURSE-10');
  });

  test('each nurse logs in with a short password: n1 uses p1 ... n10 uses p10',
      () async {
    final nurses = await ShiftRepository.loadNurses();
    final auth = AuthService(nurses);
    for (var i = 0; i < nurses.length; i++) {
      expect(AuthService.passwordFor(nurses[i]), 'p${i + 1}');
    }
    expect(await auth.login('n3', 'password123'), isNotNull); // old password
    expect(await auth.login('n3', 'p4'), isNotNull); // another nurse's password
    expect(await auth.login('n3', 'p3'), isNull); // correct
    expect(auth.currentUser?.userId, 'NURSE-03');
  });

  test('every nurse has 200 readings paired with ML alerts', () async {
    final nurses = await ShiftRepository.loadNurses();
    final table = StringBuffer();

    for (var i = 0; i < nurses.length; i++) {
      final nurse = nurses[i];
      final shift = await ShiftRepository.loadShift(nurse);
      final e = expected[i + 1]!;

      expect(shift.readings.length, 200, reason: nurse.userId);
      expect(shift.alerts.length, 200, reason: nurse.userId);
      // Every reading must have found its ML alert (no backup rules used).
      expect(shift.fallbackCount, 0, reason: nurse.userId);

      var normal = 0, caution = 0, alert = 0;
      for (final a in shift.alerts) {
        if (a.riskLevel == RiskLevel.normal) normal++;
        if (a.riskLevel == RiskLevel.caution) caution++;
        if (a.riskLevel == RiskLevel.alert) alert++;
      }

      expect([normal, caution, alert], [e[0], e[1], e[2]], reason: nurse.userId);
      expect(RiskAlert.episodeStarts(shift.alerts), e[3], reason: nurse.userId);

      table.writeln(
        '${nurse.username.padRight(4)} ${nurse.userId}  '
        '${nurse.displayName.padRight(18)} '
        'normal $normal  caution $caution  alert $alert',
      );
    }
    // ignore: avoid_print
    print('\n$table');
  });

  test('zone highlighting reads the ML reason text', () {
    final alert = RiskAlert(
      userId: 'NURSE-04',
      timestamp: DateTime(2026, 10, 8, 7, 30),
      riskLevel: RiskLevel.alert,
      reason: 'foot temperature 5.5 SD above personal baseline; '
          'heel pressure 3.5 SD above personal baseline; standing for ~5 min',
    );
    expect(alert.mentions('heel'), isTrue);
    expect(alert.mentions('temperature'), isTrue);
    expect(alert.mentions('toe'), isFalse);
    expect(alert.mentions('midfoot'), isFalse);
    expect(alert.sdFor('heel'), 3.5);
    expect(alert.sdFor('temperature'), 5.5);
    expect(alert.sdFor('toe'), isNull);
    expect(alert.reasonLines.length, 3);
    expect(alert.reasonLines.first, 'Foot temperature 5.5 SD above personal baseline');
  });
}
