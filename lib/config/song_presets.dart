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

  SongPreset(
    id: 'todokanai',
    title: '上原れな - 届かない恋',
    artist: '上原れな',
    lyricAsset: 'assets/lyrics/上原玲奈 - 届かない恋 (无法传达的恋情) (249594898).json',
    audioAsset: 'audio/上原れな - 届かない恋.flac',
    defaultOffsetMs: 1,
    defaultMotion: LyricMotionPreset.normal,
  ),

  SongPreset(
    id: 'gaobaiqiqiu',
    title: '告白气球',
    artist: '周杰伦',
    lyricAsset: 'assets/lyrics/gaobaiqiqiu.json',
    audioAsset: 'audio/告白气球 - 周杰伦',
    defaultOffsetMs: 2,
    defaultMotion: LyricMotionPreset.normal,
  ),

  SongPreset(
    id: 'On your mark',
    title: '蓮ノ空女学院スクールアイドルクラブ - On your mark (104期 Ver.)',
    artist: '蓮ノ空女学院スクールアイドルクラブ',
    lyricAsset: 'assets/lyrics/蓮ノ空女学院スクールアイドルクラブ - On your mark (403090824).json',
    audioAsset: 'audio/蓮ノ空女学院スクールアイドルクラブ - On your mark (403090824).flac',
    defaultOffsetMs: 3,
    defaultMotion: LyricMotionPreset.normal,
  ),

  SongPreset(
    id: '余韻',
    title: '小泉萌香 - 余韻',
    artist: '小泉萌香',
    lyricAsset: 'assets/lyrics/小泉萌香 - 余韻.json',
    audioAsset: 'audio/小泉萌香 - 余韻.flac',
    defaultOffsetMs: 4,
    defaultMotion: LyricMotionPreset.normal,
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