import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateRequiredScreen extends StatelessWidget {
  final String currentVersion;
  final String latestVersion;

  const UpdateRequiredScreen({
    super.key,
    required this.currentVersion,
    required this.latestVersion,
  });

  Future<void> _openUpdateLink(BuildContext context) async {
    final Uri url = Uri.parse(
      "https://drive.google.com/drive/folders/1Ub4C8fM8XUz6h4X1feSDLJqRWE1jG0Jh?usp=sharing",
    );

    try {
      // 1️⃣ Try opening in external app (browser / Drive)
      bool launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );

      // 2️⃣ Fallback: open inside app using browser view (Chrome Custom Tab / in-app browser)
      if (!launched) {
        launched = await launchUrl(
          url,
          mode: LaunchMode.inAppBrowserView,
        );
      }

      // 3️⃣ If still not launched, show error
      if (!launched) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unable to open update link.")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error opening link: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Update Required")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.system_update, size: 80),
            const SizedBox(height: 16),
            const Text(
              "A new version of the app is available.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              "Current version: $currentVersion\nLatest version: $latestVersion",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _openUpdateLink(context),
              child: const Text("Update Now"),
            ),
          ],
        ),
      ),
    );
  }
}
