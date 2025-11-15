import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/screens/login_screen.dart';
import '/screens/attendance_home.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Future<void> checkLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final staffId = prefs.getInt("staffId");

    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;

    if (staffId != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AttendanceHome()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    checkLogin();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          color: Colors.indigo,
          strokeWidth: 4,
        ),
      ),
    );
  }
}
