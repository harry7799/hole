#!/usr/bin/env python3
"""Rebuild and validate the five approved prey sprites.

The generated source renders use a chroma-key background. The installed
imagegen helper creates the matte; this script then centers each visible
subject on the exact 256 px runtime canvas used by Godot.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image


@dataclass(frozen=True)
class PreyAsset:
    source: str
    output: str


ASSETS = (
    PreyAsset("exec-09dca9c8-9a11-4ae7-9581-0cad116f21fe.png", "Art/Prey/prey_photon_mote.png"),
    PreyAsset("exec-b5dcd067-810d-4173-bc0f-98b5a2fa9b81.png", "Art/Prey/prey_plasma_seed.png"),
    PreyAsset("exec-298070d2-4d21-4aeb-9c1d-cd7855130951.png", "Art/Prey/prey_nebula_prism.png"),
    PreyAsset("exec-eedbca6e-2e88-4f53-bbc0-a395f3b6282e.png", "Art/Prey/prey_pulsar_core.png"),
    PreyAsset("exec-884899d7-80e6-424b-9408-fb866b439d1d.png", "Art/Prey/prey_quantum_relic.png"),
)

CANVAS_SIZE = (256, 256)
MAX_SUBJECT_SIZE = (208, 208)


def default_helper() -> Path:
    codex_home = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
    return codex_home / "skills/.system/imagegen/scripts/remove_chroma_key.py"


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A")
    bbox = alpha.point(lambda value: 255 if value > 2 else 0).getbbox()
    if bbox is None:
        raise ValueError("chroma removal produced an empty image")
    return bbox


def green_fringe_count(image: Image.Image) -> int:
    count = 0
    for red, green, blue, alpha in image.getdata():
        if 0 < alpha < 255 and green > 96 and green > max(red, blue) * 1.35:
            count += 1
    return count


def clean_residual_green_fringe(image: Image.Image) -> Image.Image:
    cleaned = image.copy()
    pixels = cleaned.load()
    for y in range(cleaned.height):
        for x in range(cleaned.width):
            red, green, blue, alpha = pixels[x, y]
            if 0 < alpha < 255 and green > 96 and green > max(red, blue) * 1.35:
                pixels[x, y] = (red, min(green, max(red, blue)), blue, alpha)
    return cleaned


def remove_chroma(helper: Path, source: Path, output: Path, edge_contract: int = 0) -> None:
    command = [
        sys.executable,
        str(helper),
        "--input", str(source),
        "--out", str(output),
        "--auto-key", "border",
        "--soft-matte",
        "--transparent-threshold", "12",
        "--opaque-threshold", "220",
        "--despill",
        "--force",
    ]
    if edge_contract:
        command.extend(("--edge-contract", str(edge_contract)))
    subprocess.run(command, check=True)


def normalize(cutout_path: Path, output_path: Path) -> None:
    source = Image.open(cutout_path).convert("RGBA")
    cropped = source.crop(alpha_bbox(source))
    ratio = min(MAX_SUBJECT_SIZE[0] / cropped.width, MAX_SUBJECT_SIZE[1] / cropped.height)
    size = (max(1, round(cropped.width * ratio)), max(1, round(cropped.height * ratio)))
    resized = cropped.convert("RGBa").resize(size, Image.Resampling.LANCZOS).convert("RGBA")
    canvas = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    position = ((256 - resized.width) // 2, (256 - resized.height) // 2)
    canvas.alpha_composite(resized, position)
    canvas = clean_residual_green_fringe(canvas)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output_path, format="PNG", optimize=True)


def validate(path: Path) -> str:
    image = Image.open(path).convert("RGBA")
    if image.size != CANVAS_SIZE:
        raise ValueError(f"{path}: expected {CANVAS_SIZE}, got {image.size}")
    corners = tuple(image.getpixel(point)[3] for point in ((0, 0), (255, 0), (0, 255), (255, 255)))
    if max(corners) != 0:
        raise ValueError(f"{path}: corners are not transparent: {corners}")
    fringe = green_fringe_count(image)
    if fringe:
        raise ValueError(f"{path}: {fringe} green fringe pixels remain")
    bbox = alpha_bbox(image)
    center = ((bbox[0] + bbox[2]) * 0.5, (bbox[1] + bbox[3]) * 0.5)
    if abs(center[0] - 128.0) > 2.0 or abs(center[1] - 128.0) > 2.0:
        raise ValueError(f"{path}: visible bounds are not centered: bbox={bbox}")
    return f"{path}: RGBA bbox={bbox} corners={corners} fringe=0"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--helper", type=Path, default=default_helper())
    parser.add_argument("--work-dir", type=Path)
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()

    project_root = args.project_root.resolve()
    if args.validate_only:
        for asset in ASSETS:
            print(validate(project_root / asset.output))
        return 0
    if args.source_dir is None:
        parser.error("--source-dir is required unless --validate-only is used")

    source_dir = args.source_dir.resolve()
    helper = args.helper.resolve()
    if not helper.is_file():
        raise FileNotFoundError(helper)
    work_dir = (args.work_dir or project_root / "tmp/imagegen/prey_work").resolve()
    work_dir.mkdir(parents=True, exist_ok=True)

    for asset in ASSETS:
        source = source_dir / asset.source
        output = project_root / asset.output
        if not source.is_file():
            raise FileNotFoundError(source)
        cutout = work_dir / f"{source.stem}-cutout.png"
        remove_chroma(helper, source, cutout)
        if green_fringe_count(Image.open(cutout).convert("RGBA")):
            remove_chroma(helper, source, cutout, edge_contract=1)
        normalize(cutout, output)
        print(validate(output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
