// info_screen.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import '/global.dart';
import '/widgets/background.dart';
import '/widgets/section.dart';
import '/widgets/status_indicators.dart';
import 'home_screen.dart'; // For accessing HomeScreenState

class InfoScreen extends StatefulWidget {
  const InfoScreen({super.key});

  @override
  InfoScreenState createState() => InfoScreenState();
}

class InfoScreenState extends State<InfoScreen> {
  final Logger logger = Logger();

  @override
  void initState() {
    super.initState();
    infoScreenState = this;
  }

  @override
  void dispose() {
    infoScreenState = null;
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;

    if (macAddrBoard1.isEmpty && macAddrBoard2.isEmpty) {
      wifiEnabled = args['wifiEnabled'] as bool? ?? true;
      lightsOn = args['lightsOn'] as bool? ?? false;
      espNowEnabled = args['espNowEnabled'] as bool? ?? false;

      homeScreenState = args['homeScreenState'] as HomeScreenState?;

      if (homeScreenState != null) {
        homeScreenState!.sendCommand('GET_INFO;');
      }
    }
  }

  void toggleSwitch(String command, bool status) {
    final completeCommand = '$command:${status ? 'on' : 'off'};';
    logger.i("Toggling switch with command: $completeCommand");

    // Update the state
    setState(() {
      if (command == 'toggleWiFi') {
        wifiEnabled = status;
      } else if (command == 'toggleLights') {
        lightsOn = status;
      } else if (command == 'toggleEspNow') {
        espNowEnabled = status;
      }
    });

    // Send command to the device
    homeScreenState?.sendCommand(completeCommand);
  }

  void updateOta() {
    homeScreenState?.sendCommand("UPDATE;");
  }

  void restartBoards() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Restart'),
        content: const Text(
            'Are you sure you want to restart the Cornhole LED lights?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restart'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      homeScreenState?.sendRestart();
      isConnected = false;
      await Future.delayed(
          const Duration(seconds: 1)); // Wait for restart command to be sent
      homeScreenState?.disconnectDevice();
      Navigator.pop(context);
    }
  }

  void onBackButtonPressed() {
    Navigator.pop(context, {
      'wifiEnabled': wifiEnabled,
      'lightsOn': lightsOn,
      'espNowEnabled': espNowEnabled,
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        onBackButtonPressed();
        return false; // Prevent default pop action
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.blue,
          elevation: 0,
          title: const Text('Information'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: onBackButtonPressed,
          ),
          actions: [
            Center(
              child: Row(
                children: [
                  const SizedBox(width: 5),
                  IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: homeScreenState?.navigateToSetupScreen,
                  ),
                ],
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            const Background(),
            SingleChildScrollView(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20),
                    isConnected ? buildControlScreen() : const HomeScreen(),
                    const SizedBox(height: 20),
                    const StatusIndicators(),
                    const SizedBox(height: 10), // Add some space at the bottom
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildControlScreen() {
    return Column(
      children: [
        Section(
          title: 'Controls',
          content: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              const SizedBox(height: 10),
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(1),
                  1: FlexColumnWidth(1),
                  2: FlexColumnWidth(1),
                },
                children: [
                  TableRow(
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text('WiFi',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 16)),
                          buildToggleSwitch('WiFi', 'toggleWiFi', wifiEnabled),
                        ],
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text('Lights',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 16)),
                          buildToggleSwitch('Lights', 'toggleLights', lightsOn),
                        ],
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text('LED Sync',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              )),
                          buildToggleSwitch(
                              'ESP-NOW', 'toggleEspNow', espNowEnabled),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 15),
        Section(
          title: 'Connection Information',
          content: Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                const SizedBox(height: 10),
                buildConnectionTable(),
              ]),
        ),
        const SizedBox(height: 15),
        Section(
          title: 'Other',
          content: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [buildControlButtons()],
          ),
        ),
      ],
    );
  }

  Widget buildControlButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Column(
          children: [
            const Text(
              'Updates',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            ElevatedButton(
              onPressed: updateOta,
              child: const Icon(Icons.system_update_alt, size: 30),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                elevation: 25,
                shadowColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50),
                  side: const BorderSide(color: Colors.black, width: .5),
                ),
                padding: const EdgeInsets.all(20),
              ),
            ),
          ],
        ),
        Column(
          children: [
            const Text(
              'Restart',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            ElevatedButton(
              onPressed: restartBoards,
              child: const Icon(Icons.power_settings_new,
                  size: 30, color: Colors.black),
              style: ElevatedButton.styleFrom(
                elevation: 25,
                shadowColor: Colors.black,
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50),
                  side: const BorderSide(color: Colors.black, width: .5),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget buildToggleSwitch(String label, String command, bool currentValue) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(currentValue ? 'On' : 'Off',
            style: TextStyle(color: currentValue ? Colors.green : Colors.red)),
        Switch(
          value: currentValue,
          onChanged: (bool newValue) {
            setState(() {
              if (label == 'WiFi') {
                wifiEnabled = newValue;
                logger.i("WiFi switch changed to: $newValue");
              } else if (label == 'Lights') {
                lightsOn = newValue;
                logger.i("Lights switch changed to: $newValue");
              } else if (label == 'ESP-NOW') {
                espNowEnabled = newValue;
                logger.i("ESP-NOW switch changed to: $newValue");
              }
            });
            toggleSwitch(command, newValue);
          },
        ),
      ],
    );
  }

  Widget buildConnectionTable() {
    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
      },
      children: [
        //buildTableRow('Role', boardRole1, boardRole2),
        buildTableRow('Name', nameBoard1, nameBoard2),
        buildTableRow('MAC', macAddrBoard1, macAddrBoard2),
        buildTableRow('IP', ipAddrBoard1, ipAddrBoard2),
        //buildTableRow('Voltage', '$batteryVoltageBoard1 V', '$batteryVoltageBoard2 V'),
        buildTableRow(
            'Battery', '$batteryLevelBoard1%', '$batteryLevelBoard2%'),
      ],
    );
  }

  TableRow buildTableRow(String label, String value1, String value2) {
    return TableRow(
      children: [
        TableCell(
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Text(
              label,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        TableCell(
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Text(value1, style: const TextStyle(color: Colors.white)),
          ),
        ),
        TableCell(
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Text(value2, style: const TextStyle(color: Colors.white)),
          ),
        ),
      ],
    );
  }
}
