#!/usr/bin/env python3
"""Composite the code-generated English text overlays onto the instrumental film."""

from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / ".english_video_build"
SOURCE = ROOT / "MomentFlow_Intro_Instrumental_1080p60.mp4"
OUTPUT = ROOT / "MomentFlow_Intro_English_1080p60.mp4"
OVERLAYS = BUILD / "overlays"

LAYERS = [
    ("scene1_base.png", 0.00, 2.00),
    ("scene1_ready.png", 0.35, 0.98),
    ("scene1_rec.png", 0.98, 2.00),
    ("scene1_caption.png", 0.15, 1.98),
    ("scene2_base.png", 2.00, 4.00),
    ("scene2_caption.png", 2.15, 3.94),
    ("scene3_base.png", 4.00, 6.00),
    ("scene3_caption.png", 4.12, 5.94),
    ("scene4_base.png", 6.00, 8.00),
    ("scene4_caption.png", 6.12, 7.94),
    ("scene5_base.png", 8.00, 10.00),
    ("scene5_caption.png", 8.12, 9.94),
    ("scene6_base.png", 10.00, 12.00),
    ("scene6_caption.png", 10.12, 11.94),
    ("scene7_base.png", 12.00, 14.00),
    ("scene7_caption.png", 12.13, 13.74),
    ("scene8_base.png", 14.00, 15.00),
    ("scene8_caption.png", 14.00, 14.98),
]


def main() -> None:
    command = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(SOURCE)]
    for file_name, _, _ in LAYERS:
        command.extend(["-loop", "1", "-framerate", "60", "-i", str(OVERLAYS / file_name)])

    filters: list[str] = []
    latest = "[0:v]"
    for index, (_, start, end) in enumerate(LAYERS, start=1):
        output = f"[v{index}]"
        filters.append(
            f"{latest}[{index}:v]overlay=0:0:enable='between(t,{start},{end})'{output}"
        )
        latest = output

    command.extend(
        [
            "-filter_complex",
            ";".join(filters),
            "-map",
            latest,
            "-map",
            "0:a:0",
            "-c:v",
            "libx264",
            "-preset",
            "medium",
            "-crf",
            "18",
            "-pix_fmt",
            "yuv420p",
            "-profile:v",
            "high",
            "-level",
            "4.2",
            "-colorspace",
            "bt709",
            "-color_primaries",
            "bt709",
            "-color_trc",
            "bt709",
            "-color_range",
            "tv",
            "-c:a",
            "copy",
            "-t",
            "15",
            "-movflags",
            "+faststart",
            str(OUTPUT),
        ]
    )
    subprocess.run(command, check=True)
    print(f"Rendered {OUTPUT}")


if __name__ == "__main__":
    main()
