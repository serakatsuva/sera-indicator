#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import smtplib
import ssl
from email.message import EmailMessage
from pathlib import Path
from typing import Any

SIGNALS = Path(os.getenv("SERA_SIGNALS_PATH", "data/signals.json"))
STATE = Path(os.getenv("SERA_EMAIL_STATE_PATH", "data/email-alert-state.json"))


def load(path: Path, default: Any):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def save(path: Path, data: Any):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def fmt(value: Any) -> str:
    try:
        return f"{float(value):,.3f}"
    except Exception:
        return "—"


def fmt_int(value: Any) -> str:
    try:
        return f"{int(round(float(value))):,}"
    except Exception:
        return "—"


def setup_fingerprint(row: dict[str, Any]) -> str:
    plan = row.get("setup_entry_plan") or {}
    return "|".join([
        str(row.get("setup_direction") or ""),
        str(row.get("execution_state") or ""),
        str(plan.get("status") or ""),
        str(round(float(plan.get("suggested_entry") or 0), 3)),
        str(round(float(row.get("final_confidence") or 0), 0)),
    ])


def is_alertable(row: dict[str, Any]) -> bool:
    return (
        row.get("mode") == "swing"
        and bool(row.get("setup_detected"))
        and row.get("setup_direction") in ("BUY", "SELL")
        and isinstance(row.get("setup_entry_plan"), dict)
    )


def render_row(row: dict[str, Any]) -> str:
    plan = row.get("setup_entry_plan") or {}
    levels = row.get("levels") or row.get("projected_levels") or {}
    distance = row.get("swing_distance") or row.get("projected_swing_distance") or {}
    timing = row.get("timing") or {}
    ensemble = ((row.get("open_source_ai") or {}).get("ensemble") or {})
    engine = row.get("decision_engine") or {}
    execution = row.get("execution") or {}

    reliable = ensemble.get("reliable_models", ensemble.get("available_models", 0))
    configured = ensemble.get("configured_models", 4)
    consensus = ensemble.get("consensus")
    consensus_text = "aucun vote directionnel fiable"
    if consensus is not None:
        consensus_text = f"{ensemble.get('direction','NEUTRAL')} {float(consensus):.0f}%"

    return f"""
{row.get('market','—')} — SWING {row.get('setup_direction','—')}
État entrée : {row.get('execution_state','WAIT_CONFIRMATION')}
Plan setup : {plan.get('status','—')}
Entrée proposée : {fmt(plan.get('suggested_entry'))}
Zone d'entrée : {fmt(plan.get('zone_min'))} – {fmt(plan.get('zone_max'))}
Prix de référence : {fmt(plan.get('live_reference_price'))}

SL : {fmt(levels.get('sl'))}
TP1 : {fmt(levels.get('tp1'))}
TP2 : {fmt(levels.get('tp2'))}
TP3 : {fmt(levels.get('tp3'))}
TP4 : {fmt(levels.get('tp4'))}
TP5 : {fmt(levels.get('tp5'))}

Amplitude estimée : {fmt(distance.get('estimated_swing_price_distance'))} pts · ≈ {fmt_int(distance.get('estimated_swing_pips_points'))} pips/points
Durée estimée : {timing.get('swing_days_label') or '—'}
Confiance finale : {row.get('final_confidence','—')}%
Conditions : {engine.get('condition_pass_percent','—')}%
Consensus stratégies : {engine.get('consensus','—')}%
Modèles open source : {reliable}/{configured} fiables · {consensus_text}
Score exécution : {row.get('execution_score','—')}%

Raison : {execution.get('reason') or plan.get('reason') or '—'}
""".strip()


def send_email(sender: str, password: str, recipient: str, subject: str, body: str):
    msg = EmailMessage()
    msg["From"] = sender
    msg["To"] = recipient
    msg["Subject"] = subject
    msg.set_content(body)
    context = ssl.create_default_context()
    with smtplib.SMTP("smtp.gmail.com", 587, timeout=30) as smtp:
        smtp.ehlo()
        smtp.starttls(context=context)
        smtp.ehlo()
        smtp.login(sender, password)
        smtp.send_message(msg)


def main():
    sender = os.getenv("GMAIL_ALERT_FROM", "").strip()
    password = os.getenv("GMAIL_APP_PASSWORD", "").strip()
    recipient = os.getenv("GMAIL_ALERT_TO", "").strip()

    if not sender or not password or not recipient:
        print("Sera Gmail alert: secrets not configured; skipping email delivery.")
        return

    signals = load(SIGNALS, {})
    markets = signals.get("markets") or []
    state = load(STATE, {"setups": {}})
    previous = state.get("setups") or {}

    changed = []
    current = {}
    for row in markets:
        if not is_alertable(row):
            continue
        setup_id = str(row.get("id") or f"{row.get('symbol')}:{row.get('mode')}")
        fingerprint = setup_fingerprint(row)
        current[setup_id] = fingerprint
        if previous.get(setup_id) != fingerprint:
            changed.append(row)

    if not changed:
        print("Sera Gmail alert: no new or changed Swing setups.")
        save(STATE, {"updated_at": signals.get("updated_at"), "setups": current})
        return

    actionable = sorted(
        changed,
        key=lambda r: (
            1 if r.get("execution_state") == "EXECUTE_NOW" else 0,
            float(r.get("execution_score") or 0),
            float((r.get("decision_engine") or {}).get("condition_pass_percent") or 0),
        ),
        reverse=True,
    )

    subject_direction = actionable[0].get("setup_direction", "SWING")
    subject_market = actionable[0].get("market", "Sera")
    if len(actionable) == 1:
        subject = f"Sera Swing Alert · {subject_market} · {subject_direction}"
    else:
        subject = f"Sera Swing Alert · {len(actionable)} setups détectés"

    body = [
        "SERA INDICATOR — ALERTE SWING",
        f"Analyse : {signals.get('updated_at','—')}",
        f"Moteur : {signals.get('engine_version','—')}",
        "",
        "Un setup détecté n'est pas forcément une entrée immédiate. Vérifier le statut d'entrée ci-dessous.",
        "",
        "\n\n" + ("\n\n" + ("-" * 68) + "\n\n").join(render_row(row) for row in actionable),
        "",
        "Sera n'exécute automatiquement que les setups qui passent à EXECUTE_NOW et les garde-fous EA.",
    ]
    send_email(sender, password, recipient, subject, "\n".join(body))
    save(STATE, {"updated_at": signals.get("updated_at"), "setups": current})
    print(f"Sera Gmail alert: sent {len(actionable)} setup(s) to {recipient}.")


if __name__ == "__main__":
    main()
