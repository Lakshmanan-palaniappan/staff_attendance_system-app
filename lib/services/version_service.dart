// lib/services/version_service.dart
import 'package:package_info_plus/package_info_plus.dart';

class VersionService {
  static Future<String> getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version; // e.g. "1.0.5"
  }
}
