#!/usr/bin/env python3
"""Copy league JSON files with height/weight to fifa21_body/, strip from main Data/."""

from __future__ import annotations

import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = ROOT / "assets" / "Data"
DST_DIR = ROOT / "assets" / "Data" / "fifa21_body"

REPORT_NAME = "fifa21_height_weight_unmatched_report.md"


def strip_body_fields(player: dict) -> bool:
    changed = False
    if "height_cm" in player:
        player.pop("height_cm", None)
        changed = True
    if "weight_kg" in player:
        player.pop("weight_kg", None)
        changed = True
    return changed


def main() -> None:
    DST_DIR.mkdir(parents=True, exist_ok=True)

    copied: list[str] = []
    stripped: list[str] = []

    for path in sorted(SRC_DIR.glob("*.json")):
        if path.name == REPORT_NAME:
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        players = data.get("players")
        if not isinstance(players, list):
            continue

        has_body = any(p.get("height_cm") for p in players)
        if not has_body:
            continue

        dst_path = DST_DIR / path.name
        shutil.copy2(path, dst_path)
        copied.append(path.name)

        changed = False
        for player in players:
            if strip_body_fields(player):
                changed = True
        if changed:
            path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            stripped.append(path.name)

    report_src = SRC_DIR / REPORT_NAME
    if report_src.is_file():
        shutil.copy2(report_src, DST_DIR / REPORT_NAME)

    print(f"Copied {len(copied)} files to {DST_DIR.relative_to(ROOT)}:")
    for name in copied:
        print(f"  + {name}")
    print(f"Stripped height/weight from {len(stripped)} main Data files:")
    for name in stripped:
        print(f"  - {name}")


if __name__ == "__main__":
    main()
