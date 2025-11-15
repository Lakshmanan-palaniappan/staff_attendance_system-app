import 'package:flutter/material.dart';
import '/screens/splash_screen.dart';

void main() {
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
