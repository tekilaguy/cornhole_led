// widgets/effect_button.dart
import 'package:flutter/material.dart';

class EffectButton extends StatelessWidget {
  final Color activeShadowColor;
  final String label;
  final bool isActive;
  final VoidCallback onPressed;

  const EffectButton({
    super.key,
    required this.activeShadowColor,
    required this.label,
    required this.isActive,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
   return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      width: (MediaQuery.of(context).size.width * 0.4) - 20,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isActive ? Colors.black : Colors.white,
          foregroundColor: isActive ? Colors.white : Colors.black,
          shadowColor: isActive ? activeShadowColor : Colors.black,
          elevation: isActive ? 15 : 25,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        ),
        child: Text(label),
      ),
    );
  }
}