#!/usr/bin/env python3
"""Generate legends_alltime_defenders_30.json from roster spec."""
import json
from copy import deepcopy

EMPTY_STATS = {
    "appearances": 0, "goals": 0, "assists": 0, "clean_sheets": 0,
    "yellow_cards": 0, "red_cards": 0, "avg_rating": 0.0, "minutes_played": 0,
    "shots": 0, "shots_on_target": 0, "passes_completed": 0, "passes_attempted": 0,
    "tackles_won": 0, "interceptions": 0, "fouls_committed": 0,
}
EMPTY_MORALE = {
    "manager_trust": 50, "unresolved_issue": None, "recent_treatment": None,
    "pending_promise": None, "talk_cooldown_until": None, "renewal_state": None,
}

# (id_suffix, match_name, full_name, full_name_cn, dob, nation, position, alts, foot, weak_foot, ovr, traits, attrs)
ROSTER = [
    # === GK x4 ===
    ("002", "Casillas", "Iker Casillas", "伊克尔·卡西利亚斯", "1981-05-20", "ES", "Goalkeeper", [], "Right", 4, 92,
     ["Reflexes", "Leader", "Sweeper"],
     {"pace": 55, "stamina": 86, "strength": 84, "agility": 95, "passing": 82, "shooting": 12,
      "tackling": 14, "dribbling": 50, "defending": 82, "positioning": 94, "vision": 86, "decisions": 92,
      "composure": 96, "aggression": 72, "teamwork": 90, "leadership": 94, "handling": 96, "reflexes": 98, "aerial": 88}),
    ("003", "Schmeichel", "Peter Schmeichel", "彼得·舒梅切尔", "1963-11-18", "DK", "Goalkeeper", [], "Right", 4, 93,
     ["Reflexes", "Leader", "AerialThreat"],
     {"pace": 52, "stamina": 90, "strength": 96, "agility": 88, "passing": 78, "shooting": 14,
      "tackling": 16, "dribbling": 48, "defending": 84, "positioning": 93, "vision": 82, "decisions": 90,
      "composure": 92, "aggression": 88, "teamwork": 86, "leadership": 95, "handling": 95, "reflexes": 96, "aerial": 97}),
    ("004", "Zoff", "Dino Zoff", "迪诺·佐夫", "1942-02-28", "IT", "Goalkeeper", [], "Right", 4, 92,
     ["Reflexes", "Leader", "Sweeper"],
     {"pace": 48, "stamina": 88, "strength": 86, "agility": 90, "passing": 80, "shooting": 12,
      "tackling": 14, "dribbling": 45, "defending": 82, "positioning": 97, "vision": 84, "decisions": 96,
      "composure": 98, "aggression": 70, "teamwork": 92, "leadership": 96, "handling": 94, "reflexes": 93, "aerial": 90}),
    ("005", "Kahn", "Oliver Kahn", "奥利弗·卡恩", "1969-06-15", "DE", "Goalkeeper", [], "Right", 4, 92,
     ["Reflexes", "Leader", "Sweeper"],
     {"pace": 50, "stamina": 90, "strength": 94, "agility": 90, "passing": 76, "shooting": 12,
      "tackling": 16, "dribbling": 46, "defending": 84, "positioning": 94, "vision": 80, "decisions": 92,
      "composure": 90, "aggression": 96, "teamwork": 84, "leadership": 97, "handling": 95, "reflexes": 96, "aerial": 92}),

    # === CB x10 ===
    ("006", "Nesta", "Alessandro Nesta", "亚历山德罗·内斯塔", "1976-03-19", "IT", "CentreBack", [], "Right", 4, 94,
     ["Stopper", "BallPlayingDefender", "Leader"],
     {"pace": 82, "stamina": 88, "strength": 90, "agility": 88, "passing": 88, "shooting": 55,
      "tackling": 96, "dribbling": 72, "defending": 97, "positioning": 94, "vision": 86, "decisions": 94,
      "composure": 96, "aggression": 88, "teamwork": 90, "leadership": 90, "handling": 18, "reflexes": 16, "aerial": 90}),
    ("007", "Puyol", "Carles Puyol", "卡莱斯·普约尔", "1978-04-13", "ES", "CentreBack", [], "Right", 4, 93,
     ["Stopper", "Leader", "Engine"],
     {"pace": 78, "stamina": 96, "strength": 92, "agility": 82, "passing": 82, "shooting": 52,
      "tackling": 95, "dribbling": 68, "defending": 96, "positioning": 92, "vision": 78, "decisions": 90,
      "composure": 92, "aggression": 96, "teamwork": 96, "leadership": 94, "handling": 18, "reflexes": 16, "aerial": 88}),
    ("008", "Hierro", "Fernando Hierro", "费尔南多·耶罗", "1968-03-23", "ES", "CentreBack", ["DefensiveMidfielder"], "Right", 4, 93,
     ["Stopper", "Leader", "AerialThreat"],
     {"pace": 72, "stamina": 90, "strength": 92, "agility": 78, "passing": 88, "shooting": 78,
      "tackling": 94, "dribbling": 70, "defending": 95, "positioning": 92, "vision": 84, "decisions": 92,
      "composure": 92, "aggression": 90, "teamwork": 90, "leadership": 92, "handling": 18, "reflexes": 16, "aerial": 94}),
    ("009", "Desailly", "Marcel Desailly", "马塞尔·德塞利", "1968-09-07", "FR", "CentreBack", ["DefensiveMidfielder"], "Right", 4, 92,
     ["Stopper", "Leader", "Engine"],
     {"pace": 78, "stamina": 92, "strength": 96, "agility": 80, "passing": 82, "shooting": 55,
      "tackling": 94, "dribbling": 68, "defending": 95, "positioning": 90, "vision": 78, "decisions": 88,
      "composure": 90, "aggression": 94, "teamwork": 88, "leadership": 90, "handling": 18, "reflexes": 16, "aerial": 92}),
    ("011", "Lucio", "Lúcio", "卢西奥", "1978-12-08", "BR", "CentreBack", [], "Right", 4, 91,
     ["BallPlayingDefender", "Leader", "AerialThreat"],
     {"pace": 76, "stamina": 90, "strength": 94, "agility": 78, "passing": 84, "shooting": 58,
      "tackling": 92, "dribbling": 72, "defending": 93, "positioning": 90, "vision": 80, "decisions": 88,
      "composure": 88, "aggression": 90, "teamwork": 86, "leadership": 88, "handling": 18, "reflexes": 16, "aerial": 94}),
    ("012", "Ferdinand", "Rio Ferdinand", "里奥·费迪南德", "1978-11-07", "ENG", "CentreBack", [], "Right", 4, 91,
     ["BallPlayingDefender", "Leader", "Sweeper"],
     {"pace": 78, "stamina": 86, "strength": 90, "agility": 82, "passing": 90, "shooting": 52,
      "tackling": 90, "dribbling": 74, "defending": 92, "positioning": 92, "vision": 88, "decisions": 90,
      "composure": 92, "aggression": 82, "teamwork": 88, "leadership": 90, "handling": 18, "reflexes": 16, "aerial": 90}),
    ("013", "Stam", "Jaap Stam", "雅普·斯塔姆", "1972-07-17", "NL", "CentreBack", [], "Right", 4, 90,
     ["Stopper", "Engine", "AerialThreat"],
     {"pace": 80, "stamina": 88, "strength": 94, "agility": 78, "passing": 78, "shooting": 50,
      "tackling": 94, "dribbling": 66, "defending": 94, "positioning": 88, "vision": 74, "decisions": 86,
      "composure": 86, "aggression": 94, "teamwork": 84, "leadership": 84, "handling": 18, "reflexes": 16, "aerial": 92}),
    ("014", "Blanc", "Laurent Blanc", "劳伦特·布兰科", "1965-11-08", "FR", "CentreBack", [], "Right", 4, 91,
     ["Sweeper", "BallPlayingDefender", "Leader"],
     {"pace": 76, "stamina": 88, "strength": 88, "agility": 84, "passing": 88, "shooting": 62,
      "tackling": 92, "dribbling": 76, "defending": 93, "positioning": 92, "vision": 86, "decisions": 92,
      "composure": 92, "aggression": 82, "teamwork": 90, "leadership": 90, "handling": 18, "reflexes": 16, "aerial": 88}),
    ("015", "Koeman", "Ronald Koeman", "罗纳德·科曼", "1963-03-21", "NL", "CentreBack", ["DefensiveMidfielder"], "Right", 4, 92,
     ["BallPlayingDefender", "DeadBall", "Leader"],
     {"pace": 68, "stamina": 86, "strength": 90, "agility": 72, "passing": 94, "shooting": 88,
      "tackling": 90, "dribbling": 74, "defending": 92, "positioning": 90, "vision": 90, "decisions": 90,
      "composure": 90, "aggression": 86, "teamwork": 88, "leadership": 92, "handling": 18, "reflexes": 16, "aerial": 90}),
    ("016", "Sammer", "Matthias Sammer", "马蒂亚斯·萨默尔", "1967-09-05", "DE", "CentreBack", ["DefensiveMidfielder"], "Right", 4, 92,
     ["Sweeper", "BallPlayingDefender", "Leader"],
     {"pace": 82, "stamina": 92, "strength": 88, "agility": 86, "passing": 90, "shooting": 68,
      "tackling": 92, "dribbling": 80, "defending": 94, "positioning": 94, "vision": 92, "decisions": 94,
      "composure": 92, "aggression": 86, "teamwork": 90, "leadership": 92, "handling": 18, "reflexes": 16, "aerial": 86}),

    # === LB/RB x4 ===
    ("018", "Lahm", "Philipp Lahm", "菲利普·拉姆", "1983-11-11", "DE", "RightBack", ["LeftBack", "DefensiveMidfielder"], "Right", 5, 91,
     ["Overlapper", "Engine", "Leader"],
     {"pace": 84, "stamina": 94, "strength": 78, "agility": 90, "passing": 92, "shooting": 62,
      "tackling": 90, "dribbling": 86, "defending": 92, "positioning": 92, "vision": 90, "decisions": 94,
      "composure": 94, "aggression": 78, "teamwork": 96, "leadership": 92, "handling": 18, "reflexes": 16, "aerial": 72}),
    ("019", "Alves", "Dani Alves", "达尼·阿尔维斯", "1983-05-06", "BR", "RightBack", [], "Right", 4, 91,
     ["Overlapper", "Crosser", "Engine"],
     {"pace": 90, "stamina": 96, "strength": 78, "agility": 92, "passing": 92, "shooting": 68,
      "tackling": 86, "dribbling": 90, "defending": 86, "positioning": 88, "vision": 90, "decisions": 90,
      "composure": 88, "aggression": 82, "teamwork": 88, "leadership": 84, "handling": 18, "reflexes": 16, "aerial": 76}),
    ("020", "Marcelo", "Marcelo", "马塞洛", "1988-05-12", "BR", "LeftBack", [], "Left", 4, 90,
     ["Overlapper", "Dribbler", "Crosser"],
     {"pace": 88, "stamina": 92, "strength": 76, "agility": 94, "passing": 88, "shooting": 72,
      "tackling": 82, "dribbling": 92, "defending": 84, "positioning": 86, "vision": 86, "decisions": 86,
      "composure": 86, "aggression": 78, "teamwork": 86, "leadership": 80, "handling": 18, "reflexes": 16, "aerial": 74}),
    ("022", "A. Cole", "Ashley Cole", "阿什利·科尔", "1980-12-20", "ENG", "LeftBack", [], "Left", 4, 90,
     ["Overlapper", "Engine", "Stopper"],
     {"pace": 90, "stamina": 94, "strength": 82, "agility": 90, "passing": 84, "shooting": 58,
      "tackling": 92, "dribbling": 82, "defending": 92, "positioning": 90, "vision": 80, "decisions": 88,
      "composure": 90, "aggression": 84, "teamwork": 88, "leadership": 84, "handling": 18, "reflexes": 16, "aerial": 78}),

    # === CDM x6 ===
    ("023", "Rijkaard", "Frank Rijkaard", "弗兰克·里杰卡尔德", "1962-09-30", "NL", "DefensiveMidfielder", ["CentreBack", "CentralMidfielder"], "Right", 4, 93,
     ["Engine", "Leader", "BoxToBox"],
     {"pace": 78, "stamina": 94, "strength": 92, "agility": 82, "passing": 90, "shooting": 72,
      "tackling": 94, "dribbling": 80, "defending": 94, "positioning": 92, "vision": 88, "decisions": 94,
      "composure": 94, "aggression": 88, "teamwork": 92, "leadership": 92, "handling": 18, "reflexes": 16, "aerial": 90}),
    ("024", "Vieira", "Patrick Vieira", "帕特里克·维埃拉", "1976-06-23", "FR", "DefensiveMidfielder", ["CentralMidfielder"], "Right", 4, 92,
     ["BoxToBox", "Engine", "Leader"],
     {"pace": 82, "stamina": 94, "strength": 94, "agility": 80, "passing": 88, "shooting": 68,
      "tackling": 94, "dribbling": 78, "defending": 92, "positioning": 90, "vision": 86, "decisions": 90,
      "composure": 88, "aggression": 92, "teamwork": 88, "leadership": 92, "handling": 18, "reflexes": 16, "aerial": 92}),
    ("025", "Makelele", "Claude Makélélé", "克劳德·马克莱莱", "1973-02-18", "FR", "DefensiveMidfielder", [], "Right", 4, 91,
     ["Engine", "Stopper", "Leader"],
     {"pace": 76, "stamina": 96, "strength": 86, "agility": 86, "passing": 86, "shooting": 55,
      "tackling": 96, "dribbling": 78, "defending": 94, "positioning": 94, "vision": 84, "decisions": 94,
      "composure": 92, "aggression": 90, "teamwork": 92, "leadership": 88, "handling": 18, "reflexes": 16, "aerial": 78}),
    ("026", "Keane", "Roy Keane", "罗伊·基恩", "1971-08-10", "IE", "DefensiveMidfielder", ["CentralMidfielder"], "Right", 4, 91,
     ["BoxToBox", "Leader", "Engine"],
     {"pace": 76, "stamina": 96, "strength": 90, "agility": 78, "passing": 86, "shooting": 72,
      "tackling": 94, "dribbling": 76, "defending": 90, "positioning": 88, "vision": 84, "decisions": 90,
      "composure": 86, "aggression": 98, "teamwork": 90, "leadership": 96, "handling": 18, "reflexes": 16, "aerial": 86}),
    ("028", "Redondo", "Fernando Redondo", "费尔南多·雷东多", "1970-06-06", "AR", "DefensiveMidfielder", ["CentralMidfielder"], "Right", 4, 91,
     ["Playmaker", "Visionary", "Engine"],
     {"pace": 72, "stamina": 90, "strength": 84, "agility": 84, "passing": 94, "shooting": 62,
      "tackling": 90, "dribbling": 86, "defending": 90, "positioning": 92, "vision": 94, "decisions": 94,
      "composure": 94, "aggression": 76, "teamwork": 90, "leadership": 86, "handling": 18, "reflexes": 16, "aerial": 82}),
    ("028", "Gattuso", "Gennaro Gattuso", "詹纳罗·加图索", "1978-01-09", "IT", "DefensiveMidfielder", ["CentralMidfielder"], "Right", 4, 89,
     ["Engine", "Stopper", "Leader"],
     {"pace": 74, "stamina": 98, "strength": 88, "agility": 76, "passing": 78, "shooting": 58,
      "tackling": 96, "dribbling": 70, "defending": 92, "positioning": 90, "vision": 76, "decisions": 86,
      "composure": 84, "aggression": 98, "teamwork": 94, "leadership": 88, "handling": 18, "reflexes": 16, "aerial": 78}),

    # === ST x1（补充进攻传奇）===
    ("031", "Torres", "Fernando Torres", "费尔南多·托雷斯", "1984-03-20", "ES", "Striker", ["AttackingMidfielder"], "Right", 4, 91,
     ["Finisher", "Speedster", "Poacher"],
     {"pace": 90, "stamina": 88, "strength": 82, "agility": 88, "passing": 82, "shooting": 92,
      "tackling": 45, "dribbling": 86, "defending": 40, "positioning": 94, "vision": 82, "decisions": 88,
      "composure": 88, "aggression": 78, "teamwork": 84, "leadership": 82, "handling": 18, "reflexes": 16, "aerial": 78}),
]


