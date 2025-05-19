// home_screen.dart
import 'package:flutter/material.dart';
//import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import '/ble_provider.dart';
import '/global.dart';

import '/widgets/background.dart';
import '/widgets/section.dart';
import '/widgets/status_indicators.dart';
import '/widgets/color_button.dart';
import '/widgets/effect_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin{
  final Logger logger = Logger();
  BLEProvider get bleProvider => Provider.of<BLEProvider>(context, listen: false);

  @override
  bool get wantKeepAlive => true;

  // List<BluetoothDevice> devicesList = [];
  // BluetoothDevice? connectedDevice;
  // BluetoothCharacteristic? writeCharacteristic;
  // BluetoothCharacteristic? notifyCharacteristic;
  // Timer? reconnectTimer; // Timer to handle reconnection attempts
  // static const reconnectDuration = Duration(seconds: 30);

  int getColorIndexFromRGB(int r, int g, int b) {
    int closestColorIndex = 0;
    double smallestDistance = double.infinity;

    // Iterate through the list of predefined colors
    for (int i = 0; i < colors.length; i++) {
      // Calculate the Euclidean distance between the current color and the given RGB values
      double distance = (colors[i].r.toDouble() - r.toDouble()) *
              (colors[i].r.toDouble() - r.toDouble()) +
          (colors[i].g.toDouble() - g.toDouble()) *
              (colors[i].g.toDouble() - g.toDouble()) +
          (colors[i].b.toDouble() - b.toDouble()) *
              (colors[i].b.toDouble() - b.toDouble());

      // If this distance is smaller than the smallestDistance, update the closestColorIndex and smallestDistance
      if (distance < smallestDistance) {
        smallestDistance = distance;
        closestColorIndex = i;
      }
    }

    logger.i("Closest color index found: $closestColorIndex");
    // Return the index of the closest color
    return closestColorIndex;
  }

  @override
  void initState() {
    super.initState();
    homeScreenState = this; // Reference to this state
  
    //  if (isConnected) {
    //   requestCurrentSettings(); // Request the current settings from the board
    // }
  }

 
// Inside HomeScreenState class

  void navigateToInfoScreen() async {
    final result = await Navigator.pushNamed(context, '/info', arguments: {
      'lightsOn': lightsOn,
      'espNowEnabled': espNowEnabled,
      'isConnected': isConnected,
      'connectionInfo': connectionInfo,
      'boardRole1': boardRole1,
      'nameBoard1': nameBoard1,
      'macAddrBoard1': macAddrBoard1,
      'ipAddrBoard1': ipAddrBoard1,
      'batteryLevelBoard1': batteryLevelBoard1,
      'batteryVoltageBoard1': batteryVoltageBoard1,
      'boardRole2': boardRole2,
      'nameBoard2': nameBoard2,
      'macAddrBoard2': macAddrBoard2,
      'ipAddrBoard2': ipAddrBoard2,
      'batteryLevelBoard2': batteryLevelBoard2,
      'batteryVoltageBoard2': batteryVoltageBoard2,
        'sendCommand':   bleProvider.sendCommand, // Ensure this is correctly passed
    });

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        lightsOn = result['lightsOn'] ?? lightsOn;
        espNowEnabled = result['espNowEnabled'] ?? espNowEnabled;
      });
    }
  }

  void navigateToSetupScreen() async {
    final result = await Navigator.pushNamed(
      context,
      '/setup',
      arguments: {
        'ssid': ssid,
        'password': password,
        'boardRole1': boardRole1,
        'boardRole2': boardRole2,
        'nameBoard1': nameBoard1,
        'nameBoard2': nameBoard2,
        'initialBrightness': initialBrightness,
        'effectSpeed': effectSpeed,
        'blockSize': blockSize,
        'celebrationDuration': celebrationDuration,
        'inactivityTimeout': inactivityTimeout,
        'sportEffectColor1': sportEffectColor1,
        'sportEffectColor2': sportEffectColor2,
        'initialStartupColor': initialStartupColor,
        'sendCommand':   bleProvider.sendCommand, // Pass the sendCommand function
      },
    );

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
          lightsOn = result['lightsOn'] ?? lightsOn;
        espNowEnabled = result['espNowEnabled'] ?? espNowEnabled;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
  

    return Scaffold(
      body: Stack(
        children: [
          const Background(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  // ignore: unnecessary_null_comparison
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
    );
  }

  Widget buildControlScreen() {
    return Column(
      children: [
        Section(
          title: 'Colors',
          content: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: List.generate(
                colors.length, (index) => buildColorButton(index)),
          ),
        ),
        const SizedBox(height: 15),
        Section(
          title: 'Effects',
          content: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            // Dynamically generate effect buttons from the effects list
            children: List.generate(
              effects.length,
              (index) => buildEffectButton(
                effects[index], // Button label and effect
                effects[index], // Effect command
                width: (MediaQuery.of(context).size.width * 0.4) - 20,
              ),
            ),
          ),
        ),
        const SizedBox(height: 15),
        Section(
          title: 'Brightness',
          content: Slider(
            min: 0,
            max: 100,
            value: brightness.toDouble(),
            divisions: (100 - 5) ~/ 5,
            onChanged: (value) {
              setState(() {
                brightness = value.toInt();
              });
              bleProvider.sendBrightness(brightness);
            },
          ),
        ),
      ],
    );
  }

  Widget buildColorButton(int colorIndex) {
    bool isActive = colorIndex == activeColorIndex;
    return ColorButton(
      color: colors[colorIndex],
      isActive: isActive,
      onPressed: () => bleProvider.sendColorIndex(colorIndex),
    );
  }

  Widget buildEffectButton(String label, String effect, {double? width}) {
    return EffectButton(
      activeShadowColor: colors[activeColorIndex],
      label: label,
      isActive: activeEffect == effect,
      onPressed: () => bleProvider.sendEffect(effect),
    );
  }
}
