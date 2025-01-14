// home_screen.dart
import 'dart:async'; // Required for Timer
import 'dart:convert'; // Required for utf8.encode
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';
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

class HomeScreenState extends State<HomeScreen> {
  final Logger logger = Logger();
  List<BluetoothDevice> devicesList = [];
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? writeCharacteristic;
  BluetoothCharacteristic? notifyCharacteristic;
  Timer? reconnectTimer; // Timer to handle reconnection attempts
  static const reconnectDuration = Duration(seconds: 30);

  int getColorIndexFromRGB(int r, int g, int b) {
    int closestColorIndex = 0;
    double smallestDistance = double.infinity;

    // Iterate through the list of predefined colors
    for (int i = 0; i < colors.length; i++) {
      // Calculate the Euclidean distance between the current color and the given RGB values
      double distance = (colors[i].red.toDouble() - r.toDouble()) *
              (colors[i].red.toDouble() - r.toDouble()) +
          (colors[i].green.toDouble() - g.toDouble()) *
              (colors[i].green.toDouble() - g.toDouble()) +
          (colors[i].blue.toDouble() - b.toDouble()) *
              (colors[i].blue.toDouble() - b.toDouble());

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
    initializeBluetooth();
    if (isConnected) {
      requestCurrentSettings(); // Request the current settings from the board
    }
  }

  void initializeBluetooth() {
    FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        scanForDevices();
      } else {
        logger.w("Bluetooth is not enabled. Please enable Bluetooth.");
      }
    });
  }

  void manageBluetoothState(BluetoothDevice device) {
    device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.connected) {
        logger.i("Device connected: ${device.platformName}");
        setState(() {
          isConnected = true;
          connectedDevice = device;
        });
        discoverServices(device);
        reconnectTimer?.cancel();
      } else if (state == BluetoothConnectionState.disconnected) {
        logger.w("Device disconnected: ${device.platformName}");
        setState(() {
          isConnected = false;
          connectedDevice = null;
        });
        attemptReconnection(device);
      }
    });
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    logger.i("Connecting to device: ${device.platformName}");
    try {
      await device.connect(autoConnect: false);
      await device.requestMtu(240);
      manageBluetoothState(device); // Consolidate state management

      setState(() {
        isConnected = true; // Update UI to reflect the connection
        connectedDevice = device; // Save the connected device
      });
    } catch (e) {
      logger.e("Cannot connect, exception occurred: $e");
      setState(() {
        isConnected = false; // Ensure UI reflects failed connection
      });
    }
  }

  void attemptReconnection(BluetoothDevice device) {
    if (reconnectTimer?.isActive ?? false) reconnectTimer?.cancel();

    reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (timer.tick >= reconnectDuration.inSeconds / 5) {
        logger.i("Reconnection attempts timed out.");
        timer.cancel();
      } else if (!isConnected) {
        logger.i("Attempting to reconnect...");
        try {
          await Future.delayed(const Duration(seconds: 2)); // Add a delay
          await device.connect(autoConnect: false);
          logger.i("Reconnected to device: ${device.platformName}");
          manageBluetoothState(device); // Re-register state listener
          timer.cancel(); // Stop the timer once reconnected
        } catch (e) {
          logger.e("Reconnection attempt failed: $e");
        }
      }
    });
  }

  void discoverServices(BluetoothDevice device) async {
    List<BluetoothService> services = await device.discoverServices();
    for (BluetoothService service in services) {
      for (BluetoothCharacteristic characteristic in service.characteristics) {
        if (characteristic.properties.write) {
          writeCharacteristic = characteristic;
        }
        if (characteristic.properties.notify) {
          notifyCharacteristic = characteristic;
          notifyCharacteristic?.setNotifyValue(true);
          notifyCharacteristic?.lastValueStream.listen((value) {
            onValueReceived(value);
          });
        }
      }
    }
  }

  void scanForDevices({bool rescan = false}) {
    if (rescan) {
      setState(() {
        devicesList.clear();
      });
    }

    logger.i("Scanning for devices...");
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        String deviceName = r.advertisementData.advName;
        if (deviceName.isNotEmpty) {
          logger.i("Found device: $deviceName");
          if (deviceName == "CornholeBT" && !isConnected) {
            logger.i("Attempting to connect to CornholeBT...");
            connectToDevice(r.device);
            FlutterBluePlus.stopScan();
            return;
          }
          if (!devicesList.contains(r.device)) {
            setState(() {
              devicesList.add(r.device);
            });
          }
        } else {
          logger.w("Found device with no name or empty name.");
        }
      }
    }, onError: (error) {
      logger.e("Scan error: $error");
    });
  }

  void disconnectDevice() async {
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      setState(() {
        isConnected = false;
      });
    }
  }

  void onValueReceived(List<int> value) {
    String data = utf8.decode(value);
    logger.i("Received partial data: $data");

    // Append to the buffer until a complete message with ';' is received
    receivedMessage += data;
    int endIndex;

    // Process each complete message
    while ((endIndex = receivedMessage.indexOf(";")) != -1) {
      String completeMessage = receivedMessage.substring(0, endIndex);
      logger.i("Complete message: $completeMessage");
      handleNotification(completeMessage);
      receivedMessage = receivedMessage.substring(endIndex + 1);
      //receivedMessage = '';
    }
  }

  void handleNotification(String value) {
    logger.i("Received notification: $value");

    try {
      setState(() {
        if (value.startsWith("ColorIndex:")) {
          // Extract the color index value
          String indexStr = value.substring("ColorIndex:".length).trim();
          int? colorIndex = int.tryParse(indexStr);
          if (colorIndex != null) {
            // Update your app's color index
            activeColorIndex = colorIndex;
            logger.i("Color index updated to: $colorIndex");
            // Optionally, update the UI or perform additional actions
          } else {
            logger.w("Invalid color index received: $indexStr");
          }
          return;
        } else if (value.startsWith("Effect:")) {
          // Extract the effect value
          String effect = value.substring("Effect:".length).trim();
          // Update your app's effect
          activeEffect = effect;
          logger.i("Effect updated to: $effect");
          // Optionally, update the UI or perform additional actions
          return;
        } else if (value.startsWith("toggleLights:")) {
          // Extract the value after "toggleLights:"
          String status = value.substring("toggleLights:".length).trim();

          // Convert the extracted value to a boolean
          bool lightsOn = (status.toLowerCase() == "on");

          // Log the current status
          logger.i("Lights toggled to: ${lightsOn ? 'ON' : 'OFF'}");

          // Update the UI or perform additional actions based on the new lightsOn status
          setState(() {
            lightsOn = lightsOn; // Update your app's state
          });
          return;
        }

        // Proceed to process the message
        if (value.startsWith("S:")) {
          handleSettingsResponse(value.substring(2));
          return;
        }

        // Split the entire message by `;` to get fields
        List<String> fields = value.split(';');
        for (var field in fields) {
          if (field.isEmpty) continue;

          int colonIndex = field.indexOf(':');
          if (colonIndex == -1) {
            logger.w("Malformed field: $field");
            continue;
          }

          String tag = field.substring(0, colonIndex);
          String fieldValue = field.substring(colonIndex + 1);

          if (tag.length < 2) {
            logger.w("Tag too short: $tag");
            continue;
          }
          int boardNumber = int.tryParse(tag[1]) ?? -1;
          if (boardNumber == -1) {
            logger.w("Invalid board number in tag: $tag");
            continue;
          }

          // Use the first character of the tag to determine the field
          String fieldTag = tag[0];

          // Handle the parsed field tag and value for each board
          switch (fieldTag) {
            case 'r':
              if (boardNumber == 1) {
                boardRole1 = fieldValue;
                logger.i("Board 1 Role set to: $boardRole1");
              } else if (boardNumber == 2) {
                boardRole2 = fieldValue;
                logger.i("Board 2 Role set to: $boardRole2");
              }
              break;

            case 'n':
              if (boardNumber == 1) {
                nameBoard1 = fieldValue;
                logger.i("Board 1 Name set to: $nameBoard1");
              } else if (boardNumber == 2) {
                nameBoard2 = fieldValue;
                logger.i("Board 2 Name set to: $nameBoard2");
              }
              break;

            case 'm':
              if (boardNumber == 1) {
                macAddrBoard1 = fieldValue;
                logger.i("MAC Addr Board 1 set to: $macAddrBoard1");
              } else if (boardNumber == 2) {
                macAddrBoard2 = fieldValue;
                logger.i("MAC Addr Board 2 set to: $macAddrBoard2");
              }
              break;

            case 'i':
              if (boardNumber == 1) {
                ipAddrBoard1 = fieldValue;
                logger.i("IP Addr Board 1 set to: $ipAddrBoard1");
              } else if (boardNumber == 2) {
                ipAddrBoard2 = fieldValue;
                logger.i("IP Addr Board 2 set to: $ipAddrBoard2");
              }
              break;

            case 'l':
              int batteryLevel = int.tryParse(fieldValue) ?? 0;
              if (boardNumber == 1) {
                batteryLevelBoard1 = batteryLevel;
                logger.i("Battery Level Board 1 set to: $batteryLevelBoard1%");
              } else if (boardNumber == 2) {
                batteryLevelBoard2 = batteryLevel;
                logger.i("Battery Level Board 2 set to: $batteryLevelBoard2%");
              }
              break;

            case 'v':
              int batteryVoltage = int.tryParse(fieldValue) ?? 0;
              if (boardNumber == 1) {
                batteryVoltageBoard1 = batteryVoltage;
                logger.i(
                    "Battery Voltage Board 1 set to: $batteryVoltageBoard1 V");
              } else if (boardNumber == 2) {
                batteryVoltageBoard2 = batteryVoltage;
                logger.i(
                    "Battery Voltage Board 2 set to: $batteryVoltageBoard2 V");
              }
              break;

            default:
              logger.w("Unexpected field tag: $fieldTag");
              break;
          }
        }
        if (infoScreenState != null) {
          infoScreenState!.setState(() {});
        }
      });
    } catch (e) {
      logger.e("Error handling notification: $e");
      setState(() {
        connectionInfo = "Error parsing notification";
      });
    }
  }

