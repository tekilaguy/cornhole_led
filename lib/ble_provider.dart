// ble_provider.dart

// ignore_for_file: unrelated_type_equality_checks

import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:logger/logger.dart';
import 'dart:convert';
import 'dart:async';

class BLEProvider with ChangeNotifier {
  final Logger logger = Logger();

  BluetoothDevice? device;
  BluetoothCharacteristic? writeCharacteristic;
  BluetoothCharacteristic? notifyCharacteristic;
  bool isConnected = false;
  Timer? reconnectTimer;
  static const reconnectDuration = Duration(seconds: 30);

  // State variables
  bool wifiEnabled = true;
  bool lightsOn = false;
  bool espNowEnabled = false;
  String connectionInfo = '';
  String receivedMessage = '';

  // Additional state variables
  String ssid = '';
  String password = '';
  String nameBoard1 = '';
  String nameBoard2 = '';
  double initialBrightness = 100.0;
  double blockSize = 10.0;
  double effectSpeed = 10.0;
  double celebrationDuration = 5000.0;
  double inactivityTimeout = 30.0;

  // Method to connect to the device
  Future<void> connectToDevice(BluetoothDevice device) async {
    this.device = device;
    try {
      await device.connect();
      isConnected = true;
      notifyListeners();
      await discoverServices();
    } catch (e) {
      logger.e("Failed to connect: $e");
      isConnected = false;
      notifyListeners();
    }
  }

  // Method to discover services and characteristics
Future<void> discoverServices() async {
  if (device == null) return;
  List<BluetoothService> services = await device!.discoverServices();
  for (BluetoothService service in services) {
    logger.i("Found service: ${service.uuid}");
    for (BluetoothCharacteristic characteristic in service.characteristics) {
      logger.i("Found characteristic: ${characteristic.uuid}");
      logger.i("Properties: "
          "write=${characteristic.properties.write}, "
          "notify=${characteristic.properties.notify}, "
          "indicate=${characteristic.properties.indicate}");
      
      // Replace with your specific UUIDs
      if (characteristic.uuid == "5d650eb7-c41b-44f0-9704-3710f21e1c8e" &&
          characteristic.properties.write) {
        writeCharacteristic = characteristic;
      }
      if ((characteristic.uuid == "5d650eb7-c41b-44f0-9704-3710f21e1c8e") &&
          (characteristic.properties.notify || characteristic.properties.indicate)) {
        notifyCharacteristic = characteristic;
        try {
          await notifyCharacteristic!.setNotifyValue(true);
          notifyCharacteristic!.value.listen((value) {
            onValueReceived(value);
          });
        } catch (e) {
          logger.e("Error enabling notifications: $e");
        }
      }
    }
  }
  notifyListeners();
}

  // Method to send commands
  Future<void> sendCommand(String command) async {
    if (writeCharacteristic != null) {
      sendLargeMessage(writeCharacteristic!, command);
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

  // Method to handle received values
  void onValueReceived(List<int> value) {
    String data = utf8.decode(value);
    logger.i("Received partial data: $data");

    // Append to the buffer until a complete message with '#' is received
    receivedMessage += data;
    int endIndex;

    // Process each complete message
    while ((endIndex = receivedMessage.indexOf("#")) != -1) {
      String completeMessage = receivedMessage.substring(0, endIndex);
      logger.i("Complete message: $completeMessage");
      handleNotification(completeMessage);
      receivedMessage = receivedMessage.substring(endIndex + 1);
    }
  }

  void handleNotification(String value) {
    logger.i("Received notification: $value");

    try {
      // No need to check for '#' here

      // Check if the message is a GET_SETTINGS response (starts with "S:")
      if (value.startsWith("S:")) {
        handleSettingsResponse(value.substring(2));
        return; // Exit after processing settings
      }

      // Handle messages starting with 'Color:'
      else if (value.startsWith("Color:")) {
        String colorData = value.substring(6); // Remove 'Color:'
        List<String> rgbValues = colorData.split(',');
        if (rgbValues.length == 3) {
          int r = int.parse(rgbValues[0]);
          int g = int.parse(rgbValues[1]);
          int b = int.parse(rgbValues[2]);
          int colorIndex = getColorIndexFromRGB(r, g, b);
          // Update your state variable for activeColorIndex if needed
          logger.i("Updated active color index to: $colorIndex");
        } else {
          logger.w("Invalid color data received: $colorData");
        }
      }

      // Handle messages starting with 'Effect:'
      else if (value.startsWith("Effect:")) {
        String effect = value.substring(7); // Remove 'Effect:'
        // Update your state variable for activeEffect if needed
        logger.i("Updated active effect to: $effect");
      }

      // Handle messages starting with 'toggleLights:'
      else if (value.startsWith("toggleLights:")) {
        String status = value.substring(13); // Remove 'toggleLights:'
        lightsOn = (status == "on");
        logger.i("Updated lightsOn to: $lightsOn");
        notifyListeners();
      }

      // Handle other messages
      else {
        // Existing code for handling other messages
        // ...
      }
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

    // After settings are processed, notify listeners
    notifyListeners();
  }

  // Methods to send various commands
  void sendColorIndex(int colorIndex) {
    sendCommand('colorIndex:$colorIndex;');
  }

  void sendEffect(String effect) {
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

  // Disconnect device
  void disconnectDevice() async {
    if (device != null) {
      await device!.disconnect();
      isConnected = false;
      notifyListeners();
    }
  }

  // Save WiFi Settings
  void saveWiFiSettings() {
    if (ssid.isNotEmpty && password.isNotEmpty) {
      String command = 'SSID:$ssid;PW:$password;';
      sendCommand(command);
    } else {
      logger.w("SSID or Password is empty, not sending command.");
    }
  }

  // Save Default Settings
  void saveDefaultSettings() {
    List<String> commands = [];

    commands.add('B1:$nameBoard1');
    commands.add('B2:$nameBoard2');
    commands.add('BRIGHT:$initialBrightness');
    commands.add('SIZE:$blockSize');
    commands.add('SPEED:$effectSpeed');
    commands.add('CELEB:$celebrationDuration');
    commands.add('TIMEOUT:$inactivityTimeout');

    String batchCommand = '${commands.join(';')};';
    sendCommand(batchCommand);
  }

  // Helper function
  int getColorIndexFromRGB(int r, int g, int b) {
    // Implement this function based on your app's logic
    return 0; // Placeholder
  }

  // Implement other methods as needed
}
