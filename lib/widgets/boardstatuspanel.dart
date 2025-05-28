import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '/ble_provider.dart';
import '/global.dart'; // contains latestFirmwareVersion

class BoardStatusPanel extends StatelessWidget {
  const BoardStatusPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final boards = context.watch<BLEProvider>().boards;

    if (boards.isEmpty) {
      return const Center(child: Text("🔍 No boards detected"));
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: boards.length,
      itemBuilder: (context, index) {
        final board = boards[index];
        final needsUpdate = board.version != latestFirmwareVersion;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            title: Text("${board.name} (${board.role})"),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("MAC: ${board.mac}"),
                Text("Battery: ${board.batteryLevel}% • ${board.batteryVoltage} mV"),
                Text("Firmware: ${board.version}"),
              ],
            ),
            trailing: needsUpdate
                ? const Icon(Icons.system_update_alt, color: Colors.orange)
                : const Icon(Icons.verified, color: Colors.green),
          ),
        );
      },
    );
  }
}
