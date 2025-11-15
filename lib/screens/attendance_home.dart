import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../services/api_service.dart';
import '../widgets/attendance_toggle.dart';
import 'login_screen.dart';

class AttendanceHome extends StatefulWidget {
  const AttendanceHome({super.key});

  @override
  State<AttendanceHome> createState() => _AttendanceHomeState();
}

class _AttendanceHomeState extends State<AttendanceHome> {
  bool isCheckedIn = false;
  bool isLoading = false;

  String status = "Loading...";
  String lastUpdated = "-";

  int? staffId;
  String displayName = "";
  String displayId = "";

  List<dynamic> today = [];
  List<dynamic> pairs = [];
  List<dynamic> history = [];

  // Utility
  String _clean(e) => e.toString().replaceFirst("Exception:", "").trim();

  Future<void> _vibrate({bool error = false}) async {
    if (await Vibration.hasVibrator() ?? false) {
      await Vibration.vibrate(duration: error ? 200 : 80);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _initLoad();
  }

  Future<void> _initLoad() async {
    final prefs = await SharedPreferences.getInstance();
    staffId = prefs.getInt("staffId");

    if (staffId == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    await _loadProfile();
    await _refreshAll();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await ApiService.getMyProfile(staffId!);

      setState(() {
        displayName = data["username"] ?? "Staff";
        displayId = (data["staffId"] ?? "").toString();
      });
    } catch (e) {
      _snack(_clean(e), error: true);
    }
  }

  Future<void> _refreshAll() async {
    await _loadToday();
    await _loadPairs();
    await _loadHistory();
  }

  // ========================== LOAD TODAY ==========================
  Future<void> _loadToday() async {
    try {
      today = await ApiService.getTodayAttendance(staffId!);

      if (today.isNotEmpty) {
        isCheckedIn = today.first["CheckType"].toLowerCase() == "checkin";
        status = isCheckedIn ? "Checked In" : "Not Checked In";
      } else {
        isCheckedIn = false;
        status = "No check-in yet";
      }

      setState(() {});
    } catch (e) {
      _snack(_clean(e), error: true);
    }
  }

  // ========================== LOAD WORK HOURS ==========================
  Future<void> _loadPairs() async {
    try {
      pairs = await ApiService.getAttendancePairs(staffId!);
      setState(() {});
    } catch (e) {
      _snack(_clean(e), error: true);
    }
  }

  // ========================== LOAD FULL HISTORY ==========================
  Future<void> _loadHistory() async {
    try {
      history = await ApiService.getAttendanceAll(staffId!);
      setState(() {});
    } catch (e) {
      _snack(_clean(e), error: true);
    }
  }

  // ========================== MARK ATTENDANCE ==========================
  Future<void> _manualMark() async {
    setState(() {
      isLoading = true;
      status = "Getting location…";
    });

    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        throw Exception("Location permission denied");
      }

      final pos = await Geolocator.getCurrentPosition();

      final res = await ApiService.markAttendance(
        staffId!,
        pos.latitude,
        pos.longitude,
      );

      status = res["message"];
      lastUpdated = TimeOfDay.now().format(context);

      await _refreshAll();
      await _vibrate();
      _snack(status);
    } catch (e) {
      final msg = _clean(e);
      await _vibrate(error: true);
      _snack(msg, error: true);
      status = msg;
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  // ========================== UI ==========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Attendance")),
      drawer: Drawer(
        child: ListView(
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(displayName),
              accountEmail: Text("ID: $displayId"),
              currentAccountPicture: const CircleAvatar(
                child: Icon(Icons.person, color: Colors.white),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text("Logout"),
              onTap: _logout,
            )
          ],
        ),
      ),

      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _profileCard(),
                        const SizedBox(height: 20),

                        AttendanceToggle(
                          isCheckedIn: isCheckedIn,
                          isLoading: isLoading,
                          onPressed: _manualMark,
                        ),

                        const SizedBox(height: 20),
                        _todaySummaryCard(),

                        const SizedBox(height: 12),
                        _workHoursCard(),

