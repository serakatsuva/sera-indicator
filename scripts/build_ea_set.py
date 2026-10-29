#!/usr/bin/env python3
"""Build the MT5 preset (.set) file of each EA from its `input` declarations, so the preset
always matches the EA version: mt5/Sera_EA_Swing_Intelligent_<Family>_vX.YY.set

MT5 loads it from the EA settings window (Inputs tab > Load). Written as UTF-16 LE with BOM,
the encoding MetaTrader itself uses for .set files.
Usage: build_ea_set.py [--check]   (--check: fail if a .set file is missing or out of date)"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from ea_files import FAMILIES, ea_path  # noqa: E402

INPUT = re.compile(r'^\s*input\s+(\w+)\s+(\w+)\s*=\s*(.+?)\s*;\s*(?://\s*(.*))?$')


def preset(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    version = re.search(r'#property\s+version\s+"([^"]+)"', text).group(1)
    lines = [f"; {path.stem} — preset MT5 (parametres par defaut de la version {version})",
             "; MT5 : clic droit sur l'EA > Proprietes > onglet Parametres > Charger"]
    for line in text.splitlines():
        m = INPUT.match(line)
        if not m:
            continue
        kind, name, value, _ = m.groups()
        if kind == "string":
            value = value.strip().strip('"')
        lines.append(f"{name}={value}")
    return "\r\n".join(lines) + "\r\n"


def main() -> int:
    check = "--check" in sys.argv
    stale = []
    for family in FAMILIES:
        ea = ea_path(family)
        target = ea.with_suffix(".set")
        content = preset(ea)
        if check:
            if not target.exists() or target.read_bytes() != b"\xff\xfe" + content.encode("utf-16-le"):
                stale.append(target.name)
            continue
        for old in ea.parent.glob(f"Sera_EA_Swing_Intelligent_{family}_v*.set"):
            if old != target:
                old.unlink()
        target.write_bytes(b"\xff\xfe" + content.encode("utf-16-le"))
        print(f"{target.name}: {content.count(chr(10)) - 2} parametres")
    if stale:
        print("ERROR: .set file missing or out of date (run scripts/build_ea_set.py): " + ", ".join(stale))
        return 1
    if check:
        print("EA .set presets up to date")
    return 0


if __name__ == "__main__":
    sys.exit(main())
