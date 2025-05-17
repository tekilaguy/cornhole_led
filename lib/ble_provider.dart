// ble_provider.dart

// ignore_for_file: unrelated_type_equality_checks

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';
import 'dart:convert';
import 'dart:async';
import 'global.dart';
import 'dart:io';
import 'ble_mtu.dart';

class BLEProvider with ChangeNotifier {
  final Logger logger = Logger();

  List<BluetoothDevice> devicesList = [];
  BluetoothDevice? connectedDevice;
  BluetoothDevice? device;
  BluetoothCharacteristic? writeCharacteristic;
  BluetoothCharacteristic? notifyCharacteristic;
  StreamSubscription? adapterStateSubscription;
  StreamSubscription? scanResultsSubscription;
  StreamSubscription? connectionStateSubscription;
  Timer? reconnectTimer;
  static const reconnectDuration = Duration(seconds: 30);

  bool _isConnected = false;
  bool _wifiEnabled = true;
  bool _lightsOn = true;
  bool _espNowEnabled = true;
  Color _initialStartupColor = Colors.blue;

  bool get isConnected => _isConnected;
  bool get wifiEnabled => _wifiEnabled;
  bool get lightsOn => _lightsOn;
  bool get espNowEnabled => _espNowEnabled;
  Color get initialStartupColor => _initialStartupColor;

  int _negotiatedMtu = 23; // default BLE MTU
  int get negotiatedMtu => _negotiatedMtu;

  // Board 1
  String _boardRole1 = '';
  String _nameBoard1 = '';
  String _macAddrBoard1 = '';
  String _ipAddrBoard1 = '';
  int _batteryVoltageBoard1 = 0;
  int _batteryLevelBoard1 = 0;

  // Board 2
  String _boardRole2 = '';
  String _nameBoard2 = '';
  String _macAddrBoard2 = '';
  String _ipAddrBoard2 = '';
  int _batteryVoltageBoard2 = 0;
  int _batteryLevelBoard2 = 0;

  // Wi-Fi Credentials
  String _ssid = 'CornholeAP';
  String _password = 'Funforall';

  // Getters
  String get boardRole1 => _boardRole1;
  String get nameBoard1 => _nameBoard1;
  String get macAddrBoard1 => _macAddrBoard1;
  String get ipAddrBoard1 => _ipAddrBoard1;
  int get batteryVoltageBoard1 => _batteryVoltageBoard1;
  int get batteryLevelBoard1 => _batteryLevelBoard1;

  String get boardRole2 => _boardRole2;
  String get nameBoard2 => _nameBoard2;
  String get macAddrBoard2 => _macAddrBoard2;
  String get ipAddrBoard2 => _ipAddrBoard2;
  int get batteryVoltageBoard2 => _batteryVoltageBoard2;
  int get batteryLevelBoard2 => _batteryLevelBoard2;

  String get ssid => _ssid;
  String get password => _password;

  void setConnected(bool value) {
    _isConnected = value;
    notifyListeners();
  }

  void setWifiEnabled(bool value) {
    _wifiEnabled = value;
    notifyListeners();
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
    await device.disconnect(); // always try to reset

    if (Platform.isIOS) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    const maxAttempts = 3;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await device.connect(autoConnect: false);
        FlutterBluePlus.stopScan();
        manageBluetoothState(device);
        logger.i("Connected on attempt $attempt");
        return;
      } catch (e) {
        logger.w("Connect attempt $attempt failed: $e");
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    _isConnected = false;
    notifyListeners();
    logger.e("Failed to connect after $maxAttempts attempts");

  } catch (e) {
    logger.e("Connection setup error: $e");
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
  }

