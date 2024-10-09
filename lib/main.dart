import 'dart:async'; // Required for Timer
import 'dart:convert'; // Required for utf8.encode
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:logger/logger.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:numberpicker/numberpicker.dart';
import 'package:quantity_input/quantity_input.dart';
import 'global.dart';


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cornhole LED Controller',
      home: const HomeScreen(),
      routes: {
        '/info': (context) => const InfoScreen(),
        '/setup': (context) => const SetupScreen(),
        '/ota': (context) => const OTAScreen(),
      },
    );
  }
}

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
  String connectionInfo = "";
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
    initializeBluetooth();

    // Assuming you manage Bluetooth connections in the app
    //manageBluetoothState(device);

    // After connection is established
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

    // Extract chunk metadata
    int separatorIndex = data.indexOf(":");
    if (separatorIndex != -1) {
      String chunkInfo = data.substring(0, separatorIndex);
      String chunkContent = data.substring(separatorIndex + 1);

      int currentChunk = int.parse(chunkInfo.split("/")[0]);
      totalChunks = int.parse(chunkInfo.split("/")[1]);

      // Append the chunk content
      receivedMessage += chunkContent;
      receivedChunks++;

      if (receivedChunks == totalChunks) {
        // Full message received
        logger.i("Full message received: $receivedMessage");
        handleNotification(receivedMessage);

        // Reset for the next message
        receivedMessage = "";
        receivedChunks = 0;
      }
    }
  }

  void handleNotification(String value) {
    logger.i("Received notification: $value");

    try {
      setState(() {
        if (value.startsWith("Color:")) {
          // Handle color data
          final rgbValues = value.substring(6).split(',');
          if (rgbValues.length == 3) {
            final r = int.parse(rgbValues[0]);
            final g = int.parse(rgbValues[1]);
            final b = int.parse(rgbValues[2]);
            activeColorIndex = getColorIndexFromRGB(r, g, b);
            logger.i(
                "Active color set to: R=$r, G=$g, B=$b, Index=$activeColorIndex");
          } else {
            logger.w("Color data is incomplete or malformed.");
          }
        } else if (value.startsWith("Effect:")) {
          // Handle effect data
          activeEffect = value.substring(7);
          logger.i("Active effect set to: $activeEffect");
        } else if (value.startsWith("1:") || value.startsWith("2:")) {
          // Handle board settings
          final boardId = value.substring(0, 1);
          final settingsData = value.substring(2).split(';');
          for (var setting in settingsData) {
            if (setting.startsWith("n$boardId:")) {
              if (boardId == "1") {
                nameBoard1 = setting.substring(3);
              } else {
                nameBoard2 = setting.substring(3);
              }
            } else if (setting.startsWith("m$boardId:")) {
              if (boardId == "1") {
                macAddrBoard1 = setting.substring(3);
              } else {
                macAddrBoard2 = setting.substring(3);
              }
            } else if (setting.startsWith("i$boardId:")) {
              if (boardId == "1") {
                ipAddrBoard1 = setting.substring(3);
              } else {
                ipAddrBoard2 = setting.substring(3);
              }
            } else if (setting.startsWith("l$boardId:")) {
              final level = int.parse(setting.substring(3));
              if (boardId == "1") {
                batteryLevelBoard1 = level;
              } else {
                batteryLevelBoard2 = level;
              }
            } else if (setting.startsWith("v$boardId:")) {
              final voltage = int.parse(setting.substring(3));
              if (boardId == "1") {
                batteryVoltageBoard1 = voltage;
              } else {
                batteryVoltageBoard2 = voltage;
              }
            } else {
              logger.w("Unexpected setting received: $setting");
            }
          }
        } else if (value.startsWith("S:")) {
          // Handle settings data
          final settingsData = value.substring(2).split(';');
          for (var setting in settingsData) {
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
              initialBrightness =
                  double.tryParse(setting.substring(7)) ?? initialBrightness;
              logger.i("Brightness set to: $initialBrightness");
            } else if (setting.startsWith("SIZE:")) {
              blockSize = double.tryParse(setting.substring(5)) ?? blockSize;
              logger.i("Size set to: $blockSize");
            } else if (setting.startsWith("SPEED:")) {
              effectSpeed =
                  double.tryParse(setting.substring(6)) ?? effectSpeed;
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
          setupScreenState?.updateUIWithCurrentSettings();
        } else {
          logger.w("Unknown notification tag received");
        }

        // Update connection information display
        connectionInfo = "$nameBoard1, MAC: $macAddrBoard1, IP: $ipAddrBoard1, "
            "Battery: $batteryLevelBoard1%, Voltage: $batteryVoltageBoard1 V";
      });
    } catch (e) {
      logger.e("Error handling notification: $e");
      setState(() {
        connectionInfo = "Error parsing notification";
        isLoading = false; // Stop loading spinner even if there's an error
      });
    }
  }

  Future<void> sendCommand(String command) async {
    //  logger.i("Sending command: $command");
    if (writeCharacteristic != null) {
      sendLargeMessage(writeCharacteristic!, (command));
//      writeCharacteristic!.write(utf8.encode(command));
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

      String chunk =
//          "${i + 1}/$totalChunks:${message.substring(chunkStart, chunkEnd)}";
          message.substring(chunkStart, chunkEnd);

      List<int> bytes = utf8.encode(chunk);
      await characteristic.write(bytes);
      await Future.delayed(
          Duration(milliseconds: 50)); // Delay to prevent congestion
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
    int brightness = (brightnessPercent * 255 / 100).round();
    sendCommand('brightness:$brightness;');
  }

  void requestCurrentSettings() {
    // Assuming you have a method to send data over BLE
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

  void updateBatteryLevel() async {
    // Implement battery level update logic if applicable
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
          Background(),
          SingleChildScrollView(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  isConnected ? buildControlScreen() : buildDeviceList(),
                  const SizedBox(height: 20),
                  StatusIndicators(),
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
          // Container to create the border effect
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

    if (result != null) {
      final data = result as Map<String, dynamic>;
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

    if (result != null) {
      final data = result as Map<String, dynamic>;
      setState(() {
        wifiEnabled = result['wifiEnabled'] ?? wifiEnabled;
        lightsOn = result['lightsOn'] ?? lightsOn;
        espNowEnabled = result['espNowEnabled'] ?? espNowEnabled;
      });
    }
  }
}

class InfoScreen extends StatefulWidget {
  const InfoScreen({super.key});

  @override
  InfoScreenState createState() => InfoScreenState();
}

class InfoScreenState extends State<InfoScreen> {
  final Logger logger = Logger();
  HomeScreenState? homeScreenState; // Store HomeScreenState reference

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Map<String, dynamic> args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;

    wifiEnabled = args['wifiEnabled'] as bool? ?? true;
    lightsOn = args['lightsOn'] as bool? ?? false;
    espNowEnabled = args['espNowEnabled'] as bool? ?? false;
    connectionInfo = args['connectionInfo'] as String? ?? '';

    nameBoard1 = args['nameBoard1'] as String? ?? 'Unknown';
    macAddrBoard1 = args['macAddrBoard1'] as String? ?? 'Unknown';
    ipAddrBoard1 = args['ipAddrBoard1'] as String? ?? 'Unknown';
    batteryLevelBoard1 = args['batteryLevelBoard1'] as int? ?? 0;
    batteryVoltageBoard1 = args['batteryVoltageBoard1'] as int? ?? 0;

    nameBoard2 = args['nameBoard2'] as String? ?? 'Unknown';
    macAddrBoard2 = args['macAddrBoard2'] as String? ?? 'Unknown';
    ipAddrBoard2 = args['ipAddrBoard2'] as String? ?? 'Unknown';
    batteryLevelBoard2 = args['batteryLevelBoard2'] as int? ?? 0;
    batteryVoltageBoard2 = args['batteryVoltageBoard2'] as int? ?? 0;

    homeScreenState = args['homeScreenState'] as HomeScreenState?;
    homeScreenState!.sendCommand('GET_INFO;');

    extractConnectionInfo(connectionInfo);
  }

  void extractConnectionInfo(String info) {
    try {
      var infoParts = info.split(', ');
      if (infoParts.isNotEmpty) {
        nameBoard1 = infoParts[0];
      } else {
        nameBoard1 = 'Unknown';
      }
    } catch (e) {
      nameBoard1 = 'Error';
    }
  }

  void toggleSwitch(String command, bool status) {
    final completeCommand = '$command:${status ? 'on' : 'off'}';
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
            Background(),
            SingleChildScrollView(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20),
                    isConnected ? buildControlScreen() : HomeScreen(),
                    const SizedBox(height: 20),
                    StatusIndicators(),
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
                connectionInfo.isNotEmpty
                    ? buildConnectionTable()
                    : const Text('No connection info available'),
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
        buildTableRow('Name', nameBoard1, nameBoard2),
        buildTableRow('MAC', macAddrBoard1, macAddrBoard2),
        buildTableRow('IP', ipAddrBoard1, ipAddrBoard2),
        buildTableRow(
            'Voltage', '$batteryVoltageBoard1 V', '$batteryVoltageBoard2 V'),
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

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  SetupScreenState createState() => SetupScreenState();
}

class SetupScreenState extends State<SetupScreen> {
  late TextEditingController boardName1Controller;
  late TextEditingController boardName2Controller;
  late TextEditingController ssidController;
  late TextEditingController passwordController;
  bool setupComplete = false;

  void runSetup() {
    setupComplete = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ensure GET_SETTINGS is only sent once
    if (!setupComplete) {
      final Map<String, dynamic> args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;

      ssid = args['ssid'] as String? ?? '';
      password = args['password'] as String? ?? '';
      previousNameBoard1 = args['nameBoard1'] as String?;
      previousNameBoard2 = args['nameBoard2'] as String?;
      previousInitialBrightness = args['initialBrightness'] as double?;
      previousBlockSize = args['blockSize'] as double?;
      previousEffectSpeed = args['effectSpeed'] as double?;
      previousCelebrationDuration = args['celebrationDuration'] as double?;
      previousInactivityTimeout = args['inactivityTimeout'] as double?;
      sportEffectColor1 = args['sportEffectColor1'] as Color? ?? Colors.red;
      sportEffectColor2 = args['sportEffectColor2'] as Color? ?? Colors.blue;
      initialStartupColor =
          args['initialStartupColor'] as Color? ?? Colors.white;

      ssidController = TextEditingController(text: ssid);
      passwordController = TextEditingController(text: password);
      boardName1Controller = TextEditingController(text: previousNameBoard1);
      boardName2Controller = TextEditingController(text: previousNameBoard2);

      homeScreenState = args['homeScreenState'] as HomeScreenState?;
      if (homeScreenState != null) {
        setState(() {
          isLoading = true; // Show loading indicator
        });
        homeScreenState!.sendCommand('GET_SETTINGS;');
        setupComplete =
            true; // Set this flag to true after sending GET_SETTINGS
        isLoading = false;
      } else {
        logger.e("HomeScreenState is null, cannot request settings");
      }
    }
  }

  void saveWiFiSettings() {
    final List<String> commands = [];

    final currentssid = ssidController.text;
    final currentpassword = passwordController.text;

    if (currentpassword != previousssid) {
      commands.add('SSID:$currentssid');
      previousssid = currentssid;
    }
    if (currentpassword != previouspassword) {
      commands.add('PW:$currentpassword');
      previouspassword = currentpassword;
    }

    if (commands.isNotEmpty && homeScreenState != null) {
      final batchCommand = commands.join(';');
      homeScreenState!.sendCommand(batchCommand);
    } else if (commands.isEmpty) {
      logger.i("No changes detected, no commands sent");
    } else {
      logger.w("SSID or Password is null or empty, commands not sent");
    }
  }

  void saveDefaultSettings() {
    final List<String> commands = [];

    final currentNameBoard1 = boardName1Controller.text;
    final currentNameBoard2 = boardName2Controller.text;
    final currentInitialBrightness = initialBrightness;
    final currentBlockSize = blockSize;
    final currentEffectSpeed = effectSpeed;
    final currentCelebrationDuration = celebrationDuration;
    final currentInactivityTimeout = inactivityTimeout;

    if (currentNameBoard1 != previousNameBoard1) {
      commands.add('B1:$currentNameBoard1');
      previousNameBoard1 = currentNameBoard1;
    }
    if (currentNameBoard2 != previousNameBoard2) {
      commands.add('B2:$currentNameBoard2');
      previousNameBoard2 = currentNameBoard2;
    }
    if (currentInitialBrightness != previousInitialBrightness) {
      commands.add('BRIGHT:$currentInitialBrightness');
      previousInitialBrightness = currentInitialBrightness;
    }
    if (currentBlockSize != previousBlockSize) {
      commands.add('SIZE:$currentBlockSize');
      previousBlockSize = currentBlockSize;
    }
    if (currentEffectSpeed != previousEffectSpeed) {
      commands.add('SPEED:$currentEffectSpeed');
      previousEffectSpeed = currentEffectSpeed;
    }
    if (currentCelebrationDuration != previousCelebrationDuration) {
      commands.add('CELEB:$currentCelebrationDuration');
      previousCelebrationDuration = currentCelebrationDuration;
    }
    if (currentInactivityTimeout != previousInactivityTimeout) {
      commands.add('TIMEOUT:$currentInactivityTimeout');
      previousInactivityTimeout = currentInactivityTimeout;
    }
    if (initialStartupColor != previousInitialStartupColor) {
      sendColorToMaster('INITIALCOLOR', initialStartupColor);
      previousInitialStartupColor = initialStartupColor;
    }

    if (sportEffectColor1 != previousSportEffectColor1) {
      sendColorToMaster('SPORTCOLOR1', sportEffectColor1);
      previousSportEffectColor1 = sportEffectColor1;
    }

    if (sportEffectColor2 != previousSportEffectColor2) {
      sendColorToMaster('SPORTCOLOR2', sportEffectColor2);
      previousSportEffectColor2 = sportEffectColor2;
    }
    if (commands.isNotEmpty && homeScreenState != null) {
      final batchCommand = '${commands.join(';')};';
      homeScreenState!.sendCommand(batchCommand);
    } else if (commands.isEmpty) {
      logger.i("No changes detected, no commands sent");
    } else {
      logger.e("HomeScreenState is null, cannot send commands");
    }
  }

  void onBackButtonPressed() {
    Navigator.pop(context, {
      'wifiEnabled': wifiEnabled,
      'lightsOn': lightsOn,
      'espNowEnabled': espNowEnabled,
    });
  }

  void updateUIWithCurrentSettings() {
    setState(() {
      boardName1Controller.text = nameBoard1;
      boardName2Controller.text = nameBoard2;
      initialBrightness = initialBrightness;
      blockSize = blockSize;
      effectSpeed = effectSpeed;
      celebrationDuration = celebrationDuration;
      inactivityTimeout = inactivityTimeout;

      previousNameBoard1 = nameBoard1;
      previousNameBoard2 = nameBoard2;
      previousInitialBrightness = initialBrightness;
      previousBlockSize = blockSize;
      previousEffectSpeed = effectSpeed;
      previousCelebrationDuration = celebrationDuration;
      previousInactivityTimeout = inactivityTimeout;
      isLoading = false;
      logger.i("Settings received and UI updated, isLoading set to false");
    });
  }

  void sendColorToMaster(String colorName, Color color) {
    int red = (color.value >> 16) & 0xFF;
    int green = (color.value >> 8) & 0xFF;
    int blue = (color.value) & 0xFF;

    String command = '$colorName:$red,$green,$blue';
    homeScreenState!.sendCommand(command);
  }

  void saveColorSelection(String label, Color color) {
    final r = color.red;
    final g = color.green;
    final b = color.blue;

    String command;

    if (label == "Initial Startup Color") {
      command = 'INITIALCOLOR:$r,$g,$b';
    } else if (label == "Color 1") {
      command = 'SPORTCOLOR1:$r,$g,$b';
    } else if (label == "Color 2") {
      command = 'SPORTCOLOR2:$r,$g,$b';
    } else {
      logger.w("Unknown color label: $label");
      return;
    }

    if (homeScreenState != null) {
      homeScreenState!.sendCommand(command);
      logger.i("Sent command: $command");
    } else {
      logger.e("HomeScreenState is null, cannot send commands");
    }
  }

  void clearSavedVariables() {
    if (homeScreenState != null) {
      homeScreenState!.sendCommand('CLEAR_ALL;');
      logger.i("Sent command to clear all saved variables on both boards.");
    } else {
      logger.e("HomeScreenState is null, cannot send commands");
    }
  }

  @override
  Widget build(BuildContext context) {
    return isLoading
        ? Center(child: CircularProgressIndicator())
        : WillPopScope(
            onWillPop: () async {
              onBackButtonPressed();
              return false;
            },
            child: Scaffold(
              appBar: AppBar(
                backgroundColor: Colors.blue,
                elevation: 0,
                title: const Text('Setup Screen'),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: onBackButtonPressed,
                ),
              ),
              body: Stack(
                children: [
                  Background(),
                  Padding(
                    padding: const EdgeInsets.all(5.0),
                    child: ListView(
                      children: [
                        const SizedBox(height: 20),
                        isConnected ? buildControlScreen() : HomeScreen(),
                        const SizedBox(height: 20),
                        StatusIndicators(),
                      ],
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
          title: 'Wifi Settings',
          content: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [buildWiFiSettingsContainer()],
          ),
        ),
        const SizedBox(height: 15),
        Section(
          title: 'Default Settings',
          content: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [buildDefaultSettingsContainer()],
          ),
        ),
        const SizedBox(height: 15),
        Section(
          title: 'Clear all settings',
          content: Wrap(
            children: [buildClearSettingsContainer()],
          ),
        ),
      ],
    );
  }

  Widget buildWiFiSettingsContainer() {
    return Container(
      padding: const EdgeInsets.all(10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TextField(
            controller: ssidController,
            decoration: const InputDecoration(
              labelText: "WiFi SSID",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: passwordController,
            decoration: const InputDecoration(
              labelText: "WiFi Password",
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.bottomRight,
            child: ElevatedButton(
              onPressed: saveWiFiSettings,
              child: const Text("Save WiFi Settings"),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildDefaultSettingsContainer() {
    return Container(
      padding: const EdgeInsets.all(5.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TextField(
            controller: boardName1Controller,
            decoration: const InputDecoration(
              labelText: "Board 1 Name",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: boardName2Controller,
            decoration: const InputDecoration(
              labelText: "Board 2 Name",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(
            color: Colors.blue,
            thickness: 2,
          ),
          const SizedBox(height: 20),
          buildSlider("Initial Brightness", initialBrightness, (value) {
            setState(() {
              initialBrightness = value;
            });
          }),
          const SizedBox(height: 20),

          // First Row
          Row(
            children: [
              Expanded(
                child: buildQuantityInput(
                    "Effects Size", blockSize.round(), 1, 30, 1, (value) {
                  setState(() {
                    blockSize = value.toDouble();
                  });
                }),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: buildQuantityInput(
                    "Effects Speed", effectSpeed.round(), 1, 50, 1, (value) {
                  setState(() {
                    effectSpeed = value.toDouble();
                  });
                }),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Second Row
          Row(
            children: [
              Expanded(
                child: buildQuantityInput("Scoring Duration",
                    (celebrationDuration / 1000).round(), 1, 10, 1, (value) {
                  setState(() {
                    celebrationDuration = value * 1000;
                  });
                }),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: buildQuantityInput(
                    "Inactivity Timeout", inactivityTimeout.round(), 0, 60, 5,
                    (value) {
                  setState(() {
                    inactivityTimeout = value.toDouble();
                  });
                }),
              ),
            ],
          ),
          const Divider(
            color: Colors.blue,
            thickness: 2,
          ),
          buildInitialColorPicker(),
          const SizedBox(height: 20),
          const Divider(
            color: Colors.blue,
            thickness: 2,
          ),
          const Center(
            child: Text(
              "Sport Effect Colors",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: buildColorPicker("Color 1", sportEffectColor1, (color) {
                  setState(() {
                    sportEffectColor1 = color;
                  });
                }),
              ),
              Expanded(
                child: buildColorPicker("Color 2", sportEffectColor2, (color) {
                  setState(() {
                    sportEffectColor2 = color;
                  });
                }),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.bottomRight,
            child: ElevatedButton(
              onPressed: () {
                saveDefaultSettings();
              },
              child: const Text("Save Default Settings"),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildClearSettingsContainer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.bottomRight,
          child: ElevatedButton(
            onPressed: () async {
              bool? confirmed = await showDialog<bool>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text("Are you sure?"),
                    content: const Text(
                        "This will clear all saved variables on both boards."),
                    actions: [
                      TextButton(
                        child: const Text("Cancel"),
                        onPressed: () {
                          Navigator.of(context).pop(false);
                        },
                      ),
                      TextButton(
                        child: const Text("Confirm"),
                        onPressed: () {
                          Navigator.of(context).pop(true);
                        },
                      ),
                    ],
                  );
                },
              );

              if (confirmed == true) {
                clearSavedVariables();
              }
            },
            child: const Text("Clear Settings"),
          ),
        ),
      ],
    );
  }

  Widget buildQuantityInput(String label, int initialValue, int minValue,
      int maxValue, int step, Function(int) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        QuantityInput(
          value: initialValue,
          minValue: minValue,
          maxValue: maxValue,
          step: step,
          onChanged: (value) {
            onChanged(int.parse(value.replaceAll(',', '')));
          },
          decoration: InputDecoration(),
        ),
      ],
    );
  }

  Widget buildSlider(
      String label, double value, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        Slider(
          value: value,
          min: 0,
          max: 150,
          divisions: ((100 - 5) / 5).toInt(),
          label: value.round().toString(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget buildInitialColorPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          "Select Initial Startup Color",
          style: TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: colors.map((color) {
            return GestureDetector(
              onTap: () {
                setState(() {
                  initialStartupColor = color;
                });
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: initialStartupColor == color
                        ? Colors.black
                        : Colors.transparent,
                    width: 2.0,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget buildColorPicker(
      String label, Color currentColor, ValueChanged<Color> onColorChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () async {
            Color? pickedColor; // Declare pickedColor before using it

            pickedColor = await showDialog(
              context: context,
              builder: (context) {
                return AlertDialog(
                  title: const Text("Pick a Color"),
                  content: SingleChildScrollView(
                    child: ColorPicker(
                      pickerColor: currentColor,
                      onColorChanged: (color) {
                        pickedColor = color; // Assign the picked color
                      },
                    ),
                  ),
                  actions: [
                    TextButton(
                      child: const Text("Select"),
                      onPressed: () {
                        Navigator.of(context).pop(pickedColor);
                      },
                    ),
                  ],
                );
              },
            );

            if (pickedColor != null) {
              onColorChanged(pickedColor!);
            }
          },
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: currentColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(width: 1.5, color: Colors.black),
            ),
          ),
        ),
      ],
    );
  }
}

class OTAScreen extends StatefulWidget {
  const OTAScreen({super.key});

  @override
  OTAScreenState createState() => OTAScreenState();
}

class OTAScreenState extends State<OTAScreen> {
  bool isUpdating = false;
  String updateStatus = "No updates available.";

  void checkForUpdates() async {
    setState(() {
      isUpdating = true;
      updateStatus = "Checking for updates...";
    });

    // Simulate checking for updates (replace with actual OTA logic)
    await Future.delayed(Duration(seconds: 2));

    setState(() {
      isUpdating = false;
      updateStatus = "Update available: Version 1.1.0";
    });
  }

  void startOTAUpdate() async {
    setState(() {
      isUpdating = true;
      updateStatus = "Starting update...";
    });

    // Simulate OTA update process (replace with actual OTA logic)
    await Future.delayed(Duration(seconds: 5));

    setState(() {
      isUpdating = false;
      updateStatus = "Update complete. Restarting device...";
    });

    // Simulate device restart
    await Future.delayed(Duration(seconds: 2));
    Logger().i("Device restarted after OTA update.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("OTA Update"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "OTA Update",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Text(updateStatus),
            SizedBox(height: 20),
            if (!isUpdating) ...[
              ElevatedButton(
                onPressed: checkForUpdates,
                child: Text("Check for Updates"),
              ),
              SizedBox(height: 10),
              ElevatedButton(
                onPressed: startOTAUpdate,
                child: Text("Start Update"),
              ),
            ] else ...[
              CircularProgressIndicator(),
            ],
            const SizedBox(height: 20),
            StatusIndicators(),
          ],
        ),
      ),
    );
  }
}

class Section extends StatelessWidget {
  final String title;
  final Widget content;

  const Section({
    Key? key,
    required this.title,
    required this.content,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(.50),
        border: Border.all(width: 1.5, color: Colors.black),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.75),
            spreadRadius: 5,
            blurRadius: 7,
            offset: Offset(3, 3),
          ),
        ],
      ),
      width: MediaQuery.of(context).size.width * 0.9,
      constraints: const BoxConstraints(maxWidth: 600),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Divider(
            color: Colors.white,
            thickness: 2,
          ),
          content,
        ],
      ),
    );
  }
}

class StatusIndicators extends StatelessWidget {
  const StatusIndicators({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        isConnected
            ? Text(
                'Connected',
                style: const TextStyle(
                    color: Colors.green, fontWeight: FontWeight.bold),
              )
            : const Text(
                'Not connected',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
        Text(
          'WiFi: ${wifiEnabled ? "Enabled" : "Disabled"}',
          style:
              const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
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

class Background extends StatelessWidget {
  const Background({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/background.jpg', // Ensure this path is correct
            fit: BoxFit.cover,
          ),
        ),
      ],
    );
  }
}
