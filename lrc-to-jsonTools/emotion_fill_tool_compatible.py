# emotion_fill_tool.py
# 功能：读取已格式化的歌词 JSON，把每一行 emotion（null/缺失）补成 0~1 的数值。
# 运行：python emotion_fill_tool.py

import json
import os
import re
import sys
from getpass import getpass
from pathlib import Path
from typing import Dict, List, Any

try:
    from openai import OpenAI
except ImportError:
    print("缺少 openai 库。请先运行：pip install openai")
    raise SystemExit(1)

os.environ["PYTHONIOENCODING"] = "utf-8"
try:
    sys.stdout.reconfigure(encoding="utf-8")
except AttributeError:
    pass


def get_lines_container(data):
    """支持顶层数组，或 {'lines': [...]} 两种歌词 JSON 结构。"""
    if isinstance(data, list):
        return data
    if isinstance(data, dict) and isinstance(data.get("lines"), list):
        return data["lines"]
    raise ValueError("无法识别 JSON 结构：顶层应是数组，或对象中包含 lines 数组。")


def extract_json(text):
    """兼容模型把 JSON 放进 ```json 代码块的情况。"""
    text = text.strip()
    text = re.sub(r"^```(?:json)?\s*", "", text, flags=re.IGNORECASE)
    text = re.sub(r"\s*```$", "", text)

    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1:
        raise ValueError("模型没有返回可解析的 JSON：\n%s" % text)

    return json.loads(text[start:end + 1])


def clamp_emotion(value):
    try:
        value = float(value)
    except (TypeError, ValueError):
        value = 0.5
    return round(max(0.0, min(1.0, value)), 3)


def analyze_batch(client, payload):
    """一次分析一批歌词，返回 {原始行下标: emotion}。"""
    prompt = f"""
你是歌词情绪强度标注工具。请根据每一句歌词的语义、语气和上下文，
为每一句输出一个 0 到 1 之间的 emotion 数值。

规则：
1. 0.0 表示非常平静、克制、低落或叙述性很强。
2. 1.0 表示情绪最强烈、最激昂、最爆发。
3. 只输出严格 JSON，不要解释、不要 Markdown、不要 emoji。
4. index 必须和输入完全一致。
5. 每个输入 index 都必须输出一次。

输入：
{json.dumps(payload, ensure_ascii=False)}

输出格式：
{{
  "lines": [
    {{"index": 0, "emotion": 0.5}}
  ]
}}
"""

    response = client.chat.completions.create(
        model="deepseek-chat",
        messages=[
            {
                "role": "system",
                "content": "你是歌词情绪强度标注工具，只输出严格 JSON。"
            },
            {"role": "user", "content": prompt},
        ],
        temperature=0.2,
    )

    parsed = extract_json(response.choices[0].message.content)
    result = {}

    for item in parsed.get("lines", []):
        try:
            index = int(item["index"])
        except (KeyError, TypeError, ValueError):
            continue
        result[index] = clamp_emotion(item.get("emotion", 0.5))

    return result


def default_output_path(input_path):
    return input_path.with_name(
        "{}_with_emotion{}".format(input_path.stem, input_path.suffix)
    )


def main():
    print("=" * 58)
    print("歌词 JSON emotion 自动填充工具")
    print("=" * 58)

    raw_path = input("请输入歌词 JSON 文件路径（可直接拖入 CMD）：\n> ").strip().strip('"')
    input_path = Path(raw_path)

    if not input_path.exists():
        print("\n找不到文件：{}".format(input_path))
        raise SystemExit(1)

    output_default = default_output_path(input_path)
    raw_output = input(
        "\n输出文件路径（直接回车默认生成）：\n{}\n> ".format(output_default)
    ).strip().strip('"')
    output_path = Path(raw_output) if raw_output else output_default

    api_key = os.getenv("DEEPSEEK_API_KEY")
    if not api_key:
        api_key = getpass("\n请输入 DeepSeek API Key（输入时不会显示）：\n> ").strip()

    if not api_key:
        print("没有输入 API Key，程序结束。")
        raise SystemExit(1)

    client = OpenAI(
        api_key=api_key,
        base_url="https://api.deepseek.com",
    )

    try:
        with input_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except UnicodeDecodeError:
        print("文件不是 UTF-8 编码，无法读取。请先把 JSON 保存为 UTF-8。")
        raise SystemExit(1)
    except json.JSONDecodeError as e:
        print("JSON 格式错误：{}".format(e))
        raise SystemExit(1)

    lines = get_lines_container(data)

    to_analyze = []
    for index, line in enumerate(lines):
        if not isinstance(line, dict):
            continue
        text = str(line.get("text", "")).strip()
        if text and line.get("emotion") is None:
            to_analyze.append({"index": index, "text": text})

    if not to_analyze:
        print("\n没有发现 emotion 为 null 或缺失、且包含 text 的歌词行。")
        print("不会生成新文件。")
        return

    print("\n共找到 {} 行需要填写 emotion。".format(len(to_analyze)))
    print("正在调用 DeepSeek 分析整首歌词，请稍候……")

    emotion_map = {}
    batch_size = 30

    for start in range(0, len(to_analyze), batch_size):
        batch = to_analyze[start:start + batch_size]
        batch_no = start // batch_size + 1
        total_batches = (len(to_analyze) + batch_size - 1) // batch_size
        print("  处理第 {}/{} 批（{} 行）……".format(batch_no, total_batches, len(batch)))

        try:
            emotion_map.update(analyze_batch(client, batch))
        except Exception as e:
            print("\n第 {} 批分析失败：{}".format(batch_no, e))
            print("未写入输出文件，避免生成不完整结果。")
            raise SystemExit(1)

    for item in to_analyze:
        index = item["index"]
        lines[index]["emotion"] = emotion_map.get(index, 0.5)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print("\n处理完成。")
    print("输出文件：{}".format(output_path.resolve()))
    print("原始 JSON 没有被覆盖。")


if __name__ == "__main__":
    main()
