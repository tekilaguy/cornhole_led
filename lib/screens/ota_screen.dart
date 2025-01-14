// ota_screen.dart
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import '/widgets/background.dart';
import '/widgets/status_indicators.dart';

class OTAScreen extends StatefulWidget {
  const OTAScreen({super.key});

  @override
  OTAScreenState createState() => OTAScreenState();
}

class OTAScreenState extends State<OTAScreen> {
  bool isUpdating = false;
  String updateStatus = "No updates available.";
  final Logger logger = Logger();

  void checkForUpdates() async {
    setState(() {
      isUpdating = true;
      updateStatus = "Checking for updates...";
    });

    // Simulate checking for updates (replace with actual OTA logic)
    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      isUpdating = false;
      updateStatus = "Update available: Version 1.1.0";
    });
  }

  void startOTAUpdate() async {
    setState(() {
      isUpdating = true;
      updateStatus = "Starting update...";
    });

    // Simulate OTA update process (replace with actual OTA logic)
    await Future.delayed(const Duration(seconds: 5));

    setState(() {
      isUpdating = false;
      updateStatus = "Update complete. Restarting device...";
    });

    // Simulate device restart
    await Future.delayed(const Duration(seconds: 2));
    logger.i("Device restarted after OTA update.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("OTA Update"),
      ),
      body: Stack(
        children: [
          const Background(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                const Text(
                  "OTA Update",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Text(updateStatus),
                const SizedBox(height: 20),
                if (!isUpdating) ...[
                  ElevatedButton(
                    onPressed: checkForUpdates,
                    child: const Text("Check for Updates"),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: startOTAUpdate,
                    child: const Text("Start Update"),
                  ),
                ] else ...[
                  const CircularProgressIndicator(),
                ],
                const SizedBox(height: 20),
                const StatusIndicators(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