def make_player(row):
    sid, match_name, full_name, cn, dob, nation, pos, alts, foot, weak, ovr, traits, attrs = row
    return {
        "id": f"legend-def-{sid}",
        "match_name": match_name,
        "full_name": full_name,
        "full_name_cn": cn,
        "date_of_birth": dob,
        "nationality": nation,
        "football_nation": nation,
        "birth_country": nation,
        "position": pos,
        "natural_position": pos,
        "alternate_positions": alts,
        "footedness": foot,
        "weak_foot": weak,
        "attributes": attrs,
        "condition": 100,
        "morale": 80,
        "fitness": 80,
        "injury": None,
        "team_id": None,
        "league": None,
        "league_country": nation,
        "retired": True,
        "squad_role": "Legend",
        "traits": traits,
        "ovr": ovr,
        "potential": ovr,
        "contract_end": None,
        "wage": 0,
        "market_value": 0,
        "note": "",
        "stats": deepcopy(EMPTY_STATS),
        "career": [],
        "training_focus": None,
        "transfer_listed": False,
        "loan_listed": False,
        "transfer_offers": [],
        "morale_core": deepcopy(EMPTY_MORALE),
    }


def main():
    players = [make_player(r) for r in ROSTER]
    data = {
        "name": "历史传奇球员（防守补充）",
        "description": "25位传奇球员补充池（门将/后卫/后腰为主，含托雷斯等）。",
        "players": players,
    }
    out = "assets/Data/legends_alltime_defenders_30.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"Wrote {len(players)} players to {out}")
    from collections import Counter
    c = Counter(p["position"] for p in players)
    for k, v in sorted(c.items(), key=lambda x: -x[1]):
        print(f"  {k}: {v}")


if __name__ == "__main__":
    main()
