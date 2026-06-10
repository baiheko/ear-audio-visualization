#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Convert a QRC/LRC lyric file into the JSON structure used by your project.

Features:
- Read [ti:], [ar:], [offset:] and other metadata
- Support lines with per-character timestamps:
    [00:11.053]些[00:11.408]細... [00:21.740]
- Support paired translation lines:
    [00:11.053]中文翻译[00:22.390]
- Generate:
    title, artist, duration, lines[{start,end,text,translation,emotion,chars}], beats:[]
"""

from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

TIMESTAMP_RE = re.compile(r"\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?\]")
META_RE = re.compile(r"^\[(ti|ar|al|by|offset|re|ve):(.*?)\]$", re.I)


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


def split_chars(text: str) -> List[str]:
    """
    Split into characters for the JSON char-level timeline.
    For Japanese/Chinese lyrics, code-point splitting is enough in practice.
    """
    return list(text)


def distribute_segment(seg: str, start: float, end: float) -> List[Dict[str, Any]]:
    """
    Spread a text segment evenly across its characters.
    Example:
      seg="細やか"  start=10  end=13
    -> 3 char objects with equal subranges.
    """
    if not seg:
        return []

    chars = split_chars(seg)
    duration = max(end - start, 0.0)
    step = duration / len(chars) if chars else 0.0

    out: List[Dict[str, Any]] = []
    for i, ch in enumerate(chars):
        out.append({
            "char": ch,
            "start": round(start + step * i, 3),
            "end": round(start + step * (i + 1), 3),
        })
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
        # The actual visible text is the concatenation of all text pieces
        # except the final empty tail after the last timestamp.
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

    title = title_override or meta.get("ti") or ""
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
            "text": original["text"],
            "translation": translation["text"] if translation else None,
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
    parser.add_argument("-o", "--output", type=Path, required=True, help="Output .json file")
    parser.add_argument("--title", type=str, default=None, help="Override title")
    parser.add_argument("--artist", type=str, default=None, help="Override artist")
    parser.add_argument("--duration", type=float, default=None, help="Override duration in seconds")
    args = parser.parse_args()

    data = build_project_json(
        args.input,
        title_override=args.title,
        artist_override=args.artist,
        duration_override=args.duration,
    )

    args.output.write_text(
        json.dumps(data, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(f"Saved: {args.output}")


if __name__ == "__main__":
    main()
