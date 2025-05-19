// global.dart
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'screens/home_screen.dart';
import 'screens/info_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/ota_screen.dart';

// Logger instance
Logger logger = Logger();

// Variables for handling BLE messages
String receivedMessage = "";
int totalChunks = 0;
int receivedChunks = 0;
bool isScanning = false;
bool isReconnecting = false;

// Connection and device status
bool isConnected = false;
String connectedDevice = '';
bool lightsOn = true;
bool espNowEnabled = true;
int activeColorIndex = 0;
String activeEffect = '';
String connectionInfo = '';

// Brightness
int brightness = 50;

// Variables for Board 1
String boardRole1 = 'PRIMARY';
String nameBoard1 = '';
String macAddrBoard1 = '';
String ipAddrBoard1 = '';
int batteryVoltageBoard1 = 0;
int batteryLevelBoard1 = 0;

// Variables for Board 2
String boardRole2 = 'SECONDARY';
String nameBoard2 = '';
String macAddrBoard2 = '';
String ipAddrBoard2 = '';
int batteryVoltageBoard2 = 0;
int batteryLevelBoard2 = 0;

// Wi-Fi credentials
String ssid = 'CornholeAP';
String password = 'Funforall';

// Loading status
bool isLoading = true;

// Settings variables
double initialBrightness = 50;
double blockSize = 15;
double effectSpeed = 25;
double celebrationDuration = 4000;
double inactivityTimeout = 10;

// Color settings
Color initialStartupColor = Colors.blue;
Color sportEffectColor1 = const Color.fromARGB(255, 181, 87, 0);
Color sportEffectColor2 = Colors.white;
Color sportEffectColor3 = const Color.fromARGB(255, 241, 90, 34);
Color sportEffectColor4 = const Color.fromARGB(255, 12, 35, 64);

// Screen state references
HomeScreenState? homeScreenState;
SetupScreenState? setupScreenState;
OTAScreenState? otaScreenState;
InfoScreenState? infoScreenState;

const String getSettingsCommand = "GET_SETTINGS;";
const String toggleWiFiCommand = "toggleWiFi:";

//OTA Variables
String url = "http://cornhole-updates.web.app";

// Color options
List<Color> colors = [
  const Color.fromRGBO(0, 0, 255, 1), // Blue
  const Color.fromRGBO(0, 255, 0, 1), // Green
  const Color.fromRGBO(255, 0, 0, 1), // Red
  const Color.fromRGBO(255, 255, 255, 1), // White
  const Color.fromRGBO(191, 87, 0, 1), // Burnt Orange
  const Color.fromRGBO(0, 255, 255, 1), // Aqua
  const Color.fromRGBO(128, 0, 128, 1), // Purple
  const Color.fromRGBO(255, 192, 203, 1), // Pink
];

// Effects options
List<String> effects = [
  'Solid',
  'Twinkle',
  'Chase',
  'Wipe',
  'Bounce',
  'Breathing',
  'Gradient',
  'Rainbow',
  'America',
  'Sports',
];
