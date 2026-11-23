"""Forward completed MT5 signal exports to a GitHub Actions workflow."""

import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import re
import time
from urllib.error import URLError
from urllib.request import Request, urlopen

DEFAULT_REPOSITORY = "serakatsuva/sera-indicator"
EVENT_TYPE = "sera-boom-crash-signal-v1"
NUMERIC_FIELDS = ("entry", "stop", "target", "reward_risk", "atr", "origin_h1", "obstacle_h1", "spread")


def read_signal(path: Path) -> dict:
    with path.open(encoding="utf-8-sig", newline="") as file:
        rows = list(csv.reader(file))
    if len(rows) != 1 or len(rows[0]) != 5 + len(NUMERIC_FIELDS):
        raise ValueError("Format CSV de signal incorrect")
    local_id, symbol, side, impulse, confirmation, *numbers = rows[0]
    if not local_id or not symbol or side not in {"BUY", "SELL"}:
        raise ValueError("Identifiant, symbole ou direction invalide")
    values = dict(zip(NUMERIC_FIELDS, map(float, numbers), strict=True))
    if not all(math.isfinite(value) for value in values.values()):
        raise ValueError("Prix ou métrique non fini")
    return {
        "schema_version": 1,
        "id": hashlib.sha256(local_id.encode()).hexdigest(),
        "symbol": symbol,
        "side": side,
        "impulse_mt5_time": impulse,
        "confirmation_mt5_time": confirmation,
        **values,
    }


def dispatch(repository: str, token: str, signal: dict) -> None:
    body = {"event_type": EVENT_TYPE, "client_payload": {"signal": signal}}
    request = Request(
        f"https://api.github.com/repos/{repository}/dispatches",
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urlopen(request, timeout=20) as response:
        if response.status != 204:
            raise RuntimeError(f"Réponse inattendue de GitHub ({response.status})")


def run_batch(directory: Path, repository: str, token: str, preview: bool) -> bool:
    success = True
    for path in sorted(directory.glob("*.csv"), key=lambda item: item.stat().st_mtime):
        receipt = path.with_suffix(f".{repository.replace('/', '_')}.sent")
        if receipt.exists():
            continue
        try:
            signal = read_signal(path)
        except (OSError, ValueError) as error:
            print(f"CSV ignoré ({path.name}) — {error}", flush=True)
            success = False
            continue
        if preview:
            print(json.dumps(signal, ensure_ascii=False), flush=True)
            continue
        try:
            dispatch(repository, token, signal)
            receipt.touch()
            print(f"GitHub a accepté {signal['symbol']} {signal['side']} {signal['id'][:12]}", flush=True)
        except (OSError, URLError, RuntimeError) as error:
            print(f"Envoi interrompu — {error}", flush=True)
            return False
    return success


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    windows_default = Path(os.environ.get("APPDATA", "~")).expanduser()
    windows_default /= "MetaQuotes/Terminal/Common/Files/SeraBoomCrash"
    parser.add_argument("--directory", type=Path, default=windows_default)
    parser.add_argument("--repository", default=DEFAULT_REPOSITORY)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--watch", action="store_true", help="Vérifier les nouveaux exports toutes les 30 secondes")
    mode.add_argument("--preview", action="store_true", help="Afficher les données sans les transmettre")
    args = parser.parse_args()
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", args.repository, flags=re.ASCII):
        parser.error("Le dépôt doit respecter le format propriétaire/nom.")
    if not args.directory.is_dir():
        parser.error(f"Dossier introuvable. Vérifie le chemin des exports MT5 ({args.directory}).")
    token = os.environ.get("SERA_GITHUB_TOKEN", "").strip()
    if not args.preview and not token:
        parser.error("Définis SERA_GITHUB_TOKEN dans cet environnement.")
    try:
        while True:
            sent = run_batch(args.directory, args.repository, token, args.preview)
            if not args.watch:
                return 0 if sent else 1
            time.sleep(30)
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