                        const SizedBox(height: 12),
                        _fullHistoryList(),   // ❗ Removed Expanded here
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (isLoading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 4),
              ),
            ),
        ],
      ),

    );
  }

  // ======================= CARD: PROFILE =======================
  Widget _profileCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: isCheckedIn ? Colors.green : Colors.indigo,
              child: const Icon(Icons.person, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  Text("ID: $displayId"),
                  const SizedBox(height: 6),
                  Text("Status: $status"),
                  Text("Last Updated: $lastUpdated"),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ======================= CARD: TODAY SUMMARY =======================
  Widget _todaySummaryCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Today's Logs",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            if (today.isEmpty)
              const Text("No records yet"),

            ...today.map((r) {
              return ListTile(
                leading: Icon(
                  r["CheckType"] == "checkin"
                      ? Icons.login
                      : Icons.logout,
                  color: r["CheckType"] == "checkin"
                      ? Colors.green
                      : Colors.red,
                ),
                title: Text(r["CheckType"].toUpperCase()),
                subtitle: Text(r["Timestamp"]),
              );
            })
          ],
        ),
      ),
    );
  }

  // ======================= CARD: WORK HOURS =======================
  // ======================= CARD: WORK HOURS (With Date Chips) =======================
  Widget _workHoursCard() {
    if (pairs.isEmpty) {
      return Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Text("No work hours recorded yet"),
        ),
      );
    }

    /// 1️⃣ Group by date
    Map<String, List<dynamic>> grouped = {};

    for (var p in pairs) {
      String date = p["Date"] ?? "--";
      grouped.putIfAbsent(date, () => []);
      grouped[date]!.add(p);
    }

    Duration grandTotal = Duration.zero;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Work Hours",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            /// 🔥 2️⃣ Chip List for all dates
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: grouped.keys.map((date) {
                return Chip(
                  label: Text(
                    date,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  avatar: const Icon(Icons.calendar_today, size: 18),
                  backgroundColor: Colors.indigo.shade50,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 10),

            /// 🔥 3️⃣ Build logs for each date
            ...grouped.entries.map((entry) {
              String date = entry.key;
              List<dynamic> logs = entry.value;

              Duration totalForDay = Duration.zero;
              List<Widget> logWidgets = [];

              for (var row in logs) {
                DateTime? ci = row["CheckInTime"] != null
                    ? DateTime.parse(row["CheckInTime"])
                    : null;

                DateTime? co = row["CheckOutTime"] != null
                    ? DateTime.parse(row["CheckOutTime"])
                    : null;

                Duration diff = Duration.zero;
                if (ci != null && co != null) {
                  diff = co.difference(ci);
                  totalForDay += diff;
                  grandTotal += diff;
                }

                String worked = (ci != null && co != null)
                    ? "${diff.inHours}h ${diff.inMinutes % 60}m"
                    : "—";

                logWidgets.add(
                  ListTile(
                    leading: const Icon(Icons.access_time),
                    title: Text("Check-in: ${row["CheckInTime"] ?? "-"}"),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Check-out: ${row["CheckOutTime"] ?? "-"}"),
                        Text("Worked: $worked"),
                      ],
                    ),
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),

                  /// 🔥 DATE HEADING
                  Text(
                    date,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo),
                  ),
                  const SizedBox(height: 6),

                  ...logWidgets,

                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 10),
                    child: Text(
                      "Daily Total: ${totalForDay.inHours}h ${totalForDay.inMinutes % 60}m",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ),

                  const Divider(),
                ],
              );
            }).toList(),

            const SizedBox(height: 12),

            /// 🔥 GRAND TOTAL
            Text(
              "GRAND TOTAL: ${grandTotal.inHours}h ${grandTotal.inMinutes % 60}m",
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ],
        ),
      ),
    );
  }



  // ======================= FULL HISTORY LIST =======================
  Widget _fullHistoryList() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Full Attendance History",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            SizedBox(
              height: 300,   // 🔥 Fixed height so ListView can render safely
              child: history.isEmpty
                  ? const Center(child: Text("No history found"))
                  : ListView.builder(
                itemCount: history.length,
                itemBuilder: (_, i) {
                  final r = history[i];
                  return ListTile(
                    leading: Icon(
                      r["CheckType"] == "checkin"
                          ? Icons.login
                          : Icons.logout,
                      color: r["CheckType"] == "checkin"
                          ? Colors.green
                          : Colors.red,
                    ),
                    title: Text(r["CheckType"]),
                    subtitle: Text(r["Timestamp"]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

}
