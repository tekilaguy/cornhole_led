// widgets/status_indicators.dart
import 'package:flutter/material.dart';
import '../global.dart';

class StatusIndicators extends StatelessWidget {
  const StatusIndicators({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        isConnected
            ? const Text(
                'Connected',
                style:
                    TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
              )
            : const Text(
                'Not connected',
                style: TextStyle(
                    color: Colors.red, fontWeight: FontWeight.bold),
              ),
        Text(
          'WiFi: ${wifiEnabled ? "Enabled" : "Disabled"}',
          style: const TextStyle(
              color: Colors.blue, fontWeight: FontWeight.bold),
        ),
        const Center(
          child: Text(
            '© Bluetrace Entertainment, LLC',
            style: TextStyle(fontSize: 12, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
