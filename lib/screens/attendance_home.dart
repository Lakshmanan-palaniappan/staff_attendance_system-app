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
  String appVersion = "-"; // Installed version
  String serverVersion = "-"; // Version stored in DB for this staff
  String? department;        // Department for drawer / profile

  List<dynamic> today = [];
  List<dynamic> pairs = [];
  List<dynamic> history = [];

  // Cooldown (real-time)
  Timer? _cooldownTimer;
  int _cooldownMinutesLeft = 0;

  // Selected date in Work Hours card
  String? _selectedWorkDate;

  // Key for persisting cooldown end-time in SharedPreferences
  static const String _cooldownEndKey = "cooldownEndTime";

  static const String _lastCheckTypeKey = "lastCheckType"; // "checkin" / "checkout"

  // Restore last known check-in/out from storage (for smoother initial UI)
  Future<void> _restoreCheckStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final type = prefs.getString(_lastCheckTypeKey);

    if (type == "checkin" || type == "checkout") {
      setState(() {
        isCheckedIn = (type == "checkin");
        status = type == "checkin" ? "Checked In" : "Checked Out";
      });
    }
  }

  // Save check-in/out type to storage (null = clear)
  Future<void> _saveCheckStatus(String? type) async {
    final prefs = await SharedPreferences.getInstance();
    if (type == null || type.isEmpty) {
      await prefs.remove(_lastCheckTypeKey);
    } else {
      await prefs.setString(_lastCheckTypeKey, type);
    }
  }

  // ---------- TIME HELPERS ----------

  /// Parse ISO string (possibly with Z) and return local DateTime, or null.
  DateTime? _parseIsoToLocal(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    try {
      final dt = DateTime.parse(iso); // parses as UTC if has 'Z'
      return dt.toLocal();            // convert to device local time (IST etc.)
    } catch (_) {
      return null;
    }
  }

  /// Return only time like "09:57 PM" from ISO string, localised.
  // ---------- TIME HELPERS (ASSUME SERVER TIME IS LOCAL IST) ----------

  /// Parse ISO string like "2025-12-09T21:57:39.413Z"
  /// treating it as LOCAL time (ignore Z / timezone).
  DateTime? _parseServerLocal(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    try {
      var s = iso.trim();

      // Remove trailing 'Z' or offset, so DateTime.parse treats it as local
      if (s.endsWith('Z')) {
        s = s.substring(0, s.length - 1); // drop 'Z'
      }

      // You can also strip explicit offsets if your backend ever sends them.
      // Simple defensive cut:
      // e.g. 2025-12-09T21:57:39+05:30 -> 2025-12-09T21:57:39
      final plusIndex = s.indexOf('+', 10);
      final minusIndex = s.indexOf('-', 10);
      final tzIndex = (plusIndex == -1)
          ? minusIndex
          : (minusIndex == -1 ? plusIndex : plusIndex < minusIndex ? plusIndex : minusIndex);
      if (tzIndex != -1) {
        s = s.substring(0, tzIndex);
      }

      return DateTime.parse(s); // parsed as LOCAL time
    } catch (_) {
      return null;
    }
  }

  /// Return only time like "09:57 PM" from server ISO, assuming local.
  String _formatTimeShort(String? iso) {
    final dt = _parseServerLocal(iso);
    if (dt == null) return "-";
    return TimeOfDay.fromDateTime(dt).format(context);
  }

  /// Return "YYYY-MM-DD HH:mm" from server ISO, assuming local.
  String _formatDateTimeShort(String? iso) {
    final dt = _parseServerLocal(iso);
    if (dt == null) return iso ?? "-";

    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');

    return "$y-$m-$d $hh:$mm";
  }



  // Utility
  String _clean(e) => e.toString().replaceFirst("Exception:", "").trim();

  bool get _hasVersionMismatch {
    if (appVersion == "-" || serverVersion == "-") return false;
    return appVersion.trim() != serverVersion.trim();
  }

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
    await _restoreCooldown();     // restore cooldown from previous app state
    await _restoreCheckStatus();  // restore last check-in/out for smoother UI
    await _refreshAll();          // will sync from server
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
      // IMPORTANT: only auto-mark if there is NO log for today
      // (i.e., first check-in of the day). This prevents random check-outs.
      if (today.isNotEmpty || isCheckedIn) {
        return;
      }

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

      // apply any empStatus data (including department) from this response
      _applyEmpStatus(result.empStatus);

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

        // Try multiple keys for department (depends on your API)
        final depRaw = data["department"] ??
            data["Department"] ??
            data["dept"] ??
            data["Dept"] ??
            data["departmentName"];

        department = depRaw?.toString();
        debugPrint("Dept from profile: $department");

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

  // ========================== RESTORE COOLDOWN FROM STORAGE ==========================
  Future<void> _restoreCooldown() async {
    final prefs = await SharedPreferences.getInstance();
    final endStr = prefs.getString(_cooldownEndKey);

    if (endStr == null) return;

    final end = DateTime.tryParse(endStr);
    if (end == null) {
      await prefs.remove(_cooldownEndKey);
      return;
    }

    final remaining = end.difference(DateTime.now()).inMinutes;

    if (remaining > 0) {
      _startCooldownTimer(remaining);
    } else {
      await prefs.remove(_cooldownEndKey);
    }
  }

  // ========================== LOAD TODAY ==========================
  Future<void> _loadToday() async {
    try {
      today = await ApiService.getTodayAttendance(staffId!);

      if (today.isNotEmpty) {
        // Ensure latest first (DESC by timestamp)
        today.sort((a, b) {
          final ta = DateTime.tryParse(a["Timestamp"].toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final tb = DateTime.tryParse(b["Timestamp"].toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return tb.compareTo(ta);
        });

        final latest = today.first;
        final lastType = latest["CheckType"].toString().toLowerCase();

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

        // Save this latest type so we can restore it quickly on next launch
        await _saveCheckStatus(lastType);

        // Use local time, nicely formatted
        lastUpdated = _formatTimeShort(latest["Timestamp"]?.toString());
      } else {
        isCheckedIn = false;
        status = "No check-in yet";
        lastUpdated = "-";

        // Clear stored status if no logs for today
        await _saveCheckStatus(null);
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

  // ========================== APPLY EMP STATUS TO STATE ==========================
  void _applyEmpStatus(EmpStatus? emp) {
    if (emp == null) return;

    if (emp.department != null &&
        emp.department!.isNotEmpty &&
        emp.department != department) {
      setState(() {
        department = emp.department;
      });
      debugPrint("Dept synced from EmpStatus: $department");
    }
  }

  // ========================== COOLDOWN TIMER (PERSISTED) ==========================
  void _startCooldownTimer(int minutes) async {
    _cooldownTimer?.cancel();

    if (minutes <= 0) {
      setState(() {
        _cooldownMinutesLeft = 0;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cooldownEndKey);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final end = DateTime.now().add(Duration(minutes: minutes));

    // Save cooldown end time so it survives app restart
    await prefs.setString(_cooldownEndKey, end.toIso8601String());

    setState(() {
      _cooldownMinutesLeft = minutes;
    });

    _cooldownTimer = Timer.periodic(const Duration(seconds: 30), (t) async {
      final diff = end.difference(DateTime.now());
      final m = diff.inMinutes;

      if (m <= 0) {
        t.cancel();
        await prefs.remove(_cooldownEndKey);
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
  void _showEmpStatusSheet(MarkAttendanceResult result,
      {bool isError = false}) {
    final emp = result.empStatus;
    final pending = result.pendingTasks;

    // sync dept from empStatus into screen state
    _applyEmpStatus(emp);

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

      // sync empStatus (for department) from this call
      _applyEmpStatus(result.empStatus);

      if (result.success) {
        // ✅ Any successful check-in/out cancels cooldown and clears storage
        _cooldownTimer?.cancel();
        _cooldownMinutesLeft = 0;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_cooldownEndKey);

        final s = (result.currentStatus ?? "").toLowerCase();

        if (s == "checkin") {
          isCheckedIn = true;
          status = "Checked In";
        } else if (s == "checkout") {
          isCheckedIn = false;
          status = "Checked Out";
        } else {
          status = "Updated";
        }

        // Persist last known status
        await _saveCheckStatus(s);

        lastUpdated = TimeOfDay.now().format(context);

        await _refreshAll();
        await _vibrate();
        _snack(result.message);

        _showEmpStatusSheet(result, isError: false);
      }
    else {
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

  // Wrapper used by the button
  void _handleAttendanceButton() {
    // If in cooldown, do NOT call API – just show feedback
    if (_cooldownMinutesLeft > 0) {
      _vibrate(error: true);
      _snack(
        "You are in cooldown. You can check in again after about $_cooldownMinutesLeft minute(s).",
        error: true,
      );
      return;
    }

    // Fire async mark call
    _manualMark();
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

  // ========================== COOLDOWN BANNER ==========================
  Widget _cooldownBanner() {
    if (_cooldownMinutesLeft <= 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer, size: 22, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "You are in cooldown.\nNext check-in in about $_cooldownMinutesLeft minute(s).",
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========================== UI ==========================
  @override
  Widget build(BuildContext context) {
    final bool inCooldown = _cooldownMinutesLeft > 0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("My Attendance"),
            Text(
              status,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // -------- CUSTOM CLASSIC HEADER (NO OVERFLOW) --------
              Container(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.white.withOpacity(0.15),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            displayName.isEmpty ? "Staff" : displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Department: ${department ?? "-"}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.85),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.phone_android,
                                size: 14,
                                color: Colors.white.withOpacity(0.8),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                appVersion,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(
                                Icons.cloud,
                                size: 14,
                                color: Colors.white.withOpacity(0.8),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                serverVersion,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                            ],
                          ),
                          if (_hasVersionMismatch) ...[
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  size: 16,
                                  color: Colors.amber,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    "Update available. Please install latest app.",
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.amber.shade100,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              ListTile(
                leading: const Icon(Icons.today_outlined),
                title: const Text("Today"),
                subtitle: const Text("View today’s check-ins/outs"),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text("Work Hours"),
                subtitle: const Text("Summary of your work duration"),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text("Full History"),
                subtitle: const Text("All attendance logs"),
                onTap: () {
                  Navigator.pop(context);
                },
              ),

              const Divider(),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text("Refresh data"),
                onTap: () async {
                  Navigator.pop(context);
                  await _refreshAll();
                  _snack("Data refreshed");
                },
              ),

              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text("Logout"),
                onTap: _logout,
              ),
            ],
          ),
        ),
      ),

      body: Stack(
        children: [
          Column(
            children: [
              if (inCooldown) _cooldownBanner(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _profileCard(),
                        const SizedBox(height: 20),

                        AttendanceToggle(
                          isCheckedIn: isCheckedIn,
                          isLoading: isLoading,
                          onPressed: _cooldownMinutesLeft > 0
                              ? null
                              : _handleAttendanceButton,
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
              ),
            ],
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
                  if (department != null && department!.isNotEmpty)
                    Text(
                      department!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text("Status: $status"),
                  Text("Last Updated: $lastUpdated"),
                  if (_cooldownMinutesLeft > 0)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "Next check-in in ~ $_cooldownMinutesLeft min",
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
            const Text(
              "Today's Logs",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // ---- FIXED HEIGHT SCROLL VIEW ----
            SizedBox(
              height: 180, // <-- Adjust height as needed (150 / 200 / 250)
              child: today.isEmpty
                  ? const Center(child: Text("No records yet"))
                  : ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: today.length,
                itemBuilder: (context, i) {
                  final r = today[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      r["CheckType"] == "checkin"
                          ? Icons.login
                          : Icons.logout,
                      color: r["CheckType"] == "checkin"
                          ? Colors.green
                          : Colors.red,
                    ),
                    title: Text(
                      r["CheckType"].toString().toUpperCase(),
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      _formatDateTimeShort(
                        r["Timestamp"]?.toString(),
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 2,
                      horizontal: 4,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }


  // ======================= CARD: WORK HOURS (with horizontal chips + date picker) =======================
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

    // Group by date
    final Map<String, List<dynamic>> grouped = {};

    for (var p in pairs) {
      final String date = p["Date"] ?? "--";
      grouped.putIfAbsent(date, () => []);
      grouped[date]!.add(p);
    }

    // Sort dates: recent → older
    final List<String> sortedDates = grouped.keys.toList();

    sortedDates.sort((a, b) {
      DateTime? da = DateTime.tryParse(a);
      DateTime? db = DateTime.tryParse(b);
      if (da != null && db != null) return db.compareTo(da); // desc
      return b.compareTo(a);
    });

    // Determine selected date (default = most recent)
    final String selectedDate =
    _selectedWorkDate != null && grouped.containsKey(_selectedWorkDate)
        ? _selectedWorkDate!
        : sortedDates.first;

    final List<dynamic> logsForSelected = grouped[selectedDate] ?? [];

    // Compute daily total for selected date
    Duration totalForDay = Duration.zero;

    // Compute grand total across all dates
    Duration grandTotal = Duration.zero;
    for (final logs in grouped.values) {
      for (var row in logs) {
        DateTime? ci = row["CheckInTime"] != null
            ? _parseServerLocal(row["CheckInTime"]?.toString())
            : null;

        DateTime? co = row["CheckOutTime"] != null
            ? _parseServerLocal(row["CheckOutTime"]?.toString())
            : null;

        if (ci != null && co != null) {
          grandTotal += co.difference(ci);
        }
      }
    }

    List<Widget> logTiles = [];
    for (var row in logsForSelected) {
      DateTime? ci = row["CheckInTime"] != null
          ? _parseServerLocal(row["CheckInTime"]?.toString())
          : null;

      DateTime? co = row["CheckOutTime"] != null
          ? _parseServerLocal(row["CheckOutTime"]?.toString())
          : null;

      Duration diff = Duration.zero;
      if (ci != null && co != null) {
        diff = co.difference(ci);
        totalForDay += diff;
      }

      String worked = (ci != null && co != null)
          ? "${diff.inHours}h ${diff.inMinutes % 60}m"
          : "—";

      logTiles.add(
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          leading: const Icon(Icons.access_time),
          title: Text(
            "Check-in: ${_formatDateTimeShort(row["CheckInTime"]?.toString())}",
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Check-out: ${_formatDateTimeShort(row["CheckOutTime"]?.toString())}",
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                "Worked: $worked",
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  "Work Hours",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.calendar_today, size: 20),
                  onPressed: () async {
                    DateTime initial = DateTime.now();
                    DateTime? parsedSelected = DateTime.tryParse(selectedDate);
                    if (parsedSelected != null) initial = parsedSelected;

                    final picked = await showDatePicker(
                      context: context,
                      initialDate: initial,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );

                    if (picked != null) {
                      final pickStr =
                          picked.toIso8601String().split("T").first;
                      String? match = sortedDates.firstWhere(
                            (d) => d.startsWith(pickStr),
                        orElse: () => "",
                      );
                      if (match.isNotEmpty) {
                        setState(() {
                          _selectedWorkDate = match;
                        });
                      } else {
                        _snack("No records for selected date");
                      }
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Horizontally scrollable chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: sortedDates.map((date) {
                  final bool isSelected = date == selectedDate;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        date,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() {
                          _selectedWorkDate = date;
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 12),
            const Divider(),

            Text(
              "Logs for $selectedDate",
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 6),

            // ---- FIXED HEIGHT SCROLL AREA FOR LOGS ----
            SizedBox(
              height: 220, // adjust as you like (e.g. 200/240)
              child: logsForSelected.isEmpty
                  ? const Center(child: Text("No records for this date"))
                  : ListView(
                padding: EdgeInsets.zero,
                children: logTiles,
              ),
            ),

            const SizedBox(height: 8),
            Text(
              "Daily Total: ${totalForDay.inHours}h ${totalForDay.inMinutes % 60}m",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),

            const SizedBox(height: 8),
            Text(
              "GRAND TOTAL (all days): ${grandTotal.inHours}h ${grandTotal.inMinutes % 60}m",
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
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
            const Text(
              "Full Attendance History",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // ---- FIXED HEIGHT SCROLL AREA ----
            SizedBox(
              height: 260, // tune this as you like (240/280)
              child: history.isEmpty
                  ? const Center(child: Text("No history found"))
                  : ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: history.length,
                itemBuilder: (_, i) {
                  final r = history[i];
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 2,
                      horizontal: 4,
                    ),
                    leading: Icon(
                      r["CheckType"] == "checkin"
                          ? Icons.login
                          : Icons.logout,
                      color: r["CheckType"] == "checkin"
                          ? Colors.green
                          : Colors.red,
                    ),
                    title: Text(
                      r["CheckType"].toString().toUpperCase(),
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      _formatDateTimeShort(r["Timestamp"]?.toString()),
                      style: const TextStyle(fontSize: 12),
                    ),
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
