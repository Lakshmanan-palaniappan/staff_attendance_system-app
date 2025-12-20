import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/screens/login_screen.dart';
import '/screens/attendance_home.dart';
import '/screens/update_required_screen.dart';
import '../services/version_service.dart';
import '../services/api_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _loaderController;

  late Animation<double> _logoScale;
  late Animation<double> _logoFade;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _logoScale = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutCubic),
    );

    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeIn),
    );

    _loaderController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _logoController.forward();
    _runStartupFlow();
  }

  Future<void> _runStartupFlow() async {
    final start = DateTime.now();

    try {
      // ---------------- VERSION CHECK ----------------
      final currentVersion = await VersionService.getCurrentVersion();
      String latestVersion;

      try {
        latestVersion = await ApiService.fetchLatestAppVersion();
      } catch (_) {
        latestVersion = currentVersion;
      }

      // Ensure splash stays for at least 5 seconds
      final elapsed = DateTime.now().difference(start);
      if (elapsed < const Duration(seconds: 5)) {
        await Future.delayed(const Duration(seconds: 5) - elapsed);
      }

      final prefs = await SharedPreferences.getInstance();
      final staffId = prefs.getInt("staffId");

      // 🔴 UPDATE REQUIRED → RESET DEVICE COUNT
      if (currentVersion.trim() != latestVersion.trim()) {
        if (staffId != null) {
          try {
            await ApiService.logout(staffId); // 🔴 reset DeviceCount
          } catch (_) {}
        }

        await prefs.clear();

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

      // ---------------- SESSION + DEVICE CHECK ----------------
      if (staffId != null) {
        try {
          final deviceCount = await ApiService.fetchDeviceCount(staffId);

          if (deviceCount > 1) {
            // 🔴 RESET DEVICE COUNT BEFORE CLEARING
            try {
              await ApiService.logout(staffId);
            } catch (_) {}

            await prefs.clear();

            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const LoginScreen(
                  forceMessage:
                  "Your account is already active on another device.\n\n"
                      "Please logout from the other device and try again.",
                ),
              ),
            );
            return;
          }

          // ✅ Valid session
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const AttendanceHome()),
          );
          return;
        } catch (_) {
          await prefs.clear();
        }
      }

      // No session → login
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _loaderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo.shade700,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: FadeTransition(
                  opacity: _logoFade,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: Container(
                      height: 120,
                      width: 120,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(18),
                      child: Image.asset(
                        "assets/icon/app_icon.png",
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Column(
              children: [
                RotationTransition(
                  turns: _loaderController,
                  child: const Icon(Icons.autorenew, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  "Verifying application integrity…",
                  style: TextStyle(color: Colors.white.withOpacity(0.8)),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