  Future<void> discoverServices(BluetoothDevice device) async {
    try {
      // ①  Negotiate MTU
      final mtu = await MtuNegotiator().negotiate(device);
      // You can keep it in a field if you want to show it in the UI:
      _negotiatedMtu = mtu;
      //_negotiatedMtu = await MtuNegotiator().negotiate(device);

      // ②  Now discover services
      List<BluetoothService> services = await device.discoverServices();
      for (BluetoothService service in services) {
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          if (characteristic.properties.write) {
            writeCharacteristic = characteristic;
          }
          if (characteristic.properties.notify) {
            notifyCharacteristic = characteristic;
            await notifyCharacteristic?.setNotifyValue(true);
            notifyCharacteristic?.lastValueStream.listen((value) {
              onValueReceived(value);
            });
          }
        }
      }
      // If discovery is successful, update the connection state
      updateConnectionState(true, device);
    } catch (e) {
      logger.e("Failed to discover services: $e");
    }
  }

  void scanForDevices({bool rescan = false}) {
    if (isScanning && !rescan) return;

    if (rescan) devicesList.clear();

    isScanning = true;
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 4)).then((_) {
      isScanning = false;
    });

    scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      final newDevices = results
          .map((r) => r.device)
          .where((device) => device.platformName.isNotEmpty)
          .toSet()
          .difference(devicesList.toSet());
      devicesList.addAll(newDevices);
      if (newDevices.isNotEmpty) {
        notifyListeners();
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

  void onValueReceived(List<int> value) async {
    String data = utf8.decode(value);
    logger.i("Received partial data: $data");
    receivedMessage += data;

    while (receivedMessage.contains(";")) {
      final endIndex = receivedMessage.indexOf(";");
      final completeMessage = receivedMessage.substring(0, endIndex);
      receivedMessage = receivedMessage.substring(endIndex + 1);
      handleNotification(completeMessage);
    }
  }

  void handleNotification(String value) {
    logger.i("Received notification: $value");

    try {
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
          case 'n':
            if (boardNumber == 1) {
              _nameBoard1 = fieldValue;
              logger.i("Board 1 Name set to: $nameBoard1");
            } else if (boardNumber == 2) {
              _nameBoard2 = fieldValue;
              logger.i("Board 2 Name set to: $nameBoard2");
            }
            break;

          case 'm':
            if (boardNumber == 1) {
              _macAddrBoard1 = fieldValue;
              logger.i("MAC Addr Board 1 set to: $macAddrBoard1");
            } else if (boardNumber == 2) {
              _macAddrBoard2 = fieldValue;
              logger.i("MAC Addr Board 2 set to: $macAddrBoard2");
            }
            break;

          case 'i':
            if (boardNumber == 1) {
              _ipAddrBoard1 = fieldValue;
              logger.i("IP Addr Board 1 set to: $ipAddrBoard1");
            } else if (boardNumber == 2) {
              _ipAddrBoard2 = fieldValue;
              logger.i("IP Addr Board 2 set to: $ipAddrBoard2");
            }
            break;

          case 'l':
            int batteryLevel = int.tryParse(fieldValue) ?? 0;
            if (boardNumber == 1) {
              _batteryLevelBoard1 = batteryLevel;
              logger.i("Battery Level Board 1 set to: $batteryLevelBoard1%");
            } else if (boardNumber == 2) {
              _batteryLevelBoard2 = batteryLevel;
              logger.i("Battery Level Board 2 set to: $batteryLevelBoard2%");
            }
            break;

          case 'v':
            int batteryVoltage = int.tryParse(fieldValue) ?? 0;
            if (boardNumber == 1) {
              _batteryVoltageBoard1 = batteryVoltage;
              logger
                  .i("Battery Voltage Board 1 set to: $batteryVoltageBoard1 V");
            } else if (boardNumber == 2) {
              _batteryVoltageBoard2 = batteryVoltage;
              logger
                  .i("Battery Voltage Board 2 set to: $batteryVoltageBoard2 V");
            }
            break;

          default:
            logger.w("Unexpected field tag: $fieldTag");
            break;
        }
      }
      notifyListeners();
    } catch (e) {
      logger.e("Error handling notification: $e");
      connectionInfo = "Error parsing notification";
      notifyListeners();
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

    sendCommand('colorIndex:$colorIndex;');
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
    sendCommand("GET_SETTINGS;");
  }

  void toggleWiFi() {
    _wifiEnabled = !wifiEnabled;
    logger.i("WiFi toggled: ${wifiEnabled ? 'on' : 'off'}");
    sendCommand('toggleWiFi:${wifiEnabled ? 'on' : 'off'};');
    notifyListeners();
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

  void sendRestart() {
    sendCommand('Restart;');
  }

// Setters for Board 1
  void setBoardRole1(String value) {
    _boardRole1 = value;
    notifyListeners();
  }

  void setNameBoard1(String value) {
    _nameBoard1 = value;
    notifyListeners();
  }

  void setMacAddrBoard1(String value) {
    _macAddrBoard1 = value;
    notifyListeners();
  }

  void setIpAddrBoard1(String value) {
    _ipAddrBoard1 = value;
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

  void setNameBoard2(String value) {
    _nameBoard2 = value;
    notifyListeners();
  }

  void setMacAddrBoard2(String value) {
    _macAddrBoard2 = value;
    notifyListeners();
  }

  void setIpAddrBoard2(String value) {
    _ipAddrBoard2 = value;
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

  // Setters for Wi-Fi Credentials
  void setSsid(String newSsid) {
    _ssid = newSsid;
    notifyListeners();
  }

  void setPassword(String newPassword) {
    _password = newPassword;
    notifyListeners();
  }
}
