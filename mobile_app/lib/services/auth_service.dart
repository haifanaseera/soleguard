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

  /// Demo nurses. Each one has a different sample shift so every risk
  /// situation can be shown: normal, one zone rising, temperature,
  /// prolonged standing, combined problems, and recovery.
  static const List<NurseUser> demoUsers = [
    NurseUser(
      username: 'n1',
      userId: 'NURSE-A',
      deviceId: 'INSOLE-001',
      displayName: 'A. Fernandes',
      ward: 'General Ward',
      scenario: 'Normal – steady standing',
      accentColor: Color(0xFF2E7D6B),
      sampleDataAsset: 'assets/sample_shift_nurseA.json',
    ),
    NurseUser(
      username: 'n2',
      userId: 'NURSE-B',
      deviceId: 'INSOLE-002',
      displayName: 'B. Shetty',
      ward: 'ICU',
      scenario: 'Normal – active walking',
      accentColor: Color(0xFF3B5BDB),
      sampleDataAsset: 'assets/sample_shift_nurseB.json',
    ),
    NurseUser(
      username: 'n3',
      userId: 'NURSE-C',
      deviceId: 'INSOLE-003',
      displayName: 'C. Rao',
      ward: 'Emergency',
      scenario: 'Normal – borderline values',
      accentColor: Color(0xFF7048E8),
      sampleDataAsset: 'assets/sample_shift_nurseC.json',
    ),
    NurseUser(
      username: 'n4',
      userId: 'NURSE-D',
      deviceId: 'INSOLE-004',
      displayName: 'D. Pinto',
      ward: 'Surgical Ward',
      scenario: 'Heel pressure rising',
      accentColor: Color(0xFFB4530A),
      sampleDataAsset: 'assets/sample_shift_nurseD.json',
    ),
    NurseUser(
      username: 'n5',
      userId: 'NURSE-E',
      deviceId: 'INSOLE-005',
      displayName: 'E. Kamath',
      ward: 'Orthopedics',
      scenario: 'Midfoot pressure rising',
      accentColor: Color(0xFF0C8599),
      sampleDataAsset: 'assets/sample_shift_nurseE.json',
    ),
    NurseUser(
      username: 'n6',
      userId: 'NURSE-F',
      deviceId: 'INSOLE-006',
      displayName: "F. D'Souza",
      ward: 'Pediatrics',
      scenario: 'Toe pressure rising',
      accentColor: Color(0xFFC2255C),
      sampleDataAsset: 'assets/sample_shift_nurseF.json',
    ),
    NurseUser(
      username: 'n7',
      userId: 'NURSE-G',
      deviceId: 'INSOLE-007',
      displayName: 'G. Bhat',
      ward: 'Cardiology',
      scenario: 'Temperature rising only',
      accentColor: Color(0xFFE8590C),
      sampleDataAsset: 'assets/sample_shift_nurseG.json',
    ),
    NurseUser(
      username: 'n8',
      userId: 'NURSE-H',
      deviceId: 'INSOLE-008',
      displayName: 'H. Nayak',
      ward: 'Operating Theatre',
      scenario: 'Prolonged standing (2h+)',
      accentColor: Color(0xFF5F3DC4),
      sampleDataAsset: 'assets/sample_shift_nurseH.json',
    ),
    NurseUser(
      username: 'n9',
      userId: 'NURSE-I',
      deviceId: 'INSOLE-009',
      displayName: 'I. Hegde',
      ward: 'Maternity',
      scenario: 'Heel pressure + temperature',
      accentColor: Color(0xFFA61E4D),
      sampleDataAsset: 'assets/sample_shift_nurseI.json',
    ),
    NurseUser(
      username: 'n10',
      userId: 'NURSE-J',
      deviceId: 'INSOLE-010',
      displayName: 'J. Salian',
      ward: 'Oncology',
      scenario: 'Alert, then recovery',
      accentColor: Color(0xFF2B8A3E),
      sampleDataAsset: 'assets/sample_shift_nurseJ.json',
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
