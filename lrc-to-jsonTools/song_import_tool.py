#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Import one song into the Flutter music player project.

What it does:
1) Copies the audio file into assets/audio with a short name.
2) Converts the LRC/QRC lyric file into the project's JSON format.
3) Copies the JSON into assets/lyrics with the same short name.
4) Appends a SongPreset entry into lib/config/song_presets.dart.

Recommended usage:
    python song_import_tool.py \
        --audio "原始音频文件路径" \
        --lrc "原始歌词文件路径" \
        --id "short_name" \
        --title "歌曲名" \
        --artist "歌手名"

Optional:
    --motion soft|normal|strong
    --duration 281.483
    --project-root "F:\\桌面\\document\\musicplayer\\ear"

The script is designed to be run inside the folder that contains this file,
or with --project-root explicitly pointing to the Flutter project root.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

# Reuse the lyric converter logic if the file is placed next to this script.
try:
    from lrc_to_json_converter_v2 import build_project_json
except Exception:  # pragma: no cover - fallback if import path is different
    build_project_json = None


MOTION_VALUES = {"soft", "normal", "strong"}


def ensure_converter_available() -> None:
    if build_project_json is None:
        raise RuntimeError(
            "Could not import build_project_json from lrc_to_json_converter_v2.py. "
            "Put this script in the same folder as lrc_to_json_converter_v2.py, or adjust PYTHONPATH."
        )


