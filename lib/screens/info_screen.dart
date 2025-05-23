import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble_provider.dart';
import '../widgets/background.dart';
import '../widgets/section.dart';
import '../widgets/status_indicators.dart';
import '../global.dart';

class InfoScreen extends StatefulWidget {
  const InfoScreen({super.key});

  @override
  State<InfoScreen> createState() => InfoScreenState();
}

class InfoScreenState extends State<InfoScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  BLEProvider get bleProvider =>
      Provider.of<BLEProvider>(context, listen: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (bleProvider.isConnected) {
        bleProvider.sendCommand("CMD:INFO;");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final boards = context.watch<BLEProvider>().boards;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection Information'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => bleProvider.sendCommand("CMD:INFO;"),
          ),
        ],
      ),
      body: Stack(
        children: [
          const Background(),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Expanded(
                  child: boards.isEmpty
                      ? const Center(
                          child: Text(
                            "No boards connected",
                            style: TextStyle(color: Colors.white),
                          ),
                        )
                      : ListView.builder(
                          itemCount: boards.length,
                          itemBuilder: (context, index) {
                            final board = boards[index];
                            final isOutdated =
                                board.version != latestFirmwareVersion;

                            return GestureDetector(
                              onTap: () {
                                bleProvider
                                    .sendCommand("CMD:IDENTIFY:${board.mac};");
                              },
                              child: Section(
                                title: board.role,
                                content: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      "MAC: ${board.mac}",
                                      style:
                                          const TextStyle(color: Colors.white),
                                    ),
                                    batteryIcon(board.batteryLevel),
                                    Text(
                                      "Firmware: ${board.version}",
                                      style: const TextStyle(
                                          color: Colors.white70),
                                    ),
                                    if (isOutdated)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          "⚠️ Upgrade Available",
                                          style: const TextStyle(
                                            color: Colors.amber,
                                            fontWeight: FontWeight.bold,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const StatusIndicators(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget batteryIcon(int level) {
    IconData icon;
    Color color;

    if (level >= 80) {
      icon = Icons.battery_full;
      color = Colors.green;
    } else if (level >= 60) {
      icon = Icons.battery_6_bar;
      color = Colors.lightGreen;
    } else if (level >= 40) {
      icon = Icons.battery_4_bar;
      color = Colors.orange;
    } else if (level >= 20) {
      icon = Icons.battery_2_bar;
      color = Colors.deepOrange;
    } else {
      icon = Icons.battery_alert;
      color = Colors.red;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 4),
        Text("$level%", style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}
