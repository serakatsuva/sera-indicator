#!/usr/bin/env python3
"""
Sera Open-Source Model Ensemble
--------------------------------
Adds quantitative model votes to data/signals.json.

Core models (every signal cycle):
- XGBoost
- LightGBM

Foundation time-series models (normally once per hour):
- Chronos-2 small (Apache-2.0)
- TimesFM 2.5 200M (Apache-2.0 weights)

The ensemble may confirm or veto execution timing, but it never creates a
BUY/SELL when Sera Autonomous Engine has returned ATTENDRE and it never bypasses
risk gates.
"""
from __future__ import annotations

import argparse
import json
import math
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

DEFAULT_SIGNALS = Path("data/signals.json")
DEFAULT_CANDLES = Path("/tmp/sera-candles.json")
DEFAULT_CACHE = Path("data/open-source-ai.json")
MODEL_VERSION = "Sera OSS Ensemble v1.0"


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def load_json(path: Path, default: Any = None) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def save_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


def safe_float(value: Any, default: float = 0.0) -> float:
    try:
        value = float(value)
        return value if math.isfinite(value) else default
    except Exception:
        return default


def rsi(values: np.ndarray, period: int = 14) -> float:
    if len(values) < period + 1:
        return 50.0
    delta = np.diff(values[-(period + 1):])
    gain = np.maximum(delta, 0.0).mean()
    loss = np.maximum(-delta, 0.0).mean()
    if loss <= 1e-12:
        return 100.0
    rs = gain / loss
    return float(100.0 - (100.0 / (1.0 + rs)))


def feature_vector(rows: list[dict[str, Any]], idx: int) -> list[float] | None:
    if idx < 30 or idx >= len(rows):
        return None
    closes = np.asarray([safe_float(x.get("close")) for x in rows[: idx + 1]], dtype=np.float64)
    highs = np.asarray([safe_float(x.get("high")) for x in rows[: idx + 1]], dtype=np.float64)
    lows = np.asarray([safe_float(x.get("low")) for x in rows[: idx + 1]], dtype=np.float64)
    opens = np.asarray([safe_float(x.get("open")) for x in rows[: idx + 1]], dtype=np.float64)
    price = max(abs(closes[-1]), 1e-9)

    def ret(n: int) -> float:
        if len(closes) <= n or abs(closes[-1 - n]) < 1e-12:
            return 0.0
        return float(closes[-1] / closes[-1 - n] - 1.0)

    sma5 = closes[-5:].mean()
    sma10 = closes[-10:].mean()
    sma20 = closes[-20:].mean()
    std5 = closes[-5:].std()
    std20 = closes[-20:].std()

    prev_close = closes[:-1]
    tr = np.maximum(
        highs[1:] - lows[1:],
        np.maximum(np.abs(highs[1:] - prev_close), np.abs(lows[1:] - prev_close)),
    )
    atr14 = float(tr[-14:].mean()) if len(tr) >= 14 else float(np.mean(tr)) if len(tr) else 0.0

    recent_high = float(highs[-20:].max())
    recent_low = float(lows[-20:].min())
    channel = max(recent_high - recent_low, 1e-9)
    position = float((closes[-1] - recent_low) / channel)
    body = float((closes[-1] - opens[-1]) / max(highs[-1] - lows[-1], 1e-9))
    slope = float((sma5 - np.mean(closes[-10:-5])) / price)

    return [
        ret(1), ret(2), ret(4), ret(8),
        float((sma5 - closes[-1]) / price),
        float((sma10 - closes[-1]) / price),
        float((sma20 - closes[-1]) / price),
        float(std5 / price), float(std20 / price),
        float(rsi(closes) / 100.0),
        float(atr14 / price),
        position, body, slope,
    ]


def supervised_dataset(rows: list[dict[str, Any]], horizon: int) -> tuple[np.ndarray, np.ndarray, np.ndarray] | None:
    if len(rows) < 90:
        return None
    xs: list[list[float]] = []
    ys: list[int] = []
    for i in range(30, len(rows) - horizon):
        feat = feature_vector(rows, i)
        if feat is None:
            continue
        now = safe_float(rows[i].get("close"))
        future = safe_float(rows[i + horizon].get("close"))
        if now <= 0:
            continue
        xs.append(feat)
        ys.append(1 if future > now else 0)
    current = feature_vector(rows, len(rows) - 1)
    if current is None or len(xs) < 50 or len(set(ys)) < 2:
        return None
    return np.asarray(xs, dtype=np.float32), np.asarray(ys, dtype=np.int32), np.asarray([current], dtype=np.float32)


