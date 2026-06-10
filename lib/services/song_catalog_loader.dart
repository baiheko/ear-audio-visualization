import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/lyric_models.dart';

/// 歌单中的一项。
/// 这里把音频和歌词拆开管理，后续你加新歌只要改 catalog 文件。
class SongCatalogEntry {
  final String id;
  final String title;
  final String artist;

  /// 相对 assets/ 的路径，比如：lyrics/xxx.json
  final String lyricAsset;

  /// 相对 assets/ 的路径，比如：audio/xxx.mp3
  final String audioAsset;

  /// 默认歌词偏移，单位毫秒。
  /// 这个值会在进入歌曲时自动加载到播放器里。
  final double defaultOffsetMs;

  SongCatalogEntry({
    required this.id,
    required this.title,
    required this.artist,
    required this.lyricAsset,
    required this.audioAsset,
    required this.defaultOffsetMs,
  });

  factory SongCatalogEntry.fromJson(Map<String, dynamic> json) {
    return SongCatalogEntry(
      id: _asString(json['id'], fallback: json['title']?.toString() ?? 'unknown'),
      title: _asString(json['title'], fallback: '未知歌曲'),
      artist: _asString(json['artist'], fallback: '未知歌手'),
      lyricAsset: _asString(json['lyricAsset']),
      audioAsset: _asString(json['audioAsset']),
      defaultOffsetMs: _asDoubleOrNull(json['defaultOffsetMs']),
    );
  }
}

class SongCatalogLoader {
  /// 读取歌单目录
  static Future<List<SongCatalogEntry>> loadCatalog() async {
    final raw = await rootBundle.loadString('assets/songs/song_catalog.json');
    final data = jsonDecode(raw);

    if (data is! List) {
      throw Exception('song_catalog.json 必须是数组');
    }

    return data
        .whereType<Map>()
        .map((e) => SongCatalogEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 读取单首歌的歌词 JSON
  static Future<SongModel> loadLyrics(String relativeAssetPath) async {
    final fullPath = _fullAssetPath(relativeAssetPath);
    final raw = await rootBundle.loadString(fullPath);
    final data = jsonDecode(raw);

    if (data is! Map<String, dynamic>) {
      throw Exception('歌词 JSON 格式错误：$fullPath');
    }

    return SongModel.fromJson(data);
  }

  static String _fullAssetPath(String relative) {
    final clean = relative.startsWith('assets/')
        ? relative
        : 'assets/$relative';
    return clean;
  }
}

/// -------------------------
/// 小工具
/// -------------------------

double _asDoubleOrNull(dynamic value) {
  if (value is num) return value.toDouble();
  return 0.0;
}

String _asString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  return value.toString();
}