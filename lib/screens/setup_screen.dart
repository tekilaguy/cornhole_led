// setup_screen.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:numberpicker/numberpicker.dart';
import '/global.dart';
import 'home_screen.dart';
import '/widgets/background.dart';
import '/widgets/section.dart';
import '/widgets/status_indicators.dart';

class SetupScreen extends StatefulWidget {
  final String ssid;
  final String password;
  final String nameBoard1;
  final String nameBoard2;
  final double initialBrightness;
  final double effectSpeed;
  final double blockSize;
  final double celebrationDuration;
  final double inactivityTimeout;
  final Color sportEffectColor1;
  final Color sportEffectColor2;
  final Color initialStartupColor;
  final Function(String) sendCommand;

  const SetupScreen({
    super.key,
    required this.ssid,
    required this.password,
    required this.nameBoard1,
    required this.nameBoard2,
    required this.initialBrightness,
    required this.effectSpeed,
    required this.blockSize,
    required this.celebrationDuration,
    required this.inactivityTimeout,
    required this.sportEffectColor1,
    required this.sportEffectColor2,
    required this.initialStartupColor,
    required this.sendCommand,
  });

  @override
  SetupScreenState createState() => SetupScreenState();
}

class SetupScreenState extends State<SetupScreen> {
  final Logger logger = Logger();
  late TextEditingController boardName1Controller;
  late TextEditingController boardName2Controller;
  late TextEditingController ssidController;
  late TextEditingController passwordController;
  bool setupComplete = false;

// Previous settings for comparison
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

