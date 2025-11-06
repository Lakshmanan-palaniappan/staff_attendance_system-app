import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../widgets/attendance_toggle.dart';
import 'login_screen.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class AttendanceHome extends StatefulWidget {
  const AttendanceHome({super.key});

  @override
  State<AttendanceHome> createState() => _AttendanceHomeState();
}

class _AttendanceHomeState extends State<AttendanceHome> {
  bool isCheckedIn = false;
  bool isLoading = false;
  String status = "Initializing...";
  int? staffId;
  String name = "";
  String idCard = "";
  List<dynamic> records = [];
  IO.Socket? socket;
  Timer? _longPressTimer;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    staffId = prefs.getInt("staffId");
    if (staffId != null) {
      _connectSocket();
      await _loadStaffDetails();
      await _refreshAttendance();
    } else {
      setState(() => status = "⚠️ No staff ID found. Please login again.");
    }
  }

  void _connectSocket() {
    socket = IO.io(backendBaseUrl,
        IO.OptionBuilder().setTransports(['websocket']).build());
    socket!.emit("register_staff_socket", staffId);
    socket!.on("login_approved", (data) {
      setState(() {
        status = "✅ Login Approved! You can mark attendance now.";
      });
    });
  }

  Future<void> _loadStaffDetails() async {
    try {
      final staff = await ApiService.getStaffDetails(staffId!);
      setState(() {
        name = staff["Name"] ?? "";
        idCard = staff["IdCardNumber"] ?? "";
      });
    } catch (e) {
      setState(() => status = "Failed to load staff details: $e");
    }
  }

  Future<void> _refreshAttendance() async {
    try {
      final data = await ApiService.getTodayAttendance(staffId!);
      setState(() {
        records = data;
        if (records.isNotEmpty) {
          isCheckedIn = records.first["CheckType"].toLowerCase() == "checkin";
        }
      });
    } catch (e) {
      setState(() => status = "Error fetching attendance: $e");
    }
  }

  Future<void> _markAttendance() async {
    setState(() {
      isLoading = true;
      status = "📍 Scanning your location...";
    });

    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => status = "❌ Location permission denied");
        return;
      }

      final pos =
          await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final res =
          await ApiService.markAttendance(staffId!, pos.latitude, pos.longitude);

      setState(() {
        isCheckedIn = res["currentStatus"] == "checkin";
        status = res["message"];
      });
      await _refreshAttendance();
    } catch (e) {
      setState(() => status = "Error: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const LoginRegisterScreen()));
    }
  }

  void _startLogoutTimer() {
    _longPressTimer = Timer(const Duration(seconds: 5), () => _logout());
  }

  void _cancelLogoutTimer() {
    _longPressTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Attendance")),
      drawer: Drawer(
        child: ListView(
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(name.isEmpty ? "Staff Member" : name),
              accountEmail: Text("ID: $idCard"),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, color: Colors.indigo),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text("Logout"),
              onTap: _logout,
            ),
          ],
        ),
      ),
      body: GestureDetector(
        onLongPressStart: (_) => _startLogoutTimer(),
        onLongPressEnd: (_) => _cancelLogoutTimer(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _staffCard(),
              const SizedBox(height: 20),
              AttendanceToggle(
                isCheckedIn: isCheckedIn,
                isLoading: isLoading,
                onPressed: _markAttendance,
              ),
              const SizedBox(height: 20),
              const Divider(),
              const Text("Today's Attendance",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Expanded(
                child: records.isEmpty
                    ? const Center(child: Text("No attendance records today"))
                    : ListView.builder(
                        itemCount: records.length,
                        itemBuilder: (_, i) {
                          final r = records[i];
                          return ListTile(
                            leading: Icon(
                              r["CheckType"].toLowerCase() == "checkin"
                                  ? Icons.login
                                  : Icons.logout,
                              color: r["CheckType"].toLowerCase() == "checkin"
                                  ? Colors.green
                                  : Colors.red,
                            ),
                            title: Text(r["CheckType"]),
                            subtitle: Text("Time: ${r["Timestamp"] ?? ''}"),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _staffCard() {
    final bgColor = isCheckedIn ? Colors.green.shade100 : Colors.grey.shade200;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: Colors.indigo,
                child: Icon(Icons.person, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isNotEmpty ? name : "Loading...",
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text("ID Card: ${idCard.isNotEmpty ? idCard : 'Fetching...'}",
                        style: const TextStyle(color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          Text(
            "Status: $status",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isCheckedIn ? Colors.green.shade800 : Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }
}