def short_asset_name(value: str) -> str:
    """Keep an asset name short and file-system safe."""
    value = value.strip().replace("\\", "_").replace("/", "_")
    value = re.sub(r"\s+", "_", value)
    value = re.sub(r"[<>:\"|?*]", "_", value)
    value = re.sub(r"_+", "_", value).strip("_ .")
    if not value:
        raise ValueError("Asset name resolved to empty string. Please provide --id.")
    return value


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def write_text(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")


def copy_with_short_name(src: Path, dst_dir: Path, short_name: str, overwrite: bool = True) -> Path:
    dst_dir.mkdir(parents=True, exist_ok=True)
    dst = dst_dir / f"{short_name}{src.suffix.lower()}"
    if dst.exists() and not overwrite:
        raise FileExistsError(f"Target file already exists: {dst}")
    shutil.copy2(src, dst)
    return dst


@dataclass
class DartPresetPaths:
    dart_file: Path
    audio_asset_root: str = "assets/audio"
    lyric_asset_root: str = "assets/lyrics"


def motion_default_value(motion: str) -> str:
    if motion not in MOTION_VALUES:
        raise ValueError(f"Invalid motion preset: {motion!r}. Use one of: {sorted(MOTION_VALUES)}")
    return motion


def build_song_preset_entry(
    song_id: str,
    title: str,
    artist: str,
    lyric_asset: str,
    audio_asset: str,
    offset_ms: float = 0,
    motion: str = "normal",
) -> str:
    motion = motion_default_value(motion)
    # Keep formatting aligned with the user's existing style.
    return f"""  SongPreset(
    id: '{song_id}',
    title: {json.dumps(title, ensure_ascii=False)},
    artist: {json.dumps(artist, ensure_ascii=False)},
    lyricAsset: {json.dumps(lyric_asset, ensure_ascii=False)},
    audioAsset: {json.dumps(audio_asset, ensure_ascii=False)},
    defaultOffsetMs: {int(offset_ms) if float(offset_ms).is_integer() else offset_ms},
    defaultMotion: LyricMotionPreset.{motion},
  ),"""


def update_song_presets_dart(
    dart_file: Path,
    new_entry: str,
    song_id: str,
    backup: bool = True,
) -> None:
    """Append a SongPreset to the demoSongPresets list if id doesn't already exist."""
    if not dart_file.exists():
        raise FileNotFoundError(f"Dart config file not found: {dart_file}")

    original = read_text(dart_file)

    # Prevent accidental duplicate insertion.
    if re.search(rf"id:\s*'{re.escape(song_id)}'", original):
        raise ValueError(f"Song id already exists in song_presets.dart: {song_id}")

    # Find the preset list and insert before its closing bracket.
    pattern = re.compile(r"(const\s+demoSongPresets\s*=\s*<SongPreset>\s*\[)(.*?)(\n\];)", re.S)
    m = pattern.search(original)
    if not m:
        raise RuntimeError("Could not find demoSongPresets list in song_presets.dart")

    prefix, body, suffix = m.group(1), m.group(2), m.group(3)

    body_stripped = body.rstrip()
    if body_stripped and not body_stripped.endswith("\n"):
        body_stripped += "\n"

    if body_stripped.strip():
        if not body_stripped.endswith("\n\n"):
            body_stripped += "\n"
        updated_body = body_stripped + new_entry + "\n"
    else:
        updated_body = "\n" + new_entry + "\n"

    updated = original[: m.start()] + prefix + updated_body + suffix + original[m.end() :]

    if backup:
        backup_path = dart_file.with_suffix(dart_file.suffix + ".bak")
        if not backup_path.exists():
            shutil.copy2(dart_file, backup_path)

    write_text(dart_file, updated)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Import audio + LRC into Flutter assets and update song_presets.dart"
    )
    parser.add_argument("--audio", required=True, type=Path, help="Original audio file path")
    parser.add_argument("--lrc", required=True, type=Path, help="Original lyric file path")
    parser.add_argument("--id", required=True, help="Short asset id, e.g. sasanohani")
    parser.add_argument("--title", required=True, help="Song title")
    parser.add_argument("--artist", required=True, help="Song artist")
    parser.add_argument(
        "--motion",
        default="normal",
        choices=sorted(MOTION_VALUES),
        help="Default motion preset for this song",
    )
    parser.add_argument(
        "--duration",
        type=float,
        default=None,
        help="Optional duration override in seconds",
    )
    parser.add_argument(
        "--offset-ms",
        type=float,
        default=0,
        help="Default offset in ms written to SongPreset",
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=None,
        help="Flutter project root (folder containing assets/ and lib/)",
    )
    parser.add_argument(
        "--dart-file",
        type=Path,
        default=None,
        help="Optional direct path to song_presets.dart",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show planned actions without writing files",
    )
    parser.add_argument(
        "--no-backup",
        action="store_true",
        help="Do not create a .bak backup for song_presets.dart",
    )
    parser.add_argument(
        "--keep-original-names",
        action="store_true",
        help="Also copy files using original names (not recommended for Flutter asset paths)",
    )
    args = parser.parse_args()

    ensure_converter_available()

    audio_src = args.audio.expanduser().resolve()
    lrc_src = args.lrc.expanduser().resolve()
    if not audio_src.exists():
        raise FileNotFoundError(f"Audio file not found: {audio_src}")
    if not lrc_src.exists():
        raise FileNotFoundError(f"Lyric file not found: {lrc_src}")

    song_id = short_asset_name(args.id)

    if args.dart_file is not None:
        dart_file = args.dart_file.expanduser().resolve()
        project_root = dart_file.parents[2]
    else:
        if args.project_root is not None:
            project_root = args.project_root.expanduser().resolve()
        else:
            # Default: assume this script sits in <project_root>/lrc-to-jsonTools/
            project_root = Path(__file__).resolve().parent.parent
        dart_file = project_root / "lib" / "config" / "song_presets.dart"

    assets_audio_dir = project_root / "assets" / "audio"
    assets_lyrics_dir = project_root / "assets" / "lyrics"

    audio_target = assets_audio_dir / f"{song_id}{audio_src.suffix.lower()}"
    lyric_target = assets_lyrics_dir / f"{song_id}.json"

    if args.keep_original_names:
        alt_audio_target = assets_audio_dir / audio_src.name
        alt_lyric_target = assets_lyrics_dir / f"{lrc_src.stem}.json"
    else:
        alt_audio_target = None
        alt_lyric_target = None

    data = build_project_json(
        lrc_src,
        title_override=args.title,
        artist_override=args.artist,
        duration_override=args.duration,
    )

    data["title"] = args.title
    data["artist"] = args.artist

    new_entry = build_song_preset_entry(
        song_id=song_id,
        title=args.title,
        artist=args.artist,
        lyric_asset=f"assets/lyrics/{song_id}.json",
        audio_asset=f"assets/audio/{song_id}{audio_src.suffix.lower()}",
        offset_ms=args.offset_ms,
        motion=args.motion,
    )

    print("Planned actions:")
    print(f"  Audio: {audio_src} -> {audio_target}")
    print(f"  Lyrics: {lrc_src} -> {lyric_target}")
    print(f"  Dart: {dart_file}")
    print(f"  Preset id: {song_id}")

    if args.dry_run:
        print("Dry-run mode enabled; no files were written.")
        return 0

    # Copy audio
    assets_audio_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(audio_src, audio_target)
    if alt_audio_target is not None and alt_audio_target != audio_target:
        shutil.copy2(audio_src, alt_audio_target)

    # Write lyric JSON
    assets_lyrics_dir.mkdir(parents=True, exist_ok=True)
    lyric_target.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    if alt_lyric_target is not None and alt_lyric_target != lyric_target:
        alt_lyric_target.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    # Update Dart config
    update_song_presets_dart(
        dart_file=dart_file,
        new_entry=new_entry,
        song_id=song_id,
        backup=not args.no_backup,
    )

    print("Done.")
    print(f"  Audio saved to: {audio_target}")
    print(f"  Lyrics saved to: {lyric_target}")
    print(f"  Updated config: {dart_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
