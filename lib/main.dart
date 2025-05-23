// main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/tab_screen.dart';
//import 'screens/home_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/ota_screen.dart';
import 'ble_provider.dart';

void main() {
  runApp(
    MultiProvider(providers: [
      ChangeNotifierProvider(create: (_) => BLEProvider()),
    ], child: MyApp()),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cornhole LED Controller',
      home: const TabScreen(),
       onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/setup':
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (context) => SetupScreen(

            initialBrightness: args['initialBrightness'],
            effectSpeed: args['effectSpeed'],
            blockSize: args['blockSize'],
            celebrationDuration: args['celebrationDuration'],
            inactivityTimeout: args['inactivityTimeout'],
            deepSleepTimeout: args['deepSleepTimeout'],
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
