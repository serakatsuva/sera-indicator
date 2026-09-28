#!/usr/bin/env python3
import json
import math
from pathlib import Path

path = Path("data/signals.json")
data = json.loads(path.read_text(encoding="utf-8"))
errors = []

markets = data.get("markets")
if not isinstance(markets, list) or not markets:
    errors.append("markets array missing or empty")

allowed_exec = {"EXECUTE_NOW", "WAIT_RETRACE", "WAIT_CONFIRMATION", "BLOCKED_RISK"}
allowed_side = {"BUY", "SELL", "NEUTRE"}
expected_forex = {
    "USDBRL-STD", "USDCAD-STD", "USDCHF-STD", "USDCLP-STD", "USDCNH-STD", "USDCOP-STD",
    "USDCZK-STD", "USDDKK-STD", "USDHUF-STD", "USDIDR-STD", "USDINR-STD", "USDJPY-STD",
    "USDKRW-STD", "USDMXN-STD", "USDNOK-STD", "USDPLN-STD", "USDSEK-STD", "USDSGD-STD",
    "USDTHB-STD", "USDTRY-STD", "USDTWD-STD", "USDZAR-STD", "USDILS-STD", "AUDUSD-STD",
    "EURUSD-STD", "GBPUSD-STD", "NZDUSD-STD",
}

for row in markets or []:
    rid = row.get("id", "?")
    mode = row.get("mode")
    if mode not in {"day", "swing"}:
        errors.append(f"{rid}: invalid mode {mode}")

    state = row.get("execution_state")
    if state not in allowed_exec:
        errors.append(f"{rid}: invalid execution_state {state}")

    setup = row.get("setup_direction", "NEUTRE")
    if setup not in allowed_side:
        errors.append(f"{rid}: invalid setup_direction {setup}")

    detected = bool(row.get("setup_detected"))
    projected = row.get("projected_levels")
    if detected:
        if setup not in {"BUY", "SELL"}:
            errors.append(f"{rid}: setup_detected but setup_direction={setup}")
        if not isinstance(projected, dict):
            errors.append(f"{rid}: setup_detected without projected_levels")
        else:
            for key in ("entry", "sl", "tp1", "tp2", "tp3", "tp4", "tp5"):
                value = projected.get(key)
                if not isinstance(value, (int, float)) or not math.isfinite(value):
                    errors.append(f"{rid}: invalid projected {key}")

    verdict = row.get("final_verdict")
    if mode == "swing":
        engine = row.get("decision_engine") or {}
        if row.get("timeframes") != ["H1", "H4", "D1"]:
            errors.append(f"{rid}: Swing timeframes must be H1/H4/D1")
        if not isinstance(row.get("macro_tf"), dict):
            errors.append(f"{rid}: Swing row missing macro_tf D1")
        if verdict in {"BUY", "SELL"}:
            if float(engine.get("score") or 0) < 84:
                errors.append(f"{rid}: confirmed Swing below score 84")
            if float(engine.get("consensus") or 0) < 72:
                errors.append(f"{rid}: confirmed Swing below consensus 72")
            if float(engine.get("condition_pass_percent") or 0) < 80:
                errors.append(f"{rid}: confirmed Swing below 80% conditions")
            if engine.get("confirmation_progress") != "2/2":
                errors.append(f"{rid}: confirmed Swing without confirmation 2/2")
            sides = {row.get("entry_tf", {}).get("side"), row.get("confirmation_tf", {}).get("side"), row.get("macro_tf", {}).get("side")}
            if sides != {verdict}:
                errors.append(f"{rid}: confirmed Swing H1/H4/D1 are not aligned with {verdict}")
    if verdict in {"BUY", "SELL"}:
        levels = row.get("levels")
        if not isinstance(levels, dict):
            errors.append(f"{rid}: final {verdict} without levels")
        else:
            entry, sl = levels.get("entry"), levels.get("sl")
            tps = [levels.get(f"tp{i}") for i in range(1, 6)]
            if not all(isinstance(x, (int, float)) and math.isfinite(x) for x in [entry, sl, *tps]):
                errors.append(f"{rid}: non-numeric final levels")
            else:
                if verdict == "BUY":
                    if not sl < entry < tps[0] < tps[1] < tps[2] < tps[3] < tps[4]:
                        errors.append(f"{rid}: BUY levels are not ordered")
                else:
                    if not sl > entry > tps[0] > tps[1] > tps[2] > tps[3] > tps[4]:
                        errors.append(f"{rid}: SELL levels are not ordered")

    if state == "EXECUTE_NOW" and verdict not in {"BUY", "SELL"}:
        errors.append(f"{rid}: EXECUTE_NOW without final BUY/SELL")

    oss = row.get("open_source_ai", {})
    models = oss.get("models", {}) if isinstance(oss, dict) else {}
    for model in ("xgboost", "lightgbm", "chronos2", "timesfm25"):
        if model not in models:
            errors.append(f"{rid}: missing OSS model {model}")
            continue
        vote = models[model]
        if not isinstance(vote, dict):
            errors.append(f"{rid}: invalid {model} result")
            continue
        if vote.get("status") != "ok":
            continue
        confidence = vote.get("confidence")
        if not isinstance(confidence, (int, float)) or not math.isfinite(confidence) or not 50 <= confidence <= 95:
            errors.append(f"{rid}: invalid {model} confidence")
        if model in {"chronos2", "timesfm25"}:
            price = vote.get("forecast_price")
            reference = vote.get("reference_price")
            ret = vote.get("expected_return_pct")
            vol = vote.get("volatility_threshold_pct")
            if not all(isinstance(x, (int, float)) and math.isfinite(x) for x in (price, reference, ret, vol)):
                errors.append(f"{rid}: {model} status ok without coherent forecast values")
                continue
            if price <= 0 or reference <= 0 or not 0 < vol <= 50 or abs(ret) > 50:
                errors.append(f"{rid}: {model} implausible price, return or volatility")
                continue
            calculated_return = (price / reference - 1) * 100
            if abs(calculated_return - ret) > 0.01:
                errors.append(f"{rid}: {model} forecast contradicts expected_return_pct")
            expected_side = "BUY" if ret > vol + 0.001 else "SELL" if ret < -vol - 0.001 else "NEUTRAL"
            if vote.get("direction") != expected_side:
                errors.append(f"{rid}: {model} direction contradicts expected_return_pct")
    ensemble = oss.get("ensemble", {}) if isinstance(oss, dict) else {}
    if isinstance(ensemble, dict) and ensemble.get("direction") == "NEUTRAL":
        mean = ensemble.get("mean_confidence")
        if isinstance(mean, (int, float)) and mean > 65:
            errors.append(f"{rid}: high ensemble confidence despite model divergence")

