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
                  color: effect.color.withValues(alpha: 0.45 * effect.glow),
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

/// 长间隔信息
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

/// 逐字歌词卡片
///
/// 这版的关键变化：
/// 1. 字一旦出现，就不会消失
/// 2. 当前行会一直累计显示到整行完成
/// 3. 之前已经播完的行会作为“上一句”保留
/// 4. pitch / volume 不再参与视觉变化
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
  /// 完成态的行会整体更稳，不再继续强调当前字
  final bool settled;

  /// 预进入时间，柔和型会稍微长一点
  final double leadInSeconds;

  /// 动画风格预设
  final LyricMotionPreset motionPreset;

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
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final baseBorder = const Color(0xFF2B3140);
    final accentBorder = const Color(0xFF67D9FF);
    final borderColor = Color.lerp(
      baseBorder,
      accentBorder,
      beatPulse * 0.35,
    ) ?? baseBorder;

    final cardBg = Color.lerp(
      const Color(0xFF0B1220),
      const Color(0xFF10243D),
      beatPulse * 0.14,
    )!;

    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: const Color(0xFF8EA2C7),
      fontWeight: FontWeight.w600,
    );

    final indexStyle = theme.textTheme.labelMedium?.copyWith(
      color: const Color(0xFF5ED9FF),
      fontWeight: FontWeight.w600,
    );

    final baseFontSize = _fitBaseFontSize(line.chars.length);

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
          padding: const EdgeInsets.symmetric(horizontal: 1.2),
          child: LyricCharWidget(
            char: ch.char,
            beginEffect: begin,
            endEffect: effect,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 1.2),
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
          const SizedBox(height: 14),

          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: charWidgets,
            ),
          ),

          if (line.translation.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              line.translation,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF96A6C8),
                height: 1.45,
                fontSize: 15,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 根据字数估算基础字号，避免长句撑爆屏幕
  double _fitBaseFontSize(int charCount) {
    if (charCount <= 8) return 42;
    if (charCount <= 12) return 38;
    if (charCount <= 18) return 34;
    if (charCount <= 24) return 30;
    return 26;
  }

  /// 单字视觉状态
  ///
  /// 关键变化：
  /// - 字出现后不消失
  /// - 当前字只在“正在唱”的区间里更亮、更强调
  /// - 一旦字出现，后面就保持显示
  /// - 取消 pitch / volume 对视觉的影响
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
        opacity: 0.84,
        scale: 1.0,
        translateX: 0,
        translateY: 0,
        fontSize: baseFontSize * 0.98,
        color: const Color(0xFFF3F7FF).withValues(alpha: 0.9),
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
        opacity: 0.10 + 0.30 * preProgress,
        scale: 0.98 + 0.015 * preProgress,
        translateX: preProgress * (2.4 * intensity),
        translateY: 0,
        fontSize: baseFontSize * (0.99 + 0.01 * preProgress),
        color: const Color(0xFFF3F7FF).withValues(alpha: 0.78),
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
        opacity: 0.40 + 0.60 * appearProgress,
        scale: 1.0 + 0.02 * intensity,
        translateX: driftX,
        translateY: 0,
        fontSize: baseFontSize * (1.0 + 0.015 * intensity),
        color: Color.lerp(
              const Color(0xFFF3F7FF),
              const Color(0xFF67D9FF),
              0.22 + beatPulse * 0.14,
            ) ??
            const Color(0xFFF3F7FF),
        glow: 0.20 + beatPulse * 0.45 * intensity,
      );
    }

    // 已经唱完：保留在前面，不消失
    // 这里不给它做“消失尾巴”，只给一个稳定的轻微停留状态
    return LyricCharEffect(
      opacity: 1.0,
      scale: 1.0,
      translateX: 0.0,
      translateY: 0.0,
      fontSize: baseFontSize,
      color: const Color(0xFFF3F7FF).withValues(alpha: 0.90),
      glow: 0.0,
    );
  }
}

/// 双槽歌词舞台
///
/// 这次的逻辑改成：
/// - 上一个槽：上一句
/// - 下一个槽：当前句
///
/// 但位置不是固定的，
/// 它会按照“行号奇偶”在左上 / 右下之间轮换：
///
/// 第 1 行：左上
/// 第 2 行：右下
/// 第 3 行：左上
/// 第 4 行：右下
///
/// 这样就符合你举的例子。
class LyricDualSlotStage extends StatelessWidget {
  final SongModel song;
  final double lyricTime;
  final double beatPulse;
  final Map<String, LyricCharEffect> effectCache;
  final LyricMotionPreset motionPreset;
  final bool compactLayout;
  final double ellipsisPhase;

