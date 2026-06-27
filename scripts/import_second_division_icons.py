#!/usr/bin/env python3
"""Import 512px football-logos.cc icons for second-division leagues."""

import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

LEAGUES = [
    {
        "json": "assets/Data/second/fm2024_championship.json",
        "logo_dir": "england-efl-championship-2026-2027.football-logos.cc/512x512",
        "dest_dir": "assets/Data/England - Championship",
    },
    {
        "json": "assets/Data/second/fm2024_ligue_2.json",
        "logo_dir": "france-ligue-2-2025-2026.football-logos.cc/512x512",
        "dest_dir": "assets/Data/France - Ligue 2",
    },
    {
        "json": "assets/Data/second/fm2024_bundesliga_2.json",
        "logo_dir": "germany-2-bundesliga-2025-2026.football-logos.cc/512x512",
        "dest_dir": "assets/Data/Germany - 2. Bundesliga",
    },
    {
        "json": "assets/Data/second/fm2024_serie_b.json",
        "logo_dir": "italy-serie-b-2025-2026.football-logos.cc/512x512",
        "dest_dir": "assets/Data/Italy - Serie B",
    },
    {
        "json": "assets/Data/second/fm2024_la_liga_2.json",
        "logo_dir": "spain-la-liga-2-2025-2026.football-logos.cc/512x512",
        "dest_dir": "assets/Data/Spain - LaLiga 2",
    },
]

# Explicit json team id -> logo slug (filename without .football-logos.cc.png)
TEAM_LOGO = {
    # Championship (2026-27 pack vs FM2024 roster)
    "blackburn-rovers": "blackburn-rovers",
    "bristol-city": "bristol-city",
    "cardiff-city": "cardiff-city",
    "derby-county": "derby-county",
    "middlesbrough": "middlesbrough",
    "millwall": "millwall",
    "norwich-city": "norwich-city",
    "preston-north-end": "preston-north-end",
    "queens-park-rangers": "queens-park-rangers",
    "stoke-city": "stoke-city",
    "swansea-city-afc": "swansea-city",
    "watford": "watford",
    "west-bromwich-albion": "west-bromwich-albion",
    "birmingham-city": "birmingham",
    # Ligue 2
    "esperance-sportive-troyes-aube-champagne": "troyes",
    "amiens-sporting-club-football": "amiens",
    "rodez-af": "rodez-af",
    "fc-annecy": "annecy",
    "grenoble-foot-38": "grenoble-foot-38",
    "pau-fc": "pau",
    "clermont-foot-63": "clermont-foot",
    "en-avant-guingamp": "guingamp",
    "stade-lavallois-mayenne-fc": "stade-lavallois",
    "sporting-club-de-bastia": "bastia",
    "usl-dunkerque": "dunkerque",
    "as-saint-etienne": "as-saint-etienne",
    "fc-nancy": "nancy",
    "montpellier-hsc": "montpellier",
    "red-star-fc": "red-star-fc",
    # 2. Bundesliga
    "hertha-bsc": "hertha-bsc",
    "fc-schalke-04": "schalke-04",
    "hannover-96": "hannover-96",
    "fortuna-dusseldorf": "fortuna-dusseldorf",
    "spvgg-greuther-furth": "spvgg-greuther-furth",
    "1-fc-nurnberg": "fc-nurnberg",
    "karlsruher-sc": "karlsruher",
    "sc-paderborn-07": "paderborn",
    "1-fc-magdeburg": "1-fc-magdeburg",
    "1-fc-kaiserslautern": "fc-kaiserslautern",
    "sv-darmstadt-98": "darmstadt",
    "eintracht-braunschweig": "eintracht-braunschweig",
    "sg-dynamo-dresden": "dynamo-dresden",
    "dsc-arminia-bielefeld": "arminia-bielefeld",
    "sc-preussen-munster": "preussen-munster",
    "sv-07-elversberg": "sv-elversberg",
    # Serie B
    "cremonese": "cremonese",
    "u-s-citt-di-palermo": "palermo",
    "uc-sampdoria": "sampdoria",
    "modena-fc": "modena",
    "pisa-calcio": "pisa",
    "unione-sportiva-catanzaro-1929": "catanzaro",
    "sudtirol-alto-adige": "suditrol",
    "ascoli-calcio-1898": "ascoli",
    "a-c-cesena": "cesena",
    "empoli-fc": "empoli",
    "carrarese-calcio": "carrarese",
    "calcio-padova": "padova",
    "benevento-calcio": "benevento",
    "fc-verona": "verona",
    "ss-juventus-stabia": "juve-stabia",
    # La Liga 2
    "real-zaragoza": "zaragoza",
    "real-valladolid-club-de-futbol": "valladolid",
    "real-sporting-de-gijon-s-a-d": "sporting-gijon",
    "sociedad-deportiva-eibar": "eibar",
    "albacete-balompie": "albacete",
    "real-racing-club-de-santander": "racing",
    "sociedad-deportiva-huesca": "huesca",
    "futbol-club-andorra": "fc-andorra",
    "club-deportivo-mirandes": "mirandes",
    "ud-las-palmas": "las-palmas",
    "malaga-cf": "malaga",
    "rc-deportivo-la-coruna": "deportivo-la-coruna",
    "cd-castellon": "castellon",
    "cd-leganes": "leganes",
    "granada-cf": "granada",
}

