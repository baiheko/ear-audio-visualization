import 'dart:math' as math;

/// 单个字的歌词信息
class LyricChar {
  final String char;

  /// 当前字在整首歌中的开始/结束时间（秒）
  final double start;
  final double end;

  /// 可选参数：缺失也没关系
  final double? pitch;
  final double? volume;
  final double? emotion;

  LyricChar({
    required this.char,
    required this.start,
    required this.end,
    this.pitch,
    this.volume,
    this.emotion,
  });

  /// 从 JSON 读取单字信息
  factory LyricChar.fromJson(Map<String, dynamic> json) {
    return LyricChar(
      char: _asString(json['char']),
      start: _asDouble(json['start']),
      end: _asDouble(json['end']),
      pitch: _asDoubleOrNull(json['pitch']),
      volume: _asDoubleOrNull(json['volume']),
      emotion: _asDoubleOrNull(json['emotion']),
    );
  }
}

/// 单句歌词信息
class LyricLine {
  final double start;
  final double end;

  /// 原文
  final String text;

  /// 译文，可空
  final String translation;

  /// 句子整体情绪，可空
  final double? emotion;

  /// 逐字数据
  final List<LyricChar> chars;

  LyricLine({
    required this.start,
    required this.end,
    required this.text,
    required this.translation,
    required this.emotion,
    required this.chars,
  });

  /// 从 JSON 读取单句信息
  factory LyricLine.fromJson(Map<String, dynamic> json) {
    final rawChars = (json['chars'] as List?) ?? const [];

    final chars = rawChars
        .whereType<Map>()
        .map((e) => LyricChar.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    final lineText = _asString(json['text']);

    // 如果没有 chars，就按整句均匀拆字，保证鲁棒性
    final parsedChars = chars.isNotEmpty
        ? chars
        : _splitTextToChars(
            lineText,
            _asDouble(json['start']),
            _asDouble(json['end']),
          );

    final safeText = lineText.isNotEmpty
        ? lineText
        : parsedChars.map((e) => e.char).join();

    final safeStart = parsedChars.isNotEmpty
        ? parsedChars.first.start
        : _asDouble(json['start']);

    final safeEnd = parsedChars.isNotEmpty
        ? parsedChars.last.end
        : _asDouble(json['end']);

    return LyricLine(
      start: safeStart,
      end: safeEnd > safeStart ? safeEnd : safeStart + 0.2,
      text: safeText,
      translation: _asString(json['translation'] ?? json['trans'] ?? json['translated_text']),
      emotion: _asDoubleOrNull(json['emotion']),
      chars: _normalizeCharTimes(
        parsedChars,
        safeStart,
        safeEnd > safeStart ? safeEnd : safeStart + 0.2,
      ),
    );
  }
}

/// 节拍点
class BeatMark {
  final double time;
  final double strength;

  BeatMark({
    required this.time,
    required this.strength,
  });

  factory BeatMark.fromJson(Map<String, dynamic> json) {
    return BeatMark(
      time: _asDouble(json['time']),
      strength: _clamp(_asDouble(json['strength'], fallback: 0.5), 0.0, 1.0),
    );
  }
}

/// 整首歌
class SongModel {
  final String title;
  final String artist;

  /// JSON 里可有可无；如果没有，播放器会用音频时长覆盖
  final double duration;

  final List<LyricLine> lines;
  final List<BeatMark> beats;

  SongModel({
    required this.title,
    required this.artist,
    required this.duration,
    required this.lines,
    required this.beats,
  });

  factory SongModel.fromJson(Map<String, dynamic> json) {
    final rawLines = (json['lines'] as List?) ?? const [];
    final rawBeats = (json['beats'] as List?) ?? const [];

    final lines = rawLines
        .whereType<Map>()
        .map((e) => LyricLine.fromJson(Map<String, dynamic>.from(e)))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final beats = rawBeats
        .whereType<Map>()
        .map((e) => BeatMark.fromJson(Map<String, dynamic>.from(e)))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    return SongModel(
      title: _asString(json['title'], fallback: '未知歌曲'),
      artist: _asString(json['artist'], fallback: '未知歌手'),
      duration: _asDoubleOrNull(json['duration']) ?? 0.0,
      lines: lines,
      beats: beats,
    );
  }
}

/// 当两句歌词之间间隔较长时，用它来显示“副歌展开中”的提示。
class ChorusGapInfo {
  final int fromIndex;
  final int toIndex;
  final double gapStart;
  final double gapEnd;
  final double gapDuration;
  final double progress;

  ChorusGapInfo({
    required this.fromIndex,
    required this.toIndex,
    required this.gapStart,
    required this.gapEnd,
    required this.gapDuration,
    required this.progress,
  });
}

/// -------------------------
/// 下面是内部工具函数
/// -------------------------

double _asDouble(dynamic value, {double fallback = 0.0}) {
  if (value is num) return value.toDouble();
  return fallback;
}

double? _asDoubleOrNull(dynamic value) {
  if (value is num) return value.toDouble();
  return null;
}

String _asString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  return value.toString();
}

/// 把一句话拆成逐字对象，并按整句时间均分。
List<LyricChar> _splitTextToChars(String text, double start, double end) {
  final chars = text.runes.map((r) => String.fromCharCode(r)).toList();
  if (chars.isEmpty) return [];

  final total = math.max(end - start, 0.12);
  final step = total / chars.length;

  final result = <LyricChar>[];
  for (int i = 0; i < chars.length; i++) {
    final s = start + i * step;
    final e = i == chars.length - 1 ? end : start + (i + 1) * step;
    result.add(
      LyricChar(
        char: chars[i],
        start: s,
        end: e > s ? e : s + 0.08,
      ),
    );
  }
  return result;
}

/// 如果单字时间缺失，则按整句范围补齐
List<LyricChar> _normalizeCharTimes(List<LyricChar> chars, double start, double end) {
  if (chars.isEmpty) return chars;

  final total = math.max(end - start, 0.12);
  final step = total / chars.length;

  return List.generate(chars.length, (i) {
    final old = chars[i];
    final s = old.start > 0 ? old.start : start + i * step;
    final e = old.end > 0 ? old.end : (i == chars.length - 1 ? end : start + (i + 1) * step);

    return LyricChar(
      char: old.char,
      start: s,
      end: e > s ? e : s + 0.08,
      pitch: old.pitch,
      volume: old.volume,
      emotion: old.emotion,
    );
  });
}

double _clamp(double v, double min, double max) {
  if (v < min) return min;
  if (v > max) return max;
  return v;
}

