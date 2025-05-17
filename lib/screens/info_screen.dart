// info_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '/ble_provider.dart';
//import '/global.dart';

class InfoScreenTest extends StatelessWidget {
  const InfoScreenTest({super.key});

  @override
  Widget build(BuildContext context) {
    final bleProvider = Provider.of<BLEProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Info'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connected: ${bleProvider.isConnected}'),
            const SizedBox(height: 8),
            Text('WiFi Enabled: ${bleProvider.wifiEnabled}'),
            const SizedBox(height: 8),
            Text('ESP-NOW Enabled: ${bleProvider.espNowEnabled}'),
            const SizedBox(height: 8),
            Text('Lights On: ${bleProvider.lightsOn}'),
            const SizedBox(height: 8),
            Text('Board 1 Role: ${bleProvider.boardRole1}'),
            Text('Board 1 Name: ${bleProvider.nameBoard1}'),
            Text('Board 1 MAC: ${bleProvider.macAddrBoard1}'),
            Text('Board 1 IP: ${bleProvider.ipAddrBoard1}'),
            Text('Board 1 Battery: ${bleProvider.batteryLevelBoard1}% (${bleProvider.batteryVoltageBoard1}V)'),
            const Divider(height: 20),
            Text('Board 2 Role: ${bleProvider.boardRole2}'),
            Text('Board 2 Name: ${bleProvider.nameBoard2}'),
            Text('Board 2 MAC: ${bleProvider.macAddrBoard2}'),
            Text('Board 2 IP: ${bleProvider.ipAddrBoard2}'),
            Text('Board 2 Battery: ${bleProvider.batteryLevelBoard2}% (${bleProvider.batteryVoltageBoard2}V)'),
            const Spacer(),
            Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushNamed(context, '/ota');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  textStyle: const TextStyle(fontSize: 16),
                ),
                child: const Text('Check for Updates'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
