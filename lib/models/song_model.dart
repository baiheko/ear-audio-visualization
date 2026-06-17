class SongLine {
  final String text;
  final double emotion;
  final String beat;
  final String type;

  SongLine({
    required this.text,
    required this.emotion,
    required this.beat,
    required this.type,
  });

  factory SongLine.fromJson(Map<String, dynamic> json) {
    return SongLine(
      text: json['text'],
      emotion: json['emotion'].toDouble(),
      beat: json['beat'],
      type: json['type'],
    );
  }
}

class SongData {
  final List<SongLine> lines;

  SongData({required this.lines});

  factory SongData.fromJson(Map<String, dynamic> json) {
    return SongData(
      lines: (json['lines'] as List).map((e) => SongLine.fromJson(e)).toList(),
    );
  }
}
