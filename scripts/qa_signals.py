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

if errors:
    print("\n".join("ERROR: " + e for e in errors))
    raise SystemExit(1)

print(f"Signal QA passed: {len(markets)} rows checked")
