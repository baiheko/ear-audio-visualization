import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/lyric_models.dart';

class AiLineResult {
  final int index;
  final double emotion;
  final String beat;
  final String type;

  AiLineResult({
    required this.index,
    required this.emotion,
    required this.beat,
    required this.type,
  });

  factory AiLineResult.fromJson(Map<String, dynamic> json) {
    return AiLineResult(
      index: json['index'] as int,
      emotion: (json['emotion'] as num).toDouble(),
      beat: json['beat'].toString(),
      type: json['type'].toString(),
    );
  }
}

class AiService {
  static Future<Map<int, AiLineResult>> analyzeSong(
    List<LyricLine> lines,
  ) async {
    final payload = {
      "lines": List.generate(lines.length, (index) {
        return {"index": index, "text": lines[index].text};
      }),
    };

    final response = await http
        .post(
          Uri.parse("http://127.0.0.1:5000/analyze_song"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 90));

    if (response.statusCode != 200) {
      throw Exception(response.body);
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final rawLines = data["lines"] as List;

    final Map<int, AiLineResult> result = {};

    for (final item in rawLines) {
      final aiLine = AiLineResult.fromJson(Map<String, dynamic>.from(item));
      result[aiLine.index] = aiLine;
    }

    return result;
  }
}
