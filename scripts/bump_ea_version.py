#!/usr/bin/env python3
"""Bump an EA version: renames the file (git mv), sets #property version and updates the version
shown to the user (texts inside string literals: dashboard title, journal, order comments).
Comments are left untouched, so notes like "// v2.52 : ..." keep the version that introduced them.
Usage: bump_ea_version.py Deriv|Weltrade NEW_VERSION"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ea_files import ea_path  # noqa: E402

STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"')


def main() -> int:
    family, new = sys.argv[1], sys.argv[2]
    old_path = ea_path(family)
    text = old_path.read_text(encoding="utf-8")
    old = re.search(r'#property\s+version\s+"([^"]+)"', text).group(1)
    text = re.sub(r'(#property\s+version\s+")[^"]+"', rf'\g<1>{new}"', text, count=1)
    text = STRING.sub(lambda m: m.group(0).replace("v" + old, "v" + new), text)
    new_path = old_path.with_name(old_path.name.replace(f"_v{old}.mq5", f"_v{new}.mq5"))
    if new_path != old_path:
        subprocess.run(["git", "mv", str(old_path), str(new_path)], check=True)
    new_path.write_text(text, encoding="utf-8")
    if family == "Deriv":
        (new_path.parent / "Sera_Swing_Executor.mq5").write_text(text, encoding="utf-8")
    index = Path("index.html")
    html = index.read_text(encoding="utf-8")
    html = html.replace(f"Sera_EA_Swing_Intelligent_{family}_v{old}.mq5", new_path.name)
    html = html.replace(f"EA {family} v{old}<", f"EA {family} v{new}<").replace(f"{family} v{old}", f"{family} v{new}")
    index.write_text(html, encoding="utf-8")
    print(f"{family}: v{old} -> v{new} ({new_path.name})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
