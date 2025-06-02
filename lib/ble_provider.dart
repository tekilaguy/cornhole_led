// ble_provider.dart

// ignore_for_file: unrelated_type_equality_checks

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';

import 'dart:convert';
import 'dart:async';
import 'global.dart';
import 'dart:io';
//import 'ble_mtu.dart';

class BLEProvider with ChangeNotifier {
  final Logger logger = Logger();

  List<BluetoothDevice> devicesList = [];
  // final Guid _otaServiceUuid = Guid("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
  final Guid _otaCharacteristicUuid =
      Guid("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
  final Guid _versionCharacteristicUuid =
      Guid("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");
  // final Guid _controlServiceUuid = Guid("baf6443e-a714-4114-8612-8fc18d1326f7");
  final Guid _controlCharacteristicUuid =
      Guid("5d650eb7-c41b-44f0-9704-3710f21e1c8e");

  BluetoothCharacteristic? otaCharacteristic;
  BluetoothCharacteristic? versionCharacteristic;

  BluetoothDevice? connectedDevice;
  BluetoothDevice? device;
  BluetoothCharacteristic? writeCharacteristic;
  BluetoothCharacteristic? notifyCharacteristic;
  StreamSubscription? adapterStateSubscription;
  StreamSubscription? scanResultsSubscription;
  StreamSubscription? connectionStateSubscription;
  Timer? reconnectTimer;
  static const reconnectDuration = Duration(seconds: 30);

  bool _shouldRefreshInfo = false;
  bool get shouldRefreshInfo => _shouldRefreshInfo;

  bool _isConnected = false;
  bool _lightsOn = true;
  bool _espNowEnabled = true;
  Color _initialStartupColor = Colors.blue;

  bool get isConnected => _isConnected;
  bool get lightsOn => _lightsOn;
  bool get espNowEnabled => _espNowEnabled;
  Color get initialStartupColor => _initialStartupColor;

  final int _negotiatedMtu = 512; // default BLE MTU
  int get negotiatedMtu => _negotiatedMtu;

  String normalizeMac(String mac) {
    return mac.replaceAll(":", "-").toLowerCase();
  }

  // Board 1
  String _boardRole1 = '';
  String _nameBoard1 = '';
  String _macAddrBoard1 = '';
  int _batteryVoltageBoard1 = 0;
  int _batteryLevelBoard1 = 0;

  // Board 2
  String _boardRole2 = '';
  String _nameBoard2 = '';
  String _macAddrBoard2 = '';
  int _batteryVoltageBoard2 = 0;
  int _batteryLevelBoard2 = 0;

  // Wi-Fi Credentials
  String _ssid = 'CornholeAP';
  String _password = 'Funforall';

  // Getters
  String get boardRole1 => _boardRole1;
  String get nameBoard1 => _nameBoard1;
  String get macAddrBoard1 => _macAddrBoard1;
  int get batteryVoltageBoard1 => _batteryVoltageBoard1;
  int get batteryLevelBoard1 => _batteryLevelBoard1;

  String get boardRole2 => _boardRole2;
  String get nameBoard2 => _nameBoard2;
  String get macAddrBoard2 => _macAddrBoard2;
  int get batteryVoltageBoard2 => _batteryVoltageBoard2;
  int get batteryLevelBoard2 => _batteryLevelBoard2;

  String get ssid => _ssid;
  String get password => _password;

  List<BoardInfo> _boards = [];
  List<BoardInfo> get boards => _boards;
  List<BoardInfo> get connectedBoards => _boards;

  void setConnected(bool value) {
    _isConnected = value;
    notifyListeners();
  }

  void markInfoStale() {
    _shouldRefreshInfo = true;
    notifyListeners();
  }

  void clearInfoRefreshFlag() {
    _shouldRefreshInfo = false;
  }

  void setLightsOn(bool value) {
    _lightsOn = value;
    notifyListeners();
  }

  void setEspNowEnabled(bool value) {
    _espNowEnabled = value;
    notifyListeners();
  }

  void setInitialStartupColor(Color color) {
    _initialStartupColor = color;
    notifyListeners();
  }

// Helper function
  int getColorIndexFromRGB(int r, int g, int b) {
    // Implement this function based on your app's logic
    return 0; // Placeholder
  }

  void updateBoards(List<BoardInfo> incomingBoards) {
    final Map<String, BoardInfo> uniqueBoards = {
      for (var board in _boards) board.mac: board, // keep existing
    };

    for (var board in incomingBoards) {
      uniqueBoards[board.mac] = board; // overwrite if same MAC
    }

    _boards = uniqueBoards.values.toList();
    notifyListeners();
  }

  Future<String?> readBoardVersion() async {
    if (versionCharacteristic == null) {
      logger.w("❌ versionCharacteristic is null");
      return null;
    }

    try {
      final raw = await versionCharacteristic!.read();
      final decoded = utf8.decode(raw);
      logger.i("📦 Board version read: $decoded");
      return decoded;
    } catch (e) {
      logger.e("❌ Failed to read board version: $e");
      return null;
    }
  }

  BLEProvider() {
    initializeBluetooth();
    if (isConnected) {
      requestCurrentSettings(); // Request the current settings from the board
    }
  }

  void initializeBluetooth() {
    adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        scanForDevices();
      } else {
        logger.w("Bluetooth is not enabled. Please enable Bluetooth.");
      }
    });
  }

  @override
  void dispose() {
    reconnectTimer?.cancel();
    adapterStateSubscription?.cancel();
    scanResultsSubscription?.cancel();
    connectionStateSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  void manageBluetoothState(BluetoothDevice device) {
    connectionStateSubscription?.cancel();
    connectionStateSubscription = device.connectionState.listen((state) async {
      logger.i("BLE Connection State Changed: $state");

      if (state == BluetoothConnectionState.connected) {
        logger.i("✅ Device connected: ${device.platformName}");

        _isConnected = true;
        connectedDevice = device;

        // Stop scanning manually (fixes iOS staying in scanning mode)
        FlutterBluePlus.stopScan();

        // Small delay for iOS to ensure proper state update
        if (Platform.isIOS) {
          await Future.delayed(const Duration(milliseconds: 500));
        }

        discoverServices(device);
        reconnectTimer?.cancel();

        logger.i("🔹 Notifying UI: _isConnected = $_isConnected");
        notifyListeners();
      } else if (state == BluetoothConnectionState.disconnected) {
        logger.w("⚠️ Device disconnected: ${device.platformName}");

        _isConnected = false;
        connectedDevice = null;

        // Ensure UI updates properly
        logger.i("🔹 Notifying UI: _isConnected = $_isConnected");
        notifyListeners();

        // Attempt reconnection if needed
        attemptReconnection(device);
      }
    });
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    logger.i("Connecting to device: ${device.platformName}");
    try {
      if (Platform.isIOS) {
        await Future.delayed(const Duration(seconds: 1)); // iOS stability delay
      }

      await device.connect(autoConnect: false);
      FlutterBluePlus.stopScan();
      await Future.delayed(Duration(milliseconds: 500)); // allow iOS sync

      if (Platform.isAndroid) {
        try {
          await device.requestMtu(512); // Use a safe high value
          logger.i("MTU requested");
        } catch (e) {
          logger.w("MTU negotiation failed: $e");
        }
      }

      manageBluetoothState(device); // Now safe to manage state

      await discoverServices(device);

      if (versionCharacteristic == null) {
        logger.w("⚠️ versionCharacteristic is still null after connect.");
      }

      // ⬇️ Optionally refresh board info
      await Future.delayed(const Duration(seconds: 2));
      sendCommand("CMD:INFO;");
    } catch (e) {
      logger.e("Cannot connect, exception occurred: $e");
      _isConnected = false;
      notifyListeners();
    }
  }

  Future<void> attemptReconnection(BluetoothDevice device) async {
    if (isReconnecting || isConnected) return;
    isReconnecting = true;

    for (int i = 0; i < reconnectDuration.inSeconds / 5; i++) {
      if (isConnected) break;

      try {
        logger.i("Attempting to reconnect...");
        await device.connect(autoConnect: false);
        FlutterBluePlus.stopScan();
        updateConnectionState(true, device);
        logger.i("Reconnected to device: ${device.platformName}");
        break;
      } catch (e) {
        logger.w("Reconnection attempt failed: $e");
        await Future.delayed(const Duration(seconds: 5));
      }
    }

    isReconnecting = false;
  }

  void updateConnectionState(bool state, [BluetoothDevice? device]) {
    _isConnected = state;
    connectedDevice = device;
    notifyListeners();
    markInfoStale();
    sendCommand("CMD:INFO;");
  }

  Future<void> discoverServices(BluetoothDevice device) async {
    try {
      List<BluetoothService> services = await device.discoverServices();
      for (BluetoothService service in services) {
        // Check each characteristic for known UUIDs
        for (var c in service.characteristics) {
          if (c.uuid == _otaCharacteristicUuid) {
            otaCharacteristic = c;
            logger.i("✅ Found OTA characteristic");
          } else if (c.uuid == _versionCharacteristicUuid) {
            versionCharacteristic = c;
            logger.i("✅ Found Version characteristic");
          } else if (c.uuid == _controlCharacteristicUuid) {
            writeCharacteristic = c;
            logger.i("✅ Found Write characteristic");
          }

          if (c.properties.notify) {
            notifyCharacteristic = c;
            await notifyCharacteristic?.setNotifyValue(true);
            logger.i("✅ Notify characteristic enabled");
            notifyCharacteristic?.lastValueStream.listen((value) {
              logger.i("📥 Notification received");
              onValueReceived(value);
            });
          }
        }
      }

      updateConnectionState(true, device);
    } catch (e) {
      logger.e("❌ Failed to discover services: $e");
    }
  }

  void scanForDevices({bool rescan = false}) {
    if (isScanning && !rescan) return;

    if (rescan) devicesList.clear();

    isScanning = true;
    if (!FlutterBluePlus.isScanningNow) {
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 4)).then((_) {
        isScanning = false;
      });
    }

    scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult result in results) {
        final dev = result.device;
        if (dev.platformName.contains("CornholeBT")) {
          logger.i("Found CornholeBT, attempting connection...");
          FlutterBluePlus.stopScan();
          device = dev;
          connectToDevice(device!);
          break;
        }
      }
    });
  }

  void disconnectDevice() async {
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      _isConnected = false;
      notifyListeners();
    }
  }

  String accumulatedNotification = ''; // Add at class level

  void onValueReceived(List<int> value) {
    String data = utf8.decode(value);
    logger.i("Received partial data: $data");
    receivedMessage += data;

    while (receivedMessage.contains(";")) {
      final endIndex = receivedMessage.indexOf(";");
      final completeField = receivedMessage.substring(0, endIndex);
      receivedMessage = receivedMessage.substring(endIndex + 1);

      // Accumulate into notification string
      accumulatedNotification += "$completeField;";

      // If we see version field, treat this as the last field of a board info block
      if (completeField.contains(RegExp(r"^ver\d+:"))) {
        logger.i("🧩 Reassembled board message: $accumulatedNotification");
        handleNotification(accumulatedNotification);
        accumulatedNotification = ''; // reset for next board
      }
    }
  }

  void handleNotification(String value) {
    logger.i("Received notification: $value");

    try {
      if (value.contains("OTA_LOG:")) {
        final entries = value.split(";");
        for (final entry in entries) {
          if (entry.startsWith("OTA_LOG:")) {
            final clean = entry.replaceFirst("OTA_LOG:", "");
            otaScreenKey.currentState?.logMessage(clean); // ✅ line-by-line OTA logging
          }
        }
      }
      if (value.startsWith("ColorIndex:")) {
        final colorIndex =
            int.tryParse(value.substring("ColorIndex:".length).trim());
        if (colorIndex != null) {
          activeColorIndex = colorIndex;
          logger.i("🎨 Color index updated to: $colorIndex");
        }
        return;
      }

      if (value.startsWith("Effect:")) {
        activeEffect = value.substring("Effect:".length).trim();
        logger.i("🌈 Effect updated to: $activeEffect");
        return;
      }

      if (value.startsWith("S:")) {
        handleSettingsResponse(value.substring(2));
        return;
      }

      // TEMPORARY INDEXED PARSE
      final Map<String, Map<String, String>> rawDataByIndex = {};
      final fields = value.split(';');

      for (final field in fields) {
        if (field.isEmpty || !field.contains(':')) continue;
        final parts = field.split(':');
        if (parts.length != 2) continue;

        final tag = parts[0];
        final val = parts[1];
        final match = RegExp(r'^(r|n|m|l|v|ver)(\d+)$').firstMatch(tag);
        if (match == null) continue;

        final key = match.group(1)!;
        final index = match.group(2)!;

        rawDataByIndex.putIfAbsent(index, () => {});
        rawDataByIndex[index]![key] = val;
      }

      final List<BoardInfo> updatedBoards = [];

      for (final entry in rawDataByIndex.entries) {
        final index = entry.key;
        final data = entry.value;

        final rawMac = data['m'];
        if (rawMac == null || rawMac.isEmpty) {
          logger.w("⚠️ Skipping board $index due to missing MAC");
          continue;
        }

        final mac = normalizeMac(rawMac);
        final board = BoardInfo(
          role: data['r'] ?? '',
          name: data['n'] ?? 'Board $index',
          mac: mac,
          batteryLevel: int.tryParse(data['l'] ?? '') ?? 0,
          batteryVoltage: int.tryParse(data['v'] ?? '') ?? 0,
          version: data['ver'] ?? '',
        );

        logger.i("✅ Parsed board $mac => ${board.role}, ${board.name}");
        updatedBoards.add(board);
      }

      if (updatedBoards.isNotEmpty) {
        updateBoards(updatedBoards);
      }
    } catch (e) {
      logger.e("❌ Error handling notification: $e");
      connectionInfo = "Error parsing notification";
      notifyListeners();
    }
  }

  Widget buildDeviceList() {
    return Column(
      children: [
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: () => scanForDevices(rescan: true), // ← force rescan

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

// Separate function for handling settings response
  void handleSettingsResponse(String settings) {
    logger.i("Handling settings response: $settings");

    // Split the settings data by ';'
    List<String> settingsData = settings.split(';');
    for (var setting in settingsData) {
      if (setting.isEmpty) continue;

      // Handle each setting based on its prefix
      if (setting.startsWith("SSID:")) {
        _ssid = setting.substring(5);
        logger.i("SSID set to: $ssid");
      } else if (setting.startsWith("PW:")) {
        _password = setting.substring(3);
        logger.i("Password set to: $password");
      } else if (setting.startsWith("B1:")) {
        _nameBoard1 = setting.substring(3);
        logger.i("Board 1 Name set to: $nameBoard1");
      } else if (setting.startsWith("B2:")) {
        _nameBoard2 = setting.substring(3);
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
            double.tryParse(setting.substring(8)) ?? deepSleepTimeout;
        logger.i("Deep Sllep timeout set to: $deepSleepTimeout");
      } else if (setting.startsWith("DEEPSLEEP:")) {
        deepSleepTimeout =
            double.tryParse(setting.substring(8)) ?? inactivityTimeout;
        logger.i("Inactivity timeout set to: $inactivityTimeout");
      } else {
        logger.w("Unexpected setting received: $setting");
      }
    }

    // After settings are processed, update the UI
    // setupScreenState?.updateUIWithCurrentSettings();
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

  Future<void> sendLargeMessage(
      BluetoothCharacteristic characteristic, String message) async {
    int chunkSize = _negotiatedMtu > 3
        ? _negotiatedMtu - 3
        : 20; // Default to 20 if negotiation fails
    int messageLength = message.length;
    int totalChunks = (messageLength + chunkSize - 1) ~/ chunkSize;

    for (int i = 0; i < totalChunks; i++) {
      int start = i * chunkSize;
      int end = (start + chunkSize < messageLength)
          ? start + chunkSize
          : messageLength;
      String chunk = message.substring(start, end);

      await characteristic.write(utf8.encode(chunk));
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  void sendColorIndex(int colorIndex) {
    activeColorIndex = colorIndex;
    notifyListeners();

    sendCommand('ColorIndex:$colorIndex;');
  }

  void sendEffect(String effect) {
    activeEffect = effect;
    sendCommand('Effect:$effect;');
    notifyListeners();
  }

  void sendBrightness(int brightnessPercent) {
    int brightnessValue = (brightnessPercent * 255 / 100).round();
    sendCommand('brightness:$brightnessValue;');
  }

  void requestCurrentSettings() {
    sendCommand("CMD:SETTINGS;");
  }

  void toggleLights() {
    _lightsOn = !lightsOn;
    logger.i("Lights toggled: ${lightsOn ? 'on' : 'off'}");
    sendCommand('toggleLights:${lightsOn ? 'on' : 'off'};');
    notifyListeners();
  }

  void toggleEspNow() {
    _espNowEnabled = !espNowEnabled;
    logger.i("ESP-NOW toggled: ${espNowEnabled ? 'on' : 'off'}");
    sendCommand('toggleEspNow:${espNowEnabled ? 'on' : 'off'};');
    notifyListeners();
  }

  void sendDeepSleep() {
    sendCommand('CMD:SLEEP;');
  }

  void sendRestart() {
    sendCommand('CMD:RESTART;');
  }

// Setters for Board 1
  void setBoardRole1(String value) {
    _boardRole1 = value;
    notifyListeners();
  }

  void setMacAddrBoard1(String value) {
    _macAddrBoard1 = value;
    notifyListeners();
  }

  void setBatteryVoltageBoard1(int value) {
    _batteryVoltageBoard1 = value;
    notifyListeners();
  }

  void setBatteryLevelBoard1(int value) {
    _batteryLevelBoard1 = value;
    notifyListeners();
  }

  // Setters for Board 2
  void setBoardRole2(String value) {
    _boardRole2 = value;
    notifyListeners();
  }

  void setMacAddrBoard2(String value) {
    _macAddrBoard2 = value;
    notifyListeners();
  }

  void setBatteryVoltageBoard2(int value) {
    _batteryVoltageBoard2 = value;
    notifyListeners();
  }

  void setBatteryLevelBoard2(int value) {
    _batteryLevelBoard2 = value;
    notifyListeners();
  }
}

class BoardInfo {
  final String role;
  final String name;
  final String mac;
  final int batteryLevel;
  final int batteryVoltage;
  final String version;
  bool isExpanded;

  BoardInfo({
    required this.role,
    required this.name,
    required this.mac,
    required this.batteryLevel,
    required this.batteryVoltage,
    required this.version,
    this.isExpanded = false, // default to false
  });
}

