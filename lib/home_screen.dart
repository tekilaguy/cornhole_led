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

    // Extract chunk metadata (if applicable)
    // Handle data processing and message reconstruction

    handleNotification(data);
  }

  void handleNotification(String value) {
    logger.i("Received notification: $value");

    try {
      setState(() {
        // Handle different types of messages based on prefixes
        // Update global variables accordingly
        // Update connectionInfo string
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
