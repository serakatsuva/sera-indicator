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


def validate(feed: dict) -> list[str]:
    errors = []
    text = json.dumps(feed, separators=(",", ":"))
    if not text.startswith('{"status":'):
        errors.append("status must be the first key")
    if "null" in text:
        errors.append("feed must not contain null values")
    for m in feed["markets"]:
        if m["final_verdict"] in ("BUY", "SELL"):
            lv = m.get("levels")
            if not lv:
                errors.append(f"{m['id']}: confirmed {m['final_verdict']} without levels")
                continue
            tps = [lv[f"tp{i}"] for i in range(1, 6)]
            ordered = (lv["sl"] < lv["entry"] < tps[0] < tps[1] < tps[2] < tps[3] < tps[4]) if m["final_verdict"] == "BUY" \
                else (lv["sl"] > lv["entry"] > tps[0] > tps[1] > tps[2] > tps[3] > tps[4])
            if not ordered:
                errors.append(f"{m['id']}: levels not ordered for {m['final_verdict']}")
        if m["execution_state"] == "EXECUTE_NOW" and m["final_verdict"] not in ("BUY", "SELL"):
            errors.append(f"{m['id']}: EXECUTE_NOW without final verdict")
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
    assert not validate(feed), validate(feed)
    text = json.dumps(feed, separators=(",", ":"))
    assert '"condition_pass_percent":85' in text and '"freshness_gate":false' in text
    assert "setup_entry_plan" not in text and '"levels":null' not in text
    print("EA feed self-test passed")


def main() -> int:
    if "--self-test" in sys.argv:
        self_test()
        return 0
    feed = build(json.loads(SOURCE.read_text(encoding="utf-8")))
    errors = validate(feed)
    if errors:
        print("\n".join("ERROR: " + e for e in errors))
        return 1
    TARGET.write_text(json.dumps(feed, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    print(f"EA feed written: {len(feed['markets'])} markets, {feed['confirmed_signals']} confirmed, {TARGET.stat().st_size} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
