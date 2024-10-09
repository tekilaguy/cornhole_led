// main.dart
import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'info_screen.dart';
import 'setup_screen.dart';
import 'ota_screen.dart';

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
