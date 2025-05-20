// ota_screen.dart
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import '/global.dart';
import '/ble_provider.dart';

import '/widgets/background.dart';
import '/widgets/section.dart';
import '/widgets/status_indicators.dart';

class OTAScreen extends StatefulWidget {
  const OTAScreen({super.key});

  @override
  OTAScreenState createState() => OTAScreenState();
}

class OTAScreenState extends State<OTAScreen>
    with AutomaticKeepAliveClientMixin {
  final Logger logger = Logger();
  bool _isChecking = false;
  bool _isUpdating = false;
  List<String> logs = [];
  BLEProvider get bleProvider =>
      Provider.of<BLEProvider>(context, listen: false);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    otaScreenState = this;
  }

  void logMessage(String message) {
    setState(() {
      logs.add(message);
    });
  }

  void startOtaProcess() {
    setState(() {
      _isUpdating = true;
      logs.clear();
    });
    bleProvider.sendCommand("CMD:OTA_START;");
  }

  void checkForUpdate() {
    setState(() {
      _isChecking = true;
      logs.clear();
    });
    // Checks the internet for an update for the boards;
  }

  void handleOtaStatusUpdate(String status) {
    logMessage(status);
    if (status.contains("Finished") ||
        status.contains("failed") ||
        status.contains("low")) {
      setState(() {
        _isUpdating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: Stack(
        children: [
          const Background(),
          Padding(
            padding: const EdgeInsets.all(5.0),
            child: Column(
              children: [
                const SizedBox(height: 20),
                context.watch<BLEProvider>().isConnected
                    ? buildControlScreen()
                    : bleProvider.buildDeviceList(),
                const SizedBox(height: 20),
                const StatusIndicators(),
                const SizedBox(height: 10), // Add some space at the bottom
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildControlScreen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Section(
          title: 'OTA Controls',
          content: Column(
            children: [
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _isChecking ? null : checkForUpdate,
                child: const Text("Check for Update"),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _isUpdating ? null : startOtaProcess,
                child: const Text("Start Board Update"),
              ),
              const SizedBox(height: 10),
              const Divider(thickness: 1.5),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  "Update Log",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8.0, vertical: 2.0),
                    child: Text(
                      logs[index],
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
