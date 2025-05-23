// tab_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../ble_provider.dart';
import 'home_screen.dart';
import 'setup_screen.dart';
import 'ota_screen.dart';
import 'info_screen.dart';
import '/widgets/background.dart';
import '/global.dart';

class TabScreen extends StatefulWidget {
  const TabScreen({super.key});

  @override
  State<TabScreen> createState() => _TabScreenState();
}

class _TabScreenState extends State<TabScreen> {
  int _currentIndex = 0;
  BLEProvider get bleProvider =>
      Provider.of<BLEProvider>(context, listen: false);

  List<Widget>? _screens;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _screens = [
        const HomeScreen(),
        const InfoScreen(),
        const OTAScreen(),
        SetupScreen(
          initialBrightness: initialBrightness,
          effectSpeed: effectSpeed,
          blockSize: blockSize,
          celebrationDuration: celebrationDuration,
          inactivityTimeout: inactivityTimeout,
          deepSleepTimeout: deepSleepTimeout,
          sportEffectColor1: sportEffectColor1,
          sportEffectColor2: sportEffectColor2,
          initialStartupColor: initialStartupColor,
          sendCommand: bleProvider.sendCommand,
        ),
      ];
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_screens == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Stack(
      children: [
        const Background(),
        Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.blue,
            elevation: 4,
            title: const Center(child: Text('Cornhole LED Controller')),
            actions: [
              IconButton(
                icon: const Icon(Icons.power_settings_new, color: Colors.red),
                tooltip: 'Sleep & Exit',
                onPressed: () async {
                  // Confirm first
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text("Confirm Exit"),
                      content: const Text(
                          "Put the board to sleep and exit the app?"),
                      actions: [
                        TextButton(
                          child: const Text("Cancel"),
                          onPressed: () => Navigator.of(ctx).pop(false),
                        ),
                        TextButton(
                          child: const Text("Confirm"),
                          onPressed: () => Navigator.of(ctx).pop(true),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true) {
                    bleProvider.sendDeepSleep();
                    await Future.delayed(const Duration(milliseconds: 800));
                    // Exit app
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (Platform.isAndroid) {
                        SystemNavigator.pop();
                      } else if (Platform.isIOS) {
                        exit(0); // not recommended by Apple, but functional
                      }
                    });
                  }
                },
              ),
            ],
          ),
          backgroundColor: Colors.transparent,
          body: _screens![_currentIndex],
          bottomNavigationBar: CurvedNavigationBar(
            index: _currentIndex,
            height: 60,
            color: Colors.blue.shade800,
            backgroundColor: Colors.transparent,
            buttonBackgroundColor: Colors.black,
            animationCurve: Curves.easeInOut,
            animationDuration: const Duration(milliseconds: 300),
            items: const <Widget>[
              Icon(Icons.home, size: 30, color: Colors.white),
              Icon(Icons.info, size: 30, color: Colors.white),
              Icon(Icons.update, size: 30, color: Colors.white),
              Icon(Icons.settings, size: 30, color: Colors.white),
            ],
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
          ),
        ),
      ],
    );
  }
}
