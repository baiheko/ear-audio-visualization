import os
import sys
import json
from flask import Flask, request, jsonify
from openai import OpenAI

os.environ["PYTHONIOENCODING"] = "utf-8"
sys.stdout.reconfigure(encoding="utf-8")

app = Flask(__name__)

client = OpenAI(
    api_key="sk-691018c6ed764f8fb01cbe1e0d86edf7",
    base_url="https://api.deepseek.com"
)


def extract_json(text: str) -> dict:
    text = text.strip()
    text = text.replace("```json", "").replace("```", "").strip()

    start = text.find("{")
    end = text.rfind("}")

    if start == -1 or end == -1:
        raise ValueError("AI返回内容不是JSON")

    return json.loads(text[start:end + 1])


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"})


@app.route("/analyze_song", methods=["POST"])
def analyze_song():
    data = request.get_json(force=True)
    lines = data.get("lines", [])

    prompt = f"""
你是“易耳”项目中的音乐情绪分析模块。
请分析下面这些歌词行，为 Flutter 前端生成逐句联动数据。

要求：
1. 只输出严格 JSON，不要 markdown，不要解释，不要 emoji。
2. 每句歌词返回：
   - index：必须和输入一致
   - emotion：0 到 1 之间的小数
   - beat：只能是 soft / normal / strong
   - type：只能是 verse / chorus / bridge / intro / outro
3. 不要把所有句子都判断成 chorus。
4. 情绪越强烈，emotion 越高。
5. beat 根据情绪强度判断：
   - emotion >= 0.7 通常 strong
   - emotion >= 0.4 通常 normal
   - emotion < 0.4 通常 soft

输入歌词：
{json.dumps(lines, ensure_ascii=False)}

输出格式：
{{
  "lines": [
    {{
      "index": 0,
      "emotion": 0.5,
      "beat": "normal",
      "type": "verse"
    }}
  ]
}}
"""

    res = client.chat.completions.create(
        model="deepseek-chat",
        messages=[
            {"role": "system", "content": "你是音乐情绪分析器，只输出严格JSON。"},
            {"role": "user", "content": prompt}
        ],
        temperature=0.2
    )

    raw = res.choices[0].message.content

    try:
        parsed = extract_json(raw)
    except Exception as e:
        return jsonify({
            "error": "AI返回JSON解析失败",
            "detail": str(e),
            "raw": raw
        }), 500

    result = []

    for item in parsed.get("lines", []):
        index = int(item.get("index", 0))

        try:
            emotion = float(item.get("emotion", 0.5))
        except Exception:
            emotion = 0.5

        emotion = max(0.0, min(1.0, emotion))

        beat = item.get("beat", "normal")
        if beat not in ["soft", "normal", "strong"]:
            beat = "normal"

        line_type = item.get("type", "verse")
        if line_type not in ["verse", "chorus", "bridge", "intro", "outro"]:
            line_type = "verse"

        result.append({
            "index": index,
            "emotion": round(emotion, 3),
            "beat": beat,
            "type": line_type
        })

    return jsonify({"lines": result})


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=True)