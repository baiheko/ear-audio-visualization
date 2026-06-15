import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/song_presets.dart';
import '../models/lyric_models.dart';

/// -------------------------
/// 单个字的视觉状态
/// -------------------------
class LyricCharEffect {
  final double opacity;
  final double scale;
  final double translateX;
  final double translateY;
  final double fontSize;
  final Color color;
  final double glow;

  const LyricCharEffect({
    required this.opacity,
    required this.scale,
    required this.translateX,
    required this.translateY,
    required this.fontSize,
    required this.color,
    required this.glow,
  });

  static LyricCharEffect lerp(LyricCharEffect a, LyricCharEffect b, double t) {
    return LyricCharEffect(
      opacity: lerpDouble(a.opacity, b.opacity, t),
      scale: lerpDouble(a.scale, b.scale, t),
      translateX: lerpDouble(a.translateX, b.translateX, t),
      translateY: lerpDouble(a.translateY, b.translateY, t),
      fontSize: lerpDouble(a.fontSize, b.fontSize, t),
      color: Color.lerp(a.color, b.color, t) ?? b.color,
      glow: lerpDouble(a.glow, b.glow, t),
    );
  }
}

/// 用于 TweenAnimationBuilder 的 Tween
class LyricCharEffectTween extends Tween<LyricCharEffect> {
  LyricCharEffectTween({
    required super.begin,
    required super.end,
  });

  @override
  LyricCharEffect lerp(double t) {
    return LyricCharEffect.lerp(begin!, end!, t);
  }
}

/// 单个字组件
class LyricCharWidget extends StatelessWidget {
  final String char;
  final LyricCharEffect beginEffect;
  final LyricCharEffect endEffect;
  final Duration duration;

