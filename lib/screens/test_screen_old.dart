// info_screen.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import '/global.dart';
import '/widgets/background.dart';
import '/widgets/section.dart';
import '/widgets/status_indicators.dart';
import '/ble_provider.dart';

class TestScreen extends StatefulWidget {
  final bool lightsOn;
  final bool espNowEnabled;
  final bool isConnected;
  final String connectionInfo;
  final Function(String) sendCommand;

  const TestScreen({
    super.key,
    required this.lightsOn,
    required this.espNowEnabled,
    required this.isConnected,
    required this.connectionInfo,
    required this.sendCommand,
  });

  @override
  TestScreenState createState() => TestScreenState();
}

class TestScreenState extends State<TestScreen>
    with AutomaticKeepAliveClientMixin {
  final Logger logger = Logger();
  BLEProvider get bleProvider =>
      Provider.of<BLEProvider>(context, listen: false);

  static const WidgetStateProperty<Icon> thumbIcon = WidgetStateProperty<Icon>.fromMap(
    <WidgetStatesConstraint, Icon>{
      WidgetState.selected: Icon(Icons.check),
      WidgetState.any: Icon(Icons.close),
    },
  );

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    // Delay execution to ensure BLE context is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (bleProvider.isConnected) {
        bleProvider.sendCommand('CMD:INFO;');
      }
    });
  }

  @override
  void dispose() {

    super.dispose();
  }

  void toggleSwitch(String command, bool status) {
    final completeCommand = '$command:${status ? 'on' : 'off'};';
    logger.i("Toggling switch with command: $completeCommand");

    // Update the state
    setState(() {
      if (command == 'toggleLights') {
        lightsOn = status;
      } else if (command == 'toggleEspNow') {
        espNowEnabled = status;
      }
    });

    // Send command to the device
    bleProvider.sendCommand(completeCommand);
  }

  void updateOta() {
    bleProvider.sendCommand('UPDATE:$url;');
  }

  void toggleDeepSleep() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Sleep'),
        content:
            const Text('Are you sure you want to put the Cornhole to Sleep?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sleep'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      bleProvider.sendDeepSleep();
      isConnected = false;
      await Future.delayed(
          const Duration(seconds: 1)); // Wait for restart command to be sent
      bleProvider.disconnectDevice();
      Navigator.pop(context);
    }
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
      bleProvider.sendRestart();
      isConnected = false;
      await Future.delayed(
          const Duration(seconds: 1)); // Wait for restart command to be sent
      bleProvider.disconnectDevice();
      Navigator.pop(context);
    }
  }

  void onBackButtonPressed() {
    Navigator.pop(context, {
      'lightsOn': lightsOn,
      'espNowEnabled': espNowEnabled,
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return WillPopScope(
      onWillPop: () async {
        onBackButtonPressed();
        return false; // Prevent default pop action
      },
      child: Scaffold(
        body: Stack(
          children: [
            const Background(),
            SafeArea(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20),
                    context.watch<BLEProvider>().isConnected
                        ? buildControlScreen()
                        : bleProvider.buildDeviceList(),
                    const SizedBox(height: 20),
                    const StatusIndicators(),
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
          content: buildConnectionInfoList(),
        ),
        ElevatedButton(
          onPressed: () => bleProvider.sendCommand("CMD:INFO;"),
          child: const Text("Refresh Info"),
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
              'Sleep',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            ElevatedButton(
              onPressed: toggleDeepSleep,
              child: const Icon(Icons.power, size: 30),
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
          thumbIcon: thumbIcon,
          value: currentValue,
          onChanged: (bool newValue) {
            setState(() {
              if (label == 'Lights') {
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
    final boards = context.watch<BLEProvider>().boards;

    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
        3: FlexColumnWidth(),
      },
      border: TableBorder.all(color: Colors.white24),
      children: [
        TableRow(
          children: [
            const Padding(
              padding: EdgeInsets.all(6),
              child: Text("Role",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const Padding(
              padding: EdgeInsets.all(6),
              child: Text("Name",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const Padding(
              padding: EdgeInsets.all(6),
              child: Text("Battery",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const Padding(
              padding: EdgeInsets.all(6),
              child: Text("Version",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        ...boards.map((board) => TableRow(
              children: [
                Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(board.role,
                        style: const TextStyle(color: Colors.white))),
                Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(board.name,
                        style: const TextStyle(color: Colors.white))),
                Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(board.version,
                        style: const TextStyle(color: Colors.white))),
                Padding(
                    padding: const EdgeInsets.all(6),
                    child: batteryIcon(board.batteryLevel)),
              ],
            ))
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

  Widget buildConnectionInfoList() {
    final boards = context.watch<BLEProvider>().boards;

    return ExpansionPanelList(
      expansionCallback: (int index, bool isExpanded) {
        setState(() {
          boards[index].isExpanded = !isExpanded;
        });
      },
      children: boards.map<ExpansionPanel>((board) {
        return ExpansionPanel(
          headerBuilder: (context, isExpanded) {
            return ListTile(
              title: Text('${board.role} - ${board.name}'),
              subtitle: Text(
                  'Battery: ${board.batteryLevel}% • Version: ${board.version}'),
            );
          },
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MAC Address: ${board.mac}'),
              ],
            ),
          ),
          isExpanded: board.isExpanded,
        );
      }).toList(),
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
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text('$level%', style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}
