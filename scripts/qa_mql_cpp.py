#!/usr/bin/env python3
"""Compile each EA as C++ (g++ -fsyntax-only) against tests/mql/mt5stubs.h, which declares the
MT5 API it uses. MQL5 is close enough to C++ that this catches type errors, wrong argument
counts, undeclared names and duplicated definitions before the code reaches MetaEditor.
Usage: qa_mql_cpp.py file.mq5 [...]"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "tests" / "mql" / "build"
TYPES = r"(double|MqlRates|string|int|SwxDecision|datetime|char)"


def to_cpp(src: str) -> str:
    src = re.sub(r"^#property.*$", "", src, flags=re.M).replace("#include <Trade/Trade.mqh>", '#include "../mt5stubs.h"')
    src = re.sub(rf"\b{TYPES}\s+((?:\w+\[\]\s*,\s*)*\w+\[\])\s*;",
                 lambda m: f"std::vector<{m.group(1)}> " + ", ".join(x.strip()[:-2] for x in m.group(2).split(",")) + ";", src)
    src = re.sub(rf"const {TYPES} &(\w+)\[\]", lambda m: f"const std::vector<{m.group(1)}> &{m.group(2)}", src)
    return src.replace("const string ", "const string& ")


def main() -> int:
    BUILD.mkdir(parents=True, exist_ok=True)
    failed = False
    for path in sys.argv[1:]:
        out = BUILD / (Path(path).stem + ".cpp")
        out.write_text(to_cpp(Path(path).read_text(encoding="utf-8")), encoding="utf-8")
        res = subprocess.run(["g++", "-std=c++17", "-fsyntax-only", "-Wall", "-Wno-unused-variable",
                              "-Wno-unused-but-set-variable", str(out)], capture_output=True, text=True)
        problems = [l for l in res.stderr.splitlines() if "error" in l or "warning" in l]
        print(f"{path}: {'OK' if res.returncode == 0 and not problems else 'ERRORS'}")
        for line in problems[:20]:
            print("  ", line)
        failed |= res.returncode != 0 or bool(problems)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
