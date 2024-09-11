import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'main.dart';

String receivedMessage = "";
int totalChunks = 0;
int receivedChunks = 0;

Logger logger = Logger();
int _currentIndex = 0;
bool isConnected = false;
String connectedDevice = '';

bool wifiEnabled = true;
bool lightsOn = true;
bool espNowEnabled = true;
int activeColorIndex = 0;
String activeEffect = '';
String connectionInfo = '';

int brightness = 50;

// Variables for board 1
String nameBoard1 = '';
String macAddrBoard1 = '';
String ipAddrBoard1 = '';
int batteryVoltageBoard1 = 0;
int batteryLevelBoard1 = 0;

// Variables for board 2
String nameBoard2 = '';
String macAddrBoard2 = '';
String ipAddrBoard2 = '';
int batteryVoltageBoard2 = 0;
int batteryLevelBoard2 = 0;

String ssid = 'CornholeAP';
String password = 'Funforall';

bool isLoading = true;
double initialBrightness = 50;
double blockSize = 15;
double effectSpeed = 25;
double celebrationDuration = 4000;
double inactivityTimeout = 10;
String? previousNameBoard1;
String? previousNameBoard2;
double? previousInitialBrightness;
double? previousBlockSize;
double? previousEffectSpeed;
double? previousCelebrationDuration;
double? previousInactivityTimeout;
Color? previousInitialStartupColor;
Color? previousSportEffectColor1;
Color? previousSportEffectColor2;
String? previousssid;
String? previouspassword;

Color initialStartupColor = Colors.blue;
Color sportEffectColor1 = Colors.deepOrange;
Color sportEffectColor2 = Colors.white;

HomeScreenState? homeScreenState;
SetupScreenState? setupScreenState;
InfoScreenState? infoScreenState;
OTAScreenState? otaScreenState;

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
