// widgets/color_button.dart
import 'package:flutter/material.dart';

class ColorButton extends StatelessWidget {
  final Color color;
  final bool isActive;
  final VoidCallback onPressed;

  const ColorButton({
    super.key,
    required this.color,
    required this.isActive,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(5),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: isActive ? Colors.black : color,
              shadowColor: isActive ? color : Colors.black,
              elevation: isActive ? 15 : 25,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.all(20),
            ),
            child: null,
          ),
          if (isActive)
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}
