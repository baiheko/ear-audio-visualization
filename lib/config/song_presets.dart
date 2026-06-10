enum LyricMotionPreset {
  soft,
  normal,
  strong,
}

extension LyricMotionPresetX on LyricMotionPreset {
  String get label {
    switch (this) {
      case LyricMotionPreset.soft:
        return '柔和';
      case LyricMotionPreset.normal:
        return '标准';
      case LyricMotionPreset.strong:
        return '强烈';
    }
  }

  /// 动画强度总系数
  /// - 越小：越柔和
  /// - 越大：越明显
  double get intensity {
    switch (this) {
      case LyricMotionPreset.soft:
        return 0.78;
      case LyricMotionPreset.normal:
        return 1.0;
      case LyricMotionPreset.strong:
        return 1.22;
    }
  }

  /// 字符提前出现的时间（秒）
  /// 这个值越大，越容易看到“下一句提前浮现”
  double get leadInSeconds {
    switch (this) {
      case LyricMotionPreset.soft:
        return 0.28;
      case LyricMotionPreset.normal:
        return 0.22;
      case LyricMotionPreset.strong:
        return 0.16;
    }
  }

  /// 尾巴保留时间的倍率
  /// 用来防止上一句最后一个字被下一句直接切断
  double get tailFactor {
    switch (this) {
      case LyricMotionPreset.soft:
        return 1.18;
      case LyricMotionPreset.normal:
        return 1.0;
      case LyricMotionPreset.strong:
        return 0.88;
    }
  }
}

class SongPreset {
  final String id;
  final String title;
  final String artist;
  final String lyricAsset;
  final String audioAsset;
  final double defaultOffsetMs;
  final LyricMotionPreset defaultMotion;

  const SongPreset({
    required this.id,
    required this.title,
    required this.artist,
    required this.lyricAsset,
    required this.audioAsset,
    this.defaultOffsetMs = 0,
    this.defaultMotion = LyricMotionPreset.normal,
  });

  String get displayName => '$title · $artist';
}

/// 这里先把当前这首歌放进去，后面你每加一首歌，只要在这里新增一项就行。
const demoSongPresets = <SongPreset>[
  SongPreset(
    id: 'sasanohani',
    title: 'ささのはに、うたかたに。',
    artist: '佐城雪美 ソロ・リミックス',
    lyricAsset: 'assets/lyrics/sasanohani_ukatakani_test.json',
    audioAsset: 'audio/M・A・O,中澤ミナ,森下来奈 - ささのはに、うたかたに。 (M@STER VERSION).flac',
    defaultOffsetMs: 0,
    defaultMotion: LyricMotionPreset.soft,
  ),

  // 以后加新歌就照着这个格式往下写：
  // SongPreset(
  //   id: 'xxx',
  //   title: 'xxx',
  //   artist: 'xxx',
  //   lyricAsset: 'assets/lyrics/xxx.json',
  //   audioAsset: 'audio/xxx.mp3',
  //   defaultOffsetMs: 0,
  //   defaultMotion: LyricMotionPreset.normal,
  // ),
];