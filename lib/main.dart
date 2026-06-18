import 'package:flutter/material.dart';
import 'pages/main_page.dart'; // 导入主页面
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
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0E14),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B0E14),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const YiErMainWindow(), // 改为主页面作为入口
    );
  }
}