// Separate function for handling settings response
  void handleSettingsResponse(String settings) {
    logger.i("Handling settings response: $settings");

    // Split the settings data by ';'
    List<String> settingsData = settings.split(';');
    for (var setting in settingsData) {
      if (setting.isEmpty) continue;

      // Handle each setting based on its prefix
      if (setting.startsWith("SSID:")) {
        ssid = setting.substring(5);
        logger.i("SSID set to: $ssid");
      } else if (setting.startsWith("PW:")) {
        password = setting.substring(3);
        logger.i("Password set to: $password");
      } else if (setting.startsWith("R1:")) {
        boardRole1 = setting.substring(3);
        logger.i("Board 1 Name set to: $boardRole1");
      } else if (setting.startsWith("R2:")) {
        boardRole2 = setting.substring(3);
        logger.i("Board 2 Name set to: $boardRole2");
      } else if (setting.startsWith("B1:")) {
        nameBoard1 = setting.substring(3);
        logger.i("Board 1 Name set to: $nameBoard1");
      } else if (setting.startsWith("B2:")) {
        nameBoard2 = setting.substring(3);
        logger.i("Board 2 Name set to: $nameBoard2");
      } else if (setting.startsWith("BRIGHT:")) {
        initialBrightness =
            double.tryParse(setting.substring(7)) ?? initialBrightness;
        logger.i("Brightness set to: $initialBrightness");
      } else if (setting.startsWith("SIZE:")) {
        blockSize = double.tryParse(setting.substring(5)) ?? blockSize;
        logger.i("Size set to: $blockSize");
      } else if (setting.startsWith("SPEED:")) {
        effectSpeed = double.tryParse(setting.substring(6)) ?? effectSpeed;
        logger.i("Speed set to: $effectSpeed");
      } else if (setting.startsWith("CELEB:")) {
        celebrationDuration =
            double.tryParse(setting.substring(6)) ?? celebrationDuration;
        logger.i("Celebration duration set to: $celebrationDuration");
      } else if (setting.startsWith("TIMEOUT:")) {
        inactivityTimeout =
            double.tryParse(setting.substring(8)) ?? inactivityTimeout;
        logger.i("Inactivity timeout set to: $inactivityTimeout");
      } else {
        logger.w("Unexpected setting received: $setting");
      }
    }

    // After settings are processed, update the UI
    setupScreenState?.updateUIWithCurrentSettings();
  }

  Future<void> sendCommand(String command) async {
    if (writeCharacteristic != null) {
      sendLargeMessage(writeCharacteristic!, (command));
      logger.i("Command sent: $command");
    } else {
      logger.e("Write characteristic is null");
      disconnectDevice();
    }
  }

  void sendLargeMessage(
      BluetoothCharacteristic characteristic, String message) async {
    int chunkSize = 20;
    int messageLength = message.length;
    int totalChunks = (messageLength + chunkSize - 1) ~/ chunkSize;

    for (int i = 0; i < totalChunks; i++) {
      int chunkStart = i * chunkSize;
      int chunkEnd = chunkStart + chunkSize < messageLength
          ? chunkStart + chunkSize
          : messageLength;

      String chunk = message.substring(chunkStart, chunkEnd);

      List<int> bytes = utf8.encode(chunk);
      await characteristic.write(bytes);
      await Future.delayed(
          const Duration(milliseconds: 50)); // Delay to prevent congestion
    }
  }

  void sendColorIndex(int colorIndex) {
    setState(() {
      activeColorIndex = colorIndex;
    });
    sendCommand('ColorIndex:$colorIndex;');
  }

  void sendEffect(String effect) {
    setState(() {
      activeEffect = effect;
    });
    sendCommand('Effect:$effect;');
  }

  void sendBrightness(int brightnessPercent) {
    int brightnessValue = (brightnessPercent * 255 / 100).round();
    sendCommand('brightness:$brightnessValue;');
  }

  void requestCurrentSettings() {
    sendCommand("GET_SETTINGS;");
  }

  void toggleWiFi() {
    setState(() {
      wifiEnabled = !wifiEnabled;
    });
    logger.i("WiFi toggled: ${wifiEnabled ? 'on' : 'off'}");
    sendCommand('toggleWiFi:${wifiEnabled ? 'on' : 'off'};');
  }

  void toggleLights() {
    setState(() {
      lightsOn = !lightsOn;
    });
    logger.i("Lights toggled: ${lightsOn ? 'on' : 'off'}");
    sendCommand('toggleLights:${lightsOn ? 'on' : 'off'};');
  }

  void toggleEspNow() {
    setState(() {
      espNowEnabled = !espNowEnabled;
    });
    logger.i("ESP-NOW toggled: ${espNowEnabled ? 'on' : 'off'}");
    sendCommand('toggleEspNow:${espNowEnabled ? 'on' : 'off'};');
  }

  void sendRestart() {
    sendCommand('Restart;');
  }

