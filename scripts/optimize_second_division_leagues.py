#!/usr/bin/env python3
"""Normalize second-division JSON leagues to 18 clubs and rebalance removed rosters."""

from __future__ import annotations

import copy
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "assets" / "Data"
SECOND = DATA / "second"

TARGET_TEAMS = 18

SECOND_FILES = [
    "fm2024_championship.json",
    "fm2024_la_liga_2.json",
    "fm2024_serie_b.json",
    "fm2024_bundesliga_2.json",
    "fm2024_ligue_2.json",
]

TOP_FILES = [
    "fm2024_premier_league.json",
    "fm2024_la_liga.json",
    "fm2024_serie_a.json",
    "fm2024_bundesliga.json",
    "fm2024_ligue_1.json",
]

LIGUE2_ADDITIONS = [
    {
        "id": "en-avant-guingamp",
        "name": "En Avant Guingamp",
        "short_name": "EAG",
        "city": "Guingamp",
        "stadium_name": "Stade du Roudourou",
        "stadium_capacity": 18126,
        "reputation": 548,
        "wage_budget": 215000,
        "colors": {"primary": "#e30613", "secondary": "#ffffff"},
    },
    {
        "id": "stade-lavallois-mayenne-fc",
        "name": "Stade Lavallois Mayenne FC",
        "short_name": "SLM",
        "city": "Laval",
        "stadium_name": "Stade Francis Le Basser",
        "stadium_capacity": 18900,
        "reputation": 512,
        "wage_budget": 200000,
        "colors": {"primary": "#ff6600", "secondary": "#000000"},
    },
    {
        "id": "sporting-club-de-bastia",
        "name": "Sporting Club de Bastia",
        "short_name": "SCB",
        "city": "Bastia",
        "stadium_name": "Stade Armand Cesari",
        "stadium_capacity": 16480,
        "reputation": 558,
        "wage_budget": 225000,
        "colors": {"primary": "#004996", "secondary": "#ffffff"},
    },
    {
        "id": "paris-fc",
        "name": "Paris FC",
        "short_name": "PFC",
        "city": "Paris",
        "stadium_name": "Stade Charlety",
        "stadium_capacity": 20000,
        "reputation": 572,
        "wage_budget": 240000,
        "colors": {"primary": "#002b87", "secondary": "#ffffff"},
    },
    {
        "id": "usl-dunkerque",
        "name": "USL Dunkerque",
        "short_name": "USL",
        "city": "Dunkerque",
        "stadium_name": "Stade Marcel Tribut",
        "stadium_capacity": 4933,
        "reputation": 498,
        "wage_budget": 200000,
        "colors": {"primary": "#0066cc", "secondary": "#ffffff"},
    },
]


def load_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def save_json(path: Path, data: dict) -> None:
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def top_team_ids() -> set[str]:
    ids: set[str] = set()
    for name in TOP_FILES:
        for team in load_json(DATA / name).get("teams", []):
            ids.add(team["id"])
    return ids


def make_team_from_template(template: dict, spec: dict) -> dict:
    team = copy.deepcopy(template)
    rep = spec["reputation"]
    wb = spec["wage_budget"]
    team.update(
        {
            "id": spec["id"],
            "name": spec["name"],
            "short_name": spec["short_name"],
            "country": "FR",
            "football_nation": "FR",
            "city": spec["city"],
            "stadium_name": spec["stadium_name"],
            "stadium_capacity": spec["stadium_capacity"],
            "finance": rep * 10000,
            "manager_id": None,
            "reputation": rep,
            "wage_budget": wb,
            "transfer_budget": wb * 12,
            "season_income": 0,
            "season_expenses": 0,
            "financial_ledger": [],
            "sponsorship": None,
            "facilities": {"training": 1, "medical": 1, "scouting": 1},
            "formation": "4-4-2",
            "play_style": "Balanced",
            "training_focus": "Physical",
            "training_intensity": "Medium",
            "training_schedule": "Balanced",
            "training_groups": [],
            "founded_year": 1900,
            "colors": spec["colors"],
            "starting_xi_ids": [],
            "match_roles": {
                "captain": None,
                "vice_captain": None,
                "penalty_taker": None,
                "free_kick_taker": None,
                "corner_taker": None,
            },
            "form": [],
            "history": [],
        }
    )
    return team


def player_counts(team_ids: list[str], players: list[dict]) -> Counter:
    counts = Counter({tid: 0 for tid in team_ids})
    for player in players:
        tid = player.get("team_id")
        if tid in counts:
            counts[tid] += 1
    return counts


def pick_teams_to_remove(teams: list[dict], players: list[dict], remove_n: int) -> list[str]:
    counts = player_counts([t["id"] for t in teams], players)
    ranked = sorted(
        teams,
        key=lambda t: (counts[t["id"]], t.get("reputation") or 0, t["id"]),
    )
    return [t["id"] for t in ranked[:remove_n]]


def redistribute_orphans(
    players: list[dict],
    orphans: list[dict],
    remaining_team_ids: list[str],
) -> tuple[list[dict], int]:
    if not orphans:
        return players, 0

    counts = player_counts(remaining_team_ids, players)
    moved = 0
    for player in orphans:
        target = min(remaining_team_ids, key=lambda tid: (counts[tid], tid))
        reassigned = dict(player)
        reassigned["team_id"] = target
        players.append(reassigned)
        counts[target] += 1
        moved += 1
    return players, moved


