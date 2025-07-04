// setup_screen.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:numberpicker/numberpicker.dart';
import 'package:provider/provider.dart';
import '/global.dart';
import '/ble_provider.dart';
import '/widgets/background.dart';
import '/widgets/section.dart';
import '/widgets/status_indicators.dart';

class SetupScreen extends StatefulWidget {
  final double initialBrightness;
  final double effectSpeed;
  final double blockSize;
  final double celebrationDuration;
  final double inactivityTimeout;
  final double deepSleepTimeout;
  final Color sportEffectColor1;
  final Color sportEffectColor2;
  final Color initialStartupColor;
  final Function(String) sendCommand;

  const SetupScreen({
    super.key,
    required this.initialBrightness,
    required this.effectSpeed,
    required this.blockSize,
    required this.celebrationDuration,
    required this.inactivityTimeout,
    required this.deepSleepTimeout,
    required this.sportEffectColor1,
    required this.sportEffectColor2,
    required this.initialStartupColor,
    required this.sendCommand,
  });

  @override
  SetupScreenState createState() => SetupScreenState();
}

class SetupScreenState extends State<SetupScreen>
    with AutomaticKeepAliveClientMixin {
  final Logger logger = Logger();
  BLEProvider get bleProvider =>
      Provider.of<BLEProvider>(context, listen: false);

  bool setupComplete = false;

// Previous settings for comparison
  double? previousInitialBrightness;
  double? previousBlockSize;
  double? previousEffectSpeed;
  double? previousCelebrationDuration;
  double? previousInactivityTimeout;
  double? previousDeepSleepTimeout;
  Color? previousInitialStartupColor;
  Color? previousSportEffectColor1;
  Color? previousSportEffectColor2;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    initializeSettings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!setupComplete) {
      previousInitialBrightness = widget.initialBrightness;
      previousBlockSize = widget.blockSize;
      previousEffectSpeed = widget.effectSpeed;
      previousCelebrationDuration = widget.celebrationDuration;
      previousInactivityTimeout = widget.inactivityTimeout;
      previousDeepSleepTimeout = widget.deepSleepTimeout;
      previousSportEffectColor1 = widget.sportEffectColor1;
      previousSportEffectColor2 = widget.sportEffectColor2;
      previousInitialStartupColor = widget.initialStartupColor;

      setState(() {
        isLoading = true; // Show loading indicator
      });
      widget.sendCommand('CMD:SETTINGS;');
    }
  }

  void initializeSettings() async {
    setState(() {
      isLoading = true;
    });

    await widget.sendCommand('CMD:SETTINGS;');
    setupComplete = true; // Set this flag to true after sending GET_SETTINGS

    setState(() {
      isLoading = false;
    });
  }

  void saveDefaultSettings() {
    final List<String> commands = [];

    final currentInitialBrightness = initialBrightness;
    final currentBlockSize = blockSize;
    final currentEffectSpeed = effectSpeed;
    final currentCelebrationDuration = celebrationDuration;
    final currentInactivityTimeout = inactivityTimeout;
    final currentDeepSleepTimeout = deepSleepTimeout;

    if (currentInitialBrightness != previousInitialBrightness) {
      commands.add('SET:BRIGHT:$currentInitialBrightness');
    }
    if (currentBlockSize != previousBlockSize) {
      commands.add('SET:SIZE:$currentBlockSize');
    }
    if (currentEffectSpeed != previousEffectSpeed) {
      commands.add('SET:SPEED:$currentEffectSpeed');
    }
    if (currentCelebrationDuration != previousCelebrationDuration) {
      commands.add('SET:CELEB:$currentCelebrationDuration');
    }
    if (currentInactivityTimeout != previousInactivityTimeout) {
      commands.add('SET:TIMEOUT:$currentInactivityTimeout');
    }
    if (currentDeepSleepTimeout != previousDeepSleepTimeout) {
      commands.add('SET:DEEPSLEEP:$currentDeepSleepTimeout');
    }
    if (initialStartupColor != previousInitialStartupColor) {
      int red = (initialStartupColor.value >> 16) & 0xFF;
      int green = (initialStartupColor.value >> 8) & 0xFF;
      int blue = (initialStartupColor.value) & 0xFF;
      commands.add('SET:IC:$red,$green,$blue');
    }

    if (sportEffectColor1 != previousSportEffectColor1) {
      int red = (sportEffectColor1.value >> 16) & 0xFF;
      int green = (sportEffectColor1.value >> 8) & 0xFF;
      int blue = (sportEffectColor1.value) & 0xFF;
      commands.add('SET:SC1:$red,$green,$blue');
      bleProvider.sendCommand('SC1:$red,$green,$blue');
    }

    if (sportEffectColor2 != previousSportEffectColor2) {
      int red = (sportEffectColor2.value >> 16) & 0xFF;
      int green = (sportEffectColor2.value >> 8) & 0xFF;
      int blue = (sportEffectColor2.value) & 0xFF;
      commands.add('SET:SC2:$red,$green,$blue');
      bleProvider.sendCommand('SC2:$red,$green,$blue');
    }
    logger.i(
        "homeScreenState is ${homeScreenState != null ? 'not null' : 'null'}");

    if (commands.isNotEmpty && homeScreenState != null) {
      final batchCommand = '${commands.join(';')};';
      bleProvider.sendCommand(batchCommand);
      previousInitialBrightness = currentInitialBrightness;
      previousBlockSize = currentBlockSize;
      previousEffectSpeed = currentEffectSpeed;
      previousCelebrationDuration = currentCelebrationDuration;
      previousInactivityTimeout = currentInactivityTimeout;
      previousDeepSleepTimeout = currentDeepSleepTimeout;
      previousInitialStartupColor = initialStartupColor;
      previousSportEffectColor1 = sportEffectColor1;
      previousSportEffectColor2 = sportEffectColor2;
    } else if (commands.isEmpty) {
      logger.i("No changes detected, no commands sent");
    } else {
      logger.e("HomeScreenState is null, cannot send commands");
    }
  }

  void updateUIWithCurrentSettings() {
    setState(() {
      initialBrightness = initialBrightness;
      blockSize = blockSize;
      effectSpeed = effectSpeed;
      celebrationDuration = celebrationDuration;
      inactivityTimeout = inactivityTimeout;
      deepSleepTimeout = deepSleepTimeout;
      initialStartupColor = initialStartupColor;
      sportEffectColor1 = sportEffectColor1;
      sportEffectColor2 = sportEffectColor2;
      isLoading = false;
      logger.i("Settings received and UI updated, isLoading set to false");
    });
  }

  void sendColorToPrimary(String colorName, Color color) {
    int red = (color.value >> 16) & 0xFF;
    int green = (color.value >> 8) & 0xFF;
    int blue = (color.value) & 0xFF;

    String command = '$colorName:$red,$green,$blue';
    if (homeScreenState != null) {
      bleProvider.sendCommand(command);
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
        bleProvider.sendCommand('SET_ROLE:SECONDARY;');
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
        bleProvider.sendCommand('CMD:RESET;');
        logger.i("Sent command to reset configuration on both boards.");
      } else {
        logger.e("HomeScreenState is null, cannot send commands");
      }
    }
  }

  void onBackButtonPressed() {}
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
        bleProvider.sendCommand('CMD:CLEAR;');
        logger.i("Sent command to clear all saved variables on both boards.");
      } else {
        logger.e("HomeScreenState is null, cannot send commands");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return isLoading
        ? const Center(child: CircularProgressIndicator())
        : WillPopScope(
            onWillPop: () async {
              onBackButtonPressed();
              return false;
            },
            child: Scaffold(
              body: Stack(
                children: [
                  const Background(),
                  Padding(
                    padding: const EdgeInsets.all(5.0),
                    child: ListView(
                      children: [
                        const SizedBox(height: 20),
                        context.watch<BLEProvider>().isConnected
                            ? buildControlScreen()
                            : bleProvider.buildDeviceList(),
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

  Widget buildDefaultSettingsContainer() {
    return Container(
      padding: const EdgeInsets.all(5.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Divider(
            color: Colors.blue,
            thickness: 2,
          ),
          Row(
            children: [
              Expanded(
                child: buildSliderInput(
                  "Initial Brightness",
                  initialBrightness,
                  0,
                  100,
                  1,
                  (value) {
                    setState(() {
                      initialBrightness = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: buildSliderInput(
                  "Effects Speed",
                  effectSpeed,
                  1,
                  50,
                  1,
                  (value) {
                    setState(() {
                      effectSpeed = value;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: buildSliderInput(
                  "Scoring Duration",
                  celebrationDuration / 1000, // Convert ms to seconds
                  1,
                  10,
                  1,
                  (value) {
                    setState(() {
                      celebrationDuration = value * 1000; // Convert back to ms
                    });
                  },
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: buildSliderInput(
                  "Effects Size",
                  blockSize,
                  1,
                  50,
                  1,
                  (value) {
                    setState(() {
                      blockSize = value;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const SizedBox(width: 20),
              Expanded(
                child: buildSliderInput(
                  "Timeout (minutes)",
                  inactivityTimeout,
                  0,
                  60,
                  1,
                  (value) {
                    setState(() {
                      inactivityTimeout = value;
                    });
                  },
                ),
              ),
              Expanded(
                child: buildSliderInput(
                  "Shutdown Timeout",
                  deepSleepTimeout,
                  1,
                  30,
                  1,
                  (value) {
                    setState(() {
                      deepSleepTimeout = value;
                    });
                  },
                ),
              ),
            ],
          ),
          const Divider(
            color: Colors.blue,
            thickness: 2,
          ),
          buildColorPicker("Initial Startup Color", initialStartupColor,
              (color) {
            setState(() {
              initialStartupColor = color; // Update the color
            });
          }),
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
              onPressed: saveDefaultSettings,
              child: const Text("Save Default Settings"),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSliderInput(String label, double value, double min, double max,
      double step, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: ((max - min) ~/ step).toInt(),
          label: value.round().toString(),
          onChanged: onChanged,
        ),
      ],
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
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),

        // Circular Color Picker Button
        GestureDetector(
          onTap: () async {
            // Ensure current color is set correctly
            Color pickedColor = currentColor;

            Color? selectedColor = await showDialog<Color>(
              context: context,
              builder: (context) {
                return AlertDialog(
                  title: Text("Pick a Color for $label"),
                  content: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Quick Selection of Preset Colors
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: predefinedColors.map((color) {
                            return GestureDetector(
                              onTap: () {
                                Navigator.of(context).pop(color);
                              },
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: color == pickedColor
                                        ? Colors.black
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),

                        // Full Color Picker for Custom Selection
                        ColorPicker(
                          pickerColor: pickedColor,
                          onColorChanged: (color) {
                            pickedColor = color;
                          },
                          showLabel: true,
                          pickerAreaHeightPercent: 0.5,
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      child: const Text("Cancel"),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
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

            if (selectedColor != null) {
              // Update UI and set new color
              setState(() {
                onColorChanged(selectedColor);
              });
            }
          },
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: currentColor, // Always shows the latest color
              borderRadius: BorderRadius.circular(25),
              border: Border.all(width: 2, color: Colors.black),
            ),
          ),
        ),
      ],
    );
  }

// List of predefined colors for quick selection
  final List<Color> predefinedColors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.yellow,
    Colors.orange,
    Colors.purple,
    Colors.cyan,
    Colors.pink,
    Colors.teal,
    Colors.brown,
    Colors.white,
    Colors.black,
  ];
}
