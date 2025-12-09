import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
  String appVersion = "-";       // installed version (device)
  String serverVersion = "-";    // version stored in DB for this staff

  List<dynamic> today = [];
  List<dynamic> pairs = [];
  List<dynamic> history = [];

  // Cooldown (real-time)
  Timer? _cooldownTimer;
  int _cooldownMinutesLeft = 0;

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

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _initLoad() async {
    final prefs = await SharedPreferences.getInstance();
    staffId = prefs.getInt("staffId");

    if (staffId == null) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    await _loadAppVersion();
    await _loadProfile();
    await _refreshAll();
    await _autoMarkOnStart();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() {
        appVersion = info.version;
      });
    } catch (_) {
      // ignore, keep "-"
    }
  }

  Future<void> _autoMarkOnStart() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) return;

      final pos = await Geolocator.getCurrentPosition();

      final result = await ApiService.markAttendance(
        staffId!,
        pos.latitude,
        pos.longitude,
      );

      if (result.success && result.message.isNotEmpty) {
        _snack(result.message);
      }

      await _refreshAll();
    } catch (e) {
      // silently ignore for UX
    }
  }

  Future<void> _loadProfile() async {
    try {
      final data = await ApiService.getMyProfile(staffId!);
      debugPrint("PROFILE: $data");

      setState(() {
        displayName =
            (data["name"] ?? data["username"] ?? "Staff").toString();
        displayId = (data["staffId"] ?? "").toString();
        serverVersion = data["serverAppVersion"]?.toString() ?? "-";
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
        // backend orders DESC, so first = latest
        final lastType =
        today.first["CheckType"].toString().toLowerCase();

        if (lastType == "checkin") {
          isCheckedIn = true;
          status = "Checked In";
        } else if (lastType == "checkout") {
          isCheckedIn = false;
          status = "Checked Out";
        } else {
          isCheckedIn = false;
          status = "Status Unknown";
        }

        final last = today.last;
        try {
          final dt = DateTime.parse(last["Timestamp"].toString());
          lastUpdated = TimeOfDay.fromDateTime(dt).format(context);
        } catch (_) {
          lastUpdated = "-";
        }
      } else {
        isCheckedIn = false;
        status = "No check-in yet";
        lastUpdated = "-";
      }

      if (mounted) setState(() {});
    } catch (e) {
      _snack(_clean(e), error: true);
    }
  }

  // ========================== LOAD WORK HOURS ==========================
  Future<void> _loadPairs() async {
    try {
      pairs = await ApiService.getAttendancePairs(staffId!);
      if (mounted) setState(() {});
    } catch (e) {
      _snack(_clean(e), error: true);
    }
  }

  // ========================== LOAD FULL HISTORY ==========================
  Future<void> _loadHistory() async {
    try {
      history = await ApiService.getAttendanceAll(staffId!);
      if (mounted) setState(() {});
    } catch (e) {
      _snack(_clean(e), error: true);
    }
  }

  // ========================== COOLDOWN TIMER ==========================
  void _startCooldownTimer(int minutes) {
    _cooldownTimer?.cancel();

    if (minutes <= 0) {
      setState(() {
        _cooldownMinutesLeft = 0;
      });
      return;
    }

    final end = DateTime.now().add(Duration(minutes: minutes));

    setState(() {
      _cooldownMinutesLeft = minutes;
    });

    _cooldownTimer = Timer.periodic(const Duration(seconds: 30), (t) {
      final diff = end.difference(DateTime.now());
      final m = diff.inMinutes;

      if (m <= 0) {
        t.cancel();
        if (mounted) {
          setState(() {
            _cooldownMinutesLeft = 0;
          });
        }
      } else {
        if (mounted) {
          // +1 so user sees e.g. 5,4,3,2,1 instead of jumping early to 0
          setState(() {
            _cooldownMinutesLeft = m + 1;
          });
        }
      }
    });
  }

  // ========================== STATUS SHEET FOR EMP WORK FLAGS ==========================
  void _showEmpStatusSheet(MarkAttendanceResult result, {bool isError = false}) {
    final emp = result.empStatus;
    final pending = result.pendingTasks;

    // Use dynamic cooldown from state if available, else fallback to API value
    final int cooldown = _cooldownMinutesLeft > 0
        ? _cooldownMinutesLeft
        : result.cooldownMinutesLeft;

    final bool attdOk = emp?.attdCompleted ?? false;
    final bool semOk = emp?.semPlanCompleted ?? false;

    final bool hasPending = !attdOk || !semOk || pending.isNotEmpty;
    final bool isCooldownOnly = cooldown > 0 && !hasPending;
    final bool allWorkOk = !hasPending;

    IconData icon;
    Color color;
    String titleText;

    if (isCooldownOnly) {
      icon = Icons.info;
      color = Colors.blue;
      titleText = "Work status: All clear (cooldown)";
    } else if (allWorkOk) {
      icon = Icons.check_circle;
      color = Colors.green;
      titleText = "Work status: All clear";
    } else {
      icon = Icons.warning_amber_rounded;
      color = Colors.orange;
      titleText = "Work status: Pending items";
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.only(
                top: 16,
                left: 16,
                right: 16,
                bottom: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---------- HEADER ----------
                  Row(
                    children: [
                      Icon(icon, color: color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          titleText,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      )
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ---------- EMP BASIC INFO ----------
                  if (emp != null) ...[
                    if (emp.empName != null)
                      Text(
                        emp.empName!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (emp.department != null)
                      Text(
                        emp.department!,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    const SizedBox(height: 10),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          avatar: Icon(
                            attdOk ? Icons.check : Icons.close,
                            size: 18,
                            color: Colors.white,
                          ),
                          label: Text(
                            "Attendance: ${attdOk ? "Completed" : "Pending"}",
                            style: const TextStyle(color: Colors.white),
                          ),
                          backgroundColor:
                          attdOk ? Colors.green : Colors.redAccent,
                        ),
                        Chip(
                          avatar: Icon(
                            semOk ? Icons.check : Icons.close,
                            size: 18,
                            color: Colors.white,
                          ),
                          label: Text(
                            "Sem Plan: ${semOk ? "Completed" : "Pending"}",
                            style: const TextStyle(color: Colors.white),
                          ),
                          backgroundColor:
                          semOk ? Colors.green : Colors.redAccent,
                        ),
                      ],
                    ),
                  ],

                  // ---------- COOL DOWN INFO ----------
                  if (cooldown > 0) ...[
                    const SizedBox(height: 16),
                    const Text(
                      "Check-in cooldown",
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "You have recently checked out. "
                          "You can check in again after about $cooldown minute(s).",
                      style: const TextStyle(color: Colors.blueGrey),
                    ),
                  ],

                  // ---------- PENDING TASKS ----------
                  if (pending.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      "Pending tasks:",
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: pending
                          .map(
                            (p) => Chip(
                          label: Text(p),
                          backgroundColor: Colors.orange.shade100,
                        ),
                      )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ========================== MARK ATTENDANCE (MANUAL) ==========================
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

      final result = await ApiService.markAttendance(
        staffId!,
        pos.latitude,
        pos.longitude,
      );

      if (result.success) {
        // ✅ Any successful check-in/out cancels cooldown
        _cooldownTimer?.cancel();
        _cooldownMinutesLeft = 0;

        final s = (result.currentStatus ?? "").toLowerCase();
        if (s == "checkin") {
          status = "Checked In";
        } else if (s == "checkout") {
          status = "Checked Out";
        } else {
          status = "Updated";
        }

        lastUpdated = TimeOfDay.now().format(context);

        await _refreshAll();
        await _vibrate();
        _snack(result.message);

        _showEmpStatusSheet(result, isError: false);
      } else {
        // ❌ ERROR / BLOCKED
        final bool hasCooldownOnly =
            result.cooldownMinutesLeft > 0 && result.pendingTasks.isEmpty;

        if (hasCooldownOnly) {
          // start / refresh countdown from server value
          _startCooldownTimer(result.cooldownMinutesLeft);

          // compute value to show (prefer live countdown if already ticking)
          final int effectiveCooldown = _cooldownMinutesLeft > 0
              ? _cooldownMinutesLeft
              : result.cooldownMinutesLeft;

          // short status line
          status = "Cooldown: ~$effectiveCooldown min left";

          await _vibrate(error: true);
          _snack(
            "You can check in again after about $effectiveCooldown minute(s).",
            error: true,
          );

          // show sheet with cooldown + flags
          _showEmpStatusSheet(result, isError: true);
        } else {
          // other errors (pending work etc.)
          String shortStatus = "Action blocked";
          if (result.pendingTasks.isNotEmpty) {
            shortStatus = "Pending: ${result.pendingTasks.first}";
          }
          status = shortStatus;

          await _vibrate(error: true);
          _snack(result.message, error: true);
          _showEmpStatusSheet(result, isError: true);
        }
      }
    } catch (e) {
      final msg = _clean(e);
      await _vibrate(error: true);
      _snack(msg, error: true);
      status = "Error";
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (!mounted) return;
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
              accountEmail: Text(
                "Version (Device/Server): $appVersion / $serverVersion",
              ), // only version info
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
                        _fullHistoryList(),
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
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text("Status: $status"),
                  Text("Last Updated: $lastUpdated"),
                  if (_cooldownMinutesLeft > 0)
                    Text(
                      "Next check-in in ~ $_cooldownMinutesLeft min",
                      style: const TextStyle(color: Colors.blueGrey),
                    ),
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
                title: Text(r["CheckType"].toString().toUpperCase()),
                subtitle: Text(r["Timestamp"].toString()),
              );
            })
          ],
        ),
      ),
    );
  }

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
              height: 300,
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
                    title: Text(r["CheckType"].toString()),
                    subtitle: Text(r["Timestamp"].toString()),
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
