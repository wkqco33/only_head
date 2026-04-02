import 'dart:io';

import 'package:flutter/material.dart';

import '../services/head_crop_service.dart';
import 'edit_screen.dart';

class ProcessingScreen extends StatefulWidget {
  final File imageFile;

  const ProcessingScreen({super.key, required this.imageFile});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  String _status = '머리 영역 감지 중...';

  @override
  void initState() {
    super.initState();
    _process();
  }

  Future<void> _process() async {
    try {
      setState(() => _status = 'Segmentation 실행 중...');
      final result = await processHead(widget.imageFile);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => EditScreen(result: result)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '오류 발생: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Image.file(widget.imageFile, fit: BoxFit.contain),
            ),
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    _status,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