  @override
  void initState() {
    super.initState();
    initializeSettings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!setupComplete) {
      ssid = widget.ssid;
      password = widget.password;
      previousNameBoard1 = widget.nameBoard1;
      previousNameBoard2 = widget.nameBoard2;
      previousInitialBrightness = widget.initialBrightness;
      previousBlockSize = widget.blockSize;
      previousEffectSpeed = widget.effectSpeed;
      previousCelebrationDuration = widget.celebrationDuration;
      previousInactivityTimeout = widget.inactivityTimeout;
      previousSportEffectColor1 = widget.sportEffectColor1;
      previousSportEffectColor2 = widget.sportEffectColor2;
      previousInitialStartupColor = widget.initialStartupColor;

      ssidController = TextEditingController(text: ssid);
      passwordController = TextEditingController(text: password);
      boardName1Controller = TextEditingController(text: previousNameBoard1);
      boardName2Controller = TextEditingController(text: previousNameBoard2);

      setState(() {
        isLoading = true; // Show loading indicator
      });
      widget.sendCommand('GET_SETTINGS;');
    }
  }

  void initializeSettings() async {
    setState(() {
      isLoading = true;
    });

    await widget.sendCommand('GET_SETTINGS;');
    setupComplete = true; // Set this flag to true after sending GET_SETTINGS

    setState(() {
      isLoading = false;
    });
  }

  void saveWiFiSettings() {
    final List<String> commands = [];

    final currentssid = ssidController.text;
    final currentpassword = passwordController.text;

    if (currentssid != previousssid) {
      commands.add('SSID:$currentssid');
      previousssid = currentssid;
    }
    if (currentpassword != previouspassword) {
      commands.add('PW:$currentpassword');
      previouspassword = currentpassword;
    }

    if (commands.isNotEmpty && homeScreenState != null) {
      final batchCommand = commands.join(';');
      homeScreenState!.sendCommand(batchCommand);
    } else if (commands.isEmpty) {
      logger.i("No changes detected, no commands sent");
    } else {
      logger.w("SSID or Password is null or empty, commands not sent");
    }
  }

  void saveDefaultSettings() {
    final List<String> commands = [];

    final currentNameBoard1 = boardName1Controller.text;
    final currentNameBoard2 = boardName2Controller.text;
    final currentInitialBrightness = initialBrightness;
    final currentBlockSize = blockSize;
    final currentEffectSpeed = effectSpeed;
    final currentCelebrationDuration = celebrationDuration;
    final currentInactivityTimeout = inactivityTimeout;

    if (currentNameBoard1 != previousNameBoard1) {
      commands.add('B1:$currentNameBoard1');
    }
    if (currentNameBoard2 != previousNameBoard2) {
      commands.add('B2:$currentNameBoard2');
    }
    if (currentInitialBrightness != previousInitialBrightness) {
      commands.add('BRIGHT:$currentInitialBrightness');
    }
    if (currentBlockSize != previousBlockSize) {
      commands.add('SIZE:$currentBlockSize');
    }
    if (currentEffectSpeed != previousEffectSpeed) {
      commands.add('SPEED:$currentEffectSpeed');
    }
    if (currentCelebrationDuration != previousCelebrationDuration) {
      commands.add('CELEB:$currentCelebrationDuration');
    }
    if (currentInactivityTimeout != previousInactivityTimeout) {
      commands.add('TIMEOUT:$currentInactivityTimeout');
    }
    if (initialStartupColor != previousInitialStartupColor) {
      int red = (initialStartupColor.value >> 16) & 0xFF;
      int green = (initialStartupColor.value >> 8) & 0xFF;
      int blue = (initialStartupColor.value) & 0xFF;
      commands.add('IC:$red,$green,$blue');
    }

    if (sportEffectColor1 != previousSportEffectColor1) {
      int red = (sportEffectColor1.value >> 16) & 0xFF;
      int green = (sportEffectColor1.value >> 8) & 0xFF;
      int blue = (sportEffectColor1.value) & 0xFF;
      commands.add('SC1:$red,$green,$blue');
      homeScreenState!.sendCommand('SC1:$red,$green,$blue');
   }

    if (sportEffectColor2 != previousSportEffectColor2) {
      int red = (sportEffectColor2.value >> 16) & 0xFF;
      int green = (sportEffectColor2.value >> 8) & 0xFF;
      int blue = (sportEffectColor2.value) & 0xFF;
      commands.add('SC2:$red,$green,$blue');
     homeScreenState!.sendCommand('SC2:$red,$green,$blue');
    }
    logger.i(
        "homeScreenState is ${homeScreenState != null ? 'not null' : 'null'}");

    if (commands.isNotEmpty && homeScreenState != null) {
      final batchCommand = '${commands.join(';')};';
      homeScreenState!.sendCommand(batchCommand);
      previousNameBoard1 = currentNameBoard1;
      previousNameBoard2 = currentNameBoard2;
      previousInitialBrightness = currentInitialBrightness;
      previousBlockSize = currentBlockSize;
      previousEffectSpeed = currentEffectSpeed;
      previousCelebrationDuration = currentCelebrationDuration;
      previousInactivityTimeout = currentInactivityTimeout;
      previousInitialStartupColor = initialStartupColor;
      previousSportEffectColor1 = sportEffectColor1;
      previousSportEffectColor2 = sportEffectColor2;
    } else if (commands.isEmpty) {
      logger.i("No changes detected, no commands sent");
    } else {
      logger.e("HomeScreenState is null, cannot send commands");
    }
  }

  void onBackButtonPressed() {
    Navigator.pop(context, {
      'wifiEnabled': wifiEnabled,
      'lightsOn': lightsOn,
      'espNowEnabled': espNowEnabled,
    });
  }

  void updateUIWithCurrentSettings() {
    setState(() {
      boardName1Controller.text = nameBoard1;
      boardName2Controller.text = nameBoard2;
      initialBrightness = initialBrightness;
      blockSize = blockSize;
      effectSpeed = effectSpeed;
      celebrationDuration = celebrationDuration;
      inactivityTimeout = inactivityTimeout;
      initialStartupColor = initialStartupColor;
      sportEffectColor1 = sportEffectColor1;
      sportEffectColor2 = sportEffectColor2;
      isLoading = false;
      logger.i("Settings received and UI updated, isLoading set to false");
    });
  }

  void sendColorToMaster(String colorName, Color color) {
    int red = (color.value >> 16) & 0xFF;
    int green = (color.value >> 8) & 0xFF;
    int blue = (color.value) & 0xFF;

    String command = '$colorName:$red,$green,$blue';
    if (homeScreenState != null) {
      homeScreenState!.sendCommand(command);
    }
  }

  void changeRoles() async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Are you sure?"),
          content: const Text("This will change the roles on both boards."),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              child: const Text("Confirm"),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      if (homeScreenState != null) {
        homeScreenState!.sendCommand('SET_ROLE:SLAVE;');
        logger.i("Sent command to change roles on both boards.");
      } else {
        logger.e("HomeScreenState is null, cannot send commands");
      }
    }
  }

  void resetConfig() async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Are you sure?"),
          content:
              const Text("This will clear all saved variables on both boards."),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              child: const Text("Confirm"),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      if (homeScreenState != null) {
        homeScreenState!.sendCommand('RESET_CONFIG;');
        logger.i("Sent command to reset configuration on both boards.");
      } else {
        logger.e("HomeScreenState is null, cannot send commands");
      }
    }
  }

  void clearSavedVariables() async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Are you sure?"),
          content: const Text(
              "This will clear all saved variables and roles on both boards."),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              child: const Text("Confirm"),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      if (homeScreenState != null) {
        homeScreenState!.sendCommand('CLEAR_ALL;');
        logger.i("Sent command to clear all saved variables on both boards.");
      } else {
        logger.e("HomeScreenState is null, cannot send commands");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return isLoading
        ? const Center(child: CircularProgressIndicator())
        : WillPopScope(
            onWillPop: () async {
              onBackButtonPressed();
              return false;
            },
            child: Scaffold(
              appBar: AppBar(
                backgroundColor: Colors.blue,
                elevation: 0,
                title: const Text('Setup Screen'),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: onBackButtonPressed,
                ),
              ),
              body: Stack(
                children: [
                  const Background(),
                  Padding(
                    padding: const EdgeInsets.all(5.0),
                    child: ListView(
                      children: [
                        const SizedBox(height: 20),
                        isConnected ? buildControlScreen() : const HomeScreen(),
                        const SizedBox(height: 20),
                        const StatusIndicators(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
  }

  Widget buildControlScreen() {
    return Column(
      children: [
        Section(
          title: 'Wifi Settings',
          content: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [buildWiFiSettingsContainer()],
          ),
        ),
        const SizedBox(height: 15),
        Section(
          title: 'Default Settings',
          content: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [buildDefaultSettingsContainer()],
          ),
        ),
        const SizedBox(height: 15),
        Section(
          title: 'Clear all settings',
          content: Wrap(
            children: [buildControlButtons()],
          ),
        ),
      ],
    );
  }

  Widget buildControlButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Column(
          children: [
            const Text(
              'Roles',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            ElevatedButton(
              onPressed: changeRoles,
              child: const Icon(Icons.system_update_alt, size: 30),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                elevation: 25,
                shadowColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50),
                  side: const BorderSide(color: Colors.black, width: .5),
                ),
                padding: const EdgeInsets.all(20),
              ),
            ),
          ],
        ),
        Column(
          children: [
            const Text(
              'Reset',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            ElevatedButton(
              onPressed: resetConfig,
              child: const Icon(Icons.power_settings_new,
                  size: 30, color: Colors.black),
              style: ElevatedButton.styleFrom(
                elevation: 25,
                shadowColor: Colors.black,
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50),
                  side: const BorderSide(color: Colors.black, width: .5),
                ),
              ),
            ),
          ],
        ),
        Column(
          children: [
            const Text(
              'Factory',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            ElevatedButton(
              onPressed: clearSavedVariables,
              child: const Icon(Icons.power_settings_new,
                  size: 30, color: Colors.black),
              style: ElevatedButton.styleFrom(
                elevation: 25,
                shadowColor: Colors.black,
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50),
                  side: const BorderSide(color: Colors.black, width: .5),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget buildWiFiSettingsContainer() {
    return Container(
      padding: const EdgeInsets.all(10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TextField(
            controller: ssidController,
            decoration: const InputDecoration(
              labelText: "WiFi SSID",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: passwordController,
            decoration: const InputDecoration(
              labelText: "WiFi Password",
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.bottomRight,
            child: ElevatedButton(
              onPressed: saveWiFiSettings,
              child: const Text("Save WiFi Settings"),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildDefaultSettingsContainer() {
    return Container(
      padding: const EdgeInsets.all(5.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TextField(
            controller: boardName1Controller,
            decoration: const InputDecoration(
              labelText: "Board 1 Name",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: boardName2Controller,
            decoration: const InputDecoration(
              labelText: "Board 2 Name",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(
            color: Colors.blue,
            thickness: 2,
          ),
          const SizedBox(height: 20),
          buildSlider("Initial Brightness", initialBrightness, (value) {
            setState(() {
              initialBrightness = value;
            });
          }),
          const SizedBox(height: 20),

          // First Row
          Row(
            children: [
              Expanded(
                child: buildQuantityInput(
                    "Effects Size", blockSize.round(), 1, 30, 1, (value) {
                  setState(() {
                    blockSize = value.toDouble();
                  });
                }),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: buildQuantityInput(
                    "Effects Speed", effectSpeed.round(), 1, 50, 1, (value) {
                  setState(() {
                    effectSpeed = value.toDouble();
                  });
                }),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Second Row
          Row(
            children: [
              Expanded(
                child: buildQuantityInput("Scoring Duration",
                    (celebrationDuration / 1000).round(), 1, 10, 1, (value) {
                  setState(() {
                    celebrationDuration = value * 1000;
                  });
                }),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: buildQuantityInput(
                    "Inactivity Timeout", inactivityTimeout.round(), 0, 60, 5,
                    (value) {
                  setState(() {
                    inactivityTimeout = value.toDouble();
                  });
                }),
              ),
            ],
          ),
          const Divider(
            color: Colors.blue,
            thickness: 2,
          ),
          buildInitialColorPicker(),
          const SizedBox(height: 20),
          const Divider(
            color: Colors.blue,
            thickness: 2,
          ),
          const Center(
            child: Text(
              "Sport Effect Colors",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: buildColorPicker("Color 1", sportEffectColor1, (color) {
                  setState(() {
                    sportEffectColor1 = color;
                  });
                }),
              ),
              Expanded(
                child: buildColorPicker("Color 2", sportEffectColor2, (color) {
                  setState(() {
                    sportEffectColor2 = color;
                  });
                }),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.bottomRight,
            child: ElevatedButton(
              onPressed: () {
                saveDefaultSettings();
              },
              child: const Text("Save Default Settings"),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildClearSettingsContainer() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.bottomRight,
              child: ElevatedButton(
                onPressed: () async {
                  bool? confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text("Are you sure?"),
                        content: const Text(
                            "This will clear all saved variables on both boards."),
                        actions: [
                          TextButton(
                            child: const Text("Cancel"),
                            onPressed: () {
                              Navigator.of(context).pop(false);
                            },
                          ),
                          TextButton(
                            child: const Text("Confirm"),
                            onPressed: () {
                              Navigator.of(context).pop(true);
                            },
                          ),
                        ],
                      );
                    },
                  );

                  if (confirmed == true) {
                    resetConfig();
                  }
                },
                child: const Text("Reset Config"),
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.bottomRight,
              child: ElevatedButton(
                onPressed: () async {
                  bool? confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text("Are you sure?"),
                        content: const Text(
                            "This will change the roles on both boards."),
                        actions: [
                          TextButton(
                            child: const Text("Cancel"),
                            onPressed: () {
                              Navigator.of(context).pop(false);
                            },
                          ),
                          TextButton(
                            child: const Text("Confirm"),
                            onPressed: () {
                              Navigator.of(context).pop(true);
                            },
                          ),
                        ],
                      );
                    },
                  );

                  if (confirmed == true) {
                    changeRoles();
                  }
                },
                child: const Text("Change Roles"),
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.bottomRight,
              child: ElevatedButton(
                onPressed: () async {
                  bool? confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text("Are you sure?"),
                        content: const Text(
                            "This will clear all saved variables and roles on both boards."),
                        actions: [
                          TextButton(
                            child: const Text("Cancel"),
                            onPressed: () {
                              Navigator.of(context).pop(false);
                            },
                          ),
                          TextButton(
                            child: const Text("Confirm"),
                            onPressed: () {
                              Navigator.of(context).pop(true);
                            },
                          ),
                        ],
                      );
                    },
                  );

                  if (confirmed == true) {
                    clearSavedVariables();
                  }
                },
                child: const Text("Factory Reset"),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget buildQuantityInput(String label, int initialValue, int minValue,
      int maxValue, int step, Function(int) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        NumberPicker(
          value: initialValue,
          minValue: minValue,
          maxValue: maxValue,
          step: step,
          onChanged: (value) {
            onChanged(value);
          },
        ),
      ],
    );
  }

  Widget buildSlider(
      String label, double value, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        Slider(
          value: value,
          min: 0,
          max: 100,
          divisions: (100 - 5) ~/ 5,
          label: value.round().toString(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget buildInitialColorPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          "Select Initial Startup Color",
          style: TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: colors.map((color) {
            return GestureDetector(
              onTap: () {
                setState(() {
                  initialStartupColor = color;
                });
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: initialStartupColor == color
                        ? Colors.black
                        : Colors.transparent,
                    width: 2.0,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget buildColorPicker(
      String label, Color currentColor, ValueChanged<Color> onColorChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () async {
            Color? pickedColor;

            pickedColor = await showDialog(
              context: context,
              builder: (context) {
                return AlertDialog(
                  title: const Text("Pick a Color"),
                  content: SingleChildScrollView(
                    child: ColorPicker(
                      pickerColor: currentColor,
                      onColorChanged: (color) {
                        pickedColor = color;
                      },
                    ),
                  ),
                  actions: [
                    TextButton(
                      child: const Text("Select"),
                      onPressed: () {
                        Navigator.of(context).pop(pickedColor);
                      },
                    ),
                  ],
                );
              },
            );

            if (pickedColor != null) {
              onColorChanged(pickedColor!);
            }
          },
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: currentColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(width: 1.5, color: Colors.black),
            ),
          ),
        ),
      ],
    );
  }
}
