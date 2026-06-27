#!/usr/bin/env python3
"""Match fifa21.csv height/weight onto league JSON player records."""

from __future__ import annotations

import argparse
import csv
import json
import re
import unicodedata
from collections import defaultdict
from itertools import permutations
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIFA_CSV = ROOT / "fifa21.csv"
DATA_DIR = ROOT / "assets" / "Data" / "fifa21_body"

FIFA_AGE_REFERENCE_YEAR = 2020
DEFAULT_AGE_TOLERANCE = 2
LEGEND_AGE_TOLERANCE = 18
MIN_SCORE = 14
MIN_SCORE_CROSS_NAT = 18
MIN_SCORE_MARGIN = 4

NAT_ALIASES = {
    "BRA": "BR",
    "GB-WLS": "WAL",
    "GB-SCT": "SCO",
    "GB-ENG": "ENG",
    "GB-NIR": "NIR",
    # fm2025_csl 等文件使用的奥运/ISO 三字母码
    "ESP": "ES",
    "GER": "DE",
    "FRA": "FR",
    "ITA": "IT",
    "NED": "NL",
    "POR": "PT",
    "ARG": "AR",
    "USA": "US",
    "MEX": "MX",
    "KOR": "KR",
    "JPN": "JP",
    "AUS": "AU",
    "NZL": "NZ",
    "CRO": "HR",
    "SRB": "RS",
    "SVN": "SI",
    "BIH": "BA",
    "MKD": "MK",
    "MNE": "ME",
    "GRE": "GR",
    "TUR": "TR",
    "THE": "TR",
    "UKR": "UA",
    "POL": "PL",
    "CZE": "CZ",
    "SVK": "SK",
    "HUN": "HU",
    "ROU": "RO",
    "BUL": "BG",
    "AUT": "AT",
    "SUI": "CH",
    "DEN": "DK",
    "SWE": "SE",
    "FIN": "FI",
    "ISL": "IS",
    "BEL": "BE",
    "LUX": "LU",
    "ALB": "AL",
    "ARM": "AM",
    "AZE": "AZ",
    "ISR": "IL",
    "EGY": "EG",
    "MAR": "MA",
    "TUN": "TN",
    "DZA": "DZ",
    "CMR": "CM",
    "GHA": "GH",
    "NGA": "NG",
    "SEN": "SN",
    "CIV": "CI",
    "MLI": "ML",
    "COD": "CD",
    "AGO": "AO",
    "RSA": "ZA",
    "COL": "CO",
    "URU": "UY",
    "PAR": "PY",
    "CHI": "CL",
    "ECU": "EC",
    "PER": "PE",
    "VEN": "VE",
    "BOL": "BO",
    "CRC": "CR",
    "JAM": "JM",
    "HON": "HN",
    "PAN": "PA",
    "CAN": "CA",
    "CPV": "CV",
    "EQG": "GQ",
    "SLE": "SL",
    "GUI": "GN",
    "MDA": "MD",
    "HKG": "HK",
    "IRL": "IE",
    "WAL": "WAL",
    "NIR": "NIR",
    "SCO": "SCO",
    "ENG": "ENG",
    "CHN": "CHN",
}

EXCLUDE_FILES = {"legend_tag_pools.json"}

LEAGUE_LABELS = {
    "fm2024_premier_league.json": "英超",
    "fm2024_la_liga.json": "西甲",
    "fm2024_serie_a.json": "意甲",
    "fm2024_bundesliga.json": "德甲",
    "fm2024_ligue_1.json": "法甲",
    "fm2025_csl.json": "中超",
    "fm2024_legends_outside_top5.json": "传奇(非五大联赛)",
    "legends_alltime_top50.json": "传奇Top50",
    "legends_alltime_defenders_30.json": "传奇后卫30",
    "legends_alltime_misc_25.json": "传奇Misc25",
    "wonderkids_outside_top5_2025.json": "2025新星(非五大联赛)",
}

