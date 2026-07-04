import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/lyric_models.dart';

/// 负责从 assets 里读取 JSON 歌词文件
class LyricLoader {
  static Future<SongModel> loadFromAsset(String assetPath) async {
    final jsonStr = await rootBundle.loadString(assetPath);
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    return SongModel.fromJson(data);
  }
}