import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/lyric_models.dart';

/// -------------------------
/// 逐字动画所需的“视觉状态”
/// -------------------------
///
/// 这个类不是歌词数据本身，而是“这个字在屏幕上应该长什么样”。
/// 你后续想调动画，只要改这里的参数就行。
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

/// 用于 TweenAnimationBuilder 的自定义 Tween。
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

/// 单个字的渲染组件
///
/// 这个组件做了三件事：
/// 1. 逐字平滑淡入
/// 2. 当前字轻微发光、放大、位移
/// 3. 字的效果变化时，自动过渡，不会突然跳变
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
                  height: 1.1,
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
/// 这是你主界面里“当前唱到的那一行”。
/// 里面每个字会按照时间逐个显现，当前字会更亮、更大、略微偏移。
class LyricLineCard extends StatelessWidget {
  final LyricLine line;
  final int lineIndex;
  final int totalLines;
  final double currentTime;
  final double beatPulse;
  final Map<String, LyricCharEffect> effectCache;

  const LyricLineCard({
    super.key,
    required this.line,
    required this.lineIndex,
    required this.totalLines,
    required this.currentTime,
    required this.beatPulse,
    required this.effectCache,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 卡片轮廓颜色：节拍到来时会稍微变亮
    final baseBorder = const Color(0xFF2B3140);
    final accentBorder = const Color(0xFF67D9FF);
    final borderColor = Color.lerp(baseBorder, accentBorder, beatPulse * 0.55) ?? baseBorder;

    final cardBg = Color.lerp(
      const Color(0xFF0B1220),
      const Color(0xFF11213A),
      beatPulse * 0.25,
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
        line: line,
        char: ch,
        currentTime: currentTime,
        baseFontSize: baseFontSize,
        beatPulse: beatPulse,
      );

      // 用缓存让 TweenAnimationBuilder 能从“上一帧状态”平滑过渡到“这一帧状态”
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部小标签：当前行序号
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('当前', style: labelStyle),
              Text('${lineIndex + 1} / $totalLines', style: indexStyle),
            ],
          ),
          const SizedBox(height: 14),

          // 逐字区域
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: charWidgets,
            ),
          ),

          // 译文区域：静态双行展示，不逐字动画
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

  /// 根据字数估算基础字号。
  /// 这是为了让长句不至于过大挤爆屏幕。
  double _fitBaseFontSize(int charCount) {
    if (charCount <= 8) return 42;
    if (charCount <= 12) return 38;
    if (charCount <= 18) return 34;
    if (charCount <= 24) return 30;
    return 26;
  }

  /// 计算单字的视觉状态。
  ///
  /// 这里把你之前提到的效果统一编码：
  /// - 已出现：显示
  /// - 当前字：发光、放大、轻微位移
  /// - pitch：控制上下浮动
  /// - volume：控制缩放
  /// - emotion：控制颜色偏向
  LyricCharEffect _buildCharEffect({
    required LyricLine line,
    required LyricChar char,
    required double currentTime,
    required double baseFontSize,
    required double beatPulse,
  }) {
    // 未到时间：不显示
    if (currentTime < char.start) {
      return LyricCharEffect(
        opacity: 0.0,
        scale: 0.96,
        translateX: 0,
        translateY: 6,
        fontSize: baseFontSize,
        color: const Color(0xFFF3F7FF),
        glow: 0.0,
      );
    }

    final duration = math.max(char.end - char.start, 0.12);
    final appearDuration = math.max(duration * 0.35, 0.06);
    final appearProgress = _easeOutCubic(
      _clamp((currentTime - char.start) / appearDuration, 0.0, 1.0),
    );

    final active = currentTime >= char.start && currentTime <= char.end;
    final holdProgress = _clamp((currentTime - char.start) / duration, 0.0, 1.0);

    // pitch：音高越高，字越向上；越低，越向下
    final pitch = _normalizePitch(char.pitch);
    final pitchOffsetY = pitch == null ? 0.0 : (0.5 - pitch) * 10.0;

    // volume：响度越高，字越大
    final volume = _normalizeLevel(char.volume);
    final volumeScale = 1.0 + (volume ?? 0.0) * 0.07;

    // emotion：控制颜色偏向
    final emotion = _normalizeLevel(
      char.emotion ?? line.emotion,
    );

    final baseColor = const Color(0xFFF3F7FF);
    final warmColor = const Color(0xFFFFD58B);
    final coolColor = const Color(0xFF67D9FF);

    // 情绪越强，颜色越向“暖 / 强调”方向走
    final emotionColor = emotion == null
        ? baseColor
        : Color.lerp(coolColor, warmColor, emotion)!;

    // 当前字会向右轻微滑动，长音越长，滑动越明显
    final driftMaxX = _clamp(6.0 + duration * 18.0, 6.0, 18.0);
    final driftX = active ? _easeOutCubic(holdProgress) * driftMaxX : 0.0;

    // 当前字高亮时，加发光
    final glow = active ? (0.35 + beatPulse * 0.65) : 0.0;

    // 当前字比普通字稍微更亮
    final color = active
        ? Color.lerp(emotionColor, coolColor, 0.38 + beatPulse * 0.18) ?? emotionColor
        : emotionColor.withOpacity(0.88);

    return LyricCharEffect(
      opacity: appearProgress,
      scale: volumeScale + (active ? 0.06 : 0.0),
      translateX: driftX,
      translateY: pitchOffsetY + (active ? -1.5 : 0.0),
      fontSize: baseFontSize * (1.0 + (volume ?? 0.0) * 0.05 + (active ? 0.03 : 0.0)),
      color: color,
      glow: glow,
    );
  }
}

