// widgets/toggle_switches.dart
import 'package:flutter/material.dart';

class ToggleSwitch extends StatelessWidget {
  final String label;
  final bool currentValue;
  final ValueChanged<bool> onChanged;

  const ToggleSwitch({
    super.key,
    required this.label,
    required this.currentValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 16)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              currentValue ? 'On' : 'Off',
              style: TextStyle(color: currentValue ? Colors.green : Colors.red),
            ),
            Switch(
              value: currentValue,
              onChanged: onChanged,
            ),
          ],
        ),
      ],
    );
  }
}