forex_symbols = {row.get("symbol") for row in markets or [] if row.get("asset_class") == "forex"}
extra = sorted(forex_symbols - expected_forex)
if extra:
    errors.append(f"Unexpected Forex symbols: {extra}")

memory_path = Path("data/adaptive-evidence.json")
if memory_path.exists():
    memory = json.loads(memory_path.read_text(encoding="utf-8"))
    for record in memory.get("records", []):
        if record.get("status") != "resolved":
            continue
        key = record.get("key", "?")
        result, r, epoch = record.get("result"), record.get("r"), record.get("resolved_epoch")
        if not isinstance(result, str) or not isinstance(r, (int, float)) or not math.isfinite(r):
            errors.append(f"{key}: resolved record without result and finite r")
            continue
        if not isinstance(epoch, int) or epoch <= int(record.get("opened_epoch") or 0):
            errors.append(f"{key}: invalid resolved_epoch")
        if (result == "LOSS" and r != -1) or (result in {"BREAKEVEN", "TIMEOUT_BE", "TIMEOUT_FLAT"} and r != 0) or (result.startswith(("WIN_", "LOCKED_", "TIMEOUT_TP")) and r <= 0):
            errors.append(f"{key}: resolved result inconsistent with r")
        levels = record.get("levels")
        if not isinstance(levels, dict) or not all(isinstance(levels.get(k), (int, float)) and math.isfinite(levels[k]) for k in ("entry", "sl", "tp1", "tp2", "tp3", "tp4", "tp5")):
            errors.append(f"{key}: resolved record without coherent levels")

if errors:
    print("\n".join("ERROR: " + e for e in errors))
    raise SystemExit(1)

print(f"Signal QA passed: {len(markets)} rows checked")
