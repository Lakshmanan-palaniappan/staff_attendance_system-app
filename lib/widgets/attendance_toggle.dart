import 'package:flutter/material.dart';

class AttendanceToggle extends StatelessWidget {
  final bool isCheckedIn;
  final bool isLoading;
  final VoidCallback? onPressed;

  /// Cooldown in SECONDS (0 = no cooldown)
  final int cooldownSeconds;

  const AttendanceToggle({
    super.key,
    required this.isCheckedIn,
    required this.isLoading,
    required this.onPressed,
    required this.cooldownSeconds,
  });

  String _formatCooldown(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    // 🔒 SNAPSHOT STATE — DO NOT READ isCheckedIn AGAIN
    final bool checkedIn = isCheckedIn;

    final bool cooldownActive = cooldownSeconds > 0;
    final bool disabled =
        isLoading || cooldownActive || onPressed == null;

    final Color bgColor = disabled
        ? Colors.grey.shade400
        : (checkedIn ? Colors.red : Colors.green);

    final String label = cooldownActive
        ? "WAIT ${_formatCooldown(cooldownSeconds)}"
        : (checkedIn ? "Check Out" : "Check In");

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: disabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          elevation: disabled ? 0 : 3,
          backgroundColor: bgColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _buildContent(label),
      ),
    );
  }

  Widget _buildContent(String label) {
    // ⏳ Loading spinner
    if (isLoading) {
      return const SizedBox(
        height: 22,
        width: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white,
        ),
      );
    }

    // ✅ Normal / Cooldown text
    return Text(
      label,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.4,
      ),
    );
  }
}
