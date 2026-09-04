import 'package:flutter/material.dart';

import '../screens/dashboard.dart';
import '../screens/kantor.dart';

enum AppTab { dashboard, kantor, pinjaman, akun }

class AppNavBar extends StatelessWidget {
  const AppNavBar({super.key, required this.currentTab});

  final AppTab currentTab;

  void _handleTap(BuildContext context, int index) {
    final selected = AppTab.values[index];
    if (selected == currentTab) return;

    switch (selected) {
      case AppTab.dashboard:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
        break;
      case AppTab.kantor:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const KantorScreen()),
        );
        break;
      case AppTab.pinjaman:
      case AppTab.akun:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Menu ini belum tersedia'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentTab.index,
      onDestinationSelected: (index) => _handleTap(context, index),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Dashboard',
        ),
        NavigationDestination(
          icon: Icon(Icons.apartment_outlined),
          selectedIcon: Icon(Icons.apartment),
          label: 'Kantor',
        ),
        NavigationDestination(
          icon: Icon(Icons.credit_score_outlined),
          selectedIcon: Icon(Icons.credit_score),
          label: 'Pinjaman',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Akun',
        ),
      ],
    );
  }
}