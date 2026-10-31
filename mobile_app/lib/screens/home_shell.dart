import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/shift_repository.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';

class HomeShell extends StatefulWidget {
  final AuthService authService;
  const HomeShell({super.key, required this.authService});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late Future<ShiftData> _shiftFuture;

  @override
  void initState() {
    super.initState();
    _shiftFuture = ShiftRepository.loadShift(widget.authService.currentUser!);
  }

  void _retry() {
    setState(() {
      _shiftFuture = ShiftRepository.loadShift(widget.authService.currentUser!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.authService.currentUser!;

    return FutureBuilder<ShiftData>(
      future: _shiftFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Could not load this nurse\'s shift data.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _retry,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final shift = snapshot.data!;
        return Scaffold(
          // IndexedStack keeps the dashboard's playback position when you
          // switch to another tab and back.
          body: IndexedStack(
            index: _index,
            children: [
              DashboardScreen(user: user, shift: shift),
              HistoryScreen(user: user, shift: shift),
              ProfileScreen(user: user, authService: widget.authService),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history),
                label: 'History',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        );
      },
    );
  }
}
