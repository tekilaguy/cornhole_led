// main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/tab_screen.dart';
//import 'screens/home_screen.dart';
import 'screens/info_screen1.dart';
import 'screens/setup_screen.dart';
import 'screens/ota_screen.dart';
import 'ble_provider.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => BLEProvider(),
      child:  MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cornhole LED Controller',
      home: const TabScreen(),
      routes: {
        '/ota': (context) => const OTAScreen(),
      },
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/info':
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (context) => InfoScreen(
        wifiEnabled: args['wifiEnabled'],
        lightsOn: args['lightsOn'],
        espNowEnabled: args['espNowEnabled'],
        isConnected: args['isConnected'],
        connectionInfo: args['connectionInfo'],
        boardRole1: args['boardRole1'],
        nameBoard1: args['nameBoard1'],
        macAddrBoard1: args['macAddrBoard1'],
        ipAddrBoard1: args['ipAddrBoard1'],
        batteryLevelBoard1: args['batteryLevelBoard1'],
        batteryVoltageBoard1: args['batteryVoltageBoard1'],
        boardRole2: args['boardRole2'],
        nameBoard2: args['nameBoard2'],
        macAddrBoard2: args['macAddrBoard2'],
        ipAddrBoard2: args['ipAddrBoard2'],
        batteryLevelBoard2: args['batteryLevelBoard2'],
        batteryVoltageBoard2: args['batteryVoltageBoard2'], 
        sendCommand: args['sendCommand'],

          ),
        );
      case '/setup':
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (context) => SetupScreen(
            ssid: args['ssid'],
            password: args['password'],
            nameBoard1: args['nameBoard1'],
            nameBoard2: args['nameBoard2'],
            initialBrightness: args['initialBrightness'],
            effectSpeed: args['effectSpeed'],
            blockSize: args['blockSize'],
            celebrationDuration: args['celebrationDuration'],
            inactivityTimeout: args['inactivityTimeout'],
            sportEffectColor1: args['sportEffectColor1'],
            sportEffectColor2: args['sportEffectColor2'],
            initialStartupColor: args['initialStartupColor'],
            sendCommand: args['sendCommand'],
          ),
        );
      case '/ota':
        return MaterialPageRoute(
          builder: (context) => const OTAScreen(),
        );
      default:
        return null;
    }
  }
}
