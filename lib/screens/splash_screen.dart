import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staff_attendace_system/screens/update_required_screen.dart';

import '/screens/login_screen.dart';
import '/screens/attendance_home.dart';
import '../services/version_service.dart';
import '../services/api_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Future<void> checkLogin() async {
    try {
      // 1️⃣ Check app version against backend
      final currentVersion = await VersionService.getCurrentVersion();

      String latestVersion;
      try {
        latestVersion = await ApiService.fetchLatestAppVersion();
      } catch (_) {
        // If backend not reachable, you can either block or allow.
        // Here: allow by treating latest == current.
        latestVersion = currentVersion;
      }

      if (currentVersion.trim() != latestVersion.trim()) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => UpdateRequiredScreen(
              currentVersion: currentVersion,
              latestVersion: latestVersion,
            ),
          ),
        );
        return;
      }

      // 2️⃣ If version is OK → normal login check
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
    } catch (_) {
      // Fallback to login if something unexpected happens
      if (!mounted) return;
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