def prune_fixtures(data: dict, removed_team_ids: set[str]) -> int:
    league = data.get("league") or {}
    fixtures = league.get("fixtures") or []
    if not fixtures:
        return 0
    before = len(fixtures)
    league["fixtures"] = [
        fx
        for fx in fixtures
        if fx.get("home_team_id") not in removed_team_ids
        and fx.get("away_team_id") not in removed_team_ids
    ]
    data["league"] = league
    return before - len(league["fixtures"])


def add_ligue2_teams(data: dict, needed: int, blocked_ids: set[str]) -> list[str]:
    template = next(t for t in data["teams"] if t["id"] == "rodez-af")
    added: list[str] = []
    for spec in LIGUE2_ADDITIONS:
        if len(added) >= needed:
            break
        if spec["id"] in blocked_ids:
            continue
        if any(t["id"] == spec["id"] for t in data["teams"]):
            continue
        data["teams"].append(make_team_from_template(template, spec))
        added.append(spec["id"])
    if len(added) < needed:
        raise RuntimeError(
            f"Could only add {len(added)} Ligue 2 teams, still need {needed - len(added)}"
        )
    return added


def balance_rosters(teams: list[dict], players: list[dict]) -> int:
    """Move players from deep rosters to empty/thin clubs (lowest OVR first)."""
    team_ids = [t["id"] for t in teams]
    moved = 0
    while True:
        counts = player_counts(team_ids, players)
        if not team_ids:
            break
        avg = sum(counts.values()) / len(team_ids)
        recipients = sorted(
            [tid for tid in team_ids if counts[tid] < max(3, int(avg))],
            key=lambda tid: (counts[tid], tid),
        )
        if not recipients:
            break
        recipient = recipients[0]
        donors = sorted(
            [tid for tid in team_ids if counts[tid] > counts[recipient] + 1],
            key=lambda tid: (-counts[tid], tid),
        )
        if not donors:
            break
        donor = donors[0]
        donor_players = [
            p for p in players if p.get("team_id") == donor
        ]
        if not donor_players:
            break
        donor_players.sort(key=lambda p: (p.get("ovr") or 0, p.get("id") or ""))
        pick = donor_players[0]
        pick["team_id"] = recipient
        moved += 1
    return moved


def optimize_file(path: Path, blocked_team_ids: set[str]) -> dict:
    data = load_json(path)
    teams = data.get("teams", [])
    players = data.get("players", [])
    removed: list[str] = []
    added: list[str] = []
    moved = 0
    fixtures_removed = 0

    if len(teams) > TARGET_TEAMS:
        remove_n = len(teams) - TARGET_TEAMS
        removed = pick_teams_to_remove(teams, players, remove_n)
        removed_set = set(removed)
        orphans = [p for p in players if p.get("team_id") in removed_set]
        players = [p for p in players if p.get("team_id") not in removed_set]
        teams = [t for t in teams if t["id"] not in removed_set]
        remaining_ids = [t["id"] for t in teams]
        players, moved = redistribute_orphans(players, orphans, remaining_ids)
        fixtures_removed = prune_fixtures(data, removed_set)

    if len(teams) < TARGET_TEAMS:
        need = TARGET_TEAMS - len(teams)
        if path.name == "fm2024_ligue_2.json":
            added = add_ligue2_teams(data, need, blocked_team_ids)
            teams = data["teams"]
        else:
            raise RuntimeError(f"{path.name}: {len(teams)} teams, cannot reach {TARGET_TEAMS}")

    balanced = balance_rosters(teams, players)

    data["teams"] = teams
    data["players"] = players
    save_json(path, data)

    counts = player_counts([t["id"] for t in teams], players)
    count_values = list(counts.values())
    return {
        "file": path.name,
        "teams": len(teams),
        "players": len(players),
        "removed": removed,
        "added": added,
        "players_moved": moved,
        "players_balanced": balanced,
        "fixtures_removed": fixtures_removed,
        "min_players": min(count_values) if count_values else 0,
        "max_players": max(count_values) if count_values else 0,
        "avg_players": round(sum(count_values) / len(count_values), 1) if count_values else 0,
    }


def verify() -> None:
    blocked = top_team_ids()
    for name in SECOND_FILES:
        data = load_json(SECOND / name)
        assert len(data["teams"]) == TARGET_TEAMS, name
        team_ids = {t["id"] for t in data["teams"]}
        assert not (team_ids & blocked), f"{name} overlaps top tier: {team_ids & blocked}"
        for player in data["players"]:
            assert player.get("team_id") in team_ids, f"{name} orphan player {player.get('id')}"


def main() -> None:
    blocked = top_team_ids()
    for name in SECOND_FILES:
        stats = optimize_file(SECOND / name, blocked)
        print(f"{stats['file']}: {stats['teams']} teams, {stats['players']} players")
        print(
            f"  roster min/avg/max = {stats['min_players']}/{stats['avg_players']}/{stats['max_players']}"
        )
        if stats["removed"]:
            print(f"  removed teams: {', '.join(stats['removed'])}")
            print(f"  redistributed players: {stats['players_moved']}")
        if stats["added"]:
            print(f"  added teams: {', '.join(stats['added'])}")
        if stats["fixtures_removed"]:
            print(f"  fixtures pruned: {stats['fixtures_removed']}")
        if stats["players_balanced"]:
            print(f"  balance moves: {stats['players_balanced']}")

    verify()
    print("verify ok: all second divisions have 18 teams, no top-tier slug overlap")


if __name__ == "__main__":
    main()
