import 'package:flutter/material.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(SoleGuardApp(authService: AuthService()));
}

class SoleGuardApp extends StatelessWidget {
  final AuthService authService;
  const SoleGuardApp({super.key, required this.authService});

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
      home: LoginScreen(authService: authService),
    );
  }
}
