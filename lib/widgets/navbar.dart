import 'package:flutter/material.dart';

import '../screens/dashboard.dart';
import '../screens/kantor.dart';
import '../screens/pinjaman.dart';
import '../theme/app.dart';

enum AppTab { dashboard, kantor, pinjaman, akun }

class AppNavBar extends StatelessWidget {
  const AppNavBar({super.key, required this.currentTab});

  final AppTab currentTab;

  static const double iconLabelGap = 2;

  void _handleTap(BuildContext context, AppTab selected) {
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
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const PinjamanScreen()),
        );
        break;
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
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border(
          top: BorderSide(color: AppColors.outline.withValues(alpha: 0.15)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _navItem(
              context,
              tab: AppTab.dashboard,
              outlinedIcon: Icons.dashboard_outlined,
              filledIcon: Icons.dashboard,
              label: 'Dashboard',
            ),
            _navItem(
              context,
              tab: AppTab.kantor,
              outlinedIcon: Icons.apartment_outlined,
              filledIcon: Icons.apartment,
              label: 'Kantor',
            ),
            _navItem(
              context,
              tab: AppTab.pinjaman,
              outlinedIcon: Icons.credit_score_outlined,
              filledIcon: Icons.credit_score,
              label: 'Pinjaman',
            ),
            _navItem(
              context,
              tab: AppTab.akun,
              outlinedIcon: Icons.person_outline,
              filledIcon: Icons.person,
              label: 'Akun',
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(
    BuildContext context, {
    required AppTab tab,
    required IconData outlinedIcon,
    required IconData filledIcon,
    required String label,
  }) {
    final selected = tab == currentTab;
    final color = selected ? AppColors.primary : AppColors.onSurfaceVariant;

    return Expanded(
      child: InkWell(
        onTap: () => _handleTap(context, tab),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? filledIcon : outlinedIcon, size: 22, color: color),
            SizedBox(height: iconLabelGap),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}