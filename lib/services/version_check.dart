import 'package:package_info_plus/package_info_plus.dart';

Future<void> printVersion() async {
  final info = await PackageInfo.fromPlatform();
  print("APP VERSION = ${info.version}");
}
