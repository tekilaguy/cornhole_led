// widgets/section.dart
import 'package:flutter/material.dart';

class Section extends StatelessWidget {
  final String title;
  final Widget content;

  const Section({
    super.key,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.blue,
        border: Border.all(width: 1.5, color: Colors.black),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black,
            spreadRadius: 5,
            blurRadius: 7,
            offset: const Offset(3, 3),
          ),
        ],
      ),
      width: MediaQuery.of(context).size.width * 0.9,
      constraints: const BoxConstraints(maxWidth: 600),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Divider(
            color: Colors.white,
            thickness: 2,
          ),
          content,
        ],
      ),
    );
  }
}
