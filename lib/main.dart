import 'package:flutter/material.dart';
import 'pages/player_page.dart';

void main() {
  runApp(const EarApp());
}

/// 应用入口
class EarApp extends StatelessWidget {
  const EarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '易耳',
      theme: ThemeData.dark(useMaterial3: true),
      home: const PlayerPage(),
    );
  }
}