#!/usr/bin/env python3
"""Fill second-division JSON squads to at least MIN_SQUAD players per team."""

from __future__ import annotations

import json
import random
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SECOND = ROOT / "assets" / "Data" / "second"

MIN_SQUAD = 13
RANDOM_SEED = 20260627

SECOND_FILES = [
    "fm2024_championship.json",
    "fm2024_la_liga_2.json",
    "fm2024_serie_b.json",
    "fm2024_bundesliga_2.json",
    "fm2024_ligue_2.json",
]

POSITION_GROUPS: dict[str, list[str]] = {
    "GK": ["Goalkeeper"],
    "DEF": ["CentreBack", "LeftBack", "RightBack"],
    "MID": ["DefensiveMidfielder", "CentralMidfielder", "AttackingMidfielder"],
    "FWD": ["Striker", "LeftWinger", "RightWinger"],
}

GROUP_TARGETS = {"GK": 1, "DEF": 4, "MID": 5, "FWD": 3}

OUTFIELD_ATTRS = [
    "pace", "stamina", "strength", "agility", "passing", "shooting", "tackling",
    "dribbling", "defending", "positioning", "vision", "decisions", "composure",
    "aggression", "teamwork", "leadership", "handling", "reflexes", "aerial",
]

NAME_POOLS: dict[str, tuple[list[str], list[str]]] = {
    "ENG": (
        ["James", "Oliver", "Harry", "George", "Jack", "Charlie", "Thomas", "William"],
        ["Smith", "Jones", "Brown", "Taylor", "Wilson", "Davies", "Evans", "Walker"],
    ),
    "ES": (
        ["Carlos", "Miguel", "Pablo", "Diego", "Sergio", "Alvaro", "Marcos", "Ruben"],
        ["Garcia", "Martinez", "Lopez", "Sanchez", "Perez", "Gonzalez", "Rodriguez", "Fernandez"],
    ),
    "IT": (
        ["Luca", "Marco", "Giuseppe", "Andrea", "Matteo", "Francesco", "Alessio", "Davide"],
        ["Rossi", "Russo", "Ferrari", "Esposito", "Bianchi", "Romano", "Colombo", "Ricci"],
    ),
    "DE": (
        ["Lukas", "Jonas", "Felix", "Max", "Paul", "Leon", "Tim", "Niklas"],
        ["Muller", "Schmidt", "Schneider", "Fischer", "Weber", "Meyer", "Wagner", "Becker"],
    ),
    "FR": (
        ["Lucas", "Hugo", "Louis", "Nathan", "Enzo", "Theo", "Mathis", "Clement"],
        ["Martin", "Bernard", "Petit", "Robert", "Richard", "Durand", "Moreau", "Simon"],
    ),
}

COUNTRY_NAT = {
    "ENG": "ENG",
    "ES": "ES",
    "IT": "IT",
    "DE": "DE",
    "FR": "FR",
}


def classify_position(position: str) -> str:
    for group, positions in POSITION_GROUPS.items():
        if position in positions:
            return group
    return "MID"


def pick_next_position(existing: list[dict], rng: random.Random) -> str:
    counts = Counter(classify_position(p.get("position", "")) for p in existing)
    group = max(GROUP_TARGETS, key=lambda g: GROUP_TARGETS[g] - counts.get(g, 0))
    return rng.choice(POSITION_GROUPS[group])


def clamp(v: int, lo: int = 1, hi: int = 99) -> int:
    return max(lo, min(hi, v))


def gen_attributes(position: str, ovr: int, rng: random.Random) -> dict[str, int]:
    base = max(25, int(ovr * 6.5))
    attrs = {k: clamp(base + rng.randint(-10, 10)) for k in OUTFIELD_ATTRS}
    if position == "Goalkeeper":
        attrs["handling"] = clamp(ovr * 7 + rng.randint(-5, 5))
        attrs["reflexes"] = clamp(ovr * 7 + rng.randint(-5, 5))
        attrs["aerial"] = clamp(ovr * 6 + rng.randint(-5, 5))
        attrs["positioning"] = clamp(ovr * 6 + rng.randint(-5, 5))
        attrs["shooting"] = rng.randint(15, 25)
        attrs["dribbling"] = rng.randint(20, 35)
    elif position in ("CentreBack", "LeftBack", "RightBack"):
        attrs["defending"] = clamp(ovr * 7 + rng.randint(-5, 5))
        attrs["tackling"] = clamp(ovr * 7 + rng.randint(-5, 5))
        attrs["aerial"] = clamp(ovr * 6 + rng.randint(-5, 5))
        attrs["shooting"] = rng.randint(25, 45)
    elif position == "Striker":
        attrs["shooting"] = clamp(ovr * 7 + rng.randint(-5, 5))
        attrs["positioning"] = clamp(ovr * 6 + rng.randint(-5, 5))
    elif position in ("LeftWinger", "RightWinger"):
        attrs["pace"] = clamp(ovr * 7 + rng.randint(-5, 5))
        attrs["dribbling"] = clamp(ovr * 7 + rng.randint(-5, 5))
    else:
        attrs["passing"] = clamp(ovr * 6 + rng.randint(-5, 5))
        attrs["vision"] = clamp(ovr * 6 + rng.randint(-5, 5))
    return attrs


def team_target_ovr(team: dict, existing: list[dict], rng: random.Random) -> int:
    if existing:
        avg = sum(p.get("ovr") or 60 for p in existing) / len(existing)
        return clamp(int(avg + rng.uniform(-2, 1)), 52, 67)
    rep = team.get("reputation") or 550
    return clamp(int(rep / 10) - 2, 52, 66)


