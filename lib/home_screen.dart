// home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:provider/provider.dart';
import 'ble_provider.dart';
import 'info_screen.dart';
import 'setup_screen.dart';
import 'widgets/background.dart';
import 'widgets/status_indicators.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final List<BluetoothDevice> devicesList = [];

  @override
  void initState() {
    super.initState();
    initializeBluetooth();
  }

  void initializeBluetooth() {
    FlutterBlue.instance.state.listen((state) {
      if (state == BluetoothState.on) {
        scanForDevices();
      } else {
        // Handle Bluetooth not enabled
      }
    });
  }

  void scanForDevices({bool rescan = false}) {
    if (rescan) {
      setState(() {
        devicesList.clear();
      });
    }

    FlutterBlue.instance.startScan(timeout: const Duration(seconds: 4));
    FlutterBlue.instance.scanResults.listen((results) {
      for (ScanResult r in results) {
        String deviceName = r.device.name;
        if (deviceName.isNotEmpty) {
          if (deviceName == "CornholeBT") {
            Provider.of<BLEProvider>(context, listen: false)
                .connectToDevice(r.device);
            FlutterBlue.instance.stopScan();
            return;
          }
          if (!devicesList.contains(r.device)) {
            setState(() {
              devicesList.add(r.device);
            });
          }
        }
      }
    }, onError: (error) {
      // Handle scan error
    });
  }

  @override
  Widget build(BuildContext context) {
    BLEProvider bleProvider = Provider.of<BLEProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Screen'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info),
            onPressed: bleProvider.isConnected
                ? () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const InfoScreen(),
                      ),
                    );
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: bleProvider.isConnected
                ? () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SetupScreen(),
                      ),
                    );
                  }
                : null,
          ),
        ],
      ),
      body: Stack(
        children: [
          const Background(),
          Column(
            children: [
              bleProvider.isConnected ? buildControlScreen() : buildScanScreen(),
              const StatusIndicators(),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildScanScreen() {
    return Column(
      children: [
        const Text("Scanning for devices..."),
        ElevatedButton(
          onPressed: () {
            scanForDevices(rescan: true);
          },
          child: const Text("Rescan"),
        ),
      ],
    );
  }

  Widget buildControlScreen() {
    BLEProvider bleProvider = Provider.of<BLEProvider>(context);

    return Column(
      children: [
        ElevatedButton(
          onPressed: () {
            bleProvider.sendEffect('Wipe');
          },
          child: const Text('Set Effect: Wipe'),
        ),
        ElevatedButton(
          onPressed: () {
            bleProvider.toggleLights();
          },
          child: Text(bleProvider.lightsOn ? 'Turn Lights Off' : 'Turn Lights On'),
        ),
        // Add more controls as needed
      ],
    );
  }
}