ASIAN_NAME_NATS = {"CHN", "KR", "JP", "KP", "HK", "TPE"}

FIFA_COUNTRY_TO_CODE = {
    "England": "ENG",
    "Spain": "ES",
    "Germany": "DE",
    "France": "FR",
    "Brazil": "BR",
    "Argentina": "AR",
    "Italy": "IT",
    "Netherlands": "NL",
    "Portugal": "PT",
    "United States": "US",
    "Mexico": "MX",
    "Colombia": "CO",
    "Japan": "JP",
    "Republic of Ireland": "IE",
    "Belgium": "BE",
    "Scotland": "SCO",
    "Turkey": "TR",
    "Sweden": "SE",
    "Uruguay": "UY",
    "Poland": "PL",
    "Denmark": "DK",
    "Norway": "NO",
    "Austria": "AT",
    "Australia": "AU",
    "Switzerland": "CH",
    "Chile": "CL",
    "Romania": "RO",
    "Senegal": "SN",
    "Nigeria": "NG",
    "Wales": "WAL",
    "Korea Republic": "KR",
    "Croatia": "HR",
    "Ghana": "GH",
    "China PR": "CHN",
    "Ivory Coast": "CI",
    "Serbia": "RS",
    "Ecuador": "EC",
    "Czech Republic": "CZ",
    "Paraguay": "PY",
    "Russia": "RU",
    "Morocco": "MA",
    "Algeria": "DZ",
    "Cameroon": "CM",
    "Ukraine": "UA",
    "Hungary": "HU",
    "Greece": "GR",
    "Tunisia": "TN",
    "Egypt": "EG",
    "Bosnia Herzegovina": "BA",
    "Slovakia": "SK",
    "Finland": "FI",
    "Northern Ireland": "NIR",
    "Iceland": "IS",
    "Costa Rica": "CR",
    "Venezuela": "VE",
    "Peru": "PE",
    "Bolivia": "BO",
    "Canada": "CA",
    "South Africa": "ZA",
    "Mali": "ML",
    "Guinea": "GN",
    "Albania": "AL",
    "Georgia": "GE",
    "Montenegro": "ME",
    "North Macedonia": "MK",
    "Slovenia": "SI",
    "Bulgaria": "BG",
    "Israel": "IL",
    "Jamaica": "JM",
    "New Zealand": "NZ",
    "Angola": "AO",
    "Democratic Republic of Congo": "CD",
    "Burkina Faso": "BF",
    "Gabon": "GA",
    "Togo": "TG",
    "Benin": "BJ",
    "Zimbabwe": "ZW",
    "Honduras": "HN",
    "Panama": "PA",
    "El Salvador": "SV",
    "Guatemala": "GT",
    "Qatar": "QA",
    "Saudi Arabia": "SA",
    "United Arab Emirates": "AE",
    "Iran": "IR",
    "Iraq": "IQ",
    "Syria": "SY",
    "Lebanon": "LB",
    "Jordan": "JO",
    "India": "IN",
    "Thailand": "TH",
    "Vietnam": "VN",
    "Indonesia": "ID",
    "Malaysia": "MY",
    "Philippines": "PH",
    "Korea DPR": "KP",
    "Hong Kong": "HK",
    "Armenia": "AM",
    "Cape Verde": "CV",
    "Guinea Bissau": "GW",
    "Kosovo": "XK",
    "Lithuania": "LT",
    "Latvia": "LV",
    "Estonia": "EE",
    "Luxembourg": "LU",
    "Cyprus": "CY",
    "Malta": "MT",
    "Faroe Islands": "FO",
    "Gibraltar": "GI",
    "Andorra": "AD",
    "San Marino": "SM",
    "Moldova": "MD",
    "Belarus": "BY",
    "Kazakhstan": "KZ",
    "Uzbekistan": "UZ",
}

PLAYER_JSON_GLOBS = [
    "fm2024_*.json",
    "fm2025_*.json",
    "legends_*.json",
    "wonderkids_*.json",
]


