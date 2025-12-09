import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import '../services/api_service.dart';
import 'attendance_home.dart';
import '../services/version_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool isLoading = false;
  bool _obscurePass = true;
  String status = "";
  int? pendingStaffId;
  Timer? pollTimer;

  String _cleanError(e) =>
      e.toString().replaceFirst("Exception:", "").trim();

  Future<void> _vibrate({bool error = false}) async {
    if (await Vibration.hasVibrator() ?? false) {
      await Vibration.vibrate(duration: error ? 200 : 60);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, textAlign: TextAlign.center),
        backgroundColor: error ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    pollTimer?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------
  // Polling Login Status
  // -----------------------------------------------------------
  void _startPolling() {
    pollTimer?.cancel();
    if (pendingStaffId == null) return;

    pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkStatusManual();
    });
  }

  // -----------------------------------------------------------
  // Manual refresh button → Check login request status
  // -----------------------------------------------------------
  Future<void> _checkStatusManual() async {
    if (pendingStaffId == null) return;

    try {
      final statusResp = await ApiService.checkLoginStatus(pendingStaffId!);
      setState(() => status = "Status: $statusResp");

      if (statusResp == "Approved") {
        pollTimer?.cancel();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt("staffId", pendingStaffId!);

        await _vibrate();
        if (!mounted) return;
        _snack("Login approved!");

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AttendanceHome()),
        );
      }
    } catch (e) {
      setState(() => status = _cleanError(e));
    }
  }

  // -----------------------------------------------------------
  // Submit Login Request
  // -----------------------------------------------------------
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
      status = "";
    });

    try {
      final usernameClean =
      _usernameController.text.trim().replaceAll(" ", "");

      // NEW: get current app version
      final appVersion = await VersionService.getCurrentVersion();

      final res = await ApiService.loginRequest(
        usernameClean,
        _passwordController.text.trim(),
        appVersion, // send version
      );

      pendingStaffId = int.tryParse(res["staffId"].toString());
      if (pendingStaffId == null) {
        throw Exception("Invalid staff ID returned from server");
      }

      status = res["message"] ?? "Login request sent";

      _snack("Waiting for admin approval…");
      _startPolling();
    } catch (e) {
      final msg = _cleanError(e);

      // If backend signalled outdated app
      if (msg.contains("OUTDATED_APP") ||
          msg.toLowerCase().contains("outdated")) {
        _snack(
          "Your app is outdated. Please update from Play Store / latest APK.",
          error: true,
        );
        setState(() {
          status = "App version is outdated. Please update.";
        });
      } else {
        await _vibrate(error: true);
        _snack(msg, error: true);
        setState(() => status = msg);
      }
    } finally {
      setState(() => isLoading = false);
    }
  }


  // -----------------------------------------------------------
  // UI
  // -----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 560;

    return Scaffold(
      resizeToAvoidBottomInset: true,   // ⭐ Prevent overflow with keyboard
      appBar: AppBar(title: const Text("Login")),
      body: SafeArea(
        child: SingleChildScrollView(   // ⭐ Allows scrolling when keyboard opens
          padding: EdgeInsets.all(isWide ? 24 : 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                elevation: 5,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWide ? 28 : 20,
                    vertical: 25,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "Staff Login",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 20),

                        // Username
                        TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: "Username",
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                          v == null || v.trim().isEmpty ? "Required" : null,
                        ),
                        const SizedBox(height: 12),

                        // Password
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePass,
                          decoration: InputDecoration(
                            labelText: "Password",
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePass
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () =>
                                  setState(() => _obscurePass = !_obscurePass),
                            ),
                          ),
                          validator: (v) =>
                          v == null || v.trim().isEmpty ? "Required" : null,
                        ),
                        const SizedBox(height: 20),

                        // Login Button
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: isLoading
                                ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                                : const Text(
                              "Login",
                              style: TextStyle(
                                  fontSize: 16, color: Colors.white),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Refresh Status Button
                        if (pendingStaffId != null)
                          SizedBox(
                            height: 45,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.refresh),
                              label: const Text("Refresh Status"),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.indigo),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _checkStatusManual,
                            ),
                          ),

                        if (status.isNotEmpty) const SizedBox(height: 12),

                        if (status.isNotEmpty)
                          Text(
                            status,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

}
