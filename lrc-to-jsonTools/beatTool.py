import json
import math
import sys
from pathlib import Path
from typing import List, Dict, Any


# -----------------------------
# 可调参数
# -----------------------------
# 两个 beat 太近时，认为是重复点，合并掉
MERGE_THRESHOLD_SEC = 0.08

# 长音字符持续时间大于这个值时，额外补一个中点 beat
LONG_CHAR_THRESHOLD_SEC = 0.28

# 行首 / 行尾 beat 强度
LINE_START_STRENGTH = 0.82
LINE_END_STRENGTH = 0.66

# 普通字符 beat 强度
CHAR_START_STRENGTH = 0.48

# 长音中点 beat 强度
LONG_CHAR_MID_STRENGTH = 0.38

# 符号是否参与 beat
INCLUDE_PUNCTUATION = False


def is_punctuation(ch: str) -> bool:
    if not ch:
        return True
    punctuation = set(".,!?！？。、，；：…—-~「」『』（）()[]{}<>·・・　 ")
    return ch in punctuation


def round_time(t: float) -> float:
    return round(float(t), 3)


def clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def merge_beats(beats: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    合并距离过近的 beat：
    - 保留时间更早的点
    - strength 取更大值
    """
    if not beats:
        return []

    beats = sorted(beats, key=lambda x: x["time"])
    merged = [beats[0]]

    for b in beats[1:]:
        last = merged[-1]
        if abs(b["time"] - last["time"]) < MERGE_THRESHOLD_SEC:
            # 时间太近，合并
            if b["strength"] > last["strength"]:
                last["strength"] = b["strength"]
            # 时间保留更早的那个，不改 last["time"]
        else:
            merged.append(b)

    # 统一格式化
    for b in merged:
        b["time"] = round_time(b["time"])
        b["strength"] = round(clamp(float(b["strength"]), 0.0, 1.0), 3)

    return merged


def add_beat(beats: List[Dict[str, Any]], time_sec: float, strength: float):
    if time_sec is None or math.isnan(time_sec):
        return
    if time_sec < 0:
        return
    beats.append({
        "time": round_time(time_sec),
        "strength": round(clamp(strength, 0.0, 1.0), 3)
    })


def generate_beats_from_song(song: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    根据歌词 JSON 推导 beats。
    优先使用：
    1) line.start / line.end
    2) chars[i].start / chars[i].end
    """
    beats: List[Dict[str, Any]] = []

    lines = song.get("lines", [])
    for line_index, line in enumerate(lines):
        line_start = line.get("start")
        line_end = line.get("end")
        chars = line.get("chars", []) or []

        # 1) 行首 beat：每句开始给一个稍强的触发
        if isinstance(line_start, (int, float)):
            add_beat(beats, float(line_start), LINE_START_STRENGTH)

        # 2) 字符 beat：每个字出现时给一个较轻 beat
        for char_index, ch in enumerate(chars):
            ch_start = ch.get("start")
            ch_end = ch.get("end")
            char_text = str(ch.get("char", ""))

            # 空白或标点可跳过，避免太乱
            if (not INCLUDE_PUNCTUATION) and is_punctuation(char_text):
                continue

            if isinstance(ch_start, (int, float)):
                # 普通字符起点
                strength = CHAR_START_STRENGTH

                # 行首第一个字稍微更强一点
                if char_index == 0:
                    strength = max(strength, 0.60)

                add_beat(beats, float(ch_start), strength)

            # 3) 长音字：如果持续时间较长，在中点补一个轻 beat
            if isinstance(ch_start, (int, float)) and isinstance(ch_end, (int, float)):
                duration = float(ch_end) - float(ch_start)
                if duration >= LONG_CHAR_THRESHOLD_SEC:
                    mid = (float(ch_start) + float(ch_end)) / 2.0
                    add_beat(beats, mid, LONG_CHAR_MID_STRENGTH)

        # 4) 行尾 beat：句子结束给一个收尾触发
        if isinstance(line_end, (int, float)):
            # 行尾尽量不要太强，避免和下一行开头冲突
            add_beat(beats, float(line_end), LINE_END_STRENGTH)

    # 5) 合并过近 beat
    beats = merge_beats(beats)

    # 6) 再按时间排序一次
    beats.sort(key=lambda x: x["time"])

    return beats


def build_output_song(song: Dict[str, Any]) -> Dict[str, Any]:
    """
    保留原始字段，补充 beats。
    如果原本已有 beats，也可以选择覆盖或合并。
    这里默认：如果已有 beats，就保留已有 beats；如果没有，就自动生成。
    """
    output = dict(song)

    existing_beats = song.get("beats", [])
    if isinstance(existing_beats, list) and len(existing_beats) > 0:
        # 已有 beats 就不强行覆盖
        output["beats"] = existing_beats
    else:
        output["beats"] = generate_beats_from_song(song)

    return output


def main():
    if len(sys.argv) < 2:
        print("用法: python generate_beats.py 输入json [输出json]")
        sys.exit(1)

    input_path = Path(sys.argv[1])

    if len(sys.argv) >= 3:
        output_path = Path(sys.argv[2])
    else:
        output_path = input_path.with_name(input_path.stem + "_with_beats.json")

    with input_path.open("r", encoding="utf-8") as f:
        song = json.load(f)

    output_song = build_output_song(song)

    with output_path.open("w", encoding="utf-8") as f:
        json.dump(output_song, f, ensure_ascii=False, indent=2)

    beat_count = len(output_song.get("beats", []))
    print(f"完成：{output_path}")
    print(f"生成 beats 数量：{beat_count}")


if __name__ == "__main__":
    main()