def normalize_name(value: str) -> str:
    if not value:
        return ""
    text = unicodedata.normalize("NFKD", value)
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def clean_short_name(value: str) -> str:
    return re.sub(r"^\d+\s+", "", value or "").strip()


def name_tokens(value: str) -> list[str]:
    return [t for t in normalize_name(value.replace("-", " ")).split() if t]


def reversed_name(value: str) -> str:
    tokens = name_tokens(value)
    if len(tokens) < 2:
        return normalize_name(value)
    return " ".join(reversed(tokens))


def surname_from_match_name(match_name: str) -> str:
    tokens = name_tokens(match_name)
    meaningful = [t for t in tokens if len(t) > 1 or t.isdigit()]
    if meaningful:
        return meaningful[-1]
    return tokens[-1] if tokens else ""


def first_token(value: str) -> str:
    tokens = name_tokens(value)
    return tokens[0] if tokens else ""


def initial(value: str) -> str:
    token = first_token(value)
    return token[0] if token else ""


def edit_distance_le1(a: str, b: str) -> bool:
    if a == b:
        return True
    if abs(len(a) - len(b)) > 1:
        return False
    if len(a) > len(b):
        a, b = b, a
    i = j = 0
    used = False
    while i < len(a) and j < len(b):
        if a[i] == b[j]:
            i += 1
            j += 1
            continue
        if used:
            return False
        used = True
        if len(a) == len(b):
            j += 1
        else:
            j += 1
    return True


def surname_matches(game_surname: str, fifa_tokens: list[str]) -> bool:
    if not game_surname or not fifa_tokens:
        return False
    candidates = {fifa_tokens[-1]}
    if len(fifa_tokens) >= 2:
        candidates.add(fifa_tokens[-2] + fifa_tokens[-1])
    for cand in candidates:
        if game_surname == cand or edit_distance_le1(game_surname, cand):
            return True
    return False


def asian_name_variants(full_name: str, match_name: str) -> list[str]:
    variants: list[str] = []
    for candidate in (full_name, match_name):
        norm = normalize_name(candidate)
        rev = reversed_name(candidate)
        if norm:
            variants.append(norm)
        if rev and rev != norm:
            variants.append(rev)
        tokens = name_tokens(candidate)
        if 2 <= len(tokens) <= 3:
            for perm in permutations(tokens):
                joined = " ".join(perm)
                if joined not in variants:
                    variants.append(joined)
    deduped: list[str] = []
    seen = set()
    for item in variants:
        if item and item not in seen:
            seen.add(item)
            deduped.append(item)
    return deduped


def birth_year_from_dob(dob: str | None) -> int | None:
    if not dob:
        return None
    match = re.match(r"^(\d{4})", dob)
    return int(match.group(1)) if match else None


def fifa_birth_year(age: int) -> int:
    return FIFA_AGE_REFERENCE_YEAR - age


def age_compatible(game_year: int | None, fifa_age: int, tolerance: int = DEFAULT_AGE_TOLERANCE) -> bool:
    if game_year is None:
        return True
    return abs(game_year - fifa_birth_year(fifa_age)) <= tolerance


def player_age_tolerance(player: dict) -> int:
    birth_year = birth_year_from_dob(player.get("date_of_birth"))
    if birth_year and birth_year < 1975:
        return LEGEND_AGE_TOLERANCE
    full = player.get("full_name") or ""
    match = player.get("match_name") or ""
    if normalize_name(full) == normalize_name(match) and len(name_tokens(full)) == 1:
        return LEGEND_AGE_TOLERANCE
    return DEFAULT_AGE_TOLERANCE


def player_nat_candidates(player: dict) -> list[str]:
    nats: list[str] = []
    for key in ("football_nation", "nationality", "birth_country"):
        nat = normalize_nat(player.get(key))
        if nat and nat not in nats:
            nats.append(nat)
    return nats


def normalize_nat(value: str | None) -> str | None:
    if not value:
        return None
    seen = set()
    current = value
    while current and current not in seen:
        seen.add(current)
        mapped = NAT_ALIASES.get(current)
        if not mapped or mapped == current:
            return current
        current = mapped
    return current


