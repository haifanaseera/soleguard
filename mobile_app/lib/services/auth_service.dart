import 'package:flutter/material.dart';
import '../models/user.dart';

/// Local, offline authentication for demo purposes.
///
/// IMPORTANT FOR YOUR TEAM / DEMO NOTES:
/// This intentionally does NOT call a real server. It checks credentials
/// against a small local list so the app works with zero network dependency
/// on demo day (no wifi risk, no server downtime risk).
///
/// If this becomes a real product, swap `_login` for a real API call and
/// store the session using flutter_secure_storage instead of plain memory.
/// Nothing else in the app needs to change — screens only depend on
/// AuthService.currentUser, not on how login happens internally.
class AuthService extends ChangeNotifier {
  NurseUser? _currentUser;
  NurseUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  // Local demo accounts. Change these freely.
  static const Map<String, String> _credentials = {
    'nurse.a': 'password123',
    'nurse.b': 'password123',
    'nurse.c': 'password123',
  };

  static const Map<String, NurseUser> _users = {
    'nurse.a': NurseUser(
      userId: 'NURSE-A',
      displayName: 'A. Fernandes',
      ward: 'General Ward',
      accentColor: Color(0xFF2E7D6B),
      sampleDataAsset: 'assets/sample_shift_nurseA.json',
    ),
    'nurse.b': NurseUser(
      userId: 'NURSE-B',
      displayName: 'B. Shetty',
      ward: 'ICU',
      accentColor: Color(0xFF3B5BDB),
      sampleDataAsset: 'assets/sample_shift_nurseB.json',
    ),
    'nurse.c': NurseUser(
      userId: 'NURSE-C',
      displayName: 'C. Rao',
      ward: 'Emergency',
      accentColor: Color(0xFFB4530A),
      sampleDataAsset: 'assets/sample_shift_nurseC.json',
    ),
  };

  /// Returns null on success, or an error message on failure.
  Future<String?> login(String username, String password) async {
    // Simulated delay so the loading state feels real.
    await Future.delayed(const Duration(milliseconds: 700));

    final key = username.trim().toLowerCase();

    if (key.isEmpty || password.isEmpty) {
      return 'Please enter both username and password.';
    }
    if (!_credentials.containsKey(key)) {
      return 'No account found for "$username".';
    }
    if (_credentials[key] != password) {
      return 'Incorrect password.';
    }

    _currentUser = _users[key];
    notifyListeners();
    return null;
  }

  void logout() {
    _currentUser = null;
    notifyListeners();
  }
}
