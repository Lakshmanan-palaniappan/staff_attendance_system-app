import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../services/api_service.dart';
import 'attendance_home.dart';

class LoginRegisterScreen extends StatefulWidget {
  const LoginRegisterScreen({super.key});

  @override
  State<LoginRegisterScreen> createState() => _LoginRegisterScreenState();
}

class _LoginRegisterScreenState extends State<LoginRegisterScreen> {
  bool isLogin = true;
  bool isLoading = false;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _idCardController = TextEditingController();
  final _passwordController = TextEditingController();
  String status = "";
  IO.Socket? socket;

  Future<void> _connectSocket(int staffId) async {
    socket = IO.io(backendBaseUrl, IO.OptionBuilder().setTransports(['websocket']).build());
    socket!.onConnect((_) {
      socket!.emit("register_staff_socket", staffId);
    });
    socket!.on("login_approved", (_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt("staffId", staffId);
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AttendanceHome()));
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
      status = "";
    });

    try {
      if (isLogin) {
        final res = await ApiService.loginRequest(
          _usernameController.text,
          _passwordController.text,
        );

        setState(() => status = res["message"] ?? "Waiting for admin approval...");

        if (res["staffId"] != null) {
          await _connectSocket(res["staffId"]);
        }
      } else {
        final res = await ApiService.register(
          _nameController.text,
          _usernameController.text,
          _passwordController.text,
          _idCardController.text,
        );

        setState(() {
          status = res["message"] ?? "Registered successfully!";
          isLogin = true;
        });
      }
    } catch (e) {
      setState(() => status = e.toString());
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    socket?.dispose();
    super.dispose();
  }

  String? _validateRequired(String? v) => v == null || v.isEmpty ? "Required" : null;
  String? _validatePassword(String? v) => v != null && v.length < 6 ? "Min 6 chars" : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isLogin ? "Login" : "Register")),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Text(
                    isLogin ? "Welcome Back!" : "Create an Account",
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  if (!isLogin)
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: "Full Name", hintText: "John Doe"),
                      validator: _validateRequired,
                    ),
                  TextFormField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: isLogin ? "Username / ID Card" : "Username",
                      hintText: isLogin ? "Enter your username or ID" : "Choose a username",
                    ),
                    validator: _validateRequired,
                  ),
                  if (!isLogin)
                    TextFormField(
                      controller: _idCardController,
                      decoration: const InputDecoration(labelText: "ID Card Number", hintText: "e.g. 12345"),
                      validator: _validateRequired,
                    ),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: "Password", hintText: "At least 6 characters"),
                    validator: _validatePassword,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      backgroundColor: Colors.indigo,
                    ),
                    child: isLoading
                        ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                    )
                        : Text(isLogin ? "Login" : "Register", style: const TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => setState(() {
                      isLogin = !isLogin;
                      status = "";
                    }),
                    child: Text(isLogin
                        ? "Don't have an account? Register"
                        : "Already registered? Login"),
                  ),
                  if (status.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        status,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