  const LyricDualSlotStage({
    super.key,
    required this.song,
    required this.lyricTime,
    required this.beatPulse,
    required this.effectCache,
    required this.motionPreset,
    required this.compactLayout,
    required this.ellipsisPhase,
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

    // 当前行出现的位置：偶数行左上，奇数行右下
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
    );

    Widget previousWidget;
    if (previousLine != null) {
      previousWidget = LyricLineCard(
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
      );
    } else {
      previousWidget = const SizedBox.shrink();
    }

    // 长间隔副歌提示：
    // 只在“当前时间落在大间隔”里时显示，不去显示下一句歌词
    final gapInfo = _findChorusGap(song.lines, lyricTime);
    Widget activeExtraWidget = const SizedBox.shrink();

    if (gapInfo != null) {
      activeExtraWidget = ChorusProgressCard(
        key: ValueKey('gap_${gapInfo.fromIndex}_${gapInfo.toIndex}_${gapInfo.gapStart.toStringAsFixed(2)}'),
        progress: gapInfo.progress,
        phase: ellipsisPhase,
        beatPulse: beatPulse,
        previousLine: song.lines[gapInfo.fromIndex],
        nextLine: song.lines[gapInfo.toIndex],
        gapDuration: gapInfo.gapDuration,
      );
    }

    // 位置规则：
    // - currentIsTopLeft == true:
    //   左上 = 当前句
    //   右下 = 上一句
    // - currentIsTopLeft == false:
    //   左上 = 上一句
    //   右下 = 当前句
    final topLeftChild = currentIsTopLeft
        ? currentCard
        : (previousLine != null ? previousWidget : currentCard);

    final bottomRightChild = currentIsTopLeft
        ? (previousLine != null ? previousWidget : const SizedBox.shrink())
        : currentCard;

    // 如果当前处于长间隔，那么“当前句”位置改显示副歌进度卡
    // 但仍然保留上一句。
    final topLeftFinal = currentIsTopLeft
        ? currentCard
        : (previousLine != null ? previousWidget : currentCard);

    final bottomRightFinal = currentIsTopLeft
        ? (previousLine != null ? previousWidget : const SizedBox.shrink())
        : currentCard;

    final activeSlotIsTopLeft = currentIsTopLeft;

    if (compactLayout) {
      // 小屏模式：竖向堆叠，避免挤爆
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (activeSlotIsTopLeft) ...[
            currentCard,
            const SizedBox(height: 12),
            previousLine != null ? previousWidget : const SizedBox.shrink(),
          ] else ...[
            previousLine != null ? previousWidget : const SizedBox.shrink(),
            const SizedBox(height: 12),
            currentCard,
          ],
          if (gapInfo != null) ...[
            const SizedBox(height: 12),
            activeExtraWidget,
          ],
        ],
      );
    }

    return SizedBox(
      height: 430,
      child: Stack(
        children: [
          Align(
            alignment: const Alignment(-0.98, -0.84),
            child: FractionallySizedBox(
              widthFactor: 0.94,
              child: topLeftFinal,
            ),
          ),
          Align(
            alignment: const Alignment(0.98, 0.84),
            child: FractionallySizedBox(
              widthFactor: 0.88,
              child: gapInfo != null
                  ? activeExtraWidget
                  : bottomRightFinal,
            ),
          ),
        ],
      ),
    );
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

  /// 识别长间隔区间，用来显示“副歌展开中”的省略号进度
  ChorusGapInfo? _findChorusGap(List<LyricLine> lines, double currentSec) {
    const threshold = 2.6;

    for (int i = 0; i < lines.length - 1; i++) {
      final prev = lines[i];
      final next = lines[i + 1];

      final gapStart = prev.end;
      final gapEnd = next.start;
      final gapDuration = gapEnd - gapStart;

      if (gapDuration >= threshold &&
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

/// 长间隔 / 副歌进度卡
class ChorusProgressCard extends StatelessWidget {
  final double progress;
  final double phase;
  final double beatPulse;
  final LyricLine? previousLine;
  final LyricLine? nextLine;
  final double gapDuration;

  const ChorusProgressCard({
    super.key,
    required this.progress,
    required this.phase,
    required this.beatPulse,
    required this.previousLine,
    required this.nextLine,
    required this.gapDuration,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final borderColor = Color.lerp(
      const Color(0xFF2B3140),
      const Color(0xFF67D9FF),
      0.35 + beatPulse * 0.45,
    )!;

    final cardBg = Color.lerp(
      const Color(0xFF0B1220),
      const Color(0xFF10243D),
      beatPulse * 0.22,
    )!;

    final subtitle = theme.textTheme.bodyMedium?.copyWith(
      color: const Color(0xFF96A6C8),
      height: 1.45,
    );

    final title = theme.textTheme.titleMedium?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w700,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('副歌展开中', style: title),
              Text('${gapDuration.toStringAsFixed(1)}s', style: subtitle),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              final wave = (math.sin((phase * math.pi * 2) + i * 0.75) + 1) / 2;
              final weight = _clamp(progress * 0.55 + wave * 0.45, 0.0, 1.0);

              final dotColor = Color.lerp(
                const Color(0xFF96A6C8),
                const Color(0xFF67D9FF),
                weight,
              )!;

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 16 + weight * 8,
                height: 16 + weight * 8,
                decoration: BoxDecoration(
                  color: dotColor.withValues(alpha: 0.35 + weight * 0.65),
                  shape: BoxShape.circle,
                ),
              );
            }),
          ),

          const SizedBox(height: 14),

          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: _clamp(progress, 0.0, 1.0),
              backgroundColor: const Color(0xFF1B2435),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF67D9FF),
              ),
            ),
          ),

          const SizedBox(height: 10),

          Text(
            '当前正在进入更强烈的段落',
            style: subtitle,
            textAlign: TextAlign.center,
          ),

          if (previousLine != null && nextLine != null) ...[
            const SizedBox(height: 10),
            Text(
              '上一句：${previousLine!.text}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: subtitle?.copyWith(fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '下一句：${nextLine!.text}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: subtitle?.copyWith(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
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

/// 内部工具函数
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