def vote_from_probability(prob_up: float, validation_accuracy: float | None = None) -> dict[str, Any]:
    p = clamp(float(prob_up), 0.0, 1.0)
    if p >= 0.56:
        direction = "BUY"
    elif p <= 0.44:
        direction = "SELL"
    else:
        direction = "NEUTRAL"
    confidence = round(max(p, 1.0 - p) * 100.0, 1)
    return {
        "status": "ok",
        "direction": direction,
        "probability_up": round(p * 100.0, 1),
        "confidence": confidence,
        "validation_accuracy": round(validation_accuracy * 100.0, 1) if validation_accuracy is not None else None,
    }


def fit_xgboost(rows: list[dict[str, Any]], horizon: int) -> dict[str, Any]:
    ds = supervised_dataset(rows, horizon)
    if ds is None:
        return {"status": "warming_up", "direction": "NEUTRAL"}
    X, y, current = ds
    try:
        import xgboost as xgb
        split = max(35, int(len(X) * 0.8))
        split = min(split, len(X) - 10)
        model = xgb.XGBClassifier(
            n_estimators=90,
            max_depth=3,
            learning_rate=0.05,
            subsample=0.85,
            colsample_bytree=0.85,
            objective="binary:logistic",
            eval_metric="logloss",
            tree_method="hist",
            n_jobs=2,
            random_state=26,
        )
        model.fit(X[:split], y[:split])
        accuracy = float((model.predict(X[split:]) == y[split:]).mean()) if split < len(X) else None
        model.fit(X, y)
        prob = float(model.predict_proba(current)[0, 1])
        result = vote_from_probability(prob, accuracy)
        result["model"] = "XGBoost"
        result["samples"] = int(len(X))
        return result
    except Exception as exc:
        return {"status": "error", "direction": "NEUTRAL", "error": str(exc)[:160]}


def fit_lightgbm(rows: list[dict[str, Any]], horizon: int) -> dict[str, Any]:
    ds = supervised_dataset(rows, horizon)
    if ds is None:
        return {"status": "warming_up", "direction": "NEUTRAL"}
    X, y, current = ds
    try:
        from lightgbm import LGBMClassifier
        split = max(35, int(len(X) * 0.8))
        split = min(split, len(X) - 10)
        model = LGBMClassifier(
            n_estimators=100,
            max_depth=4,
            learning_rate=0.04,
            num_leaves=15,
            subsample=0.85,
            colsample_bytree=0.85,
            verbosity=-1,
            n_jobs=2,
            random_state=26,
        )
        model.fit(X[:split], y[:split])
        accuracy = float((model.predict(X[split:]) == y[split:]).mean()) if split < len(X) else None
        model.fit(X, y)
        prob = float(model.predict_proba(current)[0, 1])
        result = vote_from_probability(prob, accuracy)
        result["model"] = "LightGBM"
        result["samples"] = int(len(X))
        return result
    except Exception as exc:
        return {"status": "error", "direction": "NEUTRAL", "error": str(exc)[:160]}


def forecast_vote(last_price: float, forecast_price: float, closes: np.ndarray, horizon: int, model_name: str) -> dict[str, Any]:
    if last_price <= 0 or not math.isfinite(forecast_price):
        return {"status": "error", "direction": "NEUTRAL", "error": "invalid forecast"}
    log_returns = np.diff(np.log(np.maximum(closes[-80:], 1e-12)))
    sigma = float(np.std(log_returns)) if len(log_returns) else 0.0
    expected_return = forecast_price / last_price - 1.0
    threshold = max(0.0002, sigma * math.sqrt(max(1, horizon)) * 0.22)
    if expected_return > threshold:
        direction = "BUY"
    elif expected_return < -threshold:
        direction = "SELL"
    else:
        direction = "NEUTRAL"
    strength = abs(expected_return) / max(threshold, 1e-9)
    confidence = round(clamp(50.0 + min(45.0, strength * 14.0), 50.0, 95.0), 1)
    return {
        "status": "ok",
        "model": model_name,
        "direction": direction,
        "confidence": confidence,
        "forecast_price": round(float(forecast_price), 8),
        "expected_return_pct": round(float(expected_return * 100.0), 4),
        "volatility_threshold_pct": round(float(threshold * 100.0), 4),
        "horizon_steps": int(horizon),
    }


def candle_rows(candles: dict[str, Any], symbol: str, timeframe: str) -> list[dict[str, Any]]:
    series = candles.get("series") or {}
    rows = series.get(f"{symbol}:{timeframe}") or []
    return rows if isinstance(rows, list) else []


