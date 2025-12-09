import 'package:flutter/material.dart';
import 'package:staff_attendace_system/services/version_check.dart';
import '/screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await printVersion();
  runApp(const StaffAttendanceApp());
}

class StaffAttendanceApp extends StatelessWidget {
  const StaffAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Staff Attendance",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
      ),
      home: const SplashScreen(),
    );
  }
}
