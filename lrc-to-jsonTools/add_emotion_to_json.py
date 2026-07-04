import os
import sys
import json
import re
from pathlib import Path
from openai import OpenAI

# 让 Windows 终端正常显示中文
os.environ["PYTHONIOENCODING"] = "utf-8"
sys.stdout.reconfigure(encoding="utf-8")

# =========================
# 需要处理的输入 / 输出文件
# =========================
INPUT_FILE = Path("../assets/lyrics/ささのはに、うたかたに.json")
OUTPUT_FILE = Path("../assets/lyrics/ささのはに、うたかたに_with_emotion.json")

# 推荐把 Key 放进环境变量，而不是写死在代码里
api_key = os.getenv("DEEPSEEK_API_KEY")

if not api_key:
    raise RuntimeError(
        "没有读取到 DEEPSEEK_API_KEY。\n"
        "请先在 PowerShell 执行：\n"
        '$env:DEEPSEEK_API_KEY="你的DeepSeek API Key"'
    )

client = OpenAI(
    api_key=api_key,
    base_url="https://api.deepseek.com",
)


def extract_json(text: str) -> dict:
    """从模型输出中提取 JSON，兼容 ```json 包裹。"""
    text = text.strip()
    text = text.replace("```json", "").replace("```", "").strip()

    start = text.find("{")
    end = text.rfind("}")

    if start == -1 or end == -1:
        raise ValueError(f"模型返回内容中没有找到 JSON：\n{text}")

    return json.loads(text[start:end + 1])


def normalize_emotion(value) -> float:
    """保证 emotion 始终是 0~1 的数值。"""
    try:
        emotion = float(value)
    except (TypeError, ValueError):
        emotion = 0.5

    emotion = max(0.0, min(1.0, emotion))
    return round(emotion, 3)


def get_lines_container(data):
    """
    兼容两种常见歌词 JSON：
    1. 顶层是列表：[{...}, {...}]
    2. 顶层是对象：{"lines": [{...}, {...}]}
    """
    if isinstance(data, list):
        return data

    if isinstance(data, dict) and isinstance(data.get("lines"), list):
        return data["lines"]

    raise ValueError(
        "无法识别 JSON 结构。需要顶层是列表，或对象中包含 lines 数组。"
    )


def analyze_full_song(lines: list[dict]) -> dict[int, float]:
    """
    一次性分析整首歌，返回：
    {歌词行下标: emotion}
    """
    payload = []

    for index, line in enumerate(lines):
        text = str(line.get("text", "")).strip()
        if text:
            payload.append({
                "index": index,
                "text": text,
            })

    if not payload:
        raise ValueError("JSON 中没有找到可分析的 text 字段。")

    prompt = f"""
你是音乐歌词情绪分析器。

请分析整首歌词中每一句的情绪强度，并返回严格 JSON。

规则：
1. emotion 是 0 到 1 的小数。
2. 数值越高表示这一句的情绪越强烈、越激昂、越有爆发感。
3. 平静、叙述、轻柔的句子通常在 0.2 到 0.5。
4. 抒情、情绪明显的句子通常在 0.5 到 0.75。
5. 高潮、强烈表达、爆发性句子通常在 0.75 到 1.0。
6. 只输出 JSON，不要解释，不要 Markdown，不要 emoji。
7. 必须保留输入的 index。

输入：
{json.dumps(payload, ensure_ascii=False)}

输出格式：
{{
  "lines": [
    {{
      "index": 0,
      "emotion": 0.5
    }}
  ]
}}
"""

    response = client.chat.completions.create(
        model="deepseek-chat",
        messages=[
            {
                "role": "system",
                "content": "你是歌词情绪分析器，只输出严格 JSON。",
            },
            {
                "role": "user",
                "content": prompt,
            },
        ],
        temperature=0.2,
    )

    raw_text = response.choices[0].message.content
    result = extract_json(raw_text)

    emotion_map = {}

    for item in result.get("lines", []):
        try:
            index = int(item["index"])
        except (KeyError, TypeError, ValueError):
            continue

        emotion_map[index] = normalize_emotion(item.get("emotion", 0.5))

    return emotion_map


def main():
    if not INPUT_FILE.exists():
        raise FileNotFoundError(f"找不到输入文件：{INPUT_FILE.resolve()}")

    print(f"读取歌词 JSON：{INPUT_FILE.resolve()}")

    with open(INPUT_FILE, "r", encoding="utf-8") as f:
        data = json.load(f)

    lines = get_lines_container(data)

    print(f"共读取到 {len(lines)} 行歌词，正在调用 AI 分析整首歌曲……")

    emotion_map = analyze_full_song(lines)

    for index, line in enumerate(lines):
        # 有 text 的歌词行才写 emotion；空行不动
        if str(line.get("text", "")).strip():
            line["emotion"] = emotion_map.get(index, 0.5)

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)

    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print("处理完成。")
    print(f"输出文件：{OUTPUT_FILE.resolve()}")


if __name__ == "__main__":
    main()