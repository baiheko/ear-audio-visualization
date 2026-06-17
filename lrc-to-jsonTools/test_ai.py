import os
import sys
os.environ["PYTHONIOENCODING"] = "utf-8"
sys.stdout.reconfigure(encoding='utf-8')

from openai import OpenAI

client = OpenAI(
    api_key="sk-691018c6ed764f8fb01cbe1e0d86edf7",
    base_url="https://api.deepseek.com"
)

res = client.chat.completions.create(
    model="deepseek-chat",
    messages=[
        {"role": "system", "content": "你是音乐情绪分析器"},
        {"role": "user", "content": "分析这句歌词：夜晚一个人走在街上"}
    ]
)

print(res.choices[0].message.content)