/// 副歌长间隔提示卡片
///
/// 当两句歌词之间的时间间隔很长时，不要空着。
/// 这里用“省略号进度”做一个平滑提示，类似 App Music 的处理方式。
class ChorusProgressCard extends StatelessWidget {
  final double progress; // 0~1
  final double phase; // 0~1，外部的循环动画相位
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
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

          // 省略号进度：越接近副歌，点越“亮”
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              // phase 在 0~1 之间循环，这里让三个点错峰呼吸
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
                  color: dotColor.withOpacity(0.35 + weight * 0.65),
                  shape: BoxShape.circle,
                  boxShadow: [
                    if (weight > 0.25)
                      BoxShadow(
                        color: dotColor.withOpacity(0.24),
                        blurRadius: 10 + weight * 8,
                      ),
                  ],
                ),
              );
            }),
          ),

          const SizedBox(height: 14),

          // 进度条：更直观地让用户知道“副歌还在展开”
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: _clamp(progress, 0.0, 1.0),
              backgroundColor: const Color(0xFF1B2435),
              valueColor: AlwaysStoppedAnimation<Color>(
                Color.lerp(
                  const Color(0xFF67D9FF),
                  const Color(0xFF9A6CFF),
                  beatPulse * 0.55,
                )!,
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

/// 时间空白时的占位提示
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
/// 内部工具函数
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

double lerpDouble(double a, double b, double t) {
  return a + (b - a) * t;
}

double? _normalizeLevel(dynamic v) {
  if (v == null || v == '') return null;

  if (v is num) {
    final d = v.toDouble();
    if (d >= 0 && d <= 1) return d;
    return _clamp(d / 100.0, 0.0, 1.0);
  }

  if (v is String) {
    switch (v.trim().toLowerCase()) {
      case 'low':
      case '弱':
        return 0.25;
      case 'mid':
      case 'middle':
      case 'medium':
      case 'normal':
      case '中':
        return 0.5;
      case 'high':
      case 'strong':
      case '高':
      case '强':
        return 0.85;
      default:
        return null;
    }
  }

  return null;
}

double? _normalizePitch(dynamic v) {
  if (v == null || v == '') return null;

  if (v is num) {
    final d = v.toDouble();
    if (d >= 0 && d <= 1) return d;
    return _clamp(d / 100.0, 0.0, 1.0);
  }

  if (v is String) {
    switch (v.trim().toLowerCase()) {
      case 'low':
      case '低':
        return 0.0;
      case 'mid':
      case 'middle':
      case 'medium':
      case 'normal':
      case '中':
        return 0.5;
      case 'high':
      case '高':
        return 1.0;
      default:
        return null;
    }
  }

  return null;
}