  const LyricCharWidget({
    super.key,
    required this.char,
    required this.beginEffect,
    required this.endEffect,
    this.duration = const Duration(milliseconds: 120),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<LyricCharEffect>(
      tween: LyricCharEffectTween(
        begin: beginEffect,
        end: endEffect,
      ),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, effect, child) {
        final shadows = effect.glow <= 0
            ? const <Shadow>[]
            : [
                Shadow(
                  color: effect.color.withOpacity(0.45 * effect.glow),
                  blurRadius: 16 * effect.glow,
                ),
              ];

        return Opacity(
          opacity: effect.opacity,
          child: Transform.translate(
            offset: Offset(effect.translateX, effect.translateY),
            child: Transform.scale(
              scale: effect.scale,
              child: Text(
                char,
                style: TextStyle(
                  fontSize: effect.fontSize,
                  height: 1.08,
                  fontWeight: FontWeight.w700,
                  color: effect.color,
                  shadows: shadows,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 逐字歌词卡片
///
/// 这版的关键变化：
/// 1. 字一旦出现，就不会消失
/// 2. 当前行会一直累计显示到整行完成
/// 3. 已经播完的行会作为“上一句”保留
/// 4. 不再使用 pitch / volume 造成乱跳
class LyricLineCard extends StatelessWidget {
  final LyricLine line;
  final int lineIndex;
  final int totalLines;
  final double currentTime;
  final double beatPulse;
  final Map<String, LyricCharEffect> effectCache;

  /// 当前槽位标签：上一句 / 当前歌词
  final String slotLabel;

  /// 当前行是否已经“完成并固定”
  final bool settled;

  /// 预进入时间
  final double leadInSeconds;

  /// 动画风格预设
  final LyricMotionPreset motionPreset;

  /// 是否紧凑模式（手机小屏）
  final bool compactLayout;

  const LyricLineCard({
    super.key,
    required this.line,
    required this.lineIndex,
    required this.totalLines,
    required this.currentTime,
    required this.beatPulse,
    required this.effectCache,
    required this.slotLabel,
    required this.settled,
    required this.leadInSeconds,
    required this.motionPreset,
    required this.compactLayout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final baseBorder = const Color(0xFF2B3140);
    final accentBorder = const Color(0xFF67D9FF);
    final borderColor = Color.lerp(
      baseBorder,
      accentBorder,
      beatPulse * 0.28,
    ) ?? baseBorder;

    final cardBg = Color.lerp(
      const Color(0xFF0B1220),
      const Color(0xFF10243D),
      beatPulse * 0.10,
    )!;

    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: const Color(0xFF8EA2C7),
      fontWeight: FontWeight.w600,
      fontSize: compactLayout ? 11.5 : 12.5,
    );

    final indexStyle = theme.textTheme.labelMedium?.copyWith(
      color: const Color(0xFF5ED9FF),
      fontWeight: FontWeight.w600,
      fontSize: compactLayout ? 11.5 : 12.5,
    );

    final baseFontSize = _fitBaseFontSize(line.chars.length, compactLayout);

    final charWidgets = <Widget>[];
    for (int i = 0; i < line.chars.length; i++) {
      final ch = line.chars[i];
      final key = '${lineIndex}_$i';

      final effect = _buildCharEffect(
        char: ch,
        currentTime: currentTime,
        baseFontSize: baseFontSize,
        beatPulse: beatPulse,
        settled: settled,
      );

      final begin = effectCache[key] ?? effect;
      effectCache[key] = effect;

      charWidgets.add(
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compactLayout ? 0.8 : 1.2),
          child: LyricCharWidget(
            char: ch.char,
            beginEffect: begin,
            endEffect: effect,
          ),
        ),
      );
    }

    final lift = (beatPulse * (settled ? 0.7 : 1.1)) * (compactLayout ? 1.1 : 1.0);
    final scale = 1.0 + beatPulse * (settled ? 0.004 : 0.008);

    return Transform.translate(
      offset: Offset(0, -lift),
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            compactLayout ? 14 : 18,
            compactLayout ? 14 : 18,
            compactLayout ? 14 : 18,
            compactLayout ? 12 : 16,
          ),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(compactLayout ? 20 : 24),
            border: Border.all(color: borderColor, width: 1.15),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(slotLabel, style: labelStyle),
                  Text('${lineIndex + 1} / $totalLines', style: indexStyle),
                ],
              ),
              SizedBox(height: compactLayout ? 10 : 14),
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  runAlignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: charWidgets,
                ),
              ),
              if (line.translation.trim().isNotEmpty) ...[
                SizedBox(height: compactLayout ? 10 : 14),
                Text(
                  line.translation,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF96A6C8),
                    height: 1.42,
                    fontSize: compactLayout ? 13 : 15,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 根据字数估算基础字号，避免长句撑爆屏幕
  double _fitBaseFontSize(int charCount, bool compact) {
    if (compact) {
      if (charCount <= 8) return 34;
      if (charCount <= 12) return 31;
      if (charCount <= 18) return 28;
      if (charCount <= 24) return 25;
      return 22;
    } else {
      if (charCount <= 8) return 42;
      if (charCount <= 12) return 38;
      if (charCount <= 18) return 34;
      if (charCount <= 24) return 30;
      return 26;
    }
  }

  /// 单字视觉状态
  ///
  /// 这版已经去掉了 pitch / volume 的视觉影响，
  /// 只保留：时间、动画风格、轻微强调、保留已出现的字。
  LyricCharEffect _buildCharEffect({
    required LyricChar char,
    required double currentTime,
    required double baseFontSize,
    required double beatPulse,
    required bool settled,
  }) {
    final intensity = motionPreset.intensity;

    // 完成态：整行已经播完并固定显示
    if (settled) {
      return LyricCharEffect(
        opacity: 0.88,
        scale: 1.0,
        translateX: 0,
        translateY: 0,
        fontSize: baseFontSize * 0.98,
        color: const Color(0xFFF3F7FF).withOpacity(0.90),
        glow: 0.0,
      );
    }

    // 还没到预进入窗口：隐藏
    final preEnterStart = char.start - leadInSeconds;
    if (currentTime < preEnterStart) {
      return LyricCharEffect(
        opacity: 0.0,
        scale: 0.98,
        translateX: 0,
        translateY: 4,
        fontSize: baseFontSize,
        color: const Color(0xFFF3F7FF),
        glow: 0.0,
      );
    }

    final duration = math.max(char.end - char.start, 0.12);
    final appearSpan = math.max(
      0.06,
      duration * (0.30 + (1.0 - intensity) * 0.12),
    );

    // 预进入：先轻轻浮现，不要“蹦”
    if (currentTime < char.start) {
      final preProgress = _easeOutCubic(
        _clamp((currentTime - preEnterStart) / leadInSeconds, 0.0, 1.0),
      );

      return LyricCharEffect(
        opacity: 0.08 + 0.26 * preProgress,
        scale: 0.98 + 0.015 * preProgress,
        translateX: preProgress * (2.2 * intensity),
        translateY: 0,
        fontSize: baseFontSize * (0.99 + 0.01 * preProgress),
        color: const Color(0xFFF3F7FF).withOpacity(0.78),
        glow: 0.0,
      );
    }

    // 正在唱：轻微强调
    if (currentTime <= char.end) {
      final appearProgress = _easeOutCubic(
        _clamp((currentTime - char.start) / appearSpan, 0.0, 1.0),
      );

      final activeProgress = _clamp((currentTime - char.start) / duration, 0.0, 1.0);
      final driftMaxX = _clamp(3.0 + duration * 8.0 * intensity, 3.0, 12.0);
      final driftX = _easeOutCubic(activeProgress) * driftMaxX;

      return LyricCharEffect(
        opacity: 0.42 + 0.58 * appearProgress,
        scale: 1.0 + 0.015 * intensity,
        translateX: driftX,
        translateY: 0,
        fontSize: baseFontSize * (1.0 + 0.012 * intensity),
        color: Color.lerp(
              const Color(0xFFF3F7FF),
              const Color(0xFF67D9FF),
              0.18 + beatPulse * 0.10,
            ) ??
            const Color(0xFFF3F7FF),
        glow: 0.16 + beatPulse * 0.32 * intensity,
      );
    }

    // 已唱完：一直保留，不消失
    return LyricCharEffect(
      opacity: 1.0,
      scale: 1.0,
      translateX: 0.0,
      translateY: 0.0,
      fontSize: baseFontSize,
      color: const Color(0xFFF3F7FF).withOpacity(0.90),
      glow: 0.0,
    );
  }
}

/// 双槽歌词舞台
///
/// 这版逻辑是：
/// - 上一行 + 当前行
/// - 行位置按奇偶轮换
///   - 第 1 行：左上
///   - 第 2 行：右下
///   - 第 3 行：左上
///   - 第 4 行：右下
/// - 副歌区出现时，两个歌词框隐藏，只显示中间浮层
class LyricDualSlotStage extends StatelessWidget {
  final SongModel song;
  final double lyricTime;
  final double beatPulse;
  final Map<String, LyricCharEffect> effectCache;
  final LyricMotionPreset motionPreset;
  final bool compactLayout;
  final double ellipsisPhase;
  final double chorusGapThresholdSeconds;

  const LyricDualSlotStage({
    super.key,
    required this.song,
    required this.lyricTime,
    required this.beatPulse,
    required this.effectCache,
    required this.motionPreset,
    required this.compactLayout,
    required this.ellipsisPhase,
    required this.chorusGapThresholdSeconds,
  });

  @override
  Widget build(BuildContext context) {
    if (song.lines.isEmpty) {
      return const EmptyStageCard(
        title: '暂无歌词',
        subtitle: '当前歌曲没有可显示的歌词。',
      );
    }

    final currentIndex = _findCurrentLineIndex(song.lines, lyricTime);

    if (currentIndex < 0) {
      return const EmptyStageCard(
        title: '准备开始',
        subtitle: '播放后，歌词会按时间平滑出现。',
      );
    }

    final currentLine = song.lines[currentIndex];
    final previousLine = currentIndex > 0 ? song.lines[currentIndex - 1] : null;

    final gapInfo = _findChorusGap(song.lines, lyricTime, chorusGapThresholdSeconds);

    // 副歌提示：中间浮层，两个歌词框隐藏
    if (gapInfo != null) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
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
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1.0).animate(anim),
                child: child,
              ),
            ),
          );
        },
        child: Center(
          key: ValueKey('chorus_${gapInfo.fromIndex}_${gapInfo.toIndex}_${gapInfo.gapStart.toStringAsFixed(2)}'),
          child: FractionallySizedBox(
            widthFactor: compactLayout ? 0.98 : 0.88,
            child: ChorusProgressOverlay(
              progress: gapInfo.progress,
              phase: ellipsisPhase,
              beatPulse: beatPulse,
              gapDuration: gapInfo.gapDuration,
              compactLayout: compactLayout,
            ),
          ),
        ),
      );
    }

    final currentIsTopLeft = currentIndex.isEven;

    final currentCard = LyricLineCard(
      key: ValueKey('current_$currentIndex'),
      line: currentLine,
      lineIndex: currentIndex,
      totalLines: song.lines.length,
      currentTime: lyricTime,
      beatPulse: beatPulse,
      effectCache: effectCache,
      slotLabel: '当前歌词',
      settled: false,
      leadInSeconds: motionPreset.leadInSeconds,
      motionPreset: motionPreset,
      compactLayout: compactLayout,
    );

    final previousCard = previousLine == null
        ? const SizedBox.shrink()
        : LyricLineCard(
            key: ValueKey('previous_${currentIndex - 1}'),
            line: previousLine,
            lineIndex: currentIndex - 1,
            totalLines: song.lines.length,
            currentTime: lyricTime,
            beatPulse: beatPulse,
            effectCache: effectCache,
            slotLabel: '上一句',
            settled: true,
            leadInSeconds: 0.0,
            motionPreset: motionPreset,
            compactLayout: compactLayout,
          );

    if (compactLayout) {
      // 小屏：竖向堆叠，减少上下挤压
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (currentIsTopLeft) ...[
            currentCard,
            SizedBox(height: previousLine != null ? 10 : 0),
            previousLine != null ? previousCard : const SizedBox.shrink(),
          ] else ...[
            previousLine != null ? previousCard : const SizedBox.shrink(),
            SizedBox(height: previousLine != null ? 10 : 0),
            currentCard,
          ],
        ],
      );
    }

    // 普通模式：两个槽位分布在左上 / 右下
    return SizedBox(
      height: 380,
      child: Stack(
        children: [
          Align(
            alignment: const Alignment(-0.98, -0.82),
            child: FractionallySizedBox(
              widthFactor: 0.94,
              child: currentIsTopLeft ? currentCard : previousCard,
            ),
          ),
          Align(
            alignment: const Alignment(0.98, 0.82),
            child: FractionallySizedBox(
              widthFactor: 0.90,
              child: currentIsTopLeft ? previousCard : currentCard,
            ),
          ),
        ],
      ),
    );
  }

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

  /// 更严格的副歌识别：
  /// - gap 必须大于动态阈值
  /// - 动态阈值 = max(4.2s, 全局中位 gap × 2.8)
  ChorusGapInfo? _findChorusGap(
    List<LyricLine> lines,
    double currentSec,
    double thresholdSeconds,
  ) {
    for (int i = 0; i < lines.length - 1; i++) {
      final prev = lines[i];
      final next = lines[i + 1];

      final gapStart = prev.end;
      final gapEnd = next.start;
      final gapDuration = gapEnd - gapStart;

      if (gapDuration >= thresholdSeconds &&
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
}

/// 中间副歌浮层
///
/// 这次不再把副歌塞进某个歌词框里，
/// 而是单独放在中间，两个歌词框一起隐藏。
class ChorusProgressOverlay extends StatelessWidget {
  final double progress;
  final double phase;
  final double beatPulse;
  final double gapDuration;
  final bool compactLayout;

  const ChorusProgressOverlay({
    super.key,
    required this.progress,
    required this.phase,
    required this.beatPulse,
    required this.gapDuration,
    required this.compactLayout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 进入/退出缓冲：
    // 头尾更柔和，中间更明显
    final visual = _bufferedVisibility(progress);
    final opacity = visual;
    final scale = 0.96 + 0.04 * visual;

    final borderColor = Color.lerp(
      const Color(0xFF2B3140),
      const Color(0xFF67D9FF),
      0.30 + beatPulse * 0.45,
    )!;

    final bgColor = Color.lerp(
      const Color(0xFF0B1220),
      const Color(0xFF10243D),
      0.20 + beatPulse * 0.18,
    )!;

    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w800,
      fontSize: compactLayout ? 17 : 18,
    );

    final subStyle = theme.textTheme.bodyMedium?.copyWith(
      color: const Color(0xFF96A6C8),
      height: 1.35,
      fontSize: compactLayout ? 12.5 : 13.5,
    );

    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            compactLayout ? 16 : 18,
            compactLayout ? 16 : 18,
            compactLayout ? 16 : 18,
            compactLayout ? 14 : 16,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(compactLayout ? 22 : 24),
            border: Border.all(color: borderColor, width: 1.15),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('副歌展开中', style: titleStyle),
              SizedBox(height: compactLayout ? 10 : 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  final wave = (math.sin((phase * math.pi * 2) + i * 0.75) + 1) / 2;
                  final dotWeight = _clamp(progress * 0.55 + wave * 0.45, 0.0, 1.0);

                  final dotColor = Color.lerp(
                    const Color(0xFF96A6C8),
                    const Color(0xFF67D9FF),
                    dotWeight,
                  )!;

                  return Container(
                    margin: EdgeInsets.symmetric(horizontal: compactLayout ? 7 : 8),
                    width: (14 + dotWeight * 7),
                    height: (14 + dotWeight * 7),
                    decoration: BoxDecoration(
                      color: dotColor.withOpacity(0.30 + dotWeight * 0.68),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),

              SizedBox(height: compactLayout ? 12 : 14),

              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: compactLayout ? 6 : 7,
                  value: _clamp(progress, 0.0, 1.0),
                  backgroundColor: const Color(0xFF1B2435),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF67D9FF),
                  ),
                ),
              ),

              SizedBox(height: compactLayout ? 8 : 10),

              Text(
                '当前正在进入更强烈的段落 · ${gapDuration.toStringAsFixed(1)}s',
                style: subStyle,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _bufferedVisibility(double p) {
    // 0~1 的平滑缓冲：
    // 前 15% 逐渐出现，中间保持，后 15% 逐渐离开
    if (p <= 0.15) {
      return _smoothStep(p / 0.15) * 0.92;
    }
    if (p >= 0.85) {
      return (1.0 - _smoothStep((p - 0.85) / 0.15)) * 0.92;
    }
    return 0.92;
  }

  double _smoothStep(double t) {
    t = _clamp(t, 0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}

/// 没歌词时的占位卡
class EmptyStageCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const EmptyStageCard({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF2B3140), width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF96A6C8),
              fontSize: 14,
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// -------------------------
/// 工具函数
/// -------------------------
double _clamp(double v, double min, double max) {
  if (v < min) return min;
  if (v > max) return max;
  return v;
}

double _easeOutCubic(double t) {
  t = _clamp(t, 0.0, 1.0);
  return 1 - math.pow(1 - t, 3).toDouble();
}

double lerpDouble(double a, double b, double t) => a + (b - a) * t;