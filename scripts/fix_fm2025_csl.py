#!/usr/bin/env python3
"""Fix fm2025 CSL data: Nantong roster, cleanup, balance calibration."""
import json
import math
import os
import uuid
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "Data", "fm2025_csl (1).json")
FM2024 = os.path.join(ROOT, "assets", "Data", "fm2024_csl.json")
OUT = os.path.join(ROOT, "assets", "Data", "fm2025_csl.json")

CSL_REP_TOP = 550
CSL_REP_STEP = 3
TARGET_WAGE_UTIL = 0.80
MAX_CALC_OVR = 73
MAX_JSON_OVR = 73

ATTR_KEYS = [
    "pace", "stamina", "strength", "agility", "passing", "shooting", "tackling",
    "dribbling", "defending", "positioning", "vision", "decisions", "composure",
    "aggression", "teamwork", "leadership", "handling", "reflexes", "aerial",
]

ATTR_MAP = {
    "pace": "speed", "stamina": "stamina", "strength": "strength", "agility": "agility",
    "passing": "passing", "shooting": "shooting", "tackling": "tackling",
    "dribbling": "dribbling", "defending": "defending", "positioning": "positioning",
    "vision": "vision", "decisions": "decisions", "composure": "composure",
    "aggression": "aggression", "teamwork": "teamwork", "leadership": "leadership",
    "handling": "handling", "reflexes": "reflexes", "aerial": "aerial",
}

POSITION_MAP = {
    "Goalkeeper": "GK", "CentreBack": "CB", "CenterBack": "CB",
    "LeftBack": "LB", "RightBack": "RB", "LeftWingBack": "LB", "RightWingBack": "RB",
    "DefensiveMidfielder": "CDM", "CentralMidfielder": "CM", "AttackingMidfielder": "CAM",
    "LeftMidfielder": "LM", "RightMidfielder": "RM",
    "LeftWinger": "LW", "RightWinger": "RW", "LeftWing": "LW", "RightWing": "RW",
    "Striker": "ST",
}

POS_WEIGHTS = {
    "GK": {"handling": 3.0, "reflexes": 3.0, "positioning": 2.0, "aerial": 1.5, "composure": 1.0, "decisions": 0.5},
    "CB": {"defending": 2.5, "tackling": 2.0, "aerial": 2.0, "strength": 1.5, "composure": 1.5, "leadership": 1.5, "decisions": 1.0},
    "LB": {"speed": 2.0, "passing": 2.0, "defending": 1.5, "tackling": 1.5, "stamina": 1.5, "dribbling": 1.0, "vision": 1.0, "positioning": 0.5},
    "RB": {"speed": 2.0, "passing": 2.0, "defending": 1.5, "tackling": 1.5, "stamina": 1.5, "dribbling": 1.0, "vision": 1.0, "positioning": 0.5},
    "CDM": {"tackling": 2.5, "defending": 2.0, "passing": 2.0, "positioning": 1.5, "stamina": 1.5, "strength": 1.0, "decisions": 0.5},
    "CM": {"passing": 2.5, "vision": 2.0, "dribbling": 2.0, "stamina": 2.0, "shooting": 1.5, "decisions": 1.5, "composure": 1.0},
    "CAM": {"vision": 2.5, "dribbling": 2.5, "passing": 2.0, "shooting": 2.0, "composure": 1.5, "decisions": 1.0, "agility": 0.5},
    "LM": {"speed": 2.0, "dribbling": 2.0, "passing": 2.0, "stamina": 2.0, "agility": 1.5, "shooting": 1.0, "vision": 1.0},
    "RM": {"speed": 2.0, "dribbling": 2.0, "passing": 2.0, "stamina": 2.0, "agility": 1.5, "shooting": 1.0, "vision": 1.0},
    "LW": {"dribbling": 3.0, "agility": 2.0, "shooting": 2.0, "speed": 1.5, "passing": 1.5, "composure": 1.0, "vision": 1.0},
    "RW": {"dribbling": 3.0, "agility": 2.0, "shooting": 2.0, "speed": 1.5, "passing": 1.5, "composure": 1.0, "vision": 1.0},
    "ST": {"shooting": 3.0, "composure": 2.5, "speed": 2.0, "positioning": 1.5, "dribbling": 1.0, "strength": 1.0, "aerial": 0.5},
}