def empty_stats() -> dict:
    return {
        "appearances": 0,
        "goals": 0,
        "assists": 0,
        "clean_sheets": 0,
        "yellow_cards": 0,
        "red_cards": 0,
        "avg_rating": 0.0,
        "minutes_played": 0,
        "shots": 0,
        "shots_on_target": 0,
        "passes_completed": 0,
        "passes_attempted": 0,
        "tackles_won": 0,
        "interceptions": 0,
        "fouls_committed": 0,
    }


def make_player(
    pid: str,
    team: dict,
    team_players: list[dict],
    seq: int,
    rng: random.Random,
) -> dict:
    country = team.get("country") or team.get("football_nation") or "ENG"
    firsts, lasts = NAME_POOLS.get(country, NAME_POOLS["ENG"])
    first = firsts[rng.randrange(len(firsts))]
    last = lasts[rng.randrange(len(lasts))]
    full_name = f"{first} {last}"
    match_name = f"{first[0]}. {last}"
    position = pick_next_position(team_players, rng)
    ovr = team_target_ovr(team, team_players, rng)
    potential = clamp(ovr + rng.randint(0, 8), ovr, 75)
    age = rng.randint(20, 31)
    birth_year = 2024 - age
    month = rng.randint(1, 12)
    day = rng.randint(1, 28)
    nat = COUNTRY_NAT.get(country, country)
    wage = max(800, int(ovr * 120 + (team.get("wage_budget") or 200000) / 800))
    value = max(50000, int(ovr * ovr * 7000))

    return {
        "id": pid,
        "match_name": match_name,
        "full_name": full_name,
        "date_of_birth": f"{birth_year}-{month:02d}-{day:02d}",
        "nationality": nat,
        "football_nation": nat,
        "birth_country": nat,
        "position": position,
        "natural_position": position,
        "alternate_positions": [],
        "footedness": rng.choice(["Right", "Left"]),
        "weak_foot": rng.randint(1, 3),
        "attributes": gen_attributes(position, ovr, rng),
        "condition": 100,
        "morale": rng.randint(60, 80),
        "fitness": rng.randint(70, 90),
        "injury": None,
        "team_id": team["id"],
        "retired": False,
        "squad_role": "Senior",
        "traits": ["synthetic_squad_fill"],
        "ovr": ovr,
        "potential": potential,
        "contract_end": "2027-06-30",
        "wage": wage,
        "market_value": value,
        "stats": empty_stats(),
        "career": [],
        "training_focus": None,
        "transfer_listed": False,
        "loan_listed": False,
        "transfer_offers": [],
        "morale_core": {
            "manager_trust": 50,
            "unresolved_issue": None,
            "recent_treatment": None,
            "pending_promise": None,
            "talk_cooldown_until": None,
            "renewal_state": None,
        },
    }


def collect_existing_ids() -> set[str]:
    ids: set[str] = set()
    for path in (ROOT / "assets" / "Data").glob("**/*.json"):
        if "second" not in path.parts and path.parent.name == "Data":
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, OSError):
                continue
            for p in data.get("players") or []:
                if isinstance(p, dict) and p.get("id"):
                    ids.add(p["id"])
    for fname in SECOND_FILES:
        data = json.loads((SECOND / fname).read_text(encoding="utf-8"))
        for p in data.get("players") or []:
            ids.add(p["id"])
    return ids


def next_synthetic_id(existing: set[str], league_tag: str, n: int) -> str:
    base = f"fm-synth-{league_tag}-{n:05d}"
    while base in existing:
        n += 1
        base = f"fm-synth-{league_tag}-{n:05d}"
    existing.add(base)
    return base


def league_tag(filename: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", filename.replace("fm2024_", "").replace(".json", "")).strip("-")


def fill_file(path: Path, existing_ids: set[str], rng: random.Random) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    tag = league_tag(path.name)
    added = 0
    by_team: dict[str, list[dict]] = {}
    for p in data.get("players", []):
        by_team.setdefault(p["team_id"], []).append(p)

    for team in data.get("teams", []):
        tid = team["id"]
        roster = by_team.setdefault(tid, [])
        need = max(0, MIN_SQUAD - len(roster))
        for _ in range(need):
            pid = next_synthetic_id(existing_ids, tag, added + 1)
            player = make_player(pid, team, roster, added, rng)
            data["players"].append(player)
            roster.append(player)
            added += 1

    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    counts = [len(by_team[t["id"]]) for t in data["teams"]]
    return {
        "file": path.name,
        "added": added,
        "players": len(data["players"]),
        "min": min(counts),
        "max": max(counts),
        "avg": round(sum(counts) / len(counts), 1),
    }


def main() -> None:
    rng = random.Random(RANDOM_SEED)
    existing_ids = collect_existing_ids()
    total_added = 0
    for fname in SECOND_FILES:
        stats = fill_file(SECOND / fname, existing_ids, rng)
        total_added += stats["added"]
        print(
            f"{stats['file']}: +{stats['added']} players -> {stats['players']} total, "
            f"per-team {stats['min']}/{stats['avg']}/{stats['max']}"
        )

    for fname in SECOND_FILES:
        data = json.loads((SECOND / fname).read_text(encoding="utf-8"))
        by = Counter(p["team_id"] for p in data["players"])
        bad = [t["id"] for t in data["teams"] if by[t["id"]] < MIN_SQUAD]
        if bad:
            raise SystemExit(f"{fname} still below {MIN_SQUAD}: {bad}")

    print(f"done: added {total_added} synthetic players, all teams >= {MIN_SQUAD}")


if __name__ == "__main__":
    main()
