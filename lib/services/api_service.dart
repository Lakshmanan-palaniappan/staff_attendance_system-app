import 'dart:convert';
import 'package:http/http.dart' as http;


const String backendBaseUrl = "http://103.207.1.87:3030";
class ApiService {
  /// 🔐 REQUEST LOGIN APPROVAL
  /// Sends a login request — admin must approve before the user can proceed
  
  static Future<Map<String, dynamic>> loginRequest(String usernameOrId, String password) async {
    final res = await http.post(
      Uri.parse("$backendBaseUrl/auth/login-request"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "usernameOrId": usernameOrId.trim(),
        "password": password.trim(),
      }),
    );
    return _handleResponse(res);
  }

  /// 🧾 REGISTER NEW STAFF
  /// Creates a new staff account (immediately redirected to login screen)
  static Future<Map<String, dynamic>> register(
      String name, String username, String password, String idCardNumber) async {
    final res = await http.post(
      Uri.parse("$backendBaseUrl/auth/register"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "name": name.trim(),
        "username": username.trim(),
        "password": password.trim(),
        "idCardNumber": idCardNumber.trim(),
      }),
    );
    return _handleResponse(res);
  }

  /// 📍 MARK ATTENDANCE (check-in or check-out based on backend logic)
  static Future<Map<String, dynamic>> markAttendance(int staffId, double lat, double lng) async {
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

  /// 📅 GET TODAY'S ATTENDANCE RECORDS
  static Future<List<dynamic>> getTodayAttendance(int staffId) async {
    final res = await http.get(
      Uri.parse("$backendBaseUrl/attendance/today/$staffId"),
      headers: {"Content-Type": "application/json"},
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    } else {
      throw Exception("Failed to load today's attendance");
    }
  }

  /// 👤 GET STAFF DETAILS (by staffId)
  /// 👤 GET STAFF DETAILS (by staffId)
static Future<Map<String, dynamic>> getStaffDetails(int staffId) async {
  final res = await http.get(
    Uri.parse("$backendBaseUrl/staff/$staffId"),
    headers: {"Content-Type": "application/json"},
  );

  final data = jsonDecode(res.body);
  if (res.statusCode == 200) {
    return Map<String, dynamic>.from(data);
  } else {
    throw Exception(data["error"] ?? "Failed to load staff details");
  }
}


  /// ⚙️ Common response handler
  static Map<String, dynamic> _handleResponse(http.Response res) {
    final data = jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Map<String, dynamic>.from(data);
    } else {
      throw Exception(data["error"] ?? "Something went wrong");
    }
  }
}


// static Future<Map<String, dynamic>> getStaffDetails({int? staffId, String? usernameOrId}) async {
// String url = "$backendBaseUrl/staff";
// if (staffId != null) {
// url += "/$staffId";
// } else if (usernameOrId != null) {
// url += "?usernameOrId=$usernameOrId";
// } else {
// throw Exception("Provide staffId or usernameOrId");
// }
//
// final res = await http.get(Uri.parse(url), headers: {"Content-Type": "application/json"});
// final data = jsonDecode(res.body);
// if (res.statusCode == 200) return data;
// throw Exception(data["error"] ?? "Failed to fetch staff details");
// }
