import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

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

  // -----------------------------
  // 播放状态
  // -----------------------------
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
      _positionSub?.cancel();
      _durationSub?.cancel();
      _stateSub?.cancel();
      _completeSub?.cancel();

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

  Future<void> _restart() async {
    try {
      _lastBeatIndex = -1;
      _effectCache.clear();

      await _player.stop();
      await _player.seek(Duration.zero);
      await _player.play(AssetSource(_presets[_presetIndex].audioAsset));
    } catch (e) {
      setState(() {
        _errorText = '重播失败：$e';
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
    }
  }

  /// 找当前歌词行
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
            animation: Listenable.merge([_beatController, _ellipsisController]),
            builder: (context, _) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final compactLayout = constraints.maxWidth < 390;

                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      compactLayout ? 12 : 16,
                    ),
                    child: _loading
                        ? _buildLoading()
                        : _errorText.isNotEmpty
                            ? _buildError()
                            : song == null
                                ? _buildLoading()
                                : Column(
                                    children: [
                                      _buildHeader(song),
                                      const SizedBox(height: 14),

                                      /// 中部歌词区尽量占大部分屏幕
                                      Expanded(
                                        child: Center(
                                          child: _buildLyricStage(
                                            song: song,
                                            compactLayout: compactLayout,
                                          ),
                                        ),
                                      ),

                                      const SizedBox(height: 12),
                                      _buildBeatMeter(),
                                      const SizedBox(height: 12),
                                      _buildControls(),
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

  Widget _buildHeader(SongModel song) {
    final total = _effectiveDuration;
    final currentText = _formatDuration(_position);
    final totalText = _formatDuration(total);
    final stateText = switch (_playerState) {
      PlayerState.playing => '播放中',
      PlayerState.paused => '已暂停',
      PlayerState.completed => '已结束',
      _ => '待播放',
    };

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
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    song.artist,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFFA7B6D6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _buildSmallPill(stateText),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '$currentText / $totalText',
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF71D9FF),
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: 10),

        /// 小而不打扰的歌曲选择器
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1220),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2B3140)),
          ),
          child: Row(
            children: [
              const Text(
                '歌曲',
                style: TextStyle(
                  color: Color(0xFF96A6C8),
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _presetIndex,
                    isDense: true,
                    dropdownColor: const Color(0xFF0B1220),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                    items: List.generate(_presets.length, (index) {
                      final preset = _presets[index];
                      return DropdownMenuItem(
                        value: index,
                        child: Text(
                          preset.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }),
                    onChanged: (index) {
                      if (index != null) {
                        _changePreset(index);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSmallPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF12233A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF2B3140)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
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
    beatPulse: _beatPulse,
    effectCache: _effectCache,
    motionPreset: _motionPreset,
    compactLayout: compactLayout,
    ellipsisPhase: _ellipsisController.value,
  );
}

  Widget _buildBeatMeter() {
    final pulse = _beatPulse;
    final total = _effectiveDuration;
    final progress = total.inMilliseconds > 0
        ? (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final fillColor = Color.lerp(
      const Color(0xFF67D9FF),
      const Color(0xFF9A6CFF),
      pulse * 0.55,
    )!;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Color.lerp(
            const Color(0xFF2B3140),
            const Color(0xFF67D9FF),
            pulse * 0.5,
          )!,
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: progress,
              backgroundColor: const Color(0xFF1B2435),
              valueColor: AlwaysStoppedAnimation<Color>(fillColor),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '节拍反馈：播放进度 ${_formatPercent(progress)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFA8B8D9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final total = _effectiveDuration;
    final sliderValue = total.inMilliseconds > 0
        ? (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(22),
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
          const SizedBox(height: 10),

          /// 小型歌词校准面板：默认收起
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() {
                _offsetExpanded = !_offsetExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
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
                  const Spacer(),
                  Icon(
                    _offsetExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: const Color(0xFFA7B6D6),
                  ),
                ],
              ),
            ),
          ),

          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF67D9FF),
                    inactiveTrackColor: const Color(0xFF283040),
                    thumbColor: const Color(0xFF9A6CFF),
                    overlayColor: const Color(0x3367D9FF),
                    trackHeight: 4.5,
                  ),
                  child: Slider(
                    min: -800,
                    max: 800,
                    divisions: 32,
                    value: _lyricsOffsetMs.clamp(-800, 800),
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
                const SizedBox(height: 10),
              ],
            ),
            crossFadeState: _offsetExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),

          const SizedBox(height: 8),

          /// 动画风格切换：柔和 / 标准 / 强烈
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: LyricMotionPreset.values.map((preset) {
                final selected = preset == _motionPreset;
                return InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    setState(() {
                      _motionPreset = preset;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF67D9FF).withOpacity(0.20)
                          : const Color(0xFF172133),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF67D9FF)
                            : const Color(0xFF2B3140),
                      ),
                    ),
                    child: Text(
                      preset.label,
                      style: TextStyle(
                        color: selected ? Colors.white : const Color(0xFFA7B6D6),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  label: _playerState == PlayerState.playing ? '暂停' : '播放',
                  onTap: _togglePlay,
                  primary: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  label: '重播',
                  onTap: _restart,
                  primary: false,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF67D9FF),
              inactiveTrackColor: const Color(0xFF283040),
              thumbColor: const Color(0xFF9A6CFF),
              overlayColor: const Color(0x3367D9FF),
              trackHeight: 4.5,
            ),
            child: Slider(
              value: sliderValue,
              onChanged: total.inMilliseconds > 0
                  ? (v) => _seekToFraction(v)
                  : null,
            ),
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
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          gradient: bg,
          color: primary ? null : const Color(0xFF172133),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: primary ? Colors.transparent : const Color(0xFF2B3140),
            width: 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
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

  String _formatPercent(double v) {
    return '${(v * 100).round()}%';
  }
}