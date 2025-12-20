import 'dart:convert';
import 'package:http/http.dart' as http;

const String backendBaseUrl = "http://103.207.1.87:3030";

/// --------- MODELS FOR ATTENDANCE STATUS ---------
class EmpStatus {
  final String? empName;
  final String? department;
  final bool attdCompleted;
  final bool semPlanCompleted;

  EmpStatus({
    this.empName,
    this.department,
    required this.attdCompleted,
    required this.semPlanCompleted,
  });

  factory EmpStatus.fromJson(Map<String, dynamic> json) {
    return EmpStatus(
      empName: json['empName'] as String?,
      department: json['department'] as String?,
      attdCompleted: (json['attdCompleted'] ?? false) as bool,
      semPlanCompleted: (json['semPlanCompleted'] ?? false) as bool,
    );
  }
}

class MarkAttendanceResult {
  final bool success;              // true = 200 OK, false = error
  final String message;            // success message or error message
  final String? currentStatus;     // "checkin" / "checkout" (may be null on error)
  final EmpStatus? empStatus;      // null if not returned
  final List<String> pendingTasks; // only on error (or empty)
  final int cooldownMinutesLeft;   // minutes remaining before next allowed check-in

  MarkAttendanceResult({
    required this.success,
    required this.message,
    this.currentStatus,
    this.empStatus,
    this.pendingTasks = const [],
    this.cooldownMinutesLeft = 0,
  });
}