def round_height(value: str) -> int:
    return int(round(float(value)))


def round_weight(value: str) -> int:
    return int(round(float(value)))


def meaningful_tokens(*values: str) -> set[str]:
    tokens: set[str] = set()
    for value in values:
        for token in name_tokens(value):
            if len(token) > 1:
                tokens.add(token)
    return tokens


def load_fifa_rows(path: Path) -> list[dict]:
    rows: list[dict] = []
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            country = row["Country"].strip()
            nat = FIFA_COUNTRY_TO_CODE.get(country)
            if not nat:
                continue
            try:
                age = int(row["Age"])
                height_cm = round_height(row["Height"])
                weight_kg = round_weight(row["Weight"])
            except (TypeError, ValueError):
                continue
            short_name = clean_short_name(row["Short Name"].strip())
            full_name = row["Full Name"].strip()
            rows.append(
                {
                    "short_name": short_name,
                    "full_name": full_name,
                    "country": country,
                    "nat": nat,
                    "age": age,
                    "birth_year": fifa_birth_year(age),
                    "height_cm": height_cm,
                    "weight_kg": weight_kg,
                    "short_norm": normalize_name(short_name),
                    "full_norm": normalize_name(full_name),
                    "short_tokens": name_tokens(short_name),
                    "full_tokens": name_tokens(full_name),
                }
            )
    return rows


def build_fifa_indexes(rows: list[dict]) -> tuple[dict, dict, dict, dict, dict, list[dict]]:
    by_full: dict[tuple[str, str], list[dict]] = defaultdict(list)
    by_short: dict[tuple[str, str], list[dict]] = defaultdict(list)
    by_surname: dict[tuple[str, str, int], list[dict]] = defaultdict(list)
    by_nat_surname: dict[tuple[str, str], list[dict]] = defaultdict(list)
    by_nat: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        by_nat[row["nat"]].append(row)
        by_full[(row["full_norm"], row["nat"])].append(row)
        by_short[(row["short_norm"], row["nat"])].append(row)
        if row["full_tokens"]:
            surname = row["full_tokens"][-1]
            by_surname[(surname, row["nat"], row["birth_year"])].append(row)
            by_nat_surname[(surname, row["nat"])].append(row)
        if row["short_tokens"]:
            short_surname = row["short_tokens"][-1]
            by_nat_surname[(short_surname, row["nat"])].append(row)
    return by_full, by_short, by_surname, by_nat_surname, by_nat, rows


def dedupe_candidates(candidates: list[dict]) -> list[dict]:
    seen = set()
    out: list[dict] = []
    for row in candidates:
        key = (row["short_norm"], row["full_norm"], row["height_cm"], row["weight_kg"], row["age"])
        if key in seen:
            continue
        seen.add(key)
        out.append(row)
    return out


def pick_unique(candidates: list[dict], birth_year: int | None, tolerance: int) -> dict | None:
    candidates = dedupe_candidates(candidates)
    if not candidates:
        return None
    if birth_year is not None:
        filtered = [c for c in candidates if age_compatible(birth_year, c["age"], tolerance)]
        if len(filtered) == 1:
            return filtered[0]
        if filtered:
            candidates = filtered
    if len(candidates) == 1:
        return candidates[0]
    return None


def names_overlap(a_tokens: list[str], b_tokens: list[str]) -> bool:
    if not a_tokens or not b_tokens:
        return False
    a_set = set(a_tokens)
    b_set = set(b_tokens)
    if a_set & b_set:
        return True
    if a_tokens[-1] == b_tokens[-1] and (
        a_tokens[0] == b_tokens[0] or len(a_tokens[0]) <= 2 or len(b_tokens[0]) <= 2
    ):
        return True
    return False


