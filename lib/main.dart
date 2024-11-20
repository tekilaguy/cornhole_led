// main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ble_provider.dart';
import 'home_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => BLEProvider(),
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cornhole LED',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomeScreen(),
    );
  }
}
