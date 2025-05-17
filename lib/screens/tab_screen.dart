// tab_screen.dart
import 'package:flutter/material.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
//import 'package:provider/provider.dart';

import 'home_screen.dart';
import 'info_screen.dart';
import 'setup_screen.dart';
import 'ota_screen.dart';
import '/widgets/background.dart';
import '/global.dart';

class TabScreen extends StatefulWidget {
  const TabScreen({super.key});

  @override
  State<TabScreen> createState() => _TabScreenState();
}

class _TabScreenState extends State<TabScreen> {
  int _currentIndex = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();

    _screens = [
      const HomeScreen(),
      InfoScreen(
        wifiEnabled: wifiEnabled,
        lightsOn: lightsOn,
        espNowEnabled: espNowEnabled,
        isConnected: isConnected,
        connectionInfo: connectionInfo,
        boardRole1: boardRole1,
        nameBoard1: nameBoard1,
        macAddrBoard1: macAddrBoard1,
        ipAddrBoard1: ipAddrBoard1,
        batteryLevelBoard1: batteryLevelBoard1,
        batteryVoltageBoard1: batteryVoltageBoard1,
        boardRole2: boardRole2,
        nameBoard2: nameBoard2,
        macAddrBoard2: macAddrBoard2,
        ipAddrBoard2: ipAddrBoard2,
        batteryLevelBoard2: batteryLevelBoard2,
        batteryVoltageBoard2: batteryVoltageBoard2,
        sendCommand: homeScreenState?.sendCommand ?? (_) {},
      ),
      const OTAScreen(), // Will use homeScreenState directly
      SetupScreen(
        ssid: ssid,
        password: password,
        nameBoard1: nameBoard1,
        nameBoard2: nameBoard2,
        initialBrightness: initialBrightness,
        effectSpeed: effectSpeed,
        blockSize: blockSize,
        celebrationDuration: celebrationDuration,
        inactivityTimeout: inactivityTimeout,
        sportEffectColor1: sportEffectColor1,
        sportEffectColor2: sportEffectColor2,
        initialStartupColor: initialStartupColor,
        sendCommand: homeScreenState?.sendCommand ?? (_) {},
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Background(),
        Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.blue,
            elevation: 0,
            title: const Text('Cornhole LED Controller'),
          ),
          backgroundColor: Colors.transparent,
          body: _screens[_currentIndex],
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
