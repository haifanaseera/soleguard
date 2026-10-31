import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class ProfileScreen extends StatelessWidget {
  final NurseUser user;
  final AuthService authService;
  const ProfileScreen({
    super.key,
    required this.user,
    required this.authService,
  });

  void _logout(BuildContext context) {
    authService.logout();
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: LoginScreen(authService: authService),
        ),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Profile',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: user.accentColor,
                    child: Text(
                      user.initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    user.displayName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${user.ward} • ${user.userId}',
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _DetailCard(
              title: 'Health profile',
              icon: Icons.favorite_border,
              rows: [
                ('Age', '${user.age}'),
                ('Gender', user.gender),
                ('Diabetes', '${user.diabetesType}, ${user.yearsWithDiabetes} years'),
                ('Foot sensation', user.footSensation),
                ('Other conditions', user.otherConditions),
                ('Years in nursing', '${user.yearsInNursing}'),
              ],
            ),
            _DetailCard(
              title: 'Device and demo',
              icon: Icons.sensors,
              rows: [
                ('Device ID', user.deviceId),
                ('Demo scenario', user.scenario),
                ('Data storage', 'Local only (demo mode), no cloud sync'),
              ],
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 16),
              child: Text(
                'Profiles and readings are simulated test data, not real people.',
                style: TextStyle(fontSize: 11.5, color: Colors.black45),
              ),
            ),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => _logout(context),
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text('Log out', style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<(String, String)> rows;
  const _DetailCard({
    required this.title,
    required this.icon,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF2E7D6B)),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      row.$1,
                      style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                    ),
                  ),
                  Expanded(
                    child: Text(row.$2, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
