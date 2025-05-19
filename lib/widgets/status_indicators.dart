// widgets/status_indicators.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble_provider.dart';


class StatusIndicators extends StatelessWidget {
  const StatusIndicators({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        context.watch<BLEProvider>().isConnected
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
