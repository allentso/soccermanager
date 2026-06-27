#!/usr/bin/env python3
"""Remove second-division teams/players that duplicate top-tier JSON slugs."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "assets" / "Data"

PAIRS = [
    ("fm2024_premier_league.json", "second/fm2024_championship.json"),
    ("fm2024_serie_a.json", "second/fm2024_serie_b.json"),
    ("fm2024_ligue_1.json", "second/fm2024_ligue_2.json"),
]


def load_json(rel_path: str) -> dict:
    with (DATA / rel_path).open(encoding="utf-8") as f:
        return json.load(f)


def save_json(rel_path: str, data: dict) -> None:
    with (DATA / rel_path).open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def prune_second(top_rel: str, second_rel: str) -> dict:
    top = load_json(top_rel)
    second = load_json(second_rel)

    top_team_ids = {t["id"] for t in top.get("teams", [])}
    top_player_ids = {p["id"] for p in top.get("players", [])}

    overlap_teams = sorted(
        top_team_ids & {t["id"] for t in second.get("teams", [])}
    )
    overlap_set = set(overlap_teams)

    teams_before = len(second.get("teams", []))
    players_before = len(second.get("players", []))
    league = second.get("league") or {}
    fixtures_before = len(league.get("fixtures") or [])

    second["teams"] = [
        t for t in second.get("teams", []) if t.get("id") not in overlap_set
    ]
    second["players"] = [
        p
        for p in second.get("players", [])
        if p.get("team_id") not in overlap_set and p.get("id") not in top_player_ids
    ]

    if league.get("fixtures"):
        league["fixtures"] = [
            fx
            for fx in league["fixtures"]
            if fx.get("home_team_id") not in overlap_set
            and fx.get("away_team_id") not in overlap_set
        ]
        second["league"] = league

    save_json(second_rel, second)

    return {
        "file": second_rel,
        "removed_teams": overlap_teams,
        "teams": (teams_before, len(second["teams"])),
        "players": (players_before, len(second["players"])),
        "fixtures": (fixtures_before, len(league.get("fixtures") or [])),
    }


def verify_no_overlap() -> list[str]:
    errors = []
    for top_rel, second_rel in PAIRS:
        top = load_json(top_rel)
        second = load_json(second_rel)
        top_team_ids = {t["id"] for t in top.get("teams", [])}
        top_player_ids = {p["id"] for p in top.get("players", [])}
        sec_team_ids = {t["id"] for t in second.get("teams", [])}
        sec_player_ids = {p["id"] for p in second.get("players", [])}
        team_overlap = top_team_ids & sec_team_ids
        player_overlap = top_player_ids & sec_player_ids
        if team_overlap:
            errors.append(f"{second_rel}: team overlap {sorted(team_overlap)}")
        if player_overlap:
            errors.append(
                f"{second_rel}: player overlap {len(player_overlap)} ids"
            )
    return errors


def main() -> None:
    for top_rel, second_rel in PAIRS:
        stats = prune_second(top_rel, second_rel)
        print(stats["file"])
        print("  removed teams:", ", ".join(stats["removed_teams"]))
        print(
            f"  teams {stats['teams'][0]} -> {stats['teams'][1]}, "
            f"players {stats['players'][0]} -> {stats['players'][1]}, "
            f"fixtures {stats['fixtures'][0]} -> {stats['fixtures'][1]}"
        )

    errors = verify_no_overlap()
    if errors:
        raise SystemExit("verify failed:\n" + "\n".join(errors))
    print("verify ok: no top/second team or player id overlap")


if __name__ == "__main__":
    main()
