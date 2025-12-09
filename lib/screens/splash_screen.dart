import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Simple screen to block outdated app
class UpdateRequiredScreen extends StatelessWidget {
  final String currentVersion;
  final String latestVersion;

  const UpdateRequiredScreen({
    super.key,
    required this.currentVersion,
    required this.latestVersion,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Update Required")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.system_update, size: 80),
            const SizedBox(height: 16),
            const Text(
              "A new version of the app is available.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              "Current version: $currentVersion\nLatest version: $latestVersion",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                // TODO: open Play Store / APK URL
                // e.g. launchUrl(Uri.parse("https://play.google.com/store/apps/details?id=your.package"));
              },
              child: const Text("Update Now"),
            ),
          ],
        ),
      ),
    );
  }
}
