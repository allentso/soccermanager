#!/usr/bin/env python3
"""Validate legends_alltime_defenders_30.json and merged pool."""
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOP50 = ROOT / "assets/Data/legends_alltime_top50.json"
DEF = ROOT / "assets/Data/legends_alltime_defenders_30.json"

DEF_COUNT = 25
MERGED_COUNT = 75


def load_players(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)["players"]


def main():
    top50 = load_players(TOP50)
    defenders = load_players(DEF)
    errors = []

    if len(top50) != 50:
        errors.append(f"top50 count {len(top50)} != 50")
    if len(defenders) != DEF_COUNT:
        errors.append(f"defenders count {len(defenders)} != {DEF_COUNT}")

    c = Counter(p["position"] for p in defenders)
    expected = {
        "Goalkeeper": 4,
        "CentreBack": 10,
        "DefensiveMidfielder": 6,
        "LeftBack": 2,
        "RightBack": 2,
        "Striker": 1,
    }
    for pos, n in expected.items():
        if c.get(pos, 0) != n:
            errors.append(f"defenders {pos}: {c.get(pos, 0)} != {n}")

    names = set()
    for p in top50 + defenders:
        key = p.get("full_name_cn") or p.get("match_name")
        if key in names:
            errors.append(f"duplicate name: {key}")
        names.add(key)

    if len(names) != MERGED_COUNT:
        errors.append(f"merged unique names {len(names)} != {MERGED_COUNT}")

    if errors:
        for e in errors:
            print("FAIL:", e)
        sys.exit(1)

    print("OK")
    print(len(top50))
    print(len(defenders))
    print(len(names))


if __name__ == "__main__":
    main()
