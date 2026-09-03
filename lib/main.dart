import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/login.dart';
import 'theme/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://urkvmopbaclmuedvueze.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVya3Ztb3BiYWNsbXVlZHZ1ZXplIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgzOTM3OTIsImV4cCI6MjEwMzk2OTc5Mn0.fKirJt4m1pWs2cB7h-vHeSNYVio5MdLwsHHBv5MtsXI',
  );

  runApp(const FundMonitorApp());
}

class FundMonitorApp extends StatelessWidget {
  const FundMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FundMonitor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const LoginScreen(),
    );
  }
}