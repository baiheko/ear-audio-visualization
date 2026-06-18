import json
import math
import sys
from pathlib import Path


def parse_time_signature(ts: str):
    """
    解析拍号，例如：
    4/4 -> (4, 4)
    3/4 -> (3, 4)
    6/8 -> (6, 8)
    """
    if "/" not in ts:
        raise ValueError("拍号格式必须像 4/4、3/4、6/8")

    num_str, den_str = ts.split("/", 1)
    numerator = int(num_str.strip())
    denominator = int(den_str.strip())

    if numerator <= 0 or denominator <= 0:
        raise ValueError("拍号分子分母必须大于 0")

    return numerator, denominator


def find_first_lyric_start(song: dict) -> float:
    """
    第一拍起点：
    优先取第一句歌词的第一个字的 start
    如果没有 chars，就取第一句的 start
    再不行就用 0.0
    """
    lines = song.get("lines", [])
    for line in lines:
        chars = line.get("chars") or []
        if chars:
            first_char = chars[0]
            start = first_char.get("start")
            if isinstance(start, (int, float)):
                return float(start)

        start = line.get("start")
        if isinstance(start, (int, float)):
            return float(start)

    return 0.0


def find_song_end_time(song: dict) -> float:
    """
    找整首歌的结束时间：
    - 优先用 lines / chars 里的最大 end
    - 如果有 duration 字段也一起考虑
    """
    max_time = 0.0

    if isinstance(song.get("duration"), (int, float)):
        max_time = max(max_time, float(song["duration"]))

    for line in song.get("lines", []):
        if isinstance(line.get("end"), (int, float)):
            max_time = max(max_time, float(line["end"]))

        for ch in line.get("chars") or []:
            if isinstance(ch.get("end"), (int, float)):
                max_time = max(max_time, float(ch["end"]))

    return max_time


def generate_last_beat_per_measure(song: dict, bpm: float, time_signature: str):
    """
    按你的规则只生成“每小节最后一拍”的 beat 数据。
    """
    numerator, denominator = parse_time_signature(time_signature)

    # 这里按“BPM 是四分音符 BPM”来理解
    beat_interval = 60.0 / bpm * (4.0 / denominator)

    first_beat_time = find_first_lyric_start(song)
    song_end_time = find_song_end_time(song)

    beats = []
    measure_index = 0

    while True:
        # 第 measure_index 小节的最后一拍
        # 公式：first_beat + ((measureIndex + 1) * numerator - 1) * beat_interval
        beat_time = first_beat_time + (((measure_index + 1) * numerator) - 1) * beat_interval

        # 超过歌曲结束就停止
        if beat_time > song_end_time + 1e-6:
            break

        beats.append({
            "time": round(beat_time, 3),
            "strength": 1.0,
            "measure": measure_index + 1,
            "beatInMeasure": numerator,
            "vibrate": True
        })

        measure_index += 1

    return beats


def main():
    if len(sys.argv) < 4:
        print("用法：python add_beats.py 输入json BPM 拍号 [输出json]")
        print("示例：python add_beats.py input.json 120 4/4 output.json")
        sys.exit(1)

    input_path = Path(sys.argv[1])
    bpm = float(sys.argv[2])
    time_signature = sys.argv[3]

    if len(sys.argv) >= 5:
        output_path = Path(sys.argv[4])
    else:
        output_path = input_path.with_name(input_path.stem + "_with_beats.json")

    with input_path.open("r", encoding="utf-8") as f:
        song = json.load(f)

    beats = generate_last_beat_per_measure(song, bpm, time_signature)

    # 输出：保留原始字段，只补 beats
    song["beats"] = beats

    with output_path.open("w", encoding="utf-8") as f:
        json.dump(song, f, ensure_ascii=False, indent=2)

    print(f"完成：{output_path}")
    print(f"生成 beats 数量：{len(beats)}")


if __name__ == "__main__":
    main()