#!/usr/bin/env python3
"""Sera SMC Zones indicator (mt5/Sera_SMC_Zones.mq5): compiled as C++ against the MT5 simulator and run on generated candles.
Checks: the trend line is filled, Premium / Equilibre / Discount zones and Strong/Weak High-Low labels are drawn, BUY/SELL
arrows appear only in the drift direction (Crash/PainX BUY, Boom/GainX SELL), none on random-walk indices (Volatility, Forex),
and every arrow is on a candle where the online engine (scripts/drift-playbook.mjs, precision mode) starts a signal.
Requires g++ and node."""
from __future__ import annotations

import json
import random
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from qa_mql_cpp import to_cpp  # noqa: E402

BUILD = ROOT / "tests" / "mql" / "build"
SHIM = r'''
template<class T> bool ArraySetAsSeries(const std::vector<T>&,bool){ return true; }
enum ENUM_INDEXBUFFER_TYPE{INDICATOR_DATA,INDICATOR_COLOR_INDEX,INDICATOR_CALCULATIONS};
enum ENUM_CUSTOMIND_PROPERTY{INDICATOR_SHORTNAME,INDICATOR_DIGITS};
std::vector<std::vector<double>*> SIM_BUFFERS;
bool SetIndexBuffer(int i,std::vector<double>& b,ENUM_INDEXBUFFER_TYPE){ if((int)SIM_BUFFERS.size()<=i) SIM_BUFFERS.resize(i+1); SIM_BUFFERS[i]=&b; return true; }
bool IndicatorSetString(ENUM_CUSTOMIND_PROPERTY,const string&){ return true; }
bool IndicatorSetInteger(ENUM_CUSTOMIND_PROPERTY,long){ return true; }
int _Digits=3; int SIM_PERIOD=3600; int PeriodSeconds(){ return SIM_PERIOD; }
const color clrTomato=0x4763FF,clrSilver=0xC0C0C0,clrMediumSeaGreen=0x71B33C,clrOrange=0x00A5FF,clrLime=0x00FF00,clrRed=0x0000FF;
'''
MAIN = r'''
#include <fstream>
int main(int argc,char** argv){
  std::ifstream in(argv[1]); string name; int n;
  std::getline(in,name); in>>n;
  std::vector<datetime> t(n); std::vector<double> o(n),h(n),l(n),c(n); std::vector<long> tv(n,0),v(n,0); std::vector<int> sp(n,0);
  for(int i=0;i<n;i++){ in>>o[i]>>h[i]>>l[i]>>c[i]; t[i]=1790000000+(long)i*3600; }
  _Symbol=name;
  OnInit();
  for(auto b:SIM_BUFFERS) b->assign(n,0.0);
  int done=OnCalculate(n,0,t,o,h,l,c,tv,v,sp);
  printf("DONE %d\n",done);
  printf("TREND %.6f %.6f COLOR %d\n",TrendBuf[n-1],TrendBuf[n-2],(int)TrendColor[n-1]);
  for(auto& kv:SIM_OBJ){
    if(kv.first.rfind("SERASMC_SIG_A",0)==0) printf("ARROW %s %d\n",kv.first.c_str()+13,kv.second.type==OBJ_ARROW_BUY?1:-1);
    else if(kv.first.rfind("SERASMC_",0)==0) printf("OBJ %s %s\n",kv.first.c_str()+8,kv.second.strs[OBJPROP_TEXT].c_str());
  }
  OnDeinit(0);
  int left=0; for(auto& kv:SIM_OBJ) if(kv.first.rfind("SERASMC_",0)==0) left++;
  printf("LEFT %d\n",left);
  return 0;
}
'''
JS = r'''
import {driftPlaybook} from './drift-playbook.mjs';
import fs from 'node:fs';
const k=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const rows=k.o.map((o,i)=>({open:o,high:k.h[i],low:k.l[i],close:k.c[i],epoch:i*3600}));
const start=Math.max(23,rows.length-2-500);let was=false;const out=[];
for(let i=1;i<=rows.length-2;i++){ if(i<start||i<210)continue;
  const p=driftPlaybook(k.name,rows.slice(0,i+1));const act=!!(p&&p.active&&p.liquidity_sweep);
  if(act&&!was)out.push([i,p.side==='BUY'?1:-1]);was=act;}
console.log(JSON.stringify(out));
'''


