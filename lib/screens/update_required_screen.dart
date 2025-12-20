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
      bool launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        launched = await launchUrl(
          url,
          mode: LaunchMode.inAppBrowserView,
        );
      }

      if (!launched) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Unable to open update link."),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error opening link: $e"),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // 🔒 Force update — disable back button
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: Colors.indigo.shade700,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Card(
                elevation: 14,
                shadowColor: Colors.black26,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ───────── ICON ─────────
                      Container(
                        height: 72,
                        width: 72,
                        decoration: BoxDecoration(
                          color: Colors.indigo.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.system_update_alt_rounded,
                          size: 38,
                          color: Colors.indigo,
                        ),
                      ),

                      const SizedBox(height: 22),

                      // ───────── TITLE ─────────
                      const Text(
                        "Update Required",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const SizedBox(height: 10),

                      // ───────── DESCRIPTION ─────────
                      Text(
                        "We’ve made improvements and added new features to "
                            "enhance your experience with e-Attendance.\n\n"
                            "Please update the app to continue.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: Colors.grey.shade700,
                        ),
                      ),

                      const SizedBox(height: 22),

                      // ───────── VERSION INFO ─────────
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            _versionRow(
                              label: "Installed Version",
                              value: currentVersion,
                              isLatest: false,
                            ),
                            const SizedBox(height: 10),
                            _versionRow(
                              label: "Latest Version",
                              value: latestVersion,
                              isLatest: true,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 26),

                      // ───────── UPDATE BUTTON ─────────
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          label: const Text(
                            "Update Now",
                            style: TextStyle(fontSize: 16,color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () => _openUpdateLink(context),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ───────── FOOTER NOTE ─────────
                      Text(
                        "Updating ensures access to the latest features and improvements.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Version Row Widget
  // ─────────────────────────────────────────────
  Widget _versionRow({
    required String label,
    required String value,
    required bool isLatest,
  }) {
    return Row(
      children: [
        Icon(
          isLatest ? Icons.check_circle : Icons.info_outline,
          size: 18,
          color: isLatest ? Colors.green : Colors.orange,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isLatest ? Colors.green : Colors.black,
          ),
        ),
      ],
    );
  }
}
