#!/usr/bin/env python3
"""Drift Playbook parity: the Weltrade EA (DriftCompute, MQL5 compiled as C++) and scripts/drift-playbook.mjs (used by
the online engine and measured by scripts/backtest-playbook.mjs) must give the same side, activation, RSI, ATR and
levels on the same candles. Also checks the family mapping (PainX BUY, GainX SELL, SwitchX/BreakX/TrendX by trend,
no playbook on FX Vol / FlipX / Volatility). Requires g++ and node."""
from __future__ import annotations

import json
import random
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from ea_files import ea_path          # noqa: E402
from qa_mql_cpp import to_cpp         # noqa: E402

BUILD = ROOT / "tests" / "mql" / "build"
NAMES = ["PainX 800", "GainX 1200", "MAX PainX 1000", "MAX GainX 2000", "SwitchX 600", "BreakX 1200", "TrendX 1800",
         "Boom 1000 Index", "Crash 500 Index", "Bull Market Index", "Bear Market Index", "FX Vol 40", "FlipX 3", "Volatility 75 Index"]

MAIN = r'''
#include <fstream>
int main(int argc,char** argv){
  std::ifstream in(argv[1]); string name; int n;
  while(std::getline(in,name)){
    in>>n; std::vector<double> h(n),l(n),c(n);
    for(int i=0;i<n;i++) in>>h[i]>>l[i]>>c[i];
    in.ignore(1000,'\n');
    DriftInfo r; bool ok=DriftCompute(name,h,l,c,n,r);
    printf("%s|%d|%d|%s|%s|%d|%.10g|%.10g|%.10g|%.10g|%.10g|%.10g|%.10g\n",name.c_str(),ok?1:0,r.active?1:0,r.group.c_str(),r.side.c_str(),r.sweep?1:0,
           r.rsi,r.atr,r.entry,r.sl,r.tp1,r.tp3,r.tp5);
  }
  return 0;
}
'''

JS = r'''
import {driftPlaybook} from './drift-playbook.mjs';
import fs from 'node:fs';
const cases=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
for(const k of cases){
  const rows=k.h.map((h,i)=>({high:h,low:k.l[i],close:k.c[i],open:k.c[i],epoch:i*3600}));
  const p=driftPlaybook(k.name,rows);
  const lv=p?.levels||{};
  console.log([k.name,p?1:0,p?.active?1:0,p?.group||'',p?.side||'NEUTRE',p?.liquidity_sweep?1:0,p?.rsi??50,p?.atr??0,lv.entry??0,lv.sl??0,lv.tp1??0,lv.tp3??0,lv.tp5??0].join('|'));
}
'''


def series(rnd: random.Random, n: int, drift: float, pull_every: int) -> tuple[list, list, list]:
    p, h, l, c = 1000.0 * (1 + rnd.random()), [], [], []
    for i in range(n):
        d = drift if (pull_every == 0 or i % pull_every < pull_every - 4) else -drift * 2.5
        o = p
        p = max(1.0, p * (1 + d + rnd.gauss(0, 0.004)))
        h.append(max(o, p) * (1 + abs(rnd.gauss(0, 0.001))))
        l.append(min(o, p) * (1 - abs(rnd.gauss(0, 0.001))))
        c.append(p)
    return h, l, c


def main() -> int:
    BUILD.mkdir(parents=True, exist_ok=True)
    src = to_cpp(ea_path("Weltrade").read_text(encoding="utf-8")).replace('#include "../mt5stubs.h"', '#include "../mt5sim.h"')
    cpp = BUILD / "drift_playbook.cpp"
    cpp.write_text(src + MAIN, encoding="utf-8")
    exe = BUILD / "drift_playbook"
    subprocess.run(["g++", "-std=c++17", "-O1", "-w", "-o", str(exe), str(cpp)], check=True)
    rnd = random.Random(7)
    cases = []
    for k in range(240):
        name = NAMES[k % len(NAMES)]
        drift = rnd.choice([0.0015, -0.0015, 0.0006, -0.0006, 0.0])
        h, l, c = series(rnd, rnd.choice([150, 260, 960]), drift, rnd.choice([0, 9, 15, 30]))
        cases.append({"name": name, "h": h, "l": l, "c": c})
    txt = BUILD / "drift_cases.txt"
    with txt.open("w") as f:
        for k in cases:
            f.write(k["name"] + "\n" + str(len(k["c"])) + "\n")
            f.write(" ".join(f"{a!r} {b!r} {x!r}" for a, b, x in zip(k["h"], k["l"], k["c"])) + "\n")
    js_cases = BUILD / "drift_cases.json"
    js_cases.write_text(json.dumps(cases))
    (ROOT / "scripts" / "_drift_parity.mjs").write_text(JS)
    try:
        js = subprocess.run(["node", "scripts/_drift_parity.mjs", str(js_cases)], cwd=ROOT, capture_output=True, text=True, check=True).stdout.split("\n")
    finally:
        (ROOT / "scripts" / "_drift_parity.mjs").unlink(missing_ok=True)
    mq = subprocess.run([str(exe), str(txt)], capture_output=True, text=True, check=True).stdout.split("\n")
    errors, active, sweeps = [], 0, 0
    for a, b in zip([x for x in mq if x], [x for x in js if x]):
        ma, jb = a.split("|"), b.split("|")
        if ma[1] == "0" and jb[1] == "0" and ma[0] == jb[0]:
            continue                       # too few candles / no playbook on both sides
        if ma[:6] != jb[:6]:
            errors.append(f"MQL {ma[:6]} != JS {jb[:6]}")
            continue
        active += ma[2] == "1"
        sweeps += ma[5] == "1"
        for x, y in zip(ma[6:], jb[6:]):
            x, y = float(x), float(y)
            if abs(x - y) > 1e-6 * max(1.0, abs(y)):
                errors.append(f"{ma[0]}: value {x} != {y}")
                break
    expected = {"PainX 800": "BUY", "GainX 1200": "SELL", "MAX PainX 1000": "BUY", "MAX GainX 2000": "SELL",
                "Boom 1000 Index": "SELL", "Crash 500 Index": "BUY", "Bull Market Index": "BUY", "Bear Market Index": "SELL"}
    for line in mq:
        if not line:
            continue
        f = line.split("|")
        if f[0] in expected and f[1] == "1" and f[4] != expected[f[0]]:
            errors.append(f"{f[0]} must always be {expected[f[0]]}, got {f[4]}")
        if f[0] in ("FX Vol 40", "FlipX 3", "Volatility 75 Index") and (f[1] == "1" or f[3]):
            errors.append(f"{f[0]}: random-walk index must have no playbook")
    if len([x for x in mq if x]) != len(cases) or active < 5:
        errors.append(f"expected {len(cases)} results with active signals, got {len([x for x in mq if x])} / {active} active")
    if errors:
        print("\n".join("ERROR: " + e for e in errors[:20]))
        return 1
    if sweeps < 3:
        errors.append(f"only {sweeps} liquidity sweeps in the test cases: the SMC sweep is not exercised")
    if errors:
        print("\n".join("ERROR: " + e for e in errors[:20]))
        return 1
    print(f"Drift Playbook parity passed: {len(cases)} cases, {active} active signals, {sweeps} liquidity sweeps, EA == online engine")
    return 0


if __name__ == "__main__":
    sys.exit(main())
