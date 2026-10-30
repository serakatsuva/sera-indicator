#!/usr/bin/env python3
"""Locate the versioned EA files and check that the version in each file name matches the
#property version inside it (Sera_EA_Swing_Intelligent_Deriv_v2.31.mq5 <-> "2.31").

Usage:
  ea_files.py            -> check, print the files
  ea_files.py --paths    -> print the paths only (for shell commands in CI)
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FAMILIES = ("Deriv", "Weltrade", "Scalping")
PREFIX = {"Deriv": "Sera_EA_Swing_Intelligent_Deriv", "Weltrade": "Sera_EA_Swing_Intelligent_Weltrade",
          "Scalping": "Sera_EA_Scalping_Intelligent"}


def ea_path(family: str) -> Path:
    found = sorted((ROOT / "mt5").glob(f"{PREFIX[family]}_v*.mq5"))
    if len(found) != 1:
        raise SystemExit(f"expected exactly one versioned {family} EA in mt5/, found {[p.name for p in found]}")
    return found[0]


def check() -> list[str]:
    errors = []
    for family in FAMILIES:
        path = ea_path(family)
        name_version = re.search(r"_v(\d+\.\d+)\.mq5$", path.name)
        code_version = re.search(r'#property\s+version\s+"([^"]+)"', path.read_text(encoding="utf-8"))
        if not name_version or not code_version:
            errors.append(f"{path.name}: version missing in file name or #property version")
        elif name_version.group(1) != code_version.group(1):
            errors.append(f"{path.name}: file name says v{name_version.group(1)} but #property version is {code_version.group(1)}")
    html = (ROOT / "index.html").read_text(encoding="utf-8")
    for family in FAMILIES:
        if f"./mt5/{ea_path(family).name}" not in html:
            errors.append(f"index.html download link does not point to {ea_path(family).name}")
    return errors


if __name__ == "__main__":
    if "--paths" in sys.argv:
        print(" ".join(str(ea_path(f).relative_to(ROOT)) for f in FAMILIES))
        sys.exit(0)
    problems = check()
    for family in FAMILIES:
        print(f"{family}: {ea_path(family).name}")
    if problems:
        print("\n".join("ERROR: " + p for p in problems))
        sys.exit(1)
    print("EA file names and versions OK")
