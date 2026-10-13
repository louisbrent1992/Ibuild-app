import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../models/project.dart';

import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'intro_screen.dart';
import 'play_screen.dart';
import 'settings_screen.dart';
import 'testflight_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showIntroOnce(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the background: pick up Pro or projects changed on another device.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) AppScope.read(context).refreshAccount();
  }

  void _go(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    // The store tab follows the project: TestFlight for iOS, Play for Android.
    final android =
        AppScope.of(context).project?.platform == AppPlatform.android;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          DashboardScreen(
            onOpenTestFlight: () => _go(2),
            onOpenSettings: () => _go(3),
          ),
          const HistoryScreen(),
          android ? const PlayScreen() : const TestFlightScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _go,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle),
            label: 'Build',
          ),
          const NavigationDestination(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          android
              ? const NavigationDestination(
                  icon: Icon(Icons.shop_outlined),
                  selectedIcon: Icon(Icons.shop),
                  label: 'Play',
                )
              : const NavigationDestination(
                  icon: Icon(Icons.flight_takeoff_outlined),
                  selectedIcon: Icon(Icons.flight_takeoff),
                  label: 'TestFlight',
                ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