def score_candidate(player: dict, row: dict, nat: str | None, tolerance: int) -> int:
    birth_year = birth_year_from_dob(player.get("date_of_birth"))
    if not age_compatible(birth_year, row["age"], tolerance):
        return -1

    full_name = player.get("full_name") or ""
    match_name = player.get("match_name") or ""
    full_norm = normalize_name(full_name)
    match_norm = normalize_name(match_name)
    full_tokens = name_tokens(full_name)
    match_tokens = name_tokens(match_name)
    game_surname = surname_from_match_name(match_name) or (full_tokens[-1] if full_tokens else "")

    score = 0
    player_nats = player_nat_candidates(player)
    if nat and nat in player_nats:
        score += 6
    elif nat and nat not in player_nats:
        score -= 4

    if full_norm and full_norm == row["full_norm"]:
        score += 24
    if full_norm and full_norm == row["short_norm"]:
        score += 22
    if match_norm and match_norm == row["short_norm"]:
        score += 20
    if match_norm and match_norm == row["full_norm"]:
        score += 20

    rev_full = reversed_name(full_name)
    rev_match = reversed_name(match_name)
    if rev_full and (rev_full == row["full_norm"] or rev_full == row["short_norm"]):
        score += 18
    if rev_match and (rev_match == row["full_norm"] or rev_match == row["short_norm"]):
        score += 16

    if full_norm and (full_norm in row["full_norm"] or row["full_norm"] in full_norm):
        score += 10
    if match_norm and (match_norm in row["short_norm"] or row["short_norm"] in match_norm):
        score += 8

    if surname_matches(game_surname, row["full_tokens"]) or surname_matches(game_surname, row["short_tokens"]):
        score += 12
    elif game_surname and (
        edit_distance_le1(game_surname, row["full_tokens"][-1] if row["full_tokens"] else "")
        or edit_distance_le1(game_surname, row["short_tokens"][-1] if row["short_tokens"] else "")
    ):
        score += 8

    game_tokens = meaningful_tokens(full_name, match_name)
    fifa_tokens = meaningful_tokens(row["full_name"], row["short_name"])
    overlap = game_tokens & fifa_tokens
    score += len(overlap) * 5

    game_initial = initial(full_name) or initial(match_name)
    if game_initial and (
        initial(row["full_name"]) == game_initial or initial(row["short_name"]) == game_initial
    ):
        score += 4

    if len(full_tokens) == 1 and full_tokens[0] == row["full_tokens"][-1]:
        score += 10

    return score


def collect_surname_candidates(
    player: dict,
    nat: str | None,
    by_nat_surname: dict,
    by_nat: dict,
) -> list[dict]:
    full_name = player.get("full_name") or ""
    match_name = player.get("match_name") or ""
    full_tokens = name_tokens(full_name)
    surname = surname_from_match_name(match_name) or (full_tokens[-1] if full_tokens else "")
    if not surname:
        return by_nat.get(nat, []) if nat else []

    candidates: list[dict] = []
    seen = set()
    keys = [(surname, nat)] if nat else []
    if nat:
        for (sur, sur_nat), rows in by_nat_surname.items():
            if sur_nat != nat:
                continue
            if sur == surname or edit_distance_le1(surname, sur):
                keys.append((sur, sur_nat))

    for key in keys:
        for row in by_nat_surname.get(key, []):
            marker = (row["short_norm"], row["full_norm"], row["age"])
            if marker not in seen:
                seen.add(marker)
                candidates.append(row)
    return candidates


def choose_best_scored(player: dict, rows: list[dict], nat: str | None, tolerance: int) -> tuple[dict | None, str]:
    scored: list[tuple[int, dict]] = []
    for row in rows:
        score = score_candidate(player, row, nat, tolerance)
        if score >= 0:
            scored.append((score, row))
    if not scored:
        return None, "unmatched"
    scored.sort(key=lambda item: item[0], reverse=True)
    best_score, best_row = scored[0]
    second_score = scored[1][0] if len(scored) > 1 else -1
    threshold = MIN_SCORE if nat in player_nat_candidates(player) else MIN_SCORE_CROSS_NAT
    if best_score >= threshold and best_score - second_score >= MIN_SCORE_MARGIN:
        return best_row, "scored"
    return None, "unmatched"