def candles(rnd: random.Random, n: int, drift: float, pull: int):
    p, o, h, l, c = 1000.0, [], [], [], []
    for i in range(n):
        d = drift if (pull == 0 or i % pull < pull - 4) else -drift * 2.5
        op = p
        p = max(1.0, p * (1 + d + rnd.gauss(0, 0.004)))
        o.append(op); c.append(p)
        h.append(max(op, p) * (1 + abs(rnd.gauss(0, 0.0015))))
        l.append(min(op, p) * (1 - abs(rnd.gauss(0, 0.0015))))
    return o, h, l, c


def main() -> int:
    BUILD.mkdir(parents=True, exist_ok=True)
    src = to_cpp((ROOT / "mt5" / "Sera_SMC_Zones.mq5").read_text(encoding="utf-8"))
    for a, b in (("const long &tick_volume[]", "const std::vector<long> &tick_volume"), ("const long &volume[]", "const std::vector<long> &volume"),
                 ("const int &spread[]", "const std::vector<int> &spread")):
        src = src.replace(a, b)
    src = '#include "../mt5sim.h"\n' + SHIM + src
    cpp = BUILD / "indicator.cpp"
    cpp.write_text(src + MAIN, encoding="utf-8")
    exe = BUILD / "indicator"
    subprocess.run(["g++", "-std=c++17", "-O1", "-w", "-o", str(exe), str(cpp)], check=True)
    (ROOT / "scripts" / "_ind_parity.mjs").write_text(JS)
    errors, total_arrows = [], 0
    try:
        for name, drift, expect in (("Crash 500 Index", 0.0012, 1), ("PainX 800", 0.0010, 1), ("Boom 1000 Index", -0.0012, -1),
                                     ("GainX 1200", -0.0010, -1), ("Volatility 75 Index", 0.0, 0), ("EURUSD", 0.0006, 0)):
            rnd = random.Random(hash(name) % 1000)
            o, h, l, c = candles(rnd, 1400, drift, 13)
            f = BUILD / "ind_case.txt"
            f.write_text(name + "\n" + str(len(c)) + "\n" + " ".join(f"{a!r} {b!r} {x!r} {y!r}" for a, b, x, y in zip(o, h, l, c)) + "\n")
            out = subprocess.run([str(exe), str(f)], capture_output=True, text=True, check=True).stdout
            arrows = [(int(a.split()[1]), int(a.split()[2])) for a in out.splitlines() if a.startswith("ARROW ")]
            objs = {a.split()[1]: " ".join(a.split()[2:]) for a in out.splitlines() if a.startswith("OBJ ")}
            if "DONE 1400" not in out or "TREND 0.000000" in out:
                errors.append(f"{name}: OnCalculate did not fill the trend line")
            for z in ("PREMIUM", "EQUILIBRE", "DISCOUNT", "PREMIUM_T", "EQUILIBRE_T", "DISCOUNT_T", "HIGH_T", "LOW_T"):
                if z not in objs:
                    errors.append(f"{name}: zone/label {z} not drawn")
            if not (("Strong High" in objs.get("HIGH_T", "") and "Weak Low" in objs.get("LOW_T", "")) or
                    ("Weak High" in objs.get("HIGH_T", "") and "Strong Low" in objs.get("LOW_T", ""))):
                errors.append(f"{name}: Strong/Weak High-Low labels inconsistent: {objs.get('HIGH_T')} / {objs.get('LOW_T')}")
            if "LEFT 0" not in out:
                errors.append(f"{name}: objects left on the chart after removing the indicator")
            if expect == 0 and arrows:
                errors.append(f"{name}: random-walk market must not get BUY/SELL arrows")
            if expect and any(s != expect for _, s in arrows):
                errors.append(f"{name}: arrow against the drift direction")
            if expect:
                jf = BUILD / "ind_case.json"
                jf.write_text(json.dumps({"name": name, "o": o, "h": h, "l": l, "c": c}))
                js = json.loads(subprocess.run(["node", "scripts/_ind_parity.mjs", str(jf)], cwd=ROOT, capture_output=True, text=True, check=True).stdout)
                if sorted(arrows) != sorted(tuple(x) for x in js):
                    errors.append(f"{name}: indicator arrows {sorted(arrows)[:6]} != online engine signals {js[:6]}")
                total_arrows += len(arrows)
    finally:
        (ROOT / "scripts" / "_ind_parity.mjs").unlink(missing_ok=True)
    if total_arrows < 3:
        errors.append(f"only {total_arrows} arrows in the drift cases: signals not exercised")
    if errors:
        print("\n".join("ERROR: " + e for e in errors[:20]))
        return 1
    print(f"Sera SMC Zones indicator passed: zones, Strong/Weak labels, {total_arrows} arrows identical to the online engine")
    return 0


if __name__ == "__main__":
    sys.exit(main())
