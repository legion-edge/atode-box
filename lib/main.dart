import 'package:flutter/material.dart';

void main() => runApp(const AtodeBoxApp());

class AtodeBoxApp extends StatelessWidget {
  const AtodeBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'あとでボックス',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF86A9A1)),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inventory_2_outlined, size: 56),
                SizedBox(height: 20),
                Text('あとでボックス', style: TextStyle(fontSize: 26)),
                SizedBox(height: 12),
                Text('今じゃない。でも忘れたくない。'),
                SizedBox(height: 24),
                Text('入力機能は準備中です'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