# Fallback: copy 512px icon from a top-flight logo pack into the second-division folder
TOP_FLIGHT_FALLBACK = {
    # Championship gaps (PL 2026-27 pack)
    "coventry-city": ("english-premier-league-2026-2027.football-logos2.cc/512x512", "coventry-city"),
    "hull-city-afc": ("english-premier-league-2026-2027.football-logos2.cc/512x512", "hull-city"),
    "leeds-united": ("english-premier-league-2026-2027.football-logos2.cc/512x512", "leeds-united"),
    "sunderland-afc": ("english-premier-league-2026-2027.football-logos2.cc/512x512", "sunderland"),
    # Ligue 2 gaps (Ligue 1 2025-26 pack)
    "association-de-la-jeunesse-auxerroise": (
        "france-ligue-1-2025-2026.football-logos2.cc/512x512",
        "auxerre",
    ),
    "fc-de-metz": ("france-ligue-1-2025-2026.football-logos2.cc/512x512", "fc-metz"),
    "paris-fc": ("france-ligue-1-2025-2026.football-logos2.cc/512x512", "paris-fc"),
    # 2. Bundesliga gaps (Bundesliga 2025-26 pack)
    "1-fc-koln": ("germany-bundesliga-2025-2026.football-logos2.cc/512x512", "koln"),
    "hamburger-sv": ("germany-bundesliga-2025-2026.football-logos2.cc/512x512", "hamburger-sv"),
    # Serie B gaps (Serie A 2025-26 pack)
    "parma-calcio-1913": ("italy-serie-a-2025-2026.football-logos2.cc/512x512", "parma"),
    "como-1907": ("italy-serie-a-2025-2026.football-logos2.cc/512x512", "como-1907"),
    "venezia-football-club": ("italy-serie-a-2025-2026.football-logos2.cc/512x512", "venezia"),
    # La Liga 2 gaps (La Liga 2025-26 pack)
    "levante-union-deportiva": ("spain-la-liga-2025-2026.football-logos2.cc/512x512", "levante"),
    "real-oviedo": ("spain-la-liga-2025-2026.football-logos2.cc/512x512", "oviedo"),
    "elche-club-de-futbol": ("spain-la-liga-2025-2026.football-logos2.cc/512x512", "elche"),
}

LOGO_FILENAME = {
    "swansea-city": "Swansea City.png",
    "clermont-foot": "Clermont Foot 63.png",
    "stade-lavallois": "Stade Lavallois Mayenne FC.png",
    "schalke-04": "FC Schalke 04.png",
    "fc-nurnberg": "1. FC Nürnberg.png",
    "karlsruher": "Karlsruher SC.png",
    "paderborn": "SC Paderborn 07.png",
    "fc-kaiserslautern": "1. FC Kaiserslautern.png",
    "darmstadt": "SV Darmstadt 98.png",
    "suditrol": "Südtirol.png",
    "fc-andorra": "FC Andorra.png",
    "sporting-gijon": "Real Sporting de Gijón.png",
    "spvgg-greuther-furth": "SpVgg Greuther Fürth.png",
    "1-fc-magdeburg": "1. FC Magdeburg.png",
    "grenoble-foot-38": "Grenoble Foot 38.png",
    "rodez-af": "Rodez AF.png",
    "as-saint-etienne": "AS Saint-Étienne.png",
    "nancy": "AS Nancy Lorraine.png",
    "montpellier": "Montpellier HSC.png",
    "red-star-fc": "Red Star FC.png",
    "dynamo-dresden": "SG Dynamo Dresden.png",
    "arminia-bielefeld": "DSC Arminia Bielefeld.png",
    "preussen-munster": "SC Preußen Münster.png",
    "sv-elversberg": "SV 07 Elversberg.png",
    "juve-stabia": "SS Juve Stabia.png",
    "deportivo-la-coruna": "RC Deportivo La Coruña.png",
    "birmingham": "Birmingham City.png",
}


