// ble_provider.dart

// ignore_for_file: unrelated_type_equality_checks

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';
import 'dart:convert';
import 'dart:async';
import 'global.dart';

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
  bool isConnected = false;
  Timer? reconnectTimer;
  static const reconnectDuration = Duration(seconds: 30);

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
    connectionStateSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.connected) {
        logger.i("Device connected: ${device.platformName}");

        isConnected = true;
        connectedDevice = device;

        discoverServices(device);
        reconnectTimer?.cancel();
        notifyListeners();
      } else if (state == BluetoothConnectionState.disconnected) {
        logger.w("Device disconnected: ${device.platformName}");
        notifyListeners();
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
    } catch (e) {
      logger.e("Cannot connect, exception occurred: $e");
      isConnected = false;
      notifyListeners();
    }
  }

  Future<void> attemptReconnection(BluetoothDevice device) async {
    if (isReconnecting) return;
    isReconnecting = true;

    for (int i = 0; i < reconnectDuration.inSeconds / 5; i++) {
      if (isConnected) break;

      try {
        logger.i("Attempting to reconnect...");
        await device.connect(autoConnect: false);
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
    isConnected = state;
    connectedDevice = device;
    notifyListeners();
  }

  void discoverServices(BluetoothDevice device) async {
    try {
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
      isConnected = false;
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
              logger
                  .i("Battery Voltage Board 1 set to: $batteryVoltageBoard1 V");
            } else if (boardNumber == 2) {
              batteryVoltageBoard2 = batteryVoltage;
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
    int mtu = await device!.requestMtu(240);
    int chunkSize =
        mtu > 3 ? mtu - 3 : 20; // Default to 20 if negotiation fails
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
    wifiEnabled = !wifiEnabled;
    logger.i("WiFi toggled: ${wifiEnabled ? 'on' : 'off'}");
    sendCommand('toggleWiFi:${wifiEnabled ? 'on' : 'off'};');
    notifyListeners();
  }

  void toggleLights() {
    lightsOn = !lightsOn;
    logger.i("Lights toggled: ${lightsOn ? 'on' : 'off'}");
    sendCommand('toggleLights:${lightsOn ? 'on' : 'off'};');
    notifyListeners();
  }

  void toggleEspNow() {
    espNowEnabled = !espNowEnabled;
    logger.i("ESP-NOW toggled: ${espNowEnabled ? 'on' : 'off'}");
    sendCommand('toggleEspNow:${espNowEnabled ? 'on' : 'off'};');
    notifyListeners();
  }

  void sendRestart() {
    sendCommand('sendRestart;');
  }
}
