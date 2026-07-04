import 'package:flutter/material.dart';

class GuidePage extends StatelessWidget {
  const GuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> guideData = [
      {"title": "连接现场", "desc": "将手机麦克风对准音源，易耳将为您捕捉每一段旋律的生命力。", "icon": "🎙️", "color": const Color(0xFF6C63FF)},
      {"title": "感知韵律", "desc": "AI 实时分析歌词，我们将为您呈现与之共鸣的视觉氛围。", "icon": "✨", "color": const Color(0xFF4CA1AF)},
      {"title": "沉浸交互", "desc": "轻触屏幕，探索音乐背后的情感色彩，享受触手可及的音乐体验。", "icon": "🧡", "color": const Color(0xFFFF7E5F)},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(title: const Text("教学指南"), backgroundColor: Colors.transparent),
      // 改为垂直的 ListView，天然支持上下滑动，且不会显示不全
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        itemCount: guideData.length,
        separatorBuilder: (_, __) => const SizedBox(height: 20), // 卡片之间的间距
        itemBuilder: (context, index) {
          final item = guideData[index];
          // 给卡片一个固定的高度，保证在小屏幕上也能展示
          return SizedBox(
            height: 200, 
            child: _buildGuideCard(item),
          );
        },
      ),
    );
  }

  Widget _buildGuideCard(Map<String, dynamic> item) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [item['color'], item['color'].withOpacity(0.6)]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row( // 使用 Row 让图标在左，文字在右，阅读体验更好
        children: [
          Text(item['icon'], style: const TextStyle(fontSize: 50)),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['title'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                Text(item['desc'], style: const TextStyle(fontSize: 14, color: Colors.white70), maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}