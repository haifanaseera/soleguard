import 'package:flutter/material.dart';
import '../models/user.dart';

/// Local, offline authentication for demo purposes.
///
/// This intentionally does NOT call a real server. It checks credentials
/// against the demo nurses loaded from nurses.json, so the app works with
/// no network on demo day. The password is plain text in the source code,
/// so this must not be used for real patient data. For production, replace
/// [login] with a real authentication backend over HTTPS.
class AuthService extends ChangeNotifier {
  /// The demo nurses, in the order they appear in nurses.json.
  final List<NurseUser> users;

  AuthService(this.users);

  NurseUser? _currentUser;
  NurseUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  /// Demo password for a nurse: username n7 has password p7, n10 has p10.
  /// Short on purpose so it is quick to type during a demo.
  static String passwordFor(NurseUser user) =>
      'p${user.username.substring(1)}';

  /// Returns null on success, or an error message on failure.
  Future<String?> login(String username, String password) async {
    // Simulated delay so the loading state feels real.
    await Future.delayed(const Duration(milliseconds: 600));

    final key = username.trim().toLowerCase();

    if (key.isEmpty || password.isEmpty) {
      return 'Please enter both username and password.';
    }

    NurseUser? match;
    for (final u in users) {
      if (u.username == key) match = u;
    }

    if (match == null) {
      return 'No account found for "${username.trim()}".';
    }
    if (password != passwordFor(match)) {
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
