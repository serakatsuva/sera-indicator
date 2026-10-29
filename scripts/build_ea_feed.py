#!/usr/bin/env python3
"""Build data/ea-signals.json: the compact feed read by the MT5 EA.

signals.json is ~2.5 MB (charts, diagnostics, model details). The EA only needs a few
fields per market, and it parses JSON with simple string searches, so a small flat file
with the SAME key names is faster to download every 30 s and safer to parse:
- every field the EA reads is at the top level of its market object (no nested look-alikes),
- null values are omitted instead of written as null (a null object could otherwise make a
  naive "find the next {" parser read the next market's data).
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

SOURCE = Path("data/signals.json")
TARGET = Path("data/ea-signals.json")
LEVEL_KEYS = ("entry", "sl", "tp1", "tp2", "tp3", "tp4", "tp5")
PLAN_KEYS = ("suggested_entry", "zone_min", "zone_max")


def finite(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def number(value, default=0):
    return value if finite(value) else default


def compact_row(row: dict) -> dict:
    engine = row.get("decision_engine") or {}
    out = {
        "id": row.get("id"),
        "market": row.get("market"),
        "symbol": row.get("symbol"),
        "mode": row.get("mode"),
        "asset_class": row.get("asset_class") or "synthetic",
        "final_verdict": row.get("final_verdict") or "ATTENDRE",
        "final_confidence": number(row.get("final_confidence")),
        "condition_pass_percent": number(engine.get("condition_pass_percent")),
        "engine_score": number(engine.get("score")),
        "engine_minimum_score": number(engine.get("minimum_score")),
        "execution_state": row.get("execution_state") or "WAIT_CONFIRMATION",
        "execution_score": number(row.get("execution_score")),
        "setup_detected": 1 if row.get("setup_detected") else 0,
        "setup_direction": row.get("setup_direction") or "NEUTRE",
        "model_ensemble_direction": row.get("model_ensemble_direction") or "NEUTRAL",
        "model_ensemble_consensus": number(row.get("model_ensemble_consensus")),
        "model_models_available": number(row.get("model_models_available")),
        "freshness_gate": engine.get("freshness_gate") is not False,
    }
    for key in ("entry_tf", "confirmation_tf"):
        tf = row.get(key) or {}
        if tf.get("side") in ("BUY", "SELL"):
            out[key] = {"side": tf["side"], "trendStrong": bool(tf.get("trendStrong"))}
    plan = row.get("setup_entry_plan") or {}
    if all(finite(plan.get(k)) for k in PLAN_KEYS):
        out["setup_entry_plan"] = {k: plan[k] for k in PLAN_KEYS}
    levels = row.get("levels") or {}
    if all(finite(levels.get(k)) and levels.get(k) > 0 for k in LEVEL_KEYS):
        out["levels"] = {k: levels[k] for k in LEVEL_KEYS}
    return {k: v for k, v in out.items() if v is not None}


def build(signals: dict) -> dict:
    markets = [compact_row(r) for r in signals.get("markets") or [] if r.get("mode") in ("swing", "day")]
    # "status" and "updated_at" first: the EA reads the first occurrence of these keys.
    feed = {
        "status": signals.get("status"),
        "updated_at": signals.get("updated_at"),
        "ok": bool(signals.get("ok")),
        "feed": "sera-ea-v1",
        "engine_version": signals.get("engine_version"),
        "confirmed_signals": sum(1 for m in markets if m["final_verdict"] in ("BUY", "SELL")),
        "markets": markets,
    }
    return {k: v for k, v in feed.items() if v is not None}


def market_problem(m: dict) -> str:
    """Why the EA must not trade this market from the feed ('' when fine)."""
    if m["final_verdict"] in ("BUY", "SELL"):
        lv = m.get("levels")
        if not lv:
            return f"confirmed {m['final_verdict']} without usable levels (missing, non-finite or <= 0)"
        tps = [lv[f"tp{i}"] for i in range(1, 6)]
        ordered = (lv["sl"] < lv["entry"] < tps[0] < tps[1] < tps[2] < tps[3] < tps[4]) if m["final_verdict"] == "BUY" \
            else (lv["sl"] > lv["entry"] > tps[0] > tps[1] > tps[2] > tps[3] > tps[4])
        if not ordered:
            return f"levels not ordered for {m['final_verdict']}"
    if m["execution_state"] == "EXECUTE_NOW" and m["final_verdict"] not in ("BUY", "SELL"):
        return "EXECUTE_NOW without final verdict"
    return ""


def neutralize(m: dict, reason: str) -> None:
    """Keep the market visible but make it untradable: safe whatever the cause."""
    m["final_verdict"] = "ATTENDRE"
    m["execution_state"] = "WAIT_CONFIRMATION"
    m["execution_score"] = 0
    m.pop("levels", None)
    m.pop("setup_entry_plan", None)
    m["excluded_reason"] = reason[:120].replace('"', "'")


def sanitize(feed: dict) -> list[str]:
    """Neutralize every market the EA could misread or mistrade. Returns warnings."""
    from qa_ea_parser import ea_markets, json_string  # same readers as the MQL5 EA
    warnings = []
    for m in feed["markets"]:
        reason = market_problem(m)
        if reason:
            neutralize(m, reason)
            warnings.append(f"{m['id']}: {reason}")
    # Replay the EA's own JSON readers: a market read back differently is neutralized too.
    text = json.dumps(feed, separators=(",", ":"), ensure_ascii=False)
    by_id = {m["id"]: m for m in feed["markets"]}
    for obj in ea_markets(text):
        m = by_id.get(json_string(obj, "id"))
        if m is None:
            continue
        for key in ("mode", "final_verdict", "execution_state", "market", "symbol"):
            if json_string(obj, key) != (m.get(key) or ""):
                neutralize(m, f"EA parser reads {key} differently")
                warnings.append(f"{m['id']}: EA parser reads {key} differently")
                break
    feed["confirmed_signals"] = sum(1 for m in feed["markets"] if m["final_verdict"] in ("BUY", "SELL"))
    return warnings


def validate(feed: dict) -> list[str]:
    """Structural problems that make the whole feed unusable (these block publication)."""
    errors = []
    text = json.dumps(feed, separators=(",", ":"))
    if not text.startswith('{"status":'):
        errors.append("status must be the first key")
    if ":null" in text:
        errors.append("feed must not contain null values")
    if not feed.get("markets"):
        errors.append("no markets")
    errors += [f"{m['id']}: {market_problem(m)}" for m in feed["markets"] if market_problem(m)]
    return errors


def self_test() -> None:
    sample = {"ok": True, "status": "autonomous_analyzed", "updated_at": "2026-10-21T16:00:00Z", "markets": [
        {"id": "R_75:swing", "market": "Volatility 75 Index", "symbol": "R_75", "mode": "swing", "final_verdict": "BUY",
         "final_confidence": 88, "execution_state": "EXECUTE_NOW", "execution_score": 90, "setup_detected": 1,
         "setup_direction": "BUY", "decision_engine": {"condition_pass_percent": 85, "freshness_gate": True},
         "entry_tf": {"side": "BUY", "trendStrong": True}, "confirmation_tf": {"side": "BUY", "trendStrong": True},
         "setup_entry_plan": None,
         "levels": {"entry": 100.0, "sl": 98.0, "tp1": 103.0, "tp2": 104.8, "tp3": 107.2, "tp4": 109.6, "tp5": 112.0}},
        {"id": "R_10:swing", "market": "Volatility 10 Index", "symbol": "R_10", "mode": "swing", "final_verdict": "ATTENDRE",
         "decision_engine": {"freshness_gate": False}, "levels": None, "entry_tf": None},
    ]}
    feed = build(sample)
    assert not sanitize(feed) and not validate(feed), validate(feed)
    # A confirmed SELL whose far target went negative must be neutralized, not block the feed.
    bad = json.loads(json.dumps(sample))
    bad["markets"][0].update(final_verdict="SELL", levels={"entry": 1.0, "sl": 1.2, "tp1": 0.7, "tp2": 0.5, "tp3": 0.3, "tp4": 0.1, "tp5": -0.1})
    broken = build(bad)
    warnings = sanitize(broken)
    assert warnings and not validate(broken), (warnings, validate(broken))
    assert broken["markets"][0]["final_verdict"] == "ATTENDRE" and "levels" not in broken["markets"][0]
    assert broken["confirmed_signals"] == 0
    text = json.dumps(feed, separators=(",", ":"))
    assert '"condition_pass_percent":85' in text and '"freshness_gate":false' in text
    assert "setup_entry_plan" not in text and '"levels":null' not in text
    print("EA feed self-test passed")


def main() -> int:
    if "--self-test" in sys.argv:
        self_test()
        return 0
    feed = build(json.loads(SOURCE.read_text(encoding="utf-8")))
    for w in sanitize(feed):
        # Visible in the Actions run summary; the market is published as untradable (ATTENDRE).
        print(f"::warning title=EA feed: market neutralized::{w}")
    errors = validate(feed)
    if errors:
        for e in errors:
            print(f"::error title=EA feed::{e}")
        return 1
    TARGET.write_text(json.dumps(feed, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    print(f"EA feed written: {len(feed['markets'])} markets, {feed['confirmed_signals']} confirmed, {TARGET.stat().st_size} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