def chronos_forecasts(requests: list[tuple[str, list[dict[str, Any]], int]]) -> dict[str, dict[str, Any]]:
    outputs: dict[str, dict[str, Any]] = {}
    if not requests:
        return outputs
    try:
        from chronos import Chronos2Pipeline
        model_id = os.getenv("CHRONOS_MODEL", "autogluon/chronos-2-small")
        pipeline = Chronos2Pipeline.from_pretrained(model_id, device_map="cpu")
        for row_id, rows, horizon in requests:
            try:
                tail = rows[-220:]
                timestamps = pd.to_datetime([int(x["epoch"]) for x in tail], unit="s", utc=True)
                values = np.asarray([safe_float(x["close"]) for x in tail], dtype=np.float32)
                frame = pd.DataFrame({"id": row_id, "timestamp": timestamps, "target": values})
                pred = pipeline.predict_df(
                    frame,
                    prediction_length=horizon,
                    quantile_levels=[0.1, 0.5, 0.9],
                    id_column="id",
                    timestamp_column="timestamp",
                    target="target",
                )
                column = "predictions" if "predictions" in pred.columns else ("0.5" if "0.5" in pred.columns else None)
                if column is None:
                    raise RuntimeError("Chronos output missing prediction column")
                forecast_price = float(pred[column].iloc[-1])
                outputs[row_id] = forecast_vote(float(values[-1]), forecast_price, values, horizon, "Chronos-2 small")
                outputs[row_id]["model_id"] = model_id
            except Exception as exc:
                outputs[row_id] = {"status": "error", "direction": "NEUTRAL", "error": str(exc)[:160]}
    except Exception as exc:
        error = str(exc)[:160]
        for row_id, _, _ in requests:
            outputs[row_id] = {"status": "unavailable", "direction": "NEUTRAL", "error": error}
    return outputs


def timesfm_forecasts(requests: list[tuple[str, list[dict[str, Any]], int]]) -> dict[str, dict[str, Any]]:
    outputs: dict[str, dict[str, Any]] = {}
    if not requests:
        return outputs
    try:
        import timesfm
        model_id = os.getenv("TIMESFM_MODEL", "google/timesfm-2.5-200m-pytorch")
        max_horizon = max(h for _, _, h in requests)
        model = timesfm.TimesFM_2p5_200M_torch.from_pretrained(model_id, torch_compile=False)
        model.compile(timesfm.ForecastConfig(
            max_context=512,
            max_horizon=max_horizon,
            normalize_inputs=True,
            use_continuous_quantile_head=True,
            fix_quantile_crossing=True,
        ))
        inputs = [np.asarray([safe_float(x["close"]) for x in rows[-240:]], dtype=np.float32) for _, rows, _ in requests]
        # Group by horizon because TimesFM forecast uses one horizon per batch.
        by_horizon: dict[int, list[int]] = {}
        for idx, (_, _, horizon) in enumerate(requests):
            by_horizon.setdefault(horizon, []).append(idx)
        for horizon, indices in by_horizon.items():
            batch = [inputs[i] for i in indices]
            points, _ = model.forecast(horizon=horizon, inputs=batch)
            for local_idx, source_idx in enumerate(indices):
                row_id, _, _ = requests[source_idx]
                series = inputs[source_idx]
                forecast_price = float(points[local_idx][-1])
                outputs[row_id] = forecast_vote(float(series[-1]), forecast_price, series, horizon, "TimesFM 2.5")
                outputs[row_id]["model_id"] = model_id
    except Exception as exc:
        error = str(exc)[:160]
        for row_id, _, _ in requests:
            outputs[row_id] = {"status": "unavailable", "direction": "NEUTRAL", "error": error}
    return outputs


def model_weight(result: dict[str, Any]) -> float:
    confidence = safe_float(result.get("confidence"), 50.0) / 100.0
    accuracy = result.get("validation_accuracy")
    if accuracy is not None:
        confidence = (confidence + clamp(safe_float(accuracy) / 100.0, 0.45, 0.90)) / 2.0
    return clamp(confidence, 0.50, 0.95)


