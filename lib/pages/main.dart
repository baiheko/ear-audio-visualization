import 'package:flutter/material.dart';

void main() => runApp(const YiErApp());

class YiErApp extends StatelessWidget {
  const YiErApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const YiErMainWindow(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class YiErMainWindow extends StatelessWidget {
  const YiErMainWindow({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                const Text(
                  "易耳 (Ear)",
                  style: TextStyle(color: Color(0xFFB070FF), fontSize: 28, fontWeight: FontWeight.w900),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                const Text(
                  "让音乐看得见 · 触得到",
                  style: TextStyle(color: Color(0xFF666666), fontSize: 11),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 25),
                
                const ModernCard(
                  title: "开始体验 (现场模式)",
                  desc: "实时同步歌词与氛围反馈",
                  icon: "🎵",
                ),
                const SizedBox(height: 12),
                const ModernCard(
                  title: "AI 问答助手",
                  desc: "智能解析现场环境状态",
                  icon: "💬",
                ),
                const SizedBox(height: 20),

                Row(
                  children: const [
                    Expanded(child: ModernCard(title: "教学指南", icon: "🎓", isSmall: true)),
                    SizedBox(width: 12),
                    Expanded(child: ModernCard(title: "系统设置", icon: "⚙️", isSmall: true)),
                  ],
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ModernCard extends StatelessWidget {
  final String title;
  final String? desc;
  final String icon;
  final bool isSmall;

  const ModernCard({
    super.key,
    required this.title,
    this.desc,
    required this.icon,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => debugPrint("点击了 $title"),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1E2E),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (desc != null && !isSmall) ...[
              const SizedBox(height: 4),
              Text(
                desc!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFA0A0B5), fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }
}