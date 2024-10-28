// setup_screen.dart
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:numberpicker/numberpicker.dart';
import 'global.dart';
import 'home_screen.dart';
import 'widgets/background.dart';
import 'widgets/section.dart';
import 'widgets/status_indicators.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!setupComplete) {
      final Map<String, dynamic> args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;

      ssid = args['ssid'] as String? ?? '';
      password = args['password'] as String? ?? '';
      previousNameBoard1 = args['nameBoard1'] as String?;
      previousNameBoard2 = args['nameBoard2'] as String?;
      previousInitialBrightness = args['initialBrightness'] as double?;
      previousBlockSize = args['blockSize'] as double?;
      previousEffectSpeed = args['effectSpeed'] as double?;
      previousCelebrationDuration = args['celebrationDuration'] as double?;
      previousInactivityTimeout = args['inactivityTimeout'] as double?;
      sportEffectColor1 = args['sportEffectColor1'] as Color? ?? Colors.red;
      sportEffectColor2 = args['sportEffectColor2'] as Color? ?? Colors.blue;
      initialStartupColor =
          args['initialStartupColor'] as Color? ?? Colors.white;

      ssidController = TextEditingController(text: ssid);
      passwordController = TextEditingController(text: password);
      boardName1Controller = TextEditingController(text: previousNameBoard1);
      boardName2Controller = TextEditingController(text: previousNameBoard2);

      homeScreenState = args['homeScreenState'] as HomeScreenState?;
      if (homeScreenState != null) {
        setState(() {
          isLoading = true; // Show loading indicator
        });
        homeScreenState!.sendCommand('GET_SETTINGS;');
        setupComplete =
            true; // Set this flag to true after sending GET_SETTINGS
        isLoading = false;
      } else {
        logger.e("HomeScreenState is null, cannot request settings");
      }
    }
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
      previousNameBoard1 = currentNameBoard1;
    }
    if (currentNameBoard2 != previousNameBoard2) {
      commands.add('B2:$currentNameBoard2');
      previousNameBoard2 = currentNameBoard2;
    }
    if (currentInitialBrightness != previousInitialBrightness) {
      commands.add('BRIGHT:$currentInitialBrightness');
      previousInitialBrightness = currentInitialBrightness;
    }
    if (currentBlockSize != previousBlockSize) {
      commands.add('SIZE:$currentBlockSize');
      previousBlockSize = currentBlockSize;
    }
    if (currentEffectSpeed != previousEffectSpeed) {
      commands.add('SPEED:$currentEffectSpeed');
      previousEffectSpeed = currentEffectSpeed;
    }
    if (currentCelebrationDuration != previousCelebrationDuration) {
      commands.add('CELEB:$currentCelebrationDuration');
      previousCelebrationDuration = currentCelebrationDuration;
    }
    if (currentInactivityTimeout != previousInactivityTimeout) {
      commands.add('TIMEOUT:$currentInactivityTimeout');
      previousInactivityTimeout = currentInactivityTimeout;
    }
    if (initialStartupColor != previousInitialStartupColor) {
      sendColorToMaster('INITIALCOLOR', initialStartupColor);
      previousInitialStartupColor = initialStartupColor;
    }

    if (sportEffectColor1 != previousSportEffectColor1) {
      sendColorToMaster('SPORTCOLOR1', sportEffectColor1);
      previousSportEffectColor1 = sportEffectColor1;
    }

    if (sportEffectColor2 != previousSportEffectColor2) {
      sendColorToMaster('SPORTCOLOR2', sportEffectColor2);
      previousSportEffectColor2 = sportEffectColor2;
    }
    if (commands.isNotEmpty && homeScreenState != null) {
      final batchCommand = '${commands.join(';')};';
      homeScreenState!.sendCommand(batchCommand);
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

      previousNameBoard1 = nameBoard1;
      previousNameBoard2 = nameBoard2;
      previousInitialBrightness = initialBrightness;
      previousBlockSize = blockSize;
      previousEffectSpeed = effectSpeed;
      previousCelebrationDuration = celebrationDuration;
      previousInactivityTimeout = inactivityTimeout;
      isLoading = false;
      logger.i("Settings received and UI updated, isLoading set to false");
    });
  }

  void sendColorToMaster(String colorName, Color color) {
    int red = (color.value >> 16) & 0xFF;
    int green = (color.value >> 8) & 0xFF;
    int blue = (color.value) & 0xFF;

    String command = '$colorName:$red,$green,$blue';
    homeScreenState!.sendCommand(command);
  }

  void clearSavedVariables() {
    if (homeScreenState != null) {
      homeScreenState!.sendCommand('CLEAR_ALL;');
      logger.i("Sent command to clear all saved variables on both boards.");
    } else {
      logger.e("HomeScreenState is null, cannot send commands");
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
            children: [buildClearSettingsContainer()],
          ),
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
    return Column(
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
                clearSavedVariables();
              }
            },
            child: const Text("Clear Settings"),
          ),
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
          max: 150,
          divisions: ((100 - 5) / 5).toInt(),
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
