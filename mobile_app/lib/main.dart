import 'package:flutter/material.dart';
import 'models/user.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/shift_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var users = <NurseUser>[];
  String? loadError;
  try {
    users = await ShiftRepository.loadNurses();
  } catch (e) {
    loadError = 'Could not load nurses.json: $e';
  }

  runApp(SoleGuardApp(authService: AuthService(users), loadError: loadError));
}

class SoleGuardApp extends StatelessWidget {
  final AuthService authService;
  final String? loadError;
  const SoleGuardApp({super.key, required this.authService, this.loadError});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SoleGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2E7D6B),
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: Color(0xFFDDEFE9),
        ),
      ),
      home: loadError != null
          ? Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    loadError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            )
          : LoginScreen(authService: authService),
    );
  }
}
