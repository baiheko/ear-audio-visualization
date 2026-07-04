#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Convert a QRC/LRC lyric file into the JSON structure used by your project.

Usage:
    python lrc_to_json_converter.py "input.lrc" --artist "Singer Name"

Output:
    Automatically writes a same-name .json file next to the input .lrc file.

Features:
- Read [ti:], [ar:], [offset:] and other metadata
- Support lines with per-character timestamps:
    [00:11.053]些[00:11.408]細... [00:21.740]
- Support paired translation lines:
    [00:11.053]中文翻译[00:22.390]
- For character-level lyrics, punctuation such as （）“”【】 etc. is converted
  into space placeholders, and its timing is merged into neighboring lyric text.
- Generate:
    title, artist, duration, lines[{start,end,text,translation,emotion,chars}], beats:[]
"""

from __future__ import annotations

import argparse
import json
import re
import unicodedata
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

TIMESTAMP_RE = re.compile(r"\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?\]")
META_RE = re.compile(r"^\[(ti|ar|al|by|offset|re|ve):(.*?)\]$", re.I)

# Common opening / closing punctuation sets.
OPEN_PUNCT = {
    "(", "（", "[", "【", "「", "『", "“", "‘", "《", "〈", "｢", "⟨", "⟪", "⟦", "⌈", "⌊", "{",
}
CLOSE_PUNCT = {
    ")", "）", "]", "】", "」", "』", "”", "’", "》", "〉", "｣", "⟩", "⟫", "⟧", "⌉", "⌋", "}",
}


def ts_to_sec(mm: str, ss: str, ms: Optional[str]) -> float:
    """Convert mm:ss.xxx to seconds."""
    ms = (ms or "0").ljust(3, "0")[:3]
    return int(mm) * 60 + int(ss) + int(ms) / 1000.0


def parse_timed_line(line: str, offset_sec: float = 0.0) -> Optional[Tuple[List[float], List[str]]]:
    """
    Parse a lyric line into:
      timestamps: [t0, t1, t2, ...]
      segments:   [text_after_t0, text_after_t1, ..., text_after_last_timestamp]
    """
    matches = list(TIMESTAMP_RE.finditer(line))
    if not matches:
        return None

    timestamps: List[float] = []
    segments: List[str] = []

    for i, m in enumerate(matches):
        timestamps.append(ts_to_sec(m.group(1), m.group(2), m.group(3)) + offset_sec)
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(line)
        segments.append(line[start:end])

    return timestamps, segments


def is_punctuation(ch: str) -> bool:
    """Unicode punctuation (plus a few common full-width symbols) should be treated as non-lyric."""
    return unicodedata.category(ch).startswith("P")


def is_open_punct(ch: str) -> bool:
    return ch in OPEN_PUNCT


def is_close_punct(ch: str) -> bool:
    return ch in CLOSE_PUNCT


def visible_text(text: str) -> str:
    """
    Replace punctuation with spaces so the line remains visually aligned,
    while keeping only lyric characters in the text field.
    """
    return "".join(" " if is_punctuation(ch) else ch for ch in text).rstrip()


def _nearest_real_left(flags: List[bool], index: int) -> Optional[int]:
    for i in range(index - 1, -1, -1):
        if not flags[i]:
            return i
    return None


def _nearest_real_right(flags: List[bool], index: int) -> Optional[int]:
    for i in range(index + 1, len(flags)):
        if not flags[i]:
            return i
    return None


def distribute_segment(seg: str, start: float, end: float) -> List[Dict[str, Any]]:
    """
    Spread a text segment across characters.

    Rules for punctuation:
    - Opening punctuation (e.g. （ “ 【) transfers its timing to the following lyric char.
    - Closing punctuation (e.g. ） ” 】) transfers its timing to the previous lyric char.
    - Other punctuation is treated like closing punctuation when possible.
    - Punctuation is emitted as a short space placeholder, not as a lyric character.
    """
    chars = list(seg)
    if not chars:
        return []

    duration = max(end - start, 0.0)
    flags = [is_punctuation(ch) for ch in chars]
    real_indices = [i for i, flag in enumerate(flags) if not flag]
    punct_count = sum(flags)

    # If there are no lyric characters, keep the placeholders evenly spread.
    if not real_indices:
        if punct_count == 0:
            return []
        step = duration / len(chars) if chars else 0.0
        out: List[Dict[str, Any]] = []
        cursor = start
        for i, _ch in enumerate(chars):
            nxt = end if i == len(chars) - 1 else cursor + step
            out.append({
                "char": " ",
                "start": round(cursor, 3),
                "end": round(nxt, 3),
            })
            cursor = nxt
        if out:
            out[-1]["end"] = round(end, 3)
        return out

    # The placeholder should be very short, but not exceed the segment duration.
    placeholder_each = 0.01 if duration >= 0.05 else max(duration * 0.1, 0.0)
    if punct_count:
        max_allowed = duration / max(punct_count * 10, 1)
        placeholder_each = min(placeholder_each, max_allowed)

    # Weights are accumulated on real lyric characters.
    weights = [0.0] * len(chars)
    for idx in real_indices:
        weights[idx] = 1.0

    for i, ch in enumerate(chars):
        if not flags[i]:
            continue

        if is_open_punct(ch):
            target = _nearest_real_right(flags, i)
            if target is None:
                target = _nearest_real_left(flags, i)
        elif is_close_punct(ch):
            target = _nearest_real_left(flags, i)
            if target is None:
                target = _nearest_real_right(flags, i)
        else:
            target = _nearest_real_left(flags, i)
            if target is None:
                target = _nearest_real_right(flags, i)

        if target is not None:
            weights[target] += 1.0

    total_placeholder = placeholder_each * punct_count
    if total_placeholder > duration:
        placeholder_each = duration / max(punct_count, 1)
        total_placeholder = placeholder_each * punct_count

    remaining = max(duration - total_placeholder, 0.0)
    total_weight = sum(weights[i] for i in real_indices)
    if total_weight <= 0:
        total_weight = float(len(real_indices))

    durations = [0.0] * len(chars)
    for i in range(len(chars)):
        if flags[i]:
            durations[i] = placeholder_each
        else:
            durations[i] = remaining * (weights[i] / total_weight)

    # Build the output sequentially, rounding only at the end.
    out: List[Dict[str, Any]] = []
    cursor = start
    for i, ch in enumerate(chars):
        d = durations[i]
        next_cursor = cursor + d if i < len(chars) - 1 else end
        out.append({
            "char": " " if flags[i] else ch,
            "start": round(cursor, 3),
            "end": round(next_cursor, 3),
        })
        cursor = next_cursor

    if out:
        out[-1]["end"] = round(end, 3)

    return out


def load_lrc(path: Path) -> Tuple[Dict[str, str], List[Dict[str, Any]]]:
    """Read metadata and raw timed lines from an LRC/QRC file."""
    meta: Dict[str, str] = {}
    lyric_lines: List[str] = []

    text = path.read_text(encoding="utf-8", errors="replace")
    for raw in text.splitlines():
        line = raw.strip("\ufeff").strip()
        if not line:
            continue

        m = META_RE.match(line)
        if m:
            meta[m.group(1).lower()] = m.group(2)
            continue

        lyric_lines.append(line)

    offset_sec = int(meta.get("offset", "0") or 0) / 1000.0

    parsed: List[Dict[str, Any]] = []
    for line in lyric_lines:
        result = parse_timed_line(line, offset_sec=offset_sec)
        if not result:
            continue

        timestamps, segments = result
        text_joined = "".join(segments[:-1]) if len(segments) > 1 else ""

        parsed.append({
            "start": timestamps[0],
            "end": timestamps[-1],
            "timestamps": timestamps,
            "segments": segments,
            "text": text_joined,
        })

    return meta, parsed


def build_project_json(
    lrc_path: Path,
    title_override: Optional[str] = None,
    artist_override: Optional[str] = None,
    duration_override: Optional[float] = None,
) -> Dict[str, Any]:
    meta, parsed = load_lrc(lrc_path)

    title = title_override or meta.get("ti") or lrc_path.stem
    artist = artist_override or meta.get("ar") or ""

    # Group lines by the same start time.
    groups: Dict[float, List[Dict[str, Any]]] = defaultdict(list)
    for item in parsed:
        groups[round(item["start"], 3)].append(item)

    output_lines: List[Dict[str, Any]] = []

    for start_key in sorted(groups.keys()):
        group = groups[start_key]

        # Original lyric line usually has the most timestamps.
        original = max(group, key=lambda x: len(x["timestamps"]))

        # Translation line: usually the other line that shares the same start.
        translation = None
        for candidate in group:
            if candidate is not original:
                translation = candidate
                break

        line_obj: Dict[str, Any] = {
            "start": round(original["start"], 3),
            "end": round(original["end"], 3),
            "text": visible_text(original["text"]),
            "translation": visible_text(translation["text"]) if translation else None,
            "emotion": None,
            "chars": [],
        }

        # Build per-character timing from the original line.
        for i in range(len(original["timestamps"]) - 1):
            seg = original["segments"][i]
            seg_start = original["timestamps"][i]
            seg_end = original["timestamps"][i + 1]
            line_obj["chars"].extend(distribute_segment(seg, seg_start, seg_end))

        output_lines.append(line_obj)

    duration = duration_override
    if duration is None:
        duration = max((x["end"] for x in output_lines), default=0.0)

    return {
        "title": title,
        "artist": artist,
        "duration": round(float(duration), 3),
        "lines": output_lines,
        "beats": [],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert LRC/QRC lyric file to project JSON.")
    parser.add_argument("input", type=Path, help="Input .lrc file")
    parser.add_argument("--artist", type=str, default=None, help="Override artist")
    parser.add_argument("--title", type=str, default=None, help="Override title")
    parser.add_argument("--duration", type=float, default=None, help="Override duration in seconds")
    parser.add_argument("-o", "--output", type=Path, default=None, help="Optional output .json path")
    args = parser.parse_args()

    data = build_project_json(
        args.input,
        title_override=args.title,
        artist_override=args.artist,
        duration_override=args.duration,
    )

    output_path = args.output or args.input.with_suffix(".json")
    output_path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(f"Saved: {output_path}")


if __name__ == "__main__":
    main()
