import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import '../config/song_presets.dart';
import '../models/lyric_models.dart';
import '../services/lyric_loader.dart';
import '../widgets/lyric_widgets.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}


class _PlayerPageState extends State<PlayerPage>
    with TickerProviderStateMixin {
  // -----------------------------
  // 歌曲库
  // -----------------------------
  final List<SongPreset> _presets = demoSongPresets;
  int _presetIndex = 0;

  // -----------------------------
  // 音频 & 歌词
  // -----------------------------
  SongModel? _song;
  final AudioPlayer _player = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;

  Duration _position = Duration.zero;
  Duration _audioDuration = Duration.zero;

  bool _loading = true;
  String _errorText = '';

  // -----------------------------
  // 动画/显示参数
  // -----------------------------
  double _lyricsOffsetMs = 0.0; // 正值 = 歌词更早显示
  bool _offsetExpanded = false;
  bool _vibrationEnabled = false;

  LyricMotionPreset _motionPreset = LyricMotionPreset.normal;

  // -----------------------------
  // 节拍闪光
  // -----------------------------
  late final AnimationController _beatController;
  late final AnimationController _ellipsisController;
  int _lastBeatIndex = -1;

  // -----------------------------
  // 逐字动画缓存
  // -----------------------------
  final Map<String, LyricCharEffect> _effectCache = {};

  bool _audioPrepared = false;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<void>? _completeSub;

  @override
  void initState() {
    super.initState();

    _beatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    _ellipsisController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();

    _preparePreset(_presets[_presetIndex]);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();

    _player.dispose();
    _beatController.dispose();
    _ellipsisController.dispose();

    super.dispose();
  }

  /// 加载当前选择的歌曲
  Future<void> _preparePreset(SongPreset preset) async {
    try {
      setState(() {
        _loading = true;
        _errorText = '';
      });

      _effectCache.clear();
      _lastBeatIndex = -1;

      // 1) 读取歌词
      final song = await LyricLoader.loadFromAsset(preset.lyricAsset);

      // 2) 设置音频源
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setSource(AssetSource(preset.audioAsset));

      // 3) 监听播放状态
      await _positionSub?.cancel();
      await _durationSub?.cancel();
      await _stateSub?.cancel();
      await _completeSub?.cancel();

      _positionSub = _player.onPositionChanged.listen((pos) {
        _onPositionUpdate(pos);
      });

      _durationSub = _player.onDurationChanged.listen((dur) {
        setState(() {
          _audioDuration = dur;
        });
      });

      _stateSub = _player.onPlayerStateChanged.listen((state) {
        setState(() {
          _playerState = state;
        });
      });

      _completeSub = _player.onPlayerComplete.listen((_) {
        setState(() {
          _playerState = PlayerState.completed;
          _position = _effectiveDuration;
        });
      });

      setState(() {
        _song = song;
        _loading = false;
        _lyricsOffsetMs = preset.defaultOffsetMs;
        _motionPreset = preset.defaultMotion;
        _playerState = PlayerState.stopped;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _errorText = '加载失败：$e';
      });
    }
  }

  void _onPositionUpdate(Duration pos) {
    final sec = pos.inMilliseconds / 1000.0;
    _triggerBeatIfNeeded(sec);

    setState(() {
      _position = pos;
    });
  }

  /// 当前有效总时长：优先用音频时长，否则用 JSON 里的 duration
  Duration get _effectiveDuration {
    if (_audioDuration.inMilliseconds > 0) return _audioDuration;
    final songDuration = _song?.duration ?? 0.0;
    return Duration(milliseconds: (songDuration * 1000).round());
  }

  double get _currentSeconds => _position.inMilliseconds / 1000.0;

  /// 歌词时间 = 音频时间 + 手动偏移
  /// 正值表示歌词更早显示
  double get _lyricSeconds => _currentSeconds + _lyricsOffsetMs / 1000.0;

  double get _totalSeconds => _effectiveDuration.inMilliseconds / 1000.0;

  double get _beatPulse => _beatController.value;

  /// 计算副歌识别阈值：
  /// - 至少 4.2 秒
  /// - 或者大于本首歌“普通间隔中位数”的 2.8 倍
  double get _chorusGapThresholdSeconds {
    final song = _song;
    if (song == null || song.lines.length < 2) return 4.2;

    final gaps = <double>[];
    for (int i = 0; i < song.lines.length - 1; i++) {
      final gap = song.lines[i + 1].start - song.lines[i].end;
      if (gap > 0) gaps.add(gap);
    }

    if (gaps.isEmpty) return 4.2;

    final median = _median(gaps);
    return math.max(4.2, median * 2.8);
  }

  Future<void> _togglePlay() async {
    if (!_audioPrepared) _audioPrepared = true;

    try {
      if (_playerState == PlayerState.playing) {
        await _player.pause();
      } else if (_playerState == PlayerState.paused ||
          _playerState == PlayerState.completed) {
        await _player.resume();
      } else {
        await _player.play(AssetSource(_presets[_presetIndex].audioAsset));
      }
    } catch (e) {
      setState(() {
        _errorText = '播放失败：$e';
      });
    }
  }

  Future<void> _seekToFraction(double fraction) async {
    final total = _effectiveDuration;
    if (total.inMilliseconds <= 0) return;

    final targetMs = (total.inMilliseconds * fraction).round();
    final target = Duration(milliseconds: targetMs);

    await _player.seek(target);
    setState(() {
      _position = target;
    });
  }

  Future<void> _changePreset(int index) async {
    if (index < 0 || index >= _presets.length) return;

    setState(() {
      _presetIndex = index;
      _loading = true;
      _errorText = '';
    });

    await _preparePreset(_presets[_presetIndex]);
  }

  void _triggerBeatIfNeeded(double currentSec) {
    final song = _song;
    if (song == null || song.beats.isEmpty) return;

    int latestBeatIndex = -1;
    for (int i = 0; i < song.beats.length; i++) {
      if (song.beats[i].time <= currentSec) {
        latestBeatIndex = i;
      } else {
        break;
      }
    }

    if (latestBeatIndex > _lastBeatIndex) {
      _lastBeatIndex = latestBeatIndex;
      _beatController.forward(from: 0.0);
      _vibrateIfEnabled();
    }
  }

  Future<void> _vibrateIfEnabled() async {
    if (!_vibrationEnabled) return;

    try {
      final hasVibrator = await Vibration.hasVibrator() ?? false;
      if (!hasVibrator) return;
      await Vibration.vibrate(duration: 18);
    } catch (_) {
      // 真机没有震动能力或者插件不可用时，直接忽略
    }
  }

  /// 找当前歌词行：取最后一个 start <= 当前时间的行
  int _findCurrentLineIndex(List<LyricLine> lines, double currentSec) {
    int left = 0;
    int right = lines.length - 1;
    int ans = -1;

    while (left <= right) {
      final mid = (left + right) >> 1;
      if (lines[mid].start <= currentSec) {
        ans = mid;
        left = mid + 1;
      } else {
        right = mid - 1;
      }
    }

    return ans;
  }

  @override
  Widget build(BuildContext context) {
    final song = _song;

    return Scaffold(
      appBar: AppBar(
        title: const Text('现场模式'),
        // 可选：自定义返回按钮样式
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () {
            // 手动返回上一页，和系统返回箭头效果完全一致
            Navigator.pop(context);
          },
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF050816),
              Color(0xFF0B1230),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            //animation: Listenable.merge([_beatController, _ellipsisController]),
            animation: _ellipsisController,
            builder: (context, _) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final compactLayout = constraints.maxWidth < 390 || constraints.maxHeight < 760;

                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      compactLayout ? 14 : 16,
                      compactLayout ? 10 : 12,
                      compactLayout ? 14 : 16,
                      compactLayout ? 10 : 14,
                    ),
                    child: _loading
                        ? _buildLoading()
                        : _errorText.isNotEmpty
                            ? _buildError()
                            : song == null
                                ? _buildLoading()
                                : Column(
                                    children: [
                                      _buildHeader(song, compactLayout),
                                      SizedBox(height: compactLayout ? 8 : 12),

                                      /// 中部歌词区尽量占大部分屏幕
                                      Expanded(
                                        child: Center(
                                          child: _buildLyricStage(
                                            song: song,
                                            compactLayout: compactLayout,
                                          ),
                                        ),
                                      ),

                                      SizedBox(height: compactLayout ? 8 : 12),
                                      _buildControls(compactLayout),
                                    ],
                                  ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(SongModel song, bool compactLayout) {
    final total = _effectiveDuration;
    final currentText = _formatDuration(_position);
    final totalText = _formatDuration(total);
    final stateText = switch (_playerState) {
      PlayerState.playing => '播放中',
      PlayerState.paused => '已暂停',
      PlayerState.completed => '已结束',
      _ => '待播放',
    };

    final titleSize = compactLayout ? 21.5 : 24.0;
    final artistSize = compactLayout ? 13.5 : 15.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    song.artist,
                    style: TextStyle(
                      fontSize: artistSize,
                      color: const Color(0xFFA7B6D6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _buildSmallPill(stateText, compactLayout),
            const SizedBox(width: 6),
            PopupMenuButton<int>(
              icon: const Icon(
                Icons.library_music_outlined,
                color: Color(0xFFB8C7E4),
                size: 20,
              ),
              tooltip: '切换歌曲',
              color: const Color(0xFF0B1220),
              onSelected: _changePreset,
              itemBuilder: (context) {
                return List.generate(_presets.length, (index) {
                  final preset = _presets[index];
                  return PopupMenuItem<int>(
                    value: index,
                    child: Text(
                      preset.displayName,
                      style: const TextStyle(color: Colors.white),
                    ),
                  );
                });
              },
            ),
          ],
        ),
        SizedBox(height: compactLayout ? 6 : 8),
        Text(
          '$currentText / $totalText',
          style: TextStyle(
            fontSize: compactLayout ? 12.5 : 14,
            color: const Color(0xFF71D9FF),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSmallPill(String text, bool compactLayout) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compactLayout ? 9 : 10,
        vertical: compactLayout ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF12233A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF2B3140)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: compactLayout ? 11.5 : 12,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildLyricStage({
    required SongModel song,
    required bool compactLayout,
  }) {
    final lyricIndex = _findCurrentLineIndex(song.lines, _lyricSeconds);

    if (lyricIndex < 0) {
      return const EmptyStageCard(
        title: '准备开始',
        subtitle: '播放后，歌词会按时间平滑出现。\n你也可以先调整歌词偏移。',
      );
    }

    return LyricDualSlotStage(
      song: song,
      lyricTime: _lyricSeconds,
      beatPulse: 0.0,
      effectCache: _effectCache,
      motionPreset: _motionPreset,
      compactLayout: compactLayout,
      ellipsisPhase: _ellipsisController.value,
      chorusGapThresholdSeconds: _chorusGapThresholdSeconds,
    );
  }

  Widget _buildControls(bool compactLayout) {
    final total = _effectiveDuration;
    final sliderValue = total.inMilliseconds > 0
        ? (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: EdgeInsets.fromLTRB(
        compactLayout ? 14 : 16,
        compactLayout ? 12 : 14,
        compactLayout ? 14 : 16,
        compactLayout ? 12 : 16,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(compactLayout ? 18 : 22),
        border: Border.all(color: const Color(0xFF2B3140), width: 1.0),
      ),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '播放控制',
              style: TextStyle(
                fontSize: 15,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(height: compactLayout ? 8 : 10),

          /// 播放按钮放在进度条前面，按钮做小一点
          Row(
            children: [
              _buildActionButton(
                label: _playerState == PlayerState.playing ? '暂停' : '播放',
                onTap: _togglePlay,
                primary: true,
                compactLayout: compactLayout,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF67D9FF),
                    inactiveTrackColor: const Color(0xFF283040),
                    thumbColor: const Color(0xFF9A6CFF),
                    overlayColor: const Color(0x3367D9FF),
                    trackHeight: compactLayout ? 3.8 : 4.5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: sliderValue,
                    onChanged: total.inMilliseconds > 0
                        ? (v) => _seekToFraction(v)
                        : null,
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: compactLayout ? 6 : 8),

          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() {
                    _offsetExpanded = !_offsetExpanded;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    children: [
                      const Text(
                        '歌词校准',
                        style: TextStyle(
                          color: Color(0xFFA7B6D6),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _lyricsOffsetMs >= 0
                            ? '+${_lyricsOffsetMs.toStringAsFixed(0)}ms'
                            : '${_lyricsOffsetMs.toStringAsFixed(0)}ms',
                        style: const TextStyle(
                          color: Color(0xFF71D9FF),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _offsetExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 18,
                        color: const Color(0xFFA7B6D6),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '震动',
                    style: TextStyle(
                      color: Color(0xFFA7B6D6),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch.adaptive(
                    value: _vibrationEnabled,
                    onChanged: (v) {
                      setState(() {
                        _vibrationEnabled = v;
                      });
                    },
                  ),
                ],
              ),
            ],
          ),

          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                const SizedBox(height: 4),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF67D9FF),
                    inactiveTrackColor: const Color(0xFF283040),
                    thumbColor: const Color(0xFF9A6CFF),
                    overlayColor: const Color(0x3367D9FF),
                    trackHeight: 3.8,
                  ),
                  child: Slider(
                    min: -800,
                    max: 800,
                    divisions: 32,
                    value: _lyricsOffsetMs.clamp(-800.0, 800.0).toDouble(),
                    label: _lyricsOffsetMs >= 0
                        ? '+${_lyricsOffsetMs.toStringAsFixed(0)}ms'
                        : '${_lyricsOffsetMs.toStringAsFixed(0)}ms',
                    onChanged: (v) {
                      setState(() {
                        _lyricsOffsetMs = v;
                      });
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _smallOffsetButton('-200', () {
                      setState(() => _lyricsOffsetMs -= 200);
                    }),
                    _smallOffsetButton('-50', () {
                      setState(() => _lyricsOffsetMs -= 50);
                    }),
                    _smallOffsetButton('+50', () {
                      setState(() => _lyricsOffsetMs += 50);
                    }),
                    _smallOffsetButton('+200', () {
                      setState(() => _lyricsOffsetMs += 200);
                    }),
                  ],
                ),
                const SizedBox(height: 4),
              ],
            ),
            crossFadeState: _offsetExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),
        ],
      ),
    );
  }

  Widget _smallOffsetButton(String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF172133),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2B3140)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFFF3F7FF),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required VoidCallback onTap,
    required bool primary,
    required bool compactLayout,
  }) {
    final bg = primary
        ? const LinearGradient(
            colors: [
              Color(0xFF67D9FF),
              Color(0xFF9A6CFF),
            ],
          )
        : null;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: compactLayout ? 72 : 78,
        height: compactLayout ? 40 : 44,
        decoration: BoxDecoration(
          gradient: bg,
          color: primary ? null : const Color(0xFF172133),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: primary ? Colors.transparent : const Color(0xFF2B3140),
            width: 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: compactLayout ? 13.5 : 14.5,
            fontWeight: FontWeight.w700,
            color: primary ? Colors.white : const Color(0xFFF3F7FF),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 14),
          Text(
            '正在读取歌词和音频…',
            style: TextStyle(color: Color(0xFFA7B6D6)),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1320),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFF7B7B)),
        ),
        child: Text(
          _errorText,
          style: const TextStyle(
            color: Color(0xFFFFB4B4),
            height: 1.45,
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  double _median(List<double> values) {
    if (values.isEmpty) return 0.0;
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length >> 1;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }
}