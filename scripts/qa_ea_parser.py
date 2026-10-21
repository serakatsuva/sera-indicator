#!/usr/bin/env python3
"""Replays the EA's MQL5 JSON readers (JsonString, JsonNumber, JsonObject, JsonFlag*,
ExtractObjectAt and the markets loop of Evaluate) on the published feeds and checks that
every value the EA reads matches the real data. Catches feed/parser mismatches that would
otherwise only show up as wrong trades in MT5."""
from __future__ import annotations

import json
import math
from pathlib import Path


def find(s: str, sub: str, start: int = 0) -> int:
    return s.find(sub, start)


def json_string(obj: str, key: str) -> str:
    token = '"' + key + '"'
    p = find(obj, token)
    if p < 0: return ""
    p = find(obj, ":", p + len(token))
    if p < 0: return ""
    p = find(obj, '"', p + 1)
    if p < 0: return ""
    e = find(obj, '"', p + 1)
    if e < 0: return ""
    return obj[p + 1:e]


def json_number(obj: str, key: str) -> float:
    token = '"' + key + '"'
    p = find(obj, token)
    if p < 0: return 0.0
    p = find(obj, ":", p + len(token))
    if p < 0: return 0.0
    p += 1
    while p < len(obj) and obj[p] in " \t": p += 1
    e = p
    while e < len(obj) and (obj[e].isdigit() or obj[e] in "-+.eE"): e += 1
    try:
        return float(obj[p:e])
    except ValueError:
        return 0.0


def json_flag(obj: str, key: str, word: str) -> bool:
    token = '"' + key + '"'
    p = find(obj, token)
    if p < 0: return False
    p = find(obj, ":", p + len(token))
    if p < 0: return False
    p += 1
    while p < len(obj) and obj[p] in " \t": p += 1
    return obj[p:p + len(word)] == word


def extract_object_at(s: str, start: int) -> str:
    depth, quoted = 0, False
    for i in range(start, len(s)):
        c = s[i]
        if c == '"' and (i == 0 or s[i - 1] != "\\"): quoted = not quoted
        if quoted: continue
        if c == "{": depth += 1
        if c == "}":
            depth -= 1
            if depth == 0: return s[start:i + 1]
    return ""


def json_object(obj: str, key: str) -> str:
    token = '"' + key + '"'
    p = find(obj, token)
    if p < 0: return ""
    p = find(obj, ":", p + len(token))
    if p < 0: return ""
    p += 1
    while p < len(obj) and obj[p] in " \t\n\r": p += 1
    if p >= len(obj) or obj[p] != "{": return ""
    return extract_object_at(obj, p)


def ea_markets(text: str):
    markets = find(text, '"markets"')
    cursor = find(text, "{", markets)
    while cursor >= 0:
        obj = extract_object_at(text, cursor)
        if not obj: break
        yield obj
        cursor = find(text, "{", cursor + len(obj))


def close(a: float, b) -> bool:
    return isinstance(b, (int, float)) and math.isclose(a, float(b), rel_tol=1e-9, abs_tol=1e-9)


def check(path: Path, compact: bool) -> list[str]:
    text = path.read_text(encoding="utf-8")
    data = json.loads(text)
    errors: list[str] = []
    if json_string(text, "status") != data.get("status"): errors.append(f"{path}: status misread")
    if json_string(text, "updated_at") != data.get("updated_at"): errors.append(f"{path}: updated_at misread")
    rows = {r["id"]: r for r in data["markets"]}
    seen = 0
    for obj in ea_markets(text):
        seen += 1
        rid = json_string(obj, "id")
        row = rows.get(rid)
        if row is None:
            # The full feed has config objects after "markets"; the EA skips them (no "mode").
            # The compact EA feed must contain markets only.
            if compact or json_string(obj, "mode") in ("swing", "day"):
                errors.append(f"{path}: EA loop read an object that is not a market ({rid!r})")
            seen -= 1
            continue
        engine = row if compact else (row.get("decision_engine") or {})
        expect = {
            "mode": row.get("mode"), "final_verdict": row.get("final_verdict"),
            "execution_state": row.get("execution_state"), "symbol": row.get("symbol"), "market": row.get("market"),
        }
        for k, v in expect.items():
            if json_string(obj, k) != (v or ""): errors.append(f"{rid}: {k} read as {json_string(obj, k)!r} instead of {v!r}")
        for k, v in {"final_confidence": row.get("final_confidence"), "execution_score": row.get("execution_score"),
                     "condition_pass_percent": engine.get("condition_pass_percent")}.items():
            if v is not None and not close(json_number(obj, k), v): errors.append(f"{rid}: {k} read as {json_number(obj, k)} instead of {v}")
        fresh = engine.get("freshness_gate")
        if (fresh is False) != json_flag(obj, "freshness_gate", "false"): errors.append(f"{rid}: freshness_gate misread")
        conf = row.get("confirmation_tf") or {}
        if conf.get("side") in ("BUY", "SELL"):
            cobj = json_object(obj, "confirmation_tf")
            if json_string(cobj, "side") != conf["side"]: errors.append(f"{rid}: confirmation side misread")
            if json_flag(cobj, "trendStrong", "true") != bool(conf.get("trendStrong")): errors.append(f"{rid}: confirmation trendStrong misread")
        if row.get("final_verdict") in ("BUY", "SELL"):
            lobj = json_object(obj, "levels")
            for k in ("entry", "sl", "tp1", "tp2", "tp3", "tp4", "tp5"):
                if not close(json_number(lobj, k), row["levels"][k]): errors.append(f"{rid}: levels.{k} misread")
            plan = row.get("setup_entry_plan")
            pobj = json_object(obj, "setup_entry_plan")
            if plan and not close(json_number(pobj, "suggested_entry"), plan["suggested_entry"]): errors.append(f"{rid}: plan misread")
            if not plan and pobj: errors.append(f"{rid}: null plan read as an object")
    if seen != len(rows): errors.append(f"{path}: EA loop saw {seen} markets instead of {len(rows)}")
    return errors


def main() -> int:
    errors: list[str] = []
    for path, compact in ((Path("data/ea-signals.json"), True), (Path("data/signals.json"), False)):
        if path.exists():
            found = check(path, compact)
            errors += found
            print(f"{path}: {'OK' if not found else str(len(found)) + ' error(s)'}")
    if errors:
        print("\n".join("ERROR: " + e for e in errors[:30]))
        return 1
    print("EA parser QA passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