def match_player(player: dict, by_full, by_short, by_surname, by_nat_surname, by_nat, all_rows) -> tuple[dict | None, str]:
    tolerance = player_age_tolerance(player)
    nats = player_nat_candidates(player) or [None]

    full_name = player.get("full_name") or ""
    match_name = player.get("match_name") or ""
    full_norm = normalize_name(full_name)
    match_norm = normalize_name(match_name)
    full_tokens = name_tokens(full_name)
    match_tokens = name_tokens(match_name)
    birth_year = birth_year_from_dob(player.get("date_of_birth"))

    for nat in nats:
        hit = pick_unique(by_full.get((full_norm, nat), []), birth_year, tolerance)
        if hit:
            return hit, "full_name"

        hit = pick_unique(by_short.get((match_norm, nat), []), birth_year, tolerance)
        if hit:
            return hit, "match_name"

        for variant in asian_name_variants(full_name, match_name):
            hit = pick_unique(by_full.get((variant, nat), []), birth_year, tolerance)
            if hit:
                return hit, "asian_name"
            hit = pick_unique(by_short.get((variant, nat), []), birth_year, tolerance)
            if hit:
                return hit, "asian_short"

        surname = surname_from_match_name(match_name) or (full_tokens[-1] if full_tokens else "")
        if surname:
            candidates = list(by_nat_surname.get((surname, nat), []))
            if not candidates:
                for (sur, sur_nat), rows in by_nat_surname.items():
                    if sur_nat == nat and edit_distance_le1(surname, sur):
                        candidates.extend(rows)
            filtered = [c for c in dedupe_candidates(candidates) if age_compatible(birth_year, c["age"], tolerance)]
            if filtered:
                game_initial = initial(full_name) or initial(match_name)
                if game_initial:
                    initial_hits = [
                        c
                        for c in filtered
                        if initial(c["full_name"]) == game_initial or initial(c["short_name"]) == game_initial
                    ]
                    hit = pick_unique(initial_hits, birth_year, tolerance)
                    if hit:
                        return hit, "surname_initial"
                fuzzy_hits = [
                    c
                    for c in filtered
                    if surname_matches(surname, c["full_tokens"]) or surname_matches(surname, c["short_tokens"])
                ]
                hit = pick_unique(fuzzy_hits or filtered, birth_year, tolerance)
                if hit:
                    return hit, "surname"

        for row in by_short.get((match_norm, nat), []):
            if names_overlap(match_tokens, row["full_tokens"]) and age_compatible(birth_year, row["age"], tolerance):
                return row, "short_to_full"

        if full_tokens:
            surname = full_tokens[-1]
            for delta in (0, -1, 1, -2, 2):
                hit = pick_unique(
                    by_surname.get((surname, nat, (birth_year or FIFA_AGE_REFERENCE_YEAR) + delta), []),
                    birth_year,
                    tolerance,
                )
                if hit and names_overlap(full_tokens, hit["full_tokens"]):
                    return hit, "surname_year"

        scored_pool = collect_surname_candidates(player, nat, by_nat_surname, by_nat)
        hit, reason = choose_best_scored(player, scored_pool, nat, tolerance)
        if hit:
            return hit, reason

    global_pool: list[dict] = []
    seen_global = set()
    for nat in nats:
        for row in collect_surname_candidates(player, nat, by_nat_surname, by_nat):
            marker = (row["short_norm"], row["full_norm"], row["age"])
            if marker not in seen_global:
                seen_global.add(marker)
                global_pool.append(row)
    hit, reason = choose_best_scored(player, global_pool, None, tolerance)
    if hit:
        return hit, "scored_global"
    return None, "unmatched"


def iter_player_json_files() -> list[Path]:
    files: list[Path] = []
    for pattern in PLAYER_JSON_GLOBS:
        files.extend(sorted(DATA_DIR.glob(pattern)))
    return [fp for fp in files if fp.is_file() and fp.name not in EXCLUDE_FILES]


