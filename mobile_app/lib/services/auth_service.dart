import 'package:flutter/material.dart';
import '../models/user.dart';

/// Local, offline authentication for demo purposes.
///
/// This intentionally does NOT call a real server. It checks credentials
/// against a local list so the app works with zero network dependency on
/// demo day. Passwords are plain text in the source code, so this must not
/// be used for real patient data. For production, replace [login] with a
/// real authentication backend over HTTPS.
class AuthService extends ChangeNotifier {
  NurseUser? _currentUser;
  NurseUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  static const String demoPassword = 'password123';

  /// Demo nurses: the simulated 10-nurse cohort (same nurses as the cohort
  /// workbook). Each has a 200-reading shift in assets/sample_shift_nurseNN.json
  /// and the ML module's alerts in assets/alerts_nurseNN.json.
  static const List<NurseUser> demoUsers = [
    NurseUser(
      username: 'n1',
      userId: 'NURSE-01',
      deviceId: 'INSOLE-001',
      displayName: "Anitha D'Souza",
      ward: 'Medical Ward',
      scenario: 'Stable all shift',
      accentColor: Color(0xFF2E7D6B),
      sampleDataAsset: 'assets/sample_shift_nurse01.json',
    ),
    NurseUser(
      username: 'n2',
      userId: 'NURSE-02',
      deviceId: 'INSOLE-002',
      displayName: "Rekha Shetty",
      ward: 'Surgical Ward',
      scenario: 'Heel pressure rises after long standing',
      accentColor: Color(0xFF3B5BDB),
      sampleDataAsset: 'assets/sample_shift_nurse02.json',
    ),
    NurseUser(
      username: 'n3',
      userId: 'NURSE-03',
      deviceId: 'INSOLE-003',
      displayName: "Fathima Noor",
      ward: 'ICU',
      scenario: 'Foot temperature hot-spot episodes',
      accentColor: Color(0xFF7048E8),
      sampleDataAsset: 'assets/sample_shift_nurse03.json',
    ),
    NurseUser(
      username: 'n4',
      userId: 'NURSE-04',
      deviceId: 'INSOLE-004',
      displayName: "Savitha Rao",
      ward: 'Operation Theatre',
      scenario: 'Pressure and temperature both rise',
      accentColor: Color(0xFFB4530A),
      sampleDataAsset: 'assets/sample_shift_nurse04.json',
    ),
    NurseUser(
      username: 'n5',
      userId: 'NURSE-05',
      deviceId: 'INSOLE-005',
      displayName: "Joseph Pinto",
      ward: 'Emergency',
      scenario: 'High readings, but normal for this nurse',
      accentColor: Color(0xFF0C8599),
      sampleDataAsset: 'assets/sample_shift_nurse05.json',
    ),
    NurseUser(
      username: 'n6',
      userId: 'NURSE-06',
      deviceId: 'INSOLE-006',
      displayName: "Deepa Nayak",
      ward: 'Paediatric Ward',
      scenario: 'Toe pressure rises while standing',
      accentColor: Color(0xFFC2255C),
      sampleDataAsset: 'assets/sample_shift_nurse06.json',
    ),
    NurseUser(
      username: 'n7',
      userId: 'NURSE-07',
      deviceId: 'INSOLE-007',
      displayName: "Lakshmi Bhat",
      ward: 'ICU',
      scenario: 'Long standing, pressure and temperature rising',
      accentColor: Color(0xFFE8590C),
      sampleDataAsset: 'assets/sample_shift_nurse07.json',
    ),
    NurseUser(
      username: 'n8',
      userId: 'NURSE-08',
      deviceId: 'INSOLE-008',
      displayName: "Mohammed Rafiq",
      ward: 'Medical Ward',
      scenario: 'Stable all shift',
      accentColor: Color(0xFF5F3DC4),
      sampleDataAsset: 'assets/sample_shift_nurse08.json',
    ),
    NurseUser(
      username: 'n9',
      userId: 'NURSE-09',
      deviceId: 'INSOLE-009',
      displayName: "Prema Kumari",
      ward: 'Maternity Ward',
      scenario: 'Temperature drifts upward',
      accentColor: Color(0xFFA61E4D),
      sampleDataAsset: 'assets/sample_shift_nurse09.json',
    ),
    NurseUser(
      username: 'n10',
      userId: 'NURSE-10',
      deviceId: 'INSOLE-010',
      displayName: "Sunitha George",
      ward: 'Surgical Ward',
      scenario: 'Mild rise in pressure and temperature',
      accentColor: Color(0xFF2B8A3E),
      sampleDataAsset: 'assets/sample_shift_nurse10.json',
    ),
  ];

  /// Returns null on success, or an error message on failure.
  Future<String?> login(String username, String password) async {
    // Simulated delay so the loading state feels real.
    await Future.delayed(const Duration(milliseconds: 600));

    final key = username.trim().toLowerCase();

    if (key.isEmpty || password.isEmpty) {
      return 'Please enter both username and password.';
    }

    NurseUser? match;
    for (final u in demoUsers) {
      if (u.username == key) match = u;
    }

    if (match == null) {
      return 'No account found for "${username.trim()}".';
    }
    if (password != demoPassword) {
      return 'Incorrect password.';
    }

    _currentUser = match;
    notifyListeners();
    return null;
  }

  void logout() {
    _currentUser = null;
    notifyListeners();
  }
}
