// ota_screen.dart
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import '/global.dart';
import '/ble_provider.dart';

import '/widgets/background.dart';
import '/widgets/section.dart';
import '/widgets/status_indicators.dart';

Future<Map<String, dynamic>> fetchUpdate() async {
var data;
final version = data['version'] ?? '';
latestFirmwareVersion = version;
  final response = await http.get(Uri.parse(
      'https://raw.githubusercontent.com/tekilaguy/cornhole_led/main/updates/cornhole_board_version.json'));
  if (response.statusCode == 200) {
    return json.decode(response.body);
  } else {
    throw Exception('Failed to load update');
  }
}

class Update {
  final String url;
  final String bin;
  final String version;

  const Update({required this.url, required this.bin, required this.version});

  factory Update.fromJson(Map<String, dynamic> json) {
    return Update(
      url: json['file_url'] ?? '',
      bin: json['bin'] ?? '',
      version: json['version'] ?? '',
    );
  }
}

class OTAScreen extends StatefulWidget {
  const OTAScreen({super.key});

  @override
  OTAScreenState createState() => OTAScreenState();
}

class OTAScreenState extends State<OTAScreen>
    with AutomaticKeepAliveClientMixin {
  late Future<Map<String, dynamic>> _updateFuture;
  final Logger logger = Logger();
  bool _isChecking = false;
  bool _isUpdating = false;
  bool _updateAvailable = false;

  List<String> logs = [];
  BLEProvider get bleProvider =>
      Provider.of<BLEProvider>(context, listen: false);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    otaScreenState = this;
       _updateFuture = fetchUpdate();
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
      _updateAvailable = false;
      _updateFuture = fetchUpdate();
    });

    _updateFuture.then((jsonData) {
      final update = Update.fromJson(jsonData);

      logMessage("✅ Latest Version: ${update.version}");
      logMessage("🧩 File: ${update.bin}");
      logMessage("🌐 URL: ${update.url}");

      final boards = bleProvider.boards;

      if (boards.isEmpty) {
        logMessage("⚠️ No boards connected.");
      } else {
        bool anyOutdated = false;
        for (final board in boards) {
          if (board.version != update.version) {
            logMessage(
                "⬆️ ${board.name} (${board.role}) has version ${board.version}. Update available.");
            anyOutdated = true;
          } else {
            logMessage(
                "✅ ${board.name} (${board.role}) is already up to date.");
          }
        }

        setState(() {
          _updateAvailable = anyOutdated;
        });
        if (!anyOutdated) {
          logMessage("🟢 All boards are already up to date.");
        }
      }
    }).catchError((error) {
      logMessage("❌ Error checking update: $error");
    }).whenComplete(() {
      setState(() {
        _isChecking = false;
      });
    });
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
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed:
                    (_isUpdating || !_updateAvailable) ? null : startOtaProcess,
                child: const Text("Start Board Update"),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