def apply_player_measurements(player: dict, hit: dict | None, reprocess: bool) -> bool:
    changed = False
    if hit:
        if player.get("height_cm") != hit["height_cm"] or player.get("weight_kg") != hit["weight_kg"]:
            player["height_cm"] = hit["height_cm"]
            player["weight_kg"] = hit["weight_kg"]
            changed = True
    elif reprocess and ("height_cm" in player or "weight_kg" in player):
        player.pop("height_cm", None)
        player.pop("weight_kg", None)
        changed = True
    return changed


def process_file(
    path: Path,
    by_full,
    by_short,
    by_surname,
    by_nat_surname,
    by_nat,
    all_rows,
    apply: bool,
    fill_missing_only: bool,
    reprocess: bool,
) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    players = data.get("players")
    if not isinstance(players, list):
        return {"file": path.name, "players": 0, "matched": 0, "updated": 0, "newly_matched": 0}

    matched = 0
    updated = 0
    newly_matched = 0
    unmatched_players: list[dict] = []

    for player in players:
        had_height = bool(player.get("height_cm"))
        if fill_missing_only and not reprocess and had_height:
            matched += 1
            continue

        hit, reason = match_player(player, by_full, by_short, by_surname, by_nat_surname, by_nat, all_rows)
        if hit:
            matched += 1
            if not had_height:
                newly_matched += 1
            if apply_player_measurements(player, hit, reprocess):
                updated += 1
        else:
            if reprocess and apply_player_measurements(player, None, reprocess):
                updated += 1
            unmatched_players.append(
                {
                    "id": player.get("id"),
                    "full_name": player.get("full_name"),
                    "match_name": player.get("match_name"),
                    "full_name_cn": player.get("full_name_cn"),
                    "nationality": player.get("nationality") or player.get("football_nation"),
                    "date_of_birth": player.get("date_of_birth"),
                    "team_id": player.get("team_id"),
                }
            )

    if apply and updated:
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    return {
        "file": path.name,
        "label": LEAGUE_LABELS.get(path.name, path.name),
        "players": len(players),
        "matched": matched,
        "updated": updated,
        "newly_matched": newly_matched,
        "unmatched": len(unmatched_players),
        "unmatched_players": unmatched_players,
    }


