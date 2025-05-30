// ota_screen.dart
import 'package:http/http.dart' as http;
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import '/global.dart';
import '/ble_provider.dart';

import '/widgets/background.dart';
import '/widgets/section.dart';
import '/widgets/status_indicators.dart';

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

  Update? update;
  double progress = 0.0;

  List<String> logs = [];
  final ScrollController _scrollController = ScrollController();

  BLEProvider get bleProvider =>
      Provider.of<BLEProvider>(context, listen: false);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _updateFuture = fetchUpdate();
  }

  void refreshUIFromBoardData() {}

  void logMessage(String message) {
    setState(() {
      logs.add(message);
    });
    // Auto-scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
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
      update = Update.fromJson(jsonData);

      logMessage("✅ Latest Version: ${update!.version}");
      logMessage("🧩 File: ${update!.bin}");
      logMessage("🌐 URL: ${update!.url}");

      final boards = bleProvider.boards;

      if (boards.isEmpty) {
        logMessage("⚠️ No boards connected.");
      } else {
        bool anyOutdated = false;
        for (final board in boards) {
          if (board.version != update!.version) {
            logMessage(
                "⬆️ ${board.name} (${board.role}) has version v${board.version}. Update available.");
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

  Future<Map<String, dynamic>> fetchUpdate() async {
    final response = await http.get(Uri.parse(
        'https://raw.githubusercontent.com/tekilaguy/cornhole_led/main/updates/cornhole_board_version.json'));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final version = data['version'] ?? '';
      latestFirmwareVersion = version;
      return data;
    } else {
      throw Exception('Failed to fetch update info');
    }
  }

  Future<void> performOta(String url,
      {void Function(double percent)? onProgress}) async {
    if (bleProvider.otaCharacteristic == null) {
      logger.e("No OTA characteristic in discoverServices!");
      return;
    }

    // 1) fetch the BIN
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      logger.e("HTTP ${resp.statusCode} fetching firmware");
      return;
    }
    final firmware = resp.bodyBytes;
    final total = firmware.length;
    logger.i("📥 Downloaded $total bytes for OTA");

    // 2) signal BEGIN
    await bleProvider.otaCharacteristic!.write(utf8.encode("BEGIN:$total"));

    // 3) chunk & write
    final chunkSize = max(
        (bleProvider.negotiatedMtu > 3 ? bleProvider.negotiatedMtu - 3 : 20),
        128);
    int offset = 0;
    while (offset < total) {
      final end = min(offset + chunkSize, total);
      final chunk = firmware.sublist(offset, end);
      await bleProvider.otaCharacteristic!.write(chunk, withoutResponse: false);
      offset = end;
      onProgress?.call(offset / total);
      await Future.delayed(const Duration(milliseconds: 20)); // pacing
    }

    // 4) finish
    await bleProvider.otaCharacteristic!.write(utf8.encode("END"));
    logger.i("✅ OTA upload finished");
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
                  controller: _scrollController,
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
                onPressed: (_isUpdating || !_updateAvailable)
                    ? null
                    : () async {
                        setState(() {
                          _isUpdating = true;
                          logs.clear();
                        });

                        final boardVer = await bleProvider.readBoardVersion();
                        if (boardVer == null) {
                          logMessage(
                              "❌ Cannot read version: versionCharacteristic is null or BLE read failed.");
                        }
                        logMessage("🔍 Board reports version: $boardVer");

                        if (boardVer != null &&
                            update != null &&
                            boardVer != update!.version &&
                            update!.url.isNotEmpty) {
                          final fullUrl = "${update!.url}${update!.bin}_v${update!.version}.bin";
                          logMessage(fullUrl);
await performOta(
                            fullUrl,
                            onProgress: (p) => setState(() => progress = p),
                          );

                          logMessage("✅ OTA upload done");

                          // STEP 1: Check if any board needs upgrade
                          final boards = bleProvider.boards;
                          final outdatedBoards = boards
                              .where((b) => b.version != update!.version)
                              .toList();

                          if (outdatedBoards.isNotEmpty) {
                            logMessage(
                                "🔁 Flipping roles to update ${outdatedBoards.first.name}...");
                            await bleProvider
                                .sendCommand("SET_ROLE:SECONDARY;");
                            // STEP 2: Wait for the boards to reboot & roles to flip
                            await Future.delayed(const Duration(seconds: 6));
                            bleProvider.disconnectDevice();
                            await Future.delayed(const Duration(seconds: 3));
                            bleProvider.scanForDevices(
                                rescan: true); // reconnect to new PRIMARY
                          }
                        } else {
                          logMessage("🟢 No update needed");
                        }

                        setState(() {
                          _isUpdating = false;
                        });
                      },
                child: Text("Start OTA"),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
