#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("m", ROOT / "scripts" / "apply_fifa21_height_weight.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

rows = m.load_fifa_rows(m.FIFA_CSV)
by_full, by_short, by_surname, by_nat_surname = m.build_fifa_indexes(rows)

queries = [
    "Rico Lewis", "Francesco Acerbi", "Warren Zaïre-Emery", "Vitinha",
    "Mathys Tel", "Josip Stanišić", "Peter Schmeichel", "Dino Zoff",
    "Yan Junling", "Wu Lei", "Zinedine Zidane", "Pelé", "Maradona",
    "Malik Tillman", "Bradley Barcola", "Arda Güler", "Brahim Díaz",
]

for q in queries:
    norm = m.normalize_name(q)
    toks = m.name_tokens(q)
    print(f"\n=== {q} ===")
    hits = []
    for row in rows:
        if norm in row["full_norm"] or norm in row["short_norm"]:
            hits.append(row)
        elif toks and toks[-1] in row["full_tokens"]:
            if any(t in row["full_tokens"] or t in row["short_tokens"] for t in toks if len(t) > 2):
                hits.append(row)
    seen = set()
    for h in hits[:8]:
        key = (h["short_name"], h["full_name"])
        if key in seen:
            continue
        seen.add(key)
        print(f"  {h['short_name']} | {h['full_name']} | {h['nat']} | age={h['age']} | {h['height_cm']}cm {h['weight_kg']}kg")