def scale_attr(v):
    if v is None:
        return 10
    return max(1, min(20, int(v / 5 + 0.5)))


def convert_attrs(j):
    return {game: scale_attr(j.get(json_k)) for json_k, game in ATTR_MAP.items()}


def calc_ovr(pos, a):
    if pos == "GK":
        all_attrs = ["handling", "reflexes", "positioning", "aerial", "composure", "decisions", "agility", "strength", "speed"]
    else:
        all_attrs = [
            "speed", "stamina", "strength", "agility", "passing", "shooting", "tackling",
            "dribbling", "defending", "positioning", "vision", "decisions", "composure",
            "aggression", "teamwork", "leadership", "aerial",
        ]
    base_sum = sum(a.get(x, 10) for x in all_attrs)
    base_score = base_sum / len(all_attrs)
    pw = POS_WEIGHTS.get(pos, {"passing": 1.5, "shooting": 1.5, "dribbling": 1.5, "defending": 1.0, "speed": 1.0, "stamina": 1.0, "decisions": 1.0})
    pos_sum = sum(a.get(k, 10) * w for k, w in pw.items())
    pos_score = pos_sum / sum(pw.values())
    final = base_score * 0.40 + pos_score * 0.60
    if final <= 13:
        ovr_raw = final * 5.0 + 8
    elif final <= 15.5:
        ovr_raw = 73 + (final - 13) * 6.5
    else:
        ovr_raw = 89.25 + (final - 15.5) * 4.5
    return max(1, min(99, math.floor(ovr_raw)))


def player_calc_ovr(p):
    pos = POSITION_MAP.get(p.get("position"), "CM")
    return calc_ovr(pos, convert_attrs(p.get("attributes", {})))


def rep_to_wb(rep):
    ratio = max(0, min(1, (rep - 500) / 450))
    log_min, log_max = math.log(200000), math.log(6500000)
    return int(math.exp(log_min + ratio * (log_max - log_min)))


def build_rep_map(teams):
    ranked = sorted(teams, key=lambda t: t.get("wage_budget", 0), reverse=True)
    return {t["id"]: CSL_REP_TOP - i * CSL_REP_STEP for i, t in enumerate(ranked)}


def scale_attributes(players, factor):
    for p in players:
        attrs = p.get("attributes") or {}
        for k in ATTR_KEYS:
            if k in attrs and attrs[k] is not None:
                attrs[k] = max(15, min(95, int(attrs[k] * factor)))


def calibrate_attributes(players):
    scale_attributes(players, 0.833)
    for _ in range(12):
        max_ovr = max(player_calc_ovr(p) for p in players)
        if max_ovr <= MAX_CALC_OVR:
            break
        scale_attributes(players, 0.97)


def update_player_ratings(players):
    for p in players:
        orig_ovr = p.get("ovr") or 60
        orig_pot = p.get("potential") or orig_ovr
        pot_gap = max(0, orig_pot - orig_ovr)
        calc = player_calc_ovr(p)
        p["ovr"] = min(MAX_JSON_OVR, calc)
        p["potential"] = min(MAX_JSON_OVR, p["ovr"] + pot_gap)


def normalize_wages(players, teams_by_id):
    by_team = defaultdict(list)
    for p in players:
        tid = p.get("team_id")
        if tid:
            by_team[tid].append(p)
    for tid, roster in by_team.items():
        team = teams_by_id.get(tid)
        if not team:
            continue
        budget = team.get("wage_budget") or 200000
        total = sum(p.get("wage") or 0 for p in roster)
        if total <= 0:
            continue
        factor = (budget * TARGET_WAGE_UTIL) / total
        for p in roster:
            old_w = p.get("wage") or 0
            old_mv = p.get("market_value") or max(10000, old_w * 100)
            p["wage"] = max(64, int(old_w * factor))
            p["market_value"] = max(10000, int(old_mv * factor))


def apply_team_finances(teams, rep_map):
    for t in teams:
        rep = rep_map[t["id"]]
        wb = rep_to_wb(rep)
        t["reputation"] = rep
        t["wage_budget"] = wb
        t["finance"] = wb
        t["transfer_budget"] = wb * 25


