import 'package:flutter/material.dart';
import 'ai_chat_page.dart';
import 'player_page.dart';
import 'guide_page.dart';
import 'settings_page.dart';

class YiErMainWindow extends StatelessWidget {
  const YiErMainWindow({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                
                // 开始体验
                ModernCard(
                  title: "开始体验 (现场模式)",
                  desc: "实时同步歌词与氛围反馈",
                  icon: "🎵",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const PlayerPage()),
                    );
                  },
                ),
                const SizedBox(height: 12),
                
                // AI 问答助手（只保留这一个）
                ModernCard(
                  title: "AI 问答助手",
                  desc: "智能解析现场环境状态",
                  icon: "💬",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AiChatPage()),
                    );
                  },
                ),
                const SizedBox(height: 20),
                
                // 教学指南 + 系统设置（只保留这一个）
                Row(
                  children: [
                    Expanded(
                      child: ModernCard(
                        title: "教学指南",
                        icon: "🎓",
                        isSmall: true,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const GuidePage()),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ModernCard(
                        title: "系统设置",
                        icon: "⚙️",
                        isSmall: true,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const SettingsPage()),
                        ),
                      ),
                    ),
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

// 卡片组件
class ModernCard extends StatelessWidget {
  final String title;
  final String? desc;
  final String icon;
  final bool isSmall;
  final VoidCallback? onTap;

  const ModernCard({
    super.key,
    required this.title,
    this.desc,
    required this.icon,
    this.isSmall = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => debugPrint("点击了 $title"),
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