def write_unmatched_report(results: list[dict], report_path: Path) -> None:
    lines = ["# FIFA21 身高体重未匹配球员名单", ""]
    total_unmatched = sum(r["unmatched"] for r in results)
    total_players = sum(r["players"] for r in results)
    total_matched = sum(r["matched"] for r in results)
    lines.append(f"生成时间：自动脚本输出")
    lines.append(f"总计：{total_matched}/{total_players} 已匹配，{total_unmatched} 未匹配")
    lines.append("")

    for result in results:
        if result["players"] == 0:
            continue
        label = result["label"]
        lines.append(f"## {label} ({result['file']})")
        lines.append(
            f"匹配 {result['matched']}/{result['players']}（{100.0 * result['matched'] / result['players']:.1f}%），"
            f"未匹配 {result['unmatched']}"
        )
        lines.append("")
        if not result["unmatched_players"]:
            lines.append("_全部匹配_")
            lines.append("")
            continue
        lines.append("| 姓名 | 比赛名 | 中文名 | 国籍 | 出生日期 | 球队 |")
        lines.append("| --- | --- | --- | --- | --- | --- |")
        for p in result["unmatched_players"]:
            cn = p.get("full_name_cn") or ""
            lines.append(
                f"| {p.get('full_name') or ''} | {p.get('match_name') or ''} | {cn} | "
                f"{p.get('nationality') or ''} | {p.get('date_of_birth') or ''} | {p.get('team_id') or ''} |"
            )
        lines.append("")

    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def collect_unmatched_from_disk(file_paths: list[Path]) -> list[dict]:
    results: list[dict] = []
    for path in file_paths:
        data = json.loads(path.read_text(encoding="utf-8"))
        players = data.get("players") or []
        unmatched_players = [
            {
                "id": p.get("id"),
                "full_name": p.get("full_name"),
                "match_name": p.get("match_name"),
                "full_name_cn": p.get("full_name_cn"),
                "nationality": p.get("nationality") or p.get("football_nation"),
                "date_of_birth": p.get("date_of_birth"),
                "team_id": p.get("team_id"),
            }
            for p in players
            if not p.get("height_cm")
        ]
        matched = len(players) - len(unmatched_players)
        results.append(
            {
                "file": path.name,
                "label": LEAGUE_LABELS.get(path.name, path.name),
                "players": len(players),
                "matched": matched,
                "updated": 0,
                "newly_matched": 0,
                "unmatched": len(unmatched_players),
                "unmatched_players": unmatched_players,
            }
        )
    return results


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="Write matched height/weight into JSON files")
    parser.add_argument(
        "--reprocess",
        action="store_true",
        help="Re-match all players; clear height/weight when no match",
    )
    parser.add_argument(
        "--only",
        nargs="*",
        help="Only process these JSON filenames (e.g. fm2025_csl.json)",
    )
    parser.add_argument(
        "--report",
        nargs="?",
        const="assets/Data/fifa21_body/fifa21_height_weight_unmatched_report.md",
        default="",
        help="Write unmatched player report to this path (relative to repo root)",
    )
    parser.add_argument(
        "--report-only",
        action="store_true",
        help="Only scan JSON files and write unmatched report",
    )
    args = parser.parse_args()

    file_paths = iter_player_json_files()
    if args.only:
        only_set = set(args.only)
        file_paths = [fp for fp in file_paths if fp.name in only_set]

    if args.report_only:
        report_path = ROOT / args.report
        write_unmatched_report(collect_unmatched_from_disk(file_paths), report_path)
        print(f"Report written to {report_path}")
        return

    fill_missing_only = not args.reprocess

    fifa_rows = load_fifa_rows(FIFA_CSV)
    by_full, by_short, by_surname, by_nat_surname, by_nat, all_rows = build_fifa_indexes(fifa_rows)

    totals = {"players": 0, "matched": 0, "updated": 0, "newly_matched": 0, "unmatched": 0}
    print(f"Loaded {len(fifa_rows)} FIFA rows with known country mapping")
    print(f"Mode: {'APPLY' if args.apply else 'DRY RUN'} | reprocess={args.reprocess} | fill_missing_only={fill_missing_only}")
    print()

    for path in file_paths:
        reprocess_file = args.reprocess or path.name == "fm2025_csl.json"
        result = process_file(
            path,
            by_full,
            by_short,
            by_surname,
            by_nat_surname,
            by_nat,
            all_rows,
            args.apply,
            fill_missing_only,
            reprocess_file,
        )
        if result["players"] == 0:
            continue
        totals["players"] += result["players"]
        totals["matched"] += result["matched"]
        totals["updated"] += result["updated"]
        totals["newly_matched"] += result["newly_matched"]
        totals["unmatched"] += result["unmatched"]
        rate = 100.0 * result["matched"] / result["players"]
        print(
            f"{result['file']}: {result['matched']}/{result['players']} matched ({rate:.1f}%), "
            f"new {result['newly_matched']}, updated {result['updated']}, unmatched {result['unmatched']}"
        )

    if totals["players"]:
        rate = 100.0 * totals["matched"] / totals["players"]
        print()
        print(
            f"TOTAL: {totals['matched']}/{totals['players']} matched ({rate:.1f}%), "
            f"new {totals['newly_matched']}, updated {totals['updated']}, unmatched {totals['unmatched']}"
        )

    if args.report:
        report_path = ROOT / args.report
        write_unmatched_report(collect_unmatched_from_disk(iter_player_json_files() if not args.only else file_paths), report_path)
        print(f"Report written to {report_path}")


if __name__ == "__main__":
    main()
