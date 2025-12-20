import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../services/api_service.dart';
import '../services/version_service.dart';
import 'attendance_home.dart';
import 'update_required_screen.dart';

class LoginScreen extends StatefulWidget {
  /// Optional message passed from Splash (e.g. device already active)
  final String? forceMessage;

  const LoginScreen({
    super.key,
    this.forceMessage,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool isLoading = false;
  bool _obscurePass = true;
  bool _deviceBlocked = false;

  String status = "";
  int? pendingStaffId;
  Timer? pollTimer;

  /* ------------------------------------------------------------
   * INIT
   * ------------------------------------------------------------ */
  @override
  void initState() {
    super.initState();

    if (widget.forceMessage != null) {
      _deviceBlocked = true;
      status = widget.forceMessage!;
    }

    _restorePendingLogin();
  }

  /* ------------------------------------------------------------
   * RESTORE PENDING LOGIN (APP REOPEN)
   * ------------------------------------------------------------ */
  Future<void> _restorePendingLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getInt("pendingStaffId");

    if (savedId == null) return;

    pendingStaffId = savedId;
    setState(() => status = "Checking previous login request…");
    _checkStatusManual();
  }

  /* ------------------------------------------------------------
   * SUBMIT LOGIN
   * ------------------------------------------------------------ */
  Future<void> _submit() async {
    if (_deviceBlocked) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
      status = "";
    });

    try {
      final username =
      _usernameController.text.trim().replaceAll(" ", "");
      final appVersion = await VersionService.getCurrentVersion();

      final res = await ApiService.loginRequest(
        username,
        _passwordController.text.trim(),
        appVersion,
      );

      pendingStaffId = int.tryParse(res["staffId"].toString());
      if (pendingStaffId == null) {
        throw Exception("Invalid staff ID returned");
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt("pendingStaffId", pendingStaffId!);

      setState(() {
        status = res["message"] ?? "Waiting for admin approval…";
      });

      _snack("Waiting for admin approval…");
      _startPolling();
    } catch (e) {
      final msg = _cleanError(e);

      // 🚫 DEVICE LIMIT
      if (msg.contains("DEVICE_LIMIT")) {
        setState(() {
          _deviceBlocked = true;
          isLoading = false; // 🔴 CRITICAL FIX
          status =
          "Your account is already active on another device.\n\n"
              "Please logout from the other device and try again.";
        });

        _snack(status, error: true);
        return;
      }

      // ⬆️ OUTDATED APP
      if (msg.contains("OUTDATED_APP")) {
        final currentVersion =
        await VersionService.getCurrentVersion();
        final latestVersion =
        await ApiService.fetchLatestAppVersion();

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

      _snack(msg, error: true);
      setState(() => status = msg);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /* ------------------------------------------------------------
   * POLLING
   * ------------------------------------------------------------ */
  void _startPolling() {
    pollTimer?.cancel();
    if (pendingStaffId == null) return;

    pollTimer = Timer.periodic(
      const Duration(seconds: 5),
          (_) => _checkStatusManual(),
    );
  }

  Future<void> _checkStatusManual() async {
    if (pendingStaffId == null) return;

    try {
      final resp =
      await ApiService.checkLoginStatus(pendingStaffId!);

      if (resp == "Approved") {
        pollTimer?.cancel();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt("staffId", pendingStaffId!);
        await prefs.remove("pendingStaffId");

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AttendanceHome()),
        );
      } else {
        setState(() => status = "Status: $resp");
      }
    } catch (e) {
      setState(() => status = _cleanError(e));
    }
  }

  /* ------------------------------------------------------------
   * UTILITIES
   * ------------------------------------------------------------ */
  String _cleanError(e) =>
      e.toString().replaceFirst("Exception:", "").trim();

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;

    final color =
    error ? Colors.red.shade600 : Colors.green.shade600;
    final icon =
    error ? Icons.error_outline : Icons.check_circle_outline;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
          duration: const Duration(seconds: 3),
          content: Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    msg,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
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

  /* ------------------------------------------------------------
   * UI
   * ------------------------------------------------------------ */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1F3C88), Color(0xFF4B6CB7)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    const Text(
                      "e-Attendance",
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 32),

                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 40,
                            offset: const Offset(0, 20),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _usernameController,
                              decoration: _field("Username"),
                              validator: (v) =>
                              v == null || v.isEmpty ? "Required" : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePass,
                              decoration: _field(
                                "Password",
                                suffix: IconButton(
                                  icon: Icon(
                                    _obscurePass
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                  onPressed: () => setState(
                                          () => _obscurePass = !_obscurePass),
                                ),
                              ),
                              validator: (v) =>
                              v == null || v.isEmpty ? "Required" : null,
                            ),
                            const SizedBox(height: 24),

                            SizedBox(
                              height: 52,
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo
                                ),
                                onPressed:
                                isLoading || _deviceBlocked ? null : _submit,
                                child: isLoading
                                    ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                                    : const Text("Login",style: TextStyle(
                                  color: Colors.white
                                ),),
                              ),
                            ),

                            // ✅ ALWAYS SHOW RETRY WHEN BLOCKED
                            if (_deviceBlocked) ...[
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.refresh),
                                label: const Text(
                                    "I logged out from other device"),
                                onPressed: () {
                                  setState(() {
                                    _deviceBlocked = false;
                                    status = "";
                                  });
                                  _snack("You can try logging in again.");
                                },
                              ),
                            ],

                            if (pendingStaffId != null)
                              TextButton(
                                onPressed: _checkStatusManual,
                                child:
                                const Text("Refresh approval status"),
                              ),

                            if (status.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  status,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _deviceBlocked
                                        ? Colors.red
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _field(String label, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      suffixIcon: suffix,
    );
  }
}
