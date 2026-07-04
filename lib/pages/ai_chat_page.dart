import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';


class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;
  final String _apiKey = "sk-a7b4b23054d44c54a373f9ca503f0491";

  Future<void> _sendMessage() async {
    if (_controller.text.isEmpty) return;
    final String userText = _controller.text;

    // 1. 先更新 UI
    setState(() {
      _messages.add({"role": "user", "content": userText});
      _isLoading = true;
    });
    _controller.clear();

    // 2. 异步请求，带上超时
    try {
      debugPrint("正在请求蓝心 API...");
      
      // 使用 timeout 确保不会一直卡在那
      final response = await http.post(
        Uri.parse('https://api.deepseek.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer sk-a7b4b23054d44c54a373f9ca503f0491',        
        },
        // 修改 body 逻辑，使用动态的 userText
body: jsonEncode({
  "model": "deepseek-chat", 
  // 如果想简单点，就只发当前这一句：
  "messages": [{"role": "user", "content": userText}], 
  
  // 如果想实现连续对话，建议发送整个列表：
  // "messages": _messages, 
  
  "stream": false
}),); // 设定 10 秒超时

      // 3. 处理响应
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        debugPrint("API 原始返回数据: $data"); // 务必观察控制台输出的这个数据结构

        // 安全校验解析
        if (data != null && data['choices'] != null && (data['choices'] as List).isNotEmpty) {
          final choice = data['choices'][0];
          if (choice['message'] != null && choice['message']['content'] != null) {
            String aiResponse = choice['message']['content'];
            setState(() => _messages.add({"role": "assistant", "content": aiResponse}));
          } else {
            debugPrint("错误：找不到 message 或 content 字段");
          }
        } else {
          // 如果这里被触发，说明 API 返回的是错误信息
          debugPrint("API 返回异常数据结构: $data");
        }
      } else {
        debugPrint("服务器返回状态码: ${response.statusCode}");
        debugPrint("错误详情: ${response.body}");
      }
    } catch (e) {
      debugPrint("请求发生异常: $e");
      setState(() => _messages.add({"role": "assistant", "content": "连接超时或出现网络错误，请重试。"}));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 组件放在类内部，方法外部
  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1E2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: "发送消息...",
                hintStyle: TextStyle(color: Colors.grey),
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Color(0xFFB070FF)),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: _messages.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("有什么我可以帮你的吗？", style: TextStyle(color: Colors.white, fontSize: 24)),
                  const SizedBox(height: 30),
                  SizedBox(width: MediaQuery.of(context).size.width * 0.85, child: _buildInputArea()),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final isUser = _messages[index]['role'] == 'user';
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isUser ? const Color(0xFFB070FF) : const Color(0xFF1A1E2E),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(_messages[index]['content']!, style: const TextStyle(color: Colors.white)),
                        ),
                      );
                    },
                  ),
                ),
                _buildInputArea(),
              ],
            ),
    );
  }
}