// Inside HomeScreenState class

  void navigateToInfoScreen() async {
    final result = await Navigator.pushNamed(context, '/info', arguments: {
      'wifiEnabled': wifiEnabled,
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
      'homeScreenState': this, // Ensure this is correctly passed
    });

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        wifiEnabled = result['wifiEnabled'] ?? wifiEnabled;
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
        'sendCommand': sendCommand, // Pass the sendCommand function
      },
    );

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        wifiEnabled = result['wifiEnabled'] ?? wifiEnabled;
        lightsOn = result['lightsOn'] ?? lightsOn;
        espNowEnabled = result['espNowEnabled'] ?? espNowEnabled;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.blue,
        elevation: 0,
        title: const Center(
          child: Text(
            'Cornhole LED Controller',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        actions: [
          Center(
            child: Row(
              children: [
                const SizedBox(width: 5),
                IconButton(
                  icon: const Icon(Icons.info),
                  onPressed: navigateToInfoScreen,
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
                  isConnected ? buildControlScreen() : buildDeviceList(),
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

  Widget buildDeviceList() {
    return Column(
      children: [
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: scanForDevices,
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.blue,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            shadowColor: Colors.black,
            elevation: 5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('Rescan for Devices'),
        ),
        const SizedBox(height: 20),
        ListView.builder(
          shrinkWrap: true,
          itemCount: devicesList.length,
          itemBuilder: (context, index) {
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListTile(
                title: Text(
                  devicesList[index].platformName.isNotEmpty
                      ? devicesList[index].platformName
                      : 'Unknown Device', // Provide a default value
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                trailing: ElevatedButton(
                  onPressed: () {
                    connectToDevice(devicesList[index]);
                  },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Connect',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
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
              sendBrightness(brightness);
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
      onPressed: () => sendColorIndex(colorIndex),
    );
  }

  Widget buildEffectButton(String label, String effect, {double? width}) {
     return EffectButton(
      activeShadowColor: colors[activeColorIndex],
      label: label,
      isActive: activeEffect == effect,
      onPressed: () => sendEffect(effect),
    );
  }
}