/// --------- API SERVICE ---------
class ApiService {
  /// POST /auth/login-request
  static Future<Map<String, dynamic>> loginRequest(
      String username,
      String password,
      String appVersion,
      ) async {
    final res = await http.post(
      Uri.parse("$backendBaseUrl/auth/login-request"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "usernameOrId": username.trim(),
        "password": password.trim(),
        "appVersion": appVersion.trim(), // NEW
      }),
    );
    return _handleResponse(res);
  }

  /// GET /auth/check-status/:staffId
  static Future<String> checkLoginStatus(int staffId) async {
    final res = await http.get(
      Uri.parse("$backendBaseUrl/auth/check-status/$staffId"),
      headers: {"Content-Type": "application/json"},
    );
    final data = jsonDecode(res.body);
    if (res.statusCode == 200) return data["status"];
    throw Exception(data["error"] ?? "Failed to get status");
  }

  /// POST /attendance/mark
  ///
  /// NOTE: this does NOT use _handleResponse because we want
  /// to keep error body (pendingTasks, empStatus, cooldown) instead of throwing.
  static Future<MarkAttendanceResult> markAttendance(
      int staffId,
      double lat,
      double lng,
      ) async {
    final res = await http.post(
      Uri.parse("$backendBaseUrl/attendance/mark"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "staffId": staffId,
        "lat": lat,
        "lng": lng,
      }),
    );

    Map<String, dynamic> data = {};
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      // if parse fails, treat as generic error
      return MarkAttendanceResult(
        success: false,
        message: "Unexpected server response",
        currentStatus: null,
        empStatus: null,
        pendingTasks: const [],
        cooldownMinutesLeft: 0,
      );
    }

    // Try to read cooldown from multiple possible keys, default 0
    int _parseCooldown(dynamic raw) {
      if (raw == null) return 0;
      if (raw is int) return raw;
      if (raw is double) return raw.toInt();
      return int.tryParse(raw.toString()) ?? 0;
    }

    final int cooldown = _parseCooldown(
      data['cooldownMinutesLeft'] ?? data['cooldown'] ?? data['cooldownMinutes'],
    );

    if (res.statusCode == 200) {
      // SUCCESS → checkin / checkout
      final empJson = data['empStatus'];
      final empStatus =
      empJson is Map<String, dynamic> ? EmpStatus.fromJson(empJson) : null;

      return MarkAttendanceResult(
        success: true,
        message: data['message']?.toString() ?? "Attendance marked",
        currentStatus: data['currentStatus']?.toString(),
        empStatus: empStatus,
        pendingTasks: const [],
        cooldownMinutesLeft: cooldown,
      );
    } else {
      // ERROR → we still want pendingTasks & empStatus & cooldown
      final List<String> pending = (data['pendingTasks'] as List? ?? [])
          .map((e) => e.toString())
          .toList();

      final empJson = data['empStatus'];
      final empStatus =
      empJson is Map<String, dynamic> ? EmpStatus.fromJson(empJson) : null;

      return MarkAttendanceResult(
        success: false,
        message: data['error']?.toString() ?? "Failed to mark attendance",
        currentStatus: data['currentStatus']?.toString(),
        empStatus: empStatus,
        pendingTasks: pending,
        cooldownMinutesLeft: cooldown,
      );
    }
  }

  /// GET /staff/attendance/today/:staffId
  static Future<List<dynamic>> getTodayAttendance(int staffId) async {
    final res = await http.get(
      Uri.parse("$backendBaseUrl/staff/attendance/today/$staffId"),
      headers: {"Content-Type": "application/json"},
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception("Failed to load attendance");
  }

  /// GET /staff/me/:staffId
  static Future<Map<String, dynamic>> getMyProfile(int staffId) async {
    final res = await http.get(
      Uri.parse("$backendBaseUrl/staff/me/$staffId"),
      headers: {"Content-Type": "application/json"},
    );
    final data = jsonDecode(res.body);
    if (res.statusCode == 200) return data;
    throw Exception(data["error"] ?? "Failed to load profile");
  }

  /// GET /staff/attendance/pairs/:staffId
  static Future<List<dynamic>> getAttendancePairs(int staffId) async {
    final res = await http.get(
      Uri.parse("$backendBaseUrl/staff/attendance/pairs/$staffId"),
      headers: {"Content-Type": "application/json"},
    );

    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception("Failed to load attendance pairs");
  }

  /// GET /staff/attendance/all/:staffId
  static Future<List<dynamic>> getAttendanceAll(int staffId) async {
    final res = await http.get(
      Uri.parse("$backendBaseUrl/staff/attendance/all/$staffId"),
      headers: {"Content-Type": "application/json"},
    );

    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception("Failed to load full attendance");
  }

  /// GET /app/latest-version
  static Future<String> fetchLatestAppVersion() async {
    final res = await http.get(
      Uri.parse("$backendBaseUrl/app/latest-version"),
      headers: {"Content-Type": "application/json"},
    );

    final data = jsonDecode(res.body);
    if (res.statusCode == 200 && data["latestVersion"] != null) {
      return data["latestVersion"] as String;
    }
    throw Exception(data["error"] ?? "Failed to get latest version");
  }

  /// generic handler for other endpoints
  static Map<String, dynamic> _handleResponse(http.Response res) {
    final data = jsonDecode(res.body);

    // ⬆️ App update required
    if (res.statusCode == 426) {
      throw Exception(
        data["errorCode"] ??
            data["message"] ??
            data["error"] ??
            "OUTDATED_APP",
      );
    }

    // 🚫 Device limit reached (EXPLICIT)
    if (res.statusCode == 409 &&
        data["errorCode"] == "DEVICE_LIMIT_REACHED") {
      throw Exception("DEVICE_LIMIT_REACHED");
    }

    // ✅ Success
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Map<String, dynamic>.from(data);
    }

    // ⛔ Other errors
    throw Exception(
      data["message"] ??
          data["error"] ??
          "Something went wrong",
    );
  }


  static Future<int> fetchDeviceCount(int staffId) async {
    final res = await http.get(
      Uri.parse("$backendBaseUrl/auth/device-count/$staffId"),
      headers: {"Content-Type": "application/json"},
    );

    final data = jsonDecode(res.body);
    if (res.statusCode == 200 && data["deviceCount"] != null) {
      return data["deviceCount"] as int;
    }

    throw Exception(data["error"] ?? "Failed to fetch device count");
  }
  static Future<void> logout(int staffId) async {
    await http.post(
      Uri.parse("$backendBaseUrl/auth/logout"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({ "staffId": staffId }),
    );
  }



}
