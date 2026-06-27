#!/usr/bin/env python3
"""Swap second-division teams without icons for clubs from the first logo batch."""

import json
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# old_id -> replacement (all logo slugs exist in first-batch second-division packs)
SWAPS = {
    "assets/Data/second/fm2024_championship.json": [
        {
            "old_id": "plymouth-argyle",
            "new_id": "birmingham-city",
            "name": "Birmingham City",
            "short_name": "BIR",
            "logo_slug": "birmingham",
        },
    ],
    "assets/Data/second/fm2024_ligue_2.json": [
        {
            "old_id": "stade-malherbe-caen-calvados",
            "new_id": "as-saint-etienne",
            "name": "AS Saint-Étienne",
            "short_name": "ASSE",
            "logo_slug": "as-saint-etienne",
        },
        {
            "old_id": "valenciennes-fc",
            "new_id": "fc-nancy",
            "name": "AS Nancy Lorraine",
            "short_name": "NAN",
            "logo_slug": "nancy",
        },
        {
            "old_id": "fc-girondins-de-bordeaux",
            "new_id": "montpellier-hsc",
            "name": "Montpellier HSC",
            "short_name": "MHSC",
            "logo_slug": "montpellier",
        },
        {
            "old_id": "athletic-club-ajaccio",
            "new_id": "red-star-fc",
            "name": "Red Star FC",
            "short_name": "RSF",
            "logo_slug": "red-star-fc",
        },
    ],
    "assets/Data/second/fm2024_bundesliga_2.json": [
        {
            "old_id": "ssv-jahn-regensburg",
            "new_id": "sg-dynamo-dresden",
            "name": "SG Dynamo Dresden",
            "short_name": "SGD",
            "logo_slug": "dynamo-dresden",
        },
        {
            "old_id": "sv-sandhausen",
            "new_id": "dsc-arminia-bielefeld",
            "name": "DSC Arminia Bielefeld",
            "short_name": "ABI",
            "logo_slug": "arminia-bielefeld",
        },
        {
            "old_id": "vfl-osnabruck",
            "new_id": "sc-preussen-munster",
            "name": "SC Preußen Münster",
            "short_name": "SCP",
            "logo_slug": "preussen-munster",
        },
        {
            "old_id": "chemnitzer-fc",
            "new_id": "sv-07-elversberg",
            "name": "SV 07 Elversberg",
            "short_name": "SVE",
            "logo_slug": "sv-elversberg",
        },
    ],
    "assets/Data/second/fm2024_serie_b.json": [
        {
            "old_id": "fc-bari-1908",
            "new_id": "empoli-fc",
            "name": "Empoli FC",
            "short_name": "EMP",
            "logo_slug": "empoli",
        },
        {
            "old_id": "associazione-calcio-reggiana-1919",
            "new_id": "carrarese-calcio",
            "name": "Carrarese Calcio",
            "short_name": "CAR",
            "logo_slug": "carrarese",
        },
        {
            "old_id": "spezia-calcio",
            "new_id": "calcio-padova",
            "name": "Calcio Padova",
            "short_name": "PAD",
            "logo_slug": "padova",
        },
        {
            "old_id": "ternana-calcio",
            "new_id": "benevento-calcio",
            "name": "Benevento Calcio",
            "short_name": "BEN",
            "logo_slug": "benevento",
        },
        {
            "old_id": "brescia-calcio-1911",
            "new_id": "fc-verona",
            "name": "Hellas Verona FC",
            "short_name": "VER",
            "logo_slug": "verona",
        },
        {
            "old_id": "feralpisal",
            "new_id": "ss-juventus-stabia",
            "name": "SS Juve Stabia",
            "short_name": "JST",
            "logo_slug": "juve-stabia",
        },
    ],
    "assets/Data/second/fm2024_la_liga_2.json": [
        {
            "old_id": "club-deportivo-tenerife",
            "new_id": "ud-las-palmas",
            "name": "UD Las Palmas",
            "short_name": "LPA",
            "logo_slug": "las-palmas",
        },
        {
            "old_id": "fc-cartagena",
            "new_id": "malaga-cf",
            "name": "Málaga CF",
            "short_name": "MLG",
            "logo_slug": "malaga",
        },
        {
            "old_id": "racing-club-de-ferrol",
            "new_id": "rc-deportivo-la-coruna",
            "name": "RC Deportivo La Coruña",
            "short_name": "DEP",
            "logo_slug": "deportivo-la-coruna",
        },
        {
            "old_id": "club-deportivo-eldense",
            "new_id": "cd-castellon",
            "name": "CD Castellón",
            "short_name": "CAS",
            "logo_slug": "castellon",
        },
        {
            "old_id": "agrupacion-deportiva-alcorcon",
            "new_id": "cd-leganes",
            "name": "CD Leganés",
            "short_name": "LEG",
            "logo_slug": "leganes",
        },
        {
            "old_id": "sociedad-deportiva-amorebieta",
            "new_id": "granada-cf",
            "name": "Granada CF",
            "short_name": "GRA",
            "logo_slug": "granada",
        },
    ],
}


def replace_strings(obj, mapping: dict[str, str]):
    if isinstance(obj, dict):
        return {k: replace_strings(v, mapping) for k, v in obj.items()}
    if isinstance(obj, list):
        return [replace_strings(v, mapping) for v in obj]
    if isinstance(obj, str) and obj in mapping:
        return mapping[obj]
    return obj


def apply_swaps(json_path: Path, swaps: list[dict]) -> list[dict]:
    data = json.loads(json_path.read_text(encoding="utf-8"))
    applied = []

    for swap in swaps:
        old_id = swap["old_id"]
        new_id = swap["new_id"]
        team_ids = {t["id"] for t in data.get("teams", [])}
        if old_id not in team_ids:
            raise SystemExit(f"{json_path}: missing team {old_id}")
        if new_id in team_ids:
            raise SystemExit(f"{json_path}: target id already exists: {new_id}")

        id_map = {old_id: new_id}
        data = replace_strings(data, id_map)

        for team in data["teams"]:
            if team["id"] == new_id:
                team["name"] = swap["name"]
                team["short_name"] = swap["short_name"]
                break

        applied.append(
            {
                "file": str(json_path.relative_to(ROOT)).replace("\\", "/"),
                "from": old_id,
                "to": new_id,
                "name": swap["name"],
                "logo_slug": swap["logo_slug"],
            }
        )

    json_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return applied


def main() -> None:
    all_applied = []
    for rel, swaps in SWAPS.items():
        all_applied.extend(apply_swaps(ROOT / rel, swaps))
    print(json.dumps(all_applied, ensure_ascii=False, indent=2))
    print(f"Swapped {len(all_applied)} teams across {len(SWAPS)} leagues")


if __name__ == "__main__":
    main()
