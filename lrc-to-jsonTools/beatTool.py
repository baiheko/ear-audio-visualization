import json
import statistics
from pathlib import Path


# =========================
# 参数配置
# =========================

# 两个 beat 小于这个间隔则合并
MIN_BEAT_INTERVAL = 0.10

# 长音阈值
LONG_CHAR_THRESHOLD = 0.35

# 长音补拍间隔
LONG_CHAR_PULSE_INTERVAL = 0.45

# 副歌最小间隔
CHORUS_MIN_GAP = 4.2

# 副歌倍率
CHORUS_GAP_FACTOR = 2.8


# =========================
# 工具函数
# =========================

def clamp(v, low, high):
    return max(low, min(high, v))


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_json(data, path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(
            data,
            f,
            ensure_ascii=False,
            indent=2
        )


# =========================
# 统计句间间隔
# =========================

def calc_line_gaps(lines):
    gaps = []

    for i in range(len(lines) - 1):
        current_end = lines[i]["end"]
        next_start = lines[i + 1]["start"]

        gap = next_start - current_end

        if gap > 0:
            gaps.append(gap)

    return gaps


# =========================
# 副歌检测
# =========================

def detect_chorus_gaps(lines):

    gaps = calc_line_gaps(lines)

    if not gaps:
        return []

    median_gap = statistics.median(gaps)

    threshold = max(
        CHORUS_MIN_GAP,
        median_gap * CHORUS_GAP_FACTOR
    )

    chorus_indexes = []

    for i in range(len(lines) - 1):

        gap = lines[i + 1]["start"] - lines[i]["end"]

        if gap >= threshold:
            chorus_indexes.append(i)

    return chorus_indexes


# =========================
# 添加 beat
# =========================

def add_beat(beats,
             time,
             strength,
             beat_type):

    beats.append({
        "time": round(float(time), 3),
        "strength": round(float(strength), 2),
        "type": beat_type
    })


# =========================
# 长音处理
# =========================

def process_long_char(beats, ch):

    duration = ch["end"] - ch["start"]

    if duration < LONG_CHAR_THRESHOLD:
        return

    add_beat(
        beats,
        ch["start"],
        0.60,
        "char_hold_start"
    )

    t = ch["start"] + LONG_CHAR_PULSE_INTERVAL

    while t < ch["end"]:

        add_beat(
            beats,
            t,
            0.35,
            "char_hold"
        )

        t += LONG_CHAR_PULSE_INTERVAL

    add_beat(
        beats,
        ch["end"],
        0.55,
        "char_hold_end"
    )


# =========================
# 单句歌词提取 beat
# =========================

def extract_line_beats(line, beats):

    chars = line.get("chars", [])

    if not chars:
        return

    # -------------------
    # 句首重拍
    # -------------------

    add_beat(
        beats,
        chars[0]["start"],
        0.90,
        "line_start"
    )

    # -------------------
    # 字级拍点
    # -------------------

    for i, ch in enumerate(chars):

        duration = ch["end"] - ch["start"]

        if i > 0:
            add_beat(
                beats,
                ch["start"],
                0.35,
                "char"
            )

        process_long_char(
            beats,
            ch
        )

    # -------------------
    # 句尾
    # -------------------

    add_beat(
        beats,
        chars[-1]["end"],
        0.75,
        "line_end"
    )


# =========================
# 副歌 beat
# =========================

def add_chorus_beats(lines,
                     chorus_indexes,
                     beats):

    for idx in chorus_indexes:

        gap_start = lines[idx]["end"]
        gap_end = lines[idx + 1]["start"]

        gap = gap_end - gap_start

        # 副歌开始
        add_beat(
            beats,
            gap_start + 0.05,
            1.0,
            "chorus_start"
        )

        # 中间省略号节奏
        pulse_count = int(gap // 1.2)

        for k in range(pulse_count):

            t = gap_start + (k + 1) * 1.2

            if t < gap_end - 0.4:

                add_beat(
                    beats,
                    t,
                    0.45,
                    "chorus_pulse"
                )

        # 副歌结束
        add_beat(
            beats,
            gap_end - 0.10,
            0.80,
            "chorus_end"
        )


# =========================
# 合并过密 beat
# =========================

def merge_beats(beats):

    beats.sort(key=lambda x: x["time"])

    result = []

    for beat in beats:

        if not result:
            result.append(beat)
            continue

        last = result[-1]

        delta = beat["time"] - last["time"]

        if delta < MIN_BEAT_INTERVAL:

            if beat["strength"] > last["strength"]:
                result[-1] = beat

        else:
            result.append(beat)

    return result


# =========================
# 主生成器
# =========================

def generate_beats(song):

    lines = song.get("lines", [])

    beats = []

    for line in lines:
        extract_line_beats(
            line,
            beats
        )

    chorus_indexes = detect_chorus_gaps(lines)

    add_chorus_beats(
        lines,
        chorus_indexes,
        beats
    )

    beats = merge_beats(beats)

    return beats


# =========================
# 主函数
# =========================

def process_file(json_path):

    song = load_json(json_path)

    beats = generate_beats(song)

    song["beats"] = beats

    out_path = (
        Path(json_path).stem +
        "_with_beats.json"
    )

    save_json(song, out_path)

    print("=" * 40)
    print("生成完成")
    print("Beat数量:", len(beats))
    print("输出文件:", out_path)
    print("=" * 40)


if __name__ == "__main__":

    json_path = input(
        "请输入歌词JSON路径："
    ).strip()

    process_file(json_path)