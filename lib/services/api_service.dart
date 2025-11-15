import 'dart:convert';
import 'package:http/http.dart' as http;

const String backendBaseUrl = "http://103.207.1.87:3030";

class ApiService {
  /// POST /auth/login-request
  static Future<Map<String, dynamic>> loginRequest(
      String username, String password) async {
    final res = await http.post(
      Uri.parse("$backendBaseUrl/auth/login-request"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "usernameOrId": username.trim(),
        "password": password.trim(),
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
  static Future<Map<String, dynamic>> markAttendance(
      int staffId, double lat, double lng) async {
    final res = await http.post(
      Uri.parse("$backendBaseUrl/attendance/mark"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "staffId": staffId,
        "lat": lat,
        "lng": lng,
      }),
    );
    return _handleResponse(res);
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

  static Map<String, dynamic> _handleResponse(http.Response res) {
    final data = jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Map<String, dynamic>.from(data);
    } else {
      throw Exception(data["error"] ?? "Something went wrong");
    }
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

}


