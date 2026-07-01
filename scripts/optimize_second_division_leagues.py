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

SECOND_DIV_FILL = {
    "fm2024_ligue_2.json": [
        {
            "id": "stade-malherbe-caen-calvados",
            "name": "Stade Malherbe Caen",
            "name_cn": "卡昂",
            "short_name": "SMC",
            "city": "Caen",
            "stadium_name": "Stade Michel d'Ornano",
            "stadium_capacity": 20835,
            "reputation": 520,
            "wage_budget": 205000,
            "colors": {"primary": "#0033a0", "secondary": "#ff0000"},
        },
        {
            "id": "valenciennes-fc",
            "name": "Valenciennes FC",
            "name_cn": "瓦朗谢纳",
            "short_name": "VAFC",
            "city": "Valenciennes",
            "stadium_name": "Stade du Hainaut",
            "stadium_capacity": 25200,
            "reputation": 505,
            "wage_budget": 195000,
            "colors": {"primary": "#cc0000", "secondary": "#ffffff"},
        },
    ],
    "fm2024_la_liga_2.json": [
        {
            "id": "cd-tenerife",
            "name": "CD Tenerife",
            "name_cn": "特内里费",
            "short_name": "TEN",
            "city": "Santa Cruz de Tenerife",
            "stadium_name": "Estadio Heliodoro Rodríguez López",
            "stadium_capacity": 22454,
            "reputation": 540,
            "wage_budget": 210000,
            "colors": {"primary": "#0033a0", "secondary": "#ffffff"},
            "country": "ES",
            "football_nation": "ES",
        },
        {
            "id": "real-burgos-cf",
            "name": "Real Burgos CF",
            "name_cn": "布尔戈斯",
            "short_name": "BUR",
            "city": "Burgos",
            "stadium_name": "Estadio El Plantío",
            "stadium_capacity": 12300,
            "reputation": 515,
            "wage_budget": 198000,
            "colors": {"primary": "#000000", "secondary": "#ffffff"},
            "country": "ES",
            "football_nation": "ES",
        },
    ],
    "fm2024_serie_b.json": [
        {
            "id": "ss-bari",
            "name": "SSC Bari",
            "name_cn": "巴里",
            "short_name": "BAR",
            "city": "Bari",
            "stadium_name": "Stadio San Nicola",
            "stadium_capacity": 58248,
            "reputation": 530,
            "wage_budget": 205000,
            "colors": {"primary": "#cc0000", "secondary": "#ffffff"},
            "country": "IT",
            "football_nation": "IT",
        },
        {
            "id": "spezia-calcio",
            "name": "Spezia Calcio",
            "name_cn": "斯佩齐亚",
            "short_name": "SPE",
            "city": "La Spezia",
            "stadium_name": "Stadio Alberto Picco",
            "stadium_capacity": 10336,
            "reputation": 508,
            "wage_budget": 192000,
            "colors": {"primary": "#ffffff", "secondary": "#000000"},
            "country": "IT",
            "football_nation": "IT",
        },
    ],
}


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
    country = spec.get("country", "FR")
    team.update(
        {
            "id": spec["id"],
            "name": spec["name"],
            "short_name": spec["short_name"],
            "country": country,
            "football_nation": spec.get("football_nation", country),
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
    if spec.get("name_cn"):
        team["name_cn"] = spec["name_cn"]
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


def add_fill_teams(data: dict, needed: int, blocked_ids: set[str], specs: list[dict]) -> list[str]:
    template = data["teams"][0]
    added: list[str] = []
    for spec in specs:
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
            f"Could only add {len(added)} teams, still need {needed - len(added)}"
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
        fill_specs = SECOND_DIV_FILL.get(path.name)
        if not fill_specs:
            raise RuntimeError(f"{path.name}: {len(teams)} teams, cannot reach {TARGET_TEAMS}")
        added = add_fill_teams(data, need, blocked_team_ids, fill_specs)
        teams = data["teams"]

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
    top_name_sets = []
    for name in TOP_FILES:
        top = load_json(DATA / name)
        top_name_sets.append({t.get("name_cn") or t["name"] for t in top.get("teams", [])})
    for name in SECOND_FILES:
        data = load_json(SECOND / name)
        assert len(data["teams"]) == TARGET_TEAMS, name
        team_ids = {t["id"] for t in data["teams"]}
        assert not (team_ids & blocked), f"{name} overlaps top tier: {team_ids & blocked}"
        sec_names = {t.get("name_cn") or t["name"] for t in data["teams"]}
        for top_names in top_name_sets:
            overlap = sec_names & top_names
            assert not overlap, f"{name} name_cn overlap with top tier: {sorted(overlap)}"
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
