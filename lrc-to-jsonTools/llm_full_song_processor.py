import os
import sys
import re
import json
from openai import OpenAI

os.environ["PYTHONIOENCODING"] = "utf-8"
sys.stdout.reconfigure(encoding='utf-8')

client = OpenAI(
    api_key="sk-691018c6ed764f8fb01cbe1e0d86edf7",
    base_url="https://api.deepseek.com"
)

# =========================
# 1. LRC解析
# =========================
def parse_lrc(lrc_text):
    """
    输入LRC字符串 → 输出纯歌词list
    """
    lines = []
    for line in lrc_text.split("\n"):
        text = re.sub(r"\[.*?\]", "", line).strip()
        if text:
            lines.append(text)
    return lines


# =========================
# 2. emotion标准化
# =========================
def normalize_emotion(raw_text):
    """
    从AI输出中提取0~1情绪值
    """
    match = re.search(r"([0-1](\.\d+)?)", raw_text)
    if match:
        return float(match.group(1))
    return 0.5  # 默认中性


# =========================
# 3. chorus识别优化
# =========================
def detect_chorus(lines):
    """
    简单重复检测：重复最多的句子当chorus
    """
    freq = {}
    for l in lines:
        freq[l] = freq.get(l, 0) + 1

    chorus = max(freq, key=freq.get)
    return chorus


# =========================
# 4. 单句AI分析
# =========================
def analyze_line(line):
    res = client.chat.completions.create(
        model="deepseek-chat",
        messages=[
            {"role": "system", "content": "你是音乐情绪分析器，只输出0~1之间的情绪值，不要解释"},
            {"role": "user", "content": f"分析这句歌词情绪：{line}"}
        ],
        temperature=0.3
    )

    return res.choices[0].message.content


# =========================
# 5. 整首歌处理（核心）
# =========================
def process_song(lrc_text):
    lines = parse_lrc(lrc_text)
    chorus_line = detect_chorus(lines)

    result = []

    for line in lines:
        raw = analyze_line(line)
        emotion = normalize_emotion(raw)

        # beat逻辑（简化版🔥）
        beat = "strong" if emotion > 0.7 else "normal" if emotion > 0.4 else "soft"

        # chorus识别
        line_type = "chorus" if line == chorus_line else "verse"

        result.append({
            "text": line,
            "emotion": round(emotion, 3),
            "beat": beat,
            "type": line_type
        })

    return {
        "lines": result
    }


# =========================
# 6. 测试入口
# =========================
if __name__ == "__main__":

    test_lrc = """
    [00:01] 夜晚一个人走在街上
    [00:05] 风吹过我的脸
    [00:09] 回忆涌上心头
    [00:13] 夜晚一个人走在街上
    """

    data = process_song(test_lrc)

    print(json.dumps(data, ensure_ascii=False, indent=2))

OUTPUT_PATH = "../flutter_app/assets/song_data.json"

os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)

with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)