def dedupe_players(players):
    kept = []
    seen = {}
    removed = 0
    for p in players:
        if (p.get("full_name") or "").endswith("2"):
            removed += 1
            continue
        key = (p.get("team_id"), p.get("full_name_cn") or p.get("full_name"))
        prev = seen.get(key)
        if prev is None:
            seen[key] = p
            kept.append(p)
            continue
        if (p.get("ovr") or 0) > (prev.get("ovr") or 0):
            kept.remove(prev)
            seen[key] = p
            kept.append(p)
        removed += 1
    return kept, removed


def replace_yunnan_with_nantong(data, nantong_template):
    teams = []
    for t in data["teams"]:
        if t["id"] == "yunnan-yukun":
            teams.append(dict(nantong_template))
        else:
            teams.append(t)
    data["teams"] = teams
    for p in data["players"]:
        if p.get("team_id") == "yunnan-yukun":
            p["team_id"] = "nantong-zhiyun"


def renumber_players(players):
    for i, p in enumerate(players, 1):
        p["id"] = f"csl25-{i:04d}"


def main():
    with open(SRC, encoding="utf-8") as f:
        data = json.load(f)
    with open(FM2024, encoding="utf-8") as f:
        fm2024 = json.load(f)

    nantong = next(t for t in fm2024["teams"] if t["id"] == "nantong-zhiyun")

    replace_yunnan_with_nantong(data, nantong)
    data["players"], removed = dedupe_players(data["players"])
    print(f"removed {removed} duplicate/placeholder players")

    # Rank by squad strength (top-11 avg ovr) before finance pass
    by_team = defaultdict(list)
    for p in data["players"]:
        by_team[p["team_id"]].append(p)
    strength = {}
    for tid, roster in by_team.items():
        top = sorted((p.get("ovr") or 0 for p in roster), reverse=True)[:11]
        strength[tid] = sum(top) / len(top) if top else 0
    for t in data["teams"]:
        t["wage_budget"] = int(strength.get(t["id"], 0) * 10000)

    rep_map = build_rep_map(data["teams"])
    apply_team_finances(data["teams"], rep_map)
    teams_by_id = {t["id"]: t for t in data["teams"]}

    calibrate_attributes(data["players"])
    update_player_ratings(data["players"])
    normalize_wages(data["players"], teams_by_id)
    renumber_players(data["players"])

    data["name"] = "Chinese Super League 2025"
    data["description"] = (
        "2025赛季中国足球协会超级联赛（中超）球员数据快照。"
        "上海海港、上海申花、北京国安、成都蓉城为完整真实一阵名单（含青年球员），"
        "山东泰山、武汉三镇为核心球员真实名单，其余球队提供各队代表性外援与国脚球员。"
        "球队列表保留南通支云。属性与财务已按第六联赛档位校准。"
        "数据来源：维基百科2025赛季条目、Transfermarkt、AiScore、FotMob。"
    )
    data["metadata"] = {
        "kind": "historicalSnapshot",
        "baseYear": 2025,
        "snapshotDate": "2025-11-23T00:00:00Z",
    }
    if data.get("league"):
        data["league"]["name"] = "Chinese Super League"
        data["league"]["season"] = 2025
        for fx in data["league"].get("fixtures", []):
            if fx.get("date", "").startswith("2024-"):
                fx["date"] = "2025" + fx["date"][4:]

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    # Validation summary
    max_ovr = max(player_calc_ovr(p) for p in data["players"])
    high_json = sum(1 for p in data["players"] if (p.get("ovr") or 0) >= 75)
    reps = [t["reputation"] for t in data["teams"]]
    pc = defaultdict(int)
    for p in data["players"]:
        pc[p["team_id"]] += 1
    print(f"written {OUT}")
    print(f"players={len(data['players'])}, max_calc_ovr={max_ovr}, json_ovr>=75={high_json}")
    print(f"reputation range={min(reps)}-{max(reps)}")
    print(f"players/team min={min(pc.values())} max={max(pc.values())}")
    for tid, cnt in sorted(pc.items(), key=lambda x: -x[1]):
        print(f"  {cnt:3d}  {tid}")


if __name__ == "__main__":
    main()