def combine_models(models: dict[str, dict[str, Any]]) -> dict[str, Any]:
    valid = {k: v for k, v in models.items() if v.get("status") == "ok"}
    buy_weight = 0.0
    sell_weight = 0.0
    neutral = 0
    for result in valid.values():
        weight = model_weight(result)
        if result.get("direction") == "BUY":
            buy_weight += weight
        elif result.get("direction") == "SELL":
            sell_weight += weight
        else:
            neutral += 1
    directional = buy_weight + sell_weight
    if directional <= 0:
        direction, consensus = "NEUTRAL", 0.0
    elif buy_weight >= sell_weight:
        direction, consensus = "BUY", buy_weight / directional
    else:
        direction, consensus = "SELL", sell_weight / directional
    if consensus < 0.60:
        direction = "NEUTRAL"
    confidences = [safe_float(x.get("confidence"), 50.0) for x in valid.values()]
    return {
        "direction": direction,
        "consensus": round(consensus * 100.0, 1),
        "available_models": len(valid),
        "directional_models": sum(1 for x in valid.values() if x.get("direction") in ("BUY", "SELL")),
        "neutral_models": neutral,
        "mean_confidence": round(float(np.mean(confidences)), 1) if confidences else 0.0,
        "buy_weight": round(buy_weight, 3),
        "sell_weight": round(sell_weight, 3),
    }


def cache_fresh(cache: dict[str, Any], max_minutes: int = 120) -> bool:
    try:
        stamp = datetime.fromisoformat(str(cache.get("updated_at")).replace("Z", "+00:00"))
        return (datetime.now(timezone.utc) - stamp).total_seconds() <= max_minutes * 60
    except Exception:
        return False


def apply_model_guard(row: dict[str, Any], ensemble: dict[str, Any]) -> None:
    row["model_ensemble_direction"] = ensemble.get("direction", "NEUTRAL")
    row["model_ensemble_consensus"] = safe_float(ensemble.get("consensus"))
    row["model_models_available"] = int(ensemble.get("available_models") or 0)

    verdict = row.get("final_verdict")
    execution = row.get("execution") if isinstance(row.get("execution"), dict) else {}
    if verdict not in ("BUY", "SELL") or not execution:
        return

    direction = ensemble.get("direction")
    consensus = safe_float(ensemble.get("consensus"))
    available = int(ensemble.get("available_models") or 0)
    opposite = "SELL" if verdict == "BUY" else "BUY"

    if available >= 2 and direction == opposite and consensus >= 67:
        execution["state"] = "WAIT_CONFIRMATION"
        execution["ready"] = False
        execution["score"] = min(safe_float(execution.get("score")), 77.0)
        execution["reason"] = (
            str(execution.get("reason") or "")
            + f" Open-source ensemble opposes {verdict} ({direction} {consensus:.0f}%); execution paused."
        ).strip()
    elif available >= 2 and direction == verdict and consensus >= 67:
        execution["score"] = round(clamp(safe_float(execution.get("score")) + min(5.0, (consensus - 60.0) / 6.0), 0.0, 98.0), 1)
        execution["reason"] = (
            str(execution.get("reason") or "")
            + f" Open-source ensemble confirms {verdict} ({consensus:.0f}%)."
        ).strip()

    row["execution"] = execution
    row["execution_state"] = execution.get("state", row.get("execution_state", "WAIT_CONFIRMATION"))
    row["execution_ready"] = 1 if execution.get("ready") and row["execution_state"] == "EXECUTE_NOW" else 0
    row["execution_score"] = safe_float(execution.get("score"))


