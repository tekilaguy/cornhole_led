// home_screen.dart
import 'dart:async'; // Required for Timer
import 'dart:convert'; // Required for utf8.encode
import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:logger/logger.dart';
import 'global.dart';
import 'info_screen.dart';
import 'setup_screen.dart';
import 'widgets/background.dart';
import 'widgets/section.dart';
import 'widgets/status_indicators.dart';

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
    FlutterBlue.instance.state.listen((state) {
      if (state == BluetoothState.on) {
        scanForDevices();
      } else {
        logger.w("Bluetooth is not enabled. Please enable Bluetooth.");
      }
    });
  }

  void manageBluetoothState(BluetoothDevice device) {
    device.state.listen((state) {
      if (state == BluetoothDeviceState.connected) {
        logger.i("Device connected: ${device.name}");
        setState(() {
          isConnected = true;
          connectedDevice = device;
        });
        discoverServices(device);
      } else if (state == BluetoothDeviceState.disconnected) {
        logger.w("Device disconnected: ${device.name}");
        setState(() {
          isConnected = false;
          connectedDevice = null;
        });
        attemptReconnection(device);
      }
    });
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    logger.i("Connecting to device: ${device.name}");
    try {
      await device.connect(autoConnect: false);
      await device.requestMtu(240);
      manageBluetoothState(device); // Consolidate state management
    } catch (e) {
      logger.e("Cannot connect, exception occurred: $e");
      setState(() {
        isConnected = false;
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
          await device.connect();
          logger.i("Reconnected to device: ${device.name}");
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
          notifyCharacteristic?.value.listen((value) {
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
    FlutterBlue.instance.startScan(timeout: const Duration(seconds: 4));
    FlutterBlue.instance.scanResults.listen((results) {
      for (ScanResult r in results) {
        String deviceName = r.device.name;
        if (deviceName != null && deviceName.isNotEmpty) {
          logger.i("Found device: $deviceName");
          if (deviceName == "CornholeBT" && !isConnected) {
            logger.i("Attempting to connect to CornholeBT...");
            connectToDevice(r.device);
            FlutterBlue.instance.stopScan();
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
    logger.i("Received value: $data");

    // Append the received data to the message buffer
    receivedMessage += data;

    // Process all complete messages
    int endIndex;
    while ((endIndex = receivedMessage.indexOf("#")) != -1) {
      // Extract the complete message (up to the semicolon)
      String completeMessage = receivedMessage.substring(0, endIndex);
      logger.i("Full message received: $completeMessage");

      // Handle the full message
      handleNotification(completeMessage);

      // Remove the processed message from the buffer
      receivedMessage = receivedMessage.substring(endIndex + 1);
    }
  }

void handleNotification(String value) {
  logger.i("Received notification: $value");

  try {
    setState(() {
      // Ensure the message ends with `#`
      if (value.endsWith('#')) {
        value = value.substring(0, value.length - 1); // Remove the ending '#'
      } else {
        logger.w("Message does not end with '#'. Possible incomplete message.");
        return;
      }

      // Check if the message is a GET_SETTINGS response (start with "S:")
      if (value.startsWith("S:")) {
        handleSettingsResponse(value.substring(2));
        return;  // Exit after processing settings
      }

      // Split the entire message by `,` to get field-value pairs
      List<String> fields = value.split(',');
      for (var field in fields) {
        if (field.isEmpty) continue; // Skip empty entries

        // Split each field by `;` (tag;value)
        List<String> keyValue = field.split(';');
        if (keyValue.length != 2) {
          logger.w("Malformed field: $field");
          continue;
        }

        String tag = keyValue[0];
        String fieldValue = keyValue[1];

        // Extract the board number (second character in the tag)
        int boardNumber = int.parse(tag[1]);

        // Use the first character of the tag to determine the field
        String fieldTag = tag[0];

        // Handle the parsed field tag and value for each board
        switch (fieldTag) {
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
            int batteryLevel = int.parse(fieldValue);
            if (boardNumber == 1) {
              batteryLevelBoard1 = batteryLevel;
              logger.i("Battery Level Board 1 set to: $batteryLevelBoard1%");
            } else if (boardNumber == 2) {
              batteryLevelBoard2 = batteryLevel;
              logger.i("Battery Level Board 2 set to: $batteryLevelBoard2%");
            }
            break;

          case 'v':
            int batteryVoltage = int.parse(fieldValue);
            if (boardNumber == 1) {
              batteryVoltageBoard1 = batteryVoltage;
              logger.i("Battery Voltage Board 1 set to: $batteryVoltageBoard1 V");
            } else if (boardNumber == 2) {
              batteryVoltageBoard2 = batteryVoltage;
              logger.i("Battery Voltage Board 2 set to: $batteryVoltageBoard2 V");
            }
            break;

          default:
            logger.w("Unexpected field tag: $fieldTag");
            break;
        }
      }
    });
  } catch (e) {
    logger.e("Error handling notification: $e");
    setState(() {
      connectionInfo = "Error parsing notification";
      isLoading = false; // Stop loading spinner even if there's an error
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
    } else if (setting.startsWith("B1:")) {
      nameBoard1 = setting.substring(3);
      logger.i("Board 1 Name set to: $nameBoard1");
    } else if (setting.startsWith("B2:")) {
      nameBoard2 = setting.substring(3);
      logger.i("Board 2 Name set to: $nameBoard2");
    } else if (setting.startsWith("BRIGHT:")) {
      initialBrightness = double.tryParse(setting.substring(7)) ?? initialBrightness;
      logger.i("Brightness set to: $initialBrightness");
    } else if (setting.startsWith("SIZE:")) {
      blockSize = double.tryParse(setting.substring(5)) ?? blockSize;
      logger.i("Size set to: $blockSize");
    } else if (setting.startsWith("SPEED:")) {
      effectSpeed = double.tryParse(setting.substring(6)) ?? effectSpeed;
      logger.i("Speed set to: $effectSpeed");
    } else if (setting.startsWith("CELEB:")) {
      celebrationDuration = double.tryParse(setting.substring(6)) ?? celebrationDuration;
      logger.i("Celebration duration set to: $celebrationDuration");
    } else if (setting.startsWith("TIMEOUT:")) {
      inactivityTimeout = double.tryParse(setting.substring(8)) ?? inactivityTimeout;
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
    sendCommand('colorIndex:$colorIndex;');
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
    sendCommand('sendRestart;');
  }

// Inside HomeScreenState class

  void navigateToInfoScreen() async {
    final result = await Navigator.pushNamed(context, '/info', arguments: {
      'wifiEnabled': wifiEnabled,
      'lightsOn': lightsOn,
      'espNowEnabled': espNowEnabled,
      'isConnected': isConnected,
      'connectionInfo': connectionInfo,
      'nameBoard1': nameBoard1,
      'macAddrBoard1': macAddrBoard1,
      'ipAddrBoard1': ipAddrBoard1,
      'batteryLevelBoard1': batteryLevelBoard1,
      'batteryVoltageBoard1': batteryVoltageBoard1,
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
    final result = await Navigator.pushNamed(context, '/setup', arguments: {
      'ssid': ssid,
      'password': password,
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
                  devicesList[index].name.isNotEmpty
                      ? devicesList[index].name
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
            divisions: ((100 - 5) / 5).toInt(),
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
    return Container(
      margin: const EdgeInsets.all(5),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ElevatedButton(
            onPressed: () => sendColorIndex(colorIndex),
            style: ElevatedButton.styleFrom(
              backgroundColor: isActive ? Colors.black : colors[colorIndex],
              shadowColor: isActive ? colors[activeColorIndex] : Colors.black,
              elevation: isActive ? 15 : 25,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.all(20),
            ),
            child: null,
          ),
          if (isActive)
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: colors[colorIndex], // Inner circle with the active color
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }

  Widget buildEffectButton(String label, String effect, {double? width}) {
    bool isActive = effect == activeEffect;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      width: width ?? MediaQuery.of(context).size.width * 0.8,
      child: ElevatedButton(
        onPressed: () => sendEffect(effect),
        style: ElevatedButton.styleFrom(
          backgroundColor: isActive ? Colors.black : Colors.white,
          foregroundColor: isActive ? Colors.white : Colors.black,
          shadowColor: isActive ? colors[activeColorIndex] : Colors.black,
          elevation: isActive ? 15 : 25,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        ),
        child: Text(label),
      ),
    );
  }
}
