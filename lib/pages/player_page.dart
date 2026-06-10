import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../models/lyric_models.dart';
import '../services/lyric_loader.dart';
import '../widgets/lyric_widgets.dart';

/// 这里改成你自己的文件名
const String kLyricAssetPath = 'assets/lyrics/sasanohani_ukatakani_test.json';

/// 这里改成你自己的音频文件名
const String kAudioAssetPath = 'audio/M・A・O,中澤ミナ,森下来奈 - ささのはに、うたかたに。 (M@STER VERSION).flac';

/// 当两句歌词之间的间隔超过这个值时，认为进入“副歌 / 大间隔段落”
/// 这个值你后续可以根据别的歌再调：
/// - 太小：会经常触发
/// - 太大：副歌提示不明显
const double kChorusGapThresholdSeconds = 2.6;

/// 这个页面同时负责：
/// 1. 读取本地歌词 JSON
/// 2. 播放音频
/// 3. 根据音频时间推进歌词
/// 4. 检测节拍并触发闪光
/// 5. 检测长间隔并显示副歌省略号进度
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage>
    with TickerProviderStateMixin {
  // -----------------------------
  // 数据
  // -----------------------------
  SongModel? _song;

  // 当前播放时间 / 音频总时长
  Duration _position = Duration.zero;
  Duration _audioDuration = Duration.zero;

  // 播放器状态
  final AudioPlayer _player = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;

  // 加载和错误
  bool _loading = true;
  String _errorText = '';

  // -----------------------------
  // 动画控制器
  // -----------------------------
  // 副歌省略号的循环动画
  late final AnimationController _ellipsisController;

  // 节拍闪光控制器
  late final AnimationController _beatController;

  // -----------------------------
  // 事件订阅
  // -----------------------------
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<void>? _completeSub;

  // -----------------------------
  // 逐字动画缓存
  // -----------------------------
  // 用于保存“上一帧”的字效果，让下一帧可以平滑过渡
  final Map<String, LyricCharEffect> _effectCache = {};

  // -----------------------------
  // 播放控制
  // -----------------------------
  bool _audioPrepared = false;

  @override
  void initState() {
    super.initState();

    _ellipsisController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();

    _beatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    _prepare();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();

    _player.dispose();
    _ellipsisController.dispose();
    _beatController.dispose();

    super.dispose();
  }

  /// 初始化：先加载歌词，再准备音频。
  Future<void> _prepare() async {
    try {
      setState(() {
        _loading = true;
        _errorText = '';
      });

      // 1. 读取歌词
      final song = await LyricLoader.loadFromAsset(kLyricAssetPath);

      // 2. 准备音频播放器
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setSource(AssetSource(kAudioAssetPath));
      _audioPrepared = true;

      // 3. 监听音频进度
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
          _position = _durationForSongOrAudio;
        });
      });

      setState(() {
        _song = song;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _errorText = '加载失败：$e';
      });
    }
  }

  /// 音频当前播放时间更新时调用。
  void _onPositionUpdate(Duration pos) {
    final sec = pos.inMilliseconds / 1000.0;

    // 根据时间检测节拍，如果跨过新的节拍点，触发一次闪光
    _triggerBeatIfNeeded(sec);

    setState(() {
      _position = pos;
    });
  }

  /// 当前歌词/音频的有效总时长：
  /// 优先用音频时长；如果还没拿到音频时长，就用 JSON 里的 duration。
  Duration get _durationForSongOrAudio {
    if (_audioDuration.inMilliseconds > 0) return _audioDuration;
    final songDuration = _song?.duration ?? 0.0;
    return Duration(milliseconds: (songDuration * 1000).round());
  }

  /// 当前时间（秒）
  double get _currentSeconds => _position.inMilliseconds / 1000.0;

  /// 当前总时间（秒）
  double get _totalSeconds {
    final d = _durationForSongOrAudio;
    return d.inMilliseconds / 1000.0;
  }

  /// 当前活跃歌词行
  int get _activeLineIndex {
    final song = _song;
    if (song == null || song.lines.isEmpty) return -1;
    return _findCurrentLineIndex(song.lines, _currentSeconds);
  }

  /// 当前是否处于“长间隔 / 副歌提示区”
  ChorusGapInfo? get _activeGapInfo {
    final song = _song;
    if (song == null || song.lines.length < 2) return null;
    return _findChorusGap(song.lines, _currentSeconds);
  }

  /// 播放 / 暂停按钮
  Future<void> _togglePlay() async {
    if (!_audioPrepared) return;

    try {
      if (_playerState == PlayerState.playing) {
        await _player.pause();
      } else if (_playerState == PlayerState.paused ||
          _playerState == PlayerState.completed) {
        await _player.resume();
      } else {
        // stopped 状态，从头播放
        await _player.play(AssetSource(kAudioAssetPath));
      }
    } catch (e) {
      setState(() {
        _errorText = '播放失败：$e';
      });
    }
  }

  /// 重播
  Future<void> _restart() async {
    try {
      await _player.stop();
      await _player.seek(Duration.zero);
      await _player.play(AssetSource(kAudioAssetPath));
    } catch (e) {
      setState(() {
        _errorText = '重播失败：$e';
      });
    }
  }

  /// 拖动进度条
  Future<void> _seekToFraction(double fraction) async {
    final total = _durationForSongOrAudio;
    if (total.inMilliseconds <= 0) return;

    final targetMs = (total.inMilliseconds * fraction).round();
    final target = Duration(milliseconds: targetMs);

    await _player.seek(target);
    setState(() {
      _position = target;
    });
  }

  /// 节拍触发：如果当前位置跨过了新的 beat 点，就触发一次闪光。
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

  int _lastBeatIndex = -1;

  /// 找当前歌词行：取最后一个 start <= 当前时间的行。
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

  /// 检测“长间隔段落”，也就是你说的副歌提示区。
  ///
  /// 逻辑：
  /// - 如果两句歌词之间的 gap 足够长
  /// - 且当前播放时间落在这个 gap 内
  /// - 就显示 App Music 风格的省略号进度卡片
  ChorusGapInfo? _findChorusGap(List<LyricLine> lines, double currentSec) {
    for (int i = 0; i < lines.length - 1; i++) {
      final prev = lines[i];
      final next = lines[i + 1];

      final gapStart = prev.end;
      final gapEnd = next.start;
      final gapDuration = gapEnd - gapStart;

      if (gapDuration >= kChorusGapThresholdSeconds &&
          currentSec >= gapStart &&
          currentSec <= gapEnd) {
        final progress = ((currentSec - gapStart) / gapDuration).clamp(0.0, 1.0);
        return ChorusGapInfo(
          fromIndex: i,
          toIndex: i + 1,
          gapStart: gapStart,
          gapEnd: gapEnd,
          gapDuration: gapDuration,
          progress: progress,
        );
      }
    }

    return null;
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
        child: Stack(
          children: [
            // 背景柔光
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _beatController,
                  builder: (context, _) {
                    final pulse = _beatController.value;
                    return Opacity(
                      opacity: pulse * 0.16,
                      child: Container(
                        color: const Color(0xFF67D9FF),
                      ),
                    );
                  },
                ),
              ),
            ),

            SafeArea(
              child: AnimatedBuilder(
                // 这个 AnimatedBuilder 让副歌省略号和节拍闪光都能顺滑刷新
                animation: Listenable.merge([_ellipsisController, _beatController]),
                builder: (context, _) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: _loading
                        ? _buildLoading()
                        : _errorText.isNotEmpty
                            ? _buildError()
                            : song == null
                                ? _buildLoading()
                                : Column(
                                    children: [
                                      _buildHeader(song),
                                      const SizedBox(height: 18),

                                      Expanded(
                                        child: Center(
                                          child: _buildLyricStage(song),
                                        ),
                                      ),

                                      const SizedBox(height: 14),
                                      _buildBeatMeter(),
                                      const SizedBox(height: 14),
                                      _buildControls(),
                                    ],
                                  ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部信息栏
  Widget _buildHeader(SongModel song) {
    final total = _durationForSongOrAudio;
    final currentText = _formatDuration(_position);
    final totalText = _formatDuration(total);
    final stateText = switch (_playerState) {
      PlayerState.playing => '播放中',
      PlayerState.paused => '已暂停',
      PlayerState.completed => '已结束',
      _ => '待播放',
    };

    return Row(
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildSmallPill(stateText),
            const SizedBox(height: 8),
            Text(
              '$currentText / $totalText',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF71D9FF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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

  /// 主歌词区域
  Widget _buildLyricStage(SongModel song) {
    final currentLineIndex = _activeLineIndex;
    final gapInfo = _activeGapInfo;
    final beatPulse = _beatController.value;

    // 还没到第一句
    if (currentLineIndex < 0 && gapInfo == null) {
      return const EmptyStageCard(
        title: '准备开始',
        subtitle: '正在等待歌词进入。\n播放后，逐字歌词会按时间平滑出现。',
      );
    }

    // 长间隔区：显示“副歌展开中”的省略号进度
    if (gapInfo != null) {
      final prev = song.lines[gapInfo.fromIndex];
      final next = song.lines[gapInfo.toIndex];

      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) {
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(anim);

          return FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: slide,
              child: child,
            ),
          );
        },
        child: ChorusProgressCard(
          key: ValueKey('gap_${gapInfo.fromIndex}_${gapInfo.toIndex}_${gapInfo.gapStart.toStringAsFixed(2)}'),
          progress: gapInfo.progress,
          phase: _ellipsisController.value,
          beatPulse: beatPulse,
          previousLine: prev,
          nextLine: next,
          gapDuration: gapInfo.gapDuration,
        ),
      );
    }

    // 正常歌词行
    final line = song.lines[currentLineIndex.clamp(0, song.lines.length - 1)];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(anim);

        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: slide,
            child: child,
          ),
        );
      },
      child: LyricLineCard(
        key: ValueKey('line_$currentLineIndex'),
        line: line,
        lineIndex: currentLineIndex,
        totalLines: song.lines.length,
        currentTime: _currentSeconds,
        beatPulse: beatPulse,
        effectCache: _effectCache,
      ),
    );
  }

  /// 节拍条：简单但有存在感
  Widget _buildBeatMeter() {
    final pulse = _beatController.value;
    final total = _durationForSongOrAudio;
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
            _activeGapInfo == null
                ? '节拍反馈：播放进度 ${_formatPercent(progress)}'
                : '副歌提示：${_formatPercent(_activeGapInfo!.progress)} · 省略号进度',
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

  /// 播放控制区
  Widget _buildControls() {
    final total = _durationForSongOrAudio;
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
          const SizedBox(height: 12),

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

          const SizedBox(height: 8),

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
        ],
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

/// 长间隔区的信息
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