import 'package:flutter/material.dart';

class UpdateRequiredScreen extends StatelessWidget {
  final String currentVersion;
  final String latestVersion;

  const UpdateRequiredScreen({
    super.key,
    required this.currentVersion,
    required this.latestVersion,
  });

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
              onPressed: () {
                // TODO: Open Play Store / download URL
                // e.g. launchUrl(Uri.parse("https://play.google.com/store/apps/details?id=your.package"));
              },
              child: const Text("Update Now"),
            ),
          ],
        ),
      ),
    );
  }
}
