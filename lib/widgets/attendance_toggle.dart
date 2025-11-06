import 'package:flutter/material.dart';

class AttendanceToggle extends StatelessWidget {
  final bool isCheckedIn;
  final bool isLoading;
  final VoidCallback onPressed;

  const AttendanceToggle({
    super.key,
    required this.isCheckedIn,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      )
          : Icon(isCheckedIn ? Icons.logout : Icons.login, color: Colors.white),
      label: Text(
        isLoading
            ? "Processing..."
            : (isCheckedIn ? "Check Out" : "Check In"),
        style: const TextStyle(fontSize: 16, color: Colors.white),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: isCheckedIn ? Colors.red : Colors.green,
        minimumSize: const Size(180, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
    );
  }
}