def run(signals_path: Path, candles_path: Path, cache_path: Path, foundation: bool) -> None:
    signals = load_json(signals_path)
    candles = load_json(candles_path)
    if not isinstance(signals, dict) or not isinstance(signals.get("markets"), list):
        raise SystemExit("Invalid signals payload")
    if not isinstance(candles, dict) or not isinstance(candles.get("series"), dict):
        raise SystemExit("Runtime candle payload unavailable")

    previous_cache = load_json(cache_path, {}) or {}
    previous_rows = previous_cache.get("markets") if cache_fresh(previous_cache) else {}
    previous_rows = previous_rows if isinstance(previous_rows, dict) else {}

    core: dict[str, dict[str, Any]] = {}
    foundation_requests: list[tuple[str, list[dict[str, Any]], int]] = []

    for row in signals["markets"]:
        row_id = str(row.get("id") or "")
        symbol = str(row.get("symbol") or "")
        mode = str(row.get("mode") or "")
        timeframe = "M15" if mode == "day" else "H1"
        horizon = 4 if mode == "day" else 6
        rows = candle_rows(candles, symbol, timeframe)
        xgb = fit_xgboost(rows, horizon)
        lgb = fit_lightgbm(rows, horizon)
        core[row_id] = {"xgboost": xgb, "lightgbm": lgb}

    # Foundation models are most useful on the strongest current candidates.
    ranked = sorted(
        signals["markets"],
        key=lambda row: (
            1 if row.get("mode") == "swing" else 0,
            safe_float((row.get("decision_engine") or {}).get("score")),
        ),
        reverse=True,
    )
    selected_ids = {str(row.get("id")) for row in ranked[:8]}

    for row in signals["markets"]:
        row_id = str(row.get("id") or "")
        if row_id not in selected_ids:
            continue
        symbol = str(row.get("symbol") or "")
        mode = str(row.get("mode") or "")
        timeframe = "M15" if mode == "day" else "H1"
        horizon = 4 if mode == "day" else 6
        rows = candle_rows(candles, symbol, timeframe)
        if len(rows) >= 80:
            foundation_requests.append((row_id, rows, horizon))

    chronos_map: dict[str, dict[str, Any]] = {}
    timesfm_map: dict[str, dict[str, Any]] = {}
    if foundation:
        chronos_map = chronos_forecasts(foundation_requests)
        timesfm_map = timesfm_forecasts(foundation_requests)

    cache_markets: dict[str, Any] = {}
    for row in signals["markets"]:
        row_id = str(row.get("id") or "")
        prior = previous_rows.get(row_id) if isinstance(previous_rows.get(row_id), dict) else {}
        chronos_result = chronos_map.get(row_id) if foundation else prior.get("chronos2")
        timesfm_result = timesfm_map.get(row_id) if foundation else prior.get("timesfm25")
        if not chronos_result:
            chronos_result = {"status": "not_selected" if row_id not in selected_ids else "pending", "direction": "NEUTRAL"}
        if not timesfm_result:
            timesfm_result = {"status": "not_selected" if row_id not in selected_ids else "pending", "direction": "NEUTRAL"}

        models = {
            "xgboost": core[row_id]["xgboost"],
            "lightgbm": core[row_id]["lightgbm"],
            "chronos2": chronos_result,
            "timesfm25": timesfm_result,
        }
        ensemble = combine_models(models)
        row["open_source_ai"] = {
            "version": MODEL_VERSION,
            "models": models,
            "ensemble": ensemble,
            "qwen_local": {"status": "browser_optional", "model": "Qwen3-0.6B-q4f16_1-MLC"},
        }
        apply_model_guard(row, ensemble)
        cache_markets[row_id] = {"chronos2": chronos_result, "timesfm25": timesfm_result}

    signals["open_source_models"] = {
        "version": MODEL_VERSION,
        "core": ["XGBoost", "LightGBM"],
        "foundation": ["Chronos-2 small", "TimesFM 2.5 200M"],
        "browser_advisor": "Qwen3-0.6B via WebLLM",
        "foundation_ran": bool(foundation),
        "policy": "Models can confirm or pause execution timing; they cannot create a trade against the autonomous engine or bypass risk gates.",
    }
    signals["model"] = str(signals.get("model") or "Sera Autonomous Engine") + " + OSS Ensemble"
    signals["model_ensemble_updated_at"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    save_json(signals_path, signals)
    save_json(cache_path, {
        "version": MODEL_VERSION,
        "updated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "foundation_ran": bool(foundation),
        "markets": cache_markets,
    })


def self_test() -> None:
    rows = []
    base = 100.0
    for i in range(140):
        close = base + i * 0.12 + math.sin(i / 5.0)
        rows.append({"open": close - 0.1, "high": close + 0.5, "low": close - 0.5, "close": close, "epoch": 1700000000 + i * 900})
    ds = supervised_dataset(rows, 4)
    if ds is None or ds[0].shape[0] < 50:
        raise RuntimeError("feature pipeline self-test failed")
    fake = {
        "final_verdict": "BUY",
        "execution": {"state": "EXECUTE_NOW", "ready": True, "score": 82, "reason": "local"},
    }
    apply_model_guard(fake, {"direction": "SELL", "consensus": 80, "available_models": 3})
    if fake["execution_state"] != "WAIT_CONFIRMATION":
        raise RuntimeError("model guard self-test failed")
    print(MODEL_VERSION + " self-test passed")


def parse_bool(value: str) -> bool:
    return str(value).lower() in {"1", "true", "yes", "on"}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--signals", default=str(DEFAULT_SIGNALS))
    parser.add_argument("--candles", default=str(DEFAULT_CANDLES))
    parser.add_argument("--cache", default=str(DEFAULT_CACHE))
    parser.add_argument("--foundation", default="false")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    run(Path(args.signals), Path(args.candles), Path(args.cache), parse_bool(args.foundation))


if __name__ == "__main__":
    main()
