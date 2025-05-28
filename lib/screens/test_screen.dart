import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';

class TestOTADownloadScreen extends StatefulWidget {
  const TestOTADownloadScreen({super.key});

  @override
  State<TestOTADownloadScreen> createState() => _TestOTADownloadScreenState();
}

class _TestOTADownloadScreenState extends State<TestOTADownloadScreen> {
  String status = "";
  int size = 0;
  double progress = 0.0;
  List<Uint8List> chunks = [];

  final testUrl = "https://raw.githubusercontent.com/tekilaguy/cornhole_led/main/updates/cornhole_board.bin";

  Future<void> downloadAndChunk() async {
    setState(() {
      status = "⏬ Downloading...";
      size = 0;
      chunks.clear();
      progress = 0;
    });

    try {
      final response = await http.get(Uri.parse(testUrl));

      if (response.statusCode != 200) {
        setState(() => status = "❌ Failed: ${response.statusCode}");
        return;
      }

      final bytes = response.bodyBytes;
      final total = bytes.length;
      final chunkSize = 240;

      for (int offset = 0; offset < total; offset += chunkSize) {
        final end = (offset + chunkSize < total) ? offset + chunkSize : total;
        chunks.add(bytes.sublist(offset, end));
        setState(() => progress = offset / total);
        await Future.delayed(const Duration(milliseconds: 10));
      }

      setState(() {
        status = "✅ Downloaded ${chunks.length} chunks";
        size = total;
        progress = 1.0;
      });
    } catch (e) {
      setState(() => status = "❌ Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("OTA Download Test")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text("Firmware URL:\n$testUrl", style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 10),
            Text("Status: $status"),
            Text("Total Bytes: $size"),
            Text("Chunks: ${chunks.length}"),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: downloadAndChunk,
              child: const Text("Test Download & Chunk"),
            ),
          ],
        ),
      ),
    );
  }
}
