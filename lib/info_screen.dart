// info_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ble_provider.dart';
import 'widgets/background.dart';
import 'widgets/section.dart';
import 'widgets/status_indicators.dart';

class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    BLEProvider bleProvider = Provider.of<BLEProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Information'),
      ),
      body: Stack(
        children: [
          const Background(),
          SingleChildScrollView(
            child: Column(
              children: [
                buildControlSection(bleProvider),
                const StatusIndicators(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildControlSection(BLEProvider bleProvider) {
    return Column(
      children: [
        Section(
          title: 'Controls',
          content: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              buildToggleSwitch('WiFi', bleProvider.wifiEnabled, (value) {
                bleProvider.toggleWiFi();
              } as VoidCallback),
              buildToggleSwitch('Lights', bleProvider.lightsOn, (value) {
                bleProvider.toggleLights();
              } as VoidCallback),
              buildToggleSwitch('LED Sync', bleProvider.espNowEnabled, (value) {
                bleProvider.toggleEspNow();
              } as VoidCallback),
            ],
          ),
        ),
        // Add other sections as needed
      ],
    );
  }

  Widget buildToggleSwitch(String label, bool currentValue, VoidCallback onPressed) {
    return Column(
      children: [
        Text(label),
        Switch(
          value: currentValue,
          onChanged: (value) {
            onPressed();
          },
        ),
      ],
    );
  }
}
