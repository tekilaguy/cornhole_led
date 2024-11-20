// setup_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ble_provider.dart';
import 'widgets/background.dart';
import 'widgets/section.dart';
import 'widgets/status_indicators.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  SetupScreenState createState() => SetupScreenState();
}

class SetupScreenState extends State<SetupScreen> {
  late TextEditingController ssidController;
  late TextEditingController passwordController;
  late TextEditingController boardName1Controller;
  late TextEditingController boardName2Controller;

  @override
  void initState() {
    super.initState();
    BLEProvider bleProvider = Provider.of<BLEProvider>(context, listen: false);
    ssidController = TextEditingController(text: bleProvider.ssid);
    passwordController = TextEditingController(text: bleProvider.password);
    boardName1Controller = TextEditingController(text: bleProvider.nameBoard1);
    boardName2Controller = TextEditingController(text: bleProvider.nameBoard2);
  }

  @override
  Widget build(BuildContext context) {
    BLEProvider bleProvider = Provider.of<BLEProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Screen'),
      ),
      body: Stack(
        children: [
          const Background(),
          SingleChildScrollView(
            child: Column(
              children: [
                Section(
                  title: 'WiFi Settings',
                  content: Column(
                    children: [
                      TextField(
                        controller: ssidController,
                        decoration: const InputDecoration(
                          labelText: "WiFi SSID",
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          bleProvider.ssid = value;
                        },
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: passwordController,
                        decoration: const InputDecoration(
                          labelText: "WiFi Password",
                          border: OutlineInputBorder(),
                        ),
                        obscureText: true,
                        onChanged: (value) {
                          bleProvider.password = value;
                        },
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () {
                          bleProvider.saveWiFiSettings();
                        },
                        child: const Text("Save WiFi Settings"),
                      ),
                    ],
                  ),
                ),
                Section(
                  title: 'Default Settings',
                  content: Column(
                    children: [
                      TextField(
                        controller: boardName1Controller,
                        decoration: const InputDecoration(
                          labelText: "Board 1 Name",
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          bleProvider.nameBoard1 = value;
                        },
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: boardName2Controller,
                        decoration: const InputDecoration(
                          labelText: "Board 2 Name",
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          bleProvider.nameBoard2 = value;
                        },
                      ),
                      // Add other settings inputs as needed
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () {
                          bleProvider.saveDefaultSettings();
                        },
                        child: const Text("Save Default Settings"),
                      ),
                    ],
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
}
