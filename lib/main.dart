import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const StaffFlowApp());
}

class StaffFlowApp extends StatelessWidget {
  // constructor
  const StaffFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'StaffFlow',
      home: const LoginScreen(),
    );
  }
}