def title_filename(name: str) -> str:
    return re.sub(r"\s+", " ", name.strip()) + ".png"


def load_logo_index(logo_dir: Path) -> dict[str, Path]:
    return {
        f.name.replace(".football-logos.cc.png", ""): f
        for f in logo_dir.glob("*.png")
    }


def dest_filename(team: dict, logo_slug: str) -> str:
    if logo_slug in LOGO_FILENAME:
        return LOGO_FILENAME[logo_slug]
    return title_filename(team.get("name", logo_slug.replace("-", " ").title()))


def main() -> None:
    team_icons_path = ROOT / "assets/Data/team_icons.json"
    mapping = json.loads(team_icons_path.read_text(encoding="utf-8"))
    icons = mapping.setdefault("icons", {})

    # Remove prior second-division entries so stale fuzzy matches don't linger.
    second_ids = set()
    for league in LEAGUES:
        teams = json.loads((ROOT / league["json"]).read_text(encoding="utf-8"))["teams"]
        second_ids.update(t["id"] for t in teams if not t["id"].startswith("fm-"))
    for tid in list(icons.keys()):
        if tid in second_ids:
            del icons[tid]

    report = []

    for league in LEAGUES:
        json_path = ROOT / league["json"]
        logo_dir = ROOT / league["logo_dir"]
        dest_dir = ROOT / league["dest_dir"]
        dest_dir.mkdir(parents=True, exist_ok=True)

        teams = json.loads(json_path.read_text(encoding="utf-8"))["teams"]
        logos = load_logo_index(logo_dir)

        matched = []
        missing = []
        used_logos = set()

        for team in teams:
            tid = team["id"]
            if tid.startswith("fm-"):
                continue

            logo_slug = TEAM_LOGO.get(tid)
            if logo_slug and logo_slug in logos:
                fname = dest_filename(team, logo_slug)
                rel_path = f"Data/{dest_dir.name}/{fname}"
                src = logos[logo_slug]
                dst = dest_dir / fname
                shutil.copy2(src, dst)
                icons[tid] = rel_path
                matched.append({"id": tid, "name": team.get("name", ""), "logo": logo_slug, "source": "second"})
                used_logos.add(logo_slug)
                continue

            if tid in TOP_FLIGHT_FALLBACK:
                pack_rel, fallback_slug = TOP_FLIGHT_FALLBACK[tid]
                pack_logos = load_logo_index(ROOT / pack_rel)
                if fallback_slug in pack_logos:
                    fname = dest_filename(team, fallback_slug)
                    rel_path = f"Data/{dest_dir.name}/{fname}"
                    shutil.copy2(pack_logos[fallback_slug], dest_dir / fname)
                    icons[tid] = rel_path
                    matched.append(
                        {
                            "id": tid,
                            "name": team.get("name", ""),
                            "logo": fallback_slug,
                            "source": pack_rel,
                        }
                    )
                    continue

            missing.append({"id": tid, "name": team.get("name", "")})

        unused = sorted(set(logos.keys()) - used_logos)
        report.append(
            {
                "league": league["json"],
                "matched": len(matched),
                "total": len([t for t in teams if not t["id"].startswith("fm-")]),
                "missing": missing,
                "unused_logos": unused,
            }
        )

    team_icons_path.write_text(
        json.dumps(mapping, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    total_matched = sum(r["matched"] for r in report)
    total_teams = sum(r["total"] for r in report)
    print(f"Coverage: {total_matched}/{total_teams} ({100 * total_matched / total_teams:.0f}%)")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
