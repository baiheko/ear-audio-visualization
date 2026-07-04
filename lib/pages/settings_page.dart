import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(title: const Text("系统设置"), backgroundColor: Colors.transparent),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildGroup("听觉辅助与个性化", [
            _buildSwitch("环境音增强", true),
            _buildSlider("环境音强度", 0.7),
            _buildSwitch("语音转文字", true),
            _buildSlider("文字大小", 0.5),
          ]),
          _buildGroup("振动反馈", [
            _buildSlider("振动强度", 0.8),
            _buildSelection("振动模式", "跟随音乐节拍"),
          ]),
          _buildGroup("现场模式快捷设置", [
            _buildSelection("默认场景", "主舞台前方"),
            _buildSwitch("防打扰模式", false),
          ]),
        ],
      ),
    );
  }

  // 组件构建：分组卡片
  Widget _buildGroup(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1A1E2E), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Color(0xFFB070FF), fontWeight: FontWeight.bold, fontSize: 16)),
        const Divider(color: Colors.white10),
        ...children,
      ]),
    );
  }

  // 控件封装：开关、滑块、选项
  Widget _buildSwitch(String label, bool value) => SwitchListTile(
    title: Text(label, style: const TextStyle(color: Colors.white)),
    value: value, onChanged: (v) {}, activeColor: const Color(0xFFB070FF),
  );

  Widget _buildSlider(String label, double value) => Column(
    children: [
      ListTile(title: Text(label, style: const TextStyle(color: Colors.white))),
      Slider(value: value, onChanged: (v) {}, activeColor: const Color(0xFFB070FF)),
    ],
  );

  Widget _buildSelection(String label, String current) => ListTile(
    title: Text(label, style: const TextStyle(color: Colors.white)),
    trailing: Text(current, style: const TextStyle(color: Colors.grey)),
    onTap: () {},
  );
}