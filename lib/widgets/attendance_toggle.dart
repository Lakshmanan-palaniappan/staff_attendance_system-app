import 'package:flutter/material.dart';

class AttendanceToggle extends StatelessWidget {
  final bool isCheckedIn;
  final bool isLoading;
  final VoidCallback? onPressed; // nullable → disabled when null

  const AttendanceToggle({
    super.key,
    required this.isCheckedIn,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDisabled = onPressed == null || isLoading;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isDisabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          elevation: isDisabled ? 0 : 3,
          backgroundColor: isDisabled
              ? Colors.grey.shade400
              : (isCheckedIn ? Colors.red : Colors.green),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: isLoading
            ? const SizedBox(
          height: 22,
          width: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        )
            : Text(
          isCheckedIn ? "Check Out" : "Check In",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isDisabled ? Colors.white70 : Colors.white,
          ),
        ),
      ),
    );
  }
}
