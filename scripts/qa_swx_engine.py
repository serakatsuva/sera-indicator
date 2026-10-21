#!/usr/bin/env python3
"""Equivalence test: Weltrade SyntX EA analysis engine (MQL5) vs the production engine (JS).

The MQL5 analysis section of mt5/Sera_EA_Swing_Intelligent_Weltrade.mq5 is compiled as C++ through a
small shim (tests/mql/shim.h), then fed the same candles / indicators as the JavaScript
engine in scripts/update-signals.mjs. Three suites must match value for value:
  1. indicators of one timeframe (EMA, Wilder RSI/ATR/ADX, MACD, structure, regime...),
  2. full Swing decision on simulated H1/H4/D1 markets (score, consensus, verdict, state),
  3. signal path on crafted indicators (BUY/SELL, EXECUTE_NOW, WAIT_RETRACE, SL/TP levels).
Requires g++ and node.
"""
from __future__ import annotations

import json
import math
import random
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / "tests" / "mql"
BUILD = TESTS / "build"
EA = ROOT / "mt5" / "Sera_EA_Swing_Intelligent_Weltrade.mq5"
ENGINE_JS = ROOT / "scripts" / "update-signals.mjs"
SEP = "// ===================================================================================\n"


def translate_engine() -> None:
    src = EA.read_text(encoding="utf-8")
    eng = src[src.index(SEP + "//  MOTEUR D'ANALYSE"):src.index(SEP + "//  SCANNER")]
    eng = re.sub(r"\b(double|MqlRates)\s+((?:\w+\[\]\s*,\s*)*\w+\[\])\s*;",
                 lambda m: f"std::vector<{m.group(1)}> " + ", ".join(x.strip()[:-2] for x in m.group(2).split(",")) + ";", eng)
    for a, b in (("const double &v[]", "const std::vector<double> &v"), ("const double &c[]", "const std::vector<double> &c"),
                 ("const double &src[]", "const std::vector<double> &src"), ("const string symbol", "const string& symbol"),
                 ("const string family", "const string& family"), ("const string bias", "const string& bias"),
                 ("const ENUM_TIMEFRAMES tf", "ENUM_TIMEFRAMES tf")):
        eng = eng.replace(a, b)
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD / "engine.cpp").write_text('#include "../shim.h"\n' + eng, encoding="utf-8")
    fake = eng.replace("!InspectTf(symbol,PERIOD_H1,e) || !InspectTf(symbol,PERIOD_H4,cf) || !InspectTf(symbol,PERIOD_D1,dd)",
                       "!FakeInspect(PERIOD_H1,e) || !FakeInspect(PERIOD_H4,cf) || !FakeInspect(PERIOD_D1,dd)")
    if fake == eng:
        raise SystemExit("could not locate InspectTf calls in Decide()")
    (BUILD / "engine_fake.cpp").write_text('#include "../shim.h"\nstruct TfInfo;\nbool FakeInspect(ENUM_TIMEFRAMES tf,TfInfo &r);\n' + fake, encoding="utf-8")


def compile_all() -> None:
    for name in ("indicators", "decision", "signals"):
        subprocess.run(["g++", "-std=c++17", "-O1", "-Wall", "-Wno-unused-variable", "-o", str(BUILD / name),
                        str(TESTS / f"main_{name}.cpp")], check=True, cwd=TESTS)


def series(rnd: random.Random, drift, vol, step, base, n, now, pull=0, pullk=1.5, spikes=False):
    p, rows = base, []
    for i in range(n):
        o = p
        d = drift if (pull == 0 or i % pull < pull - 3) else -drift * pullk
        c = o + d + rnd.gauss(0, vol)
        if spikes and i % 37 == 0:
            c += vol * 12 * (1 if rnd.random() < 0.5 else -1)
        h = max(o, c) + abs(rnd.gauss(0, vol * 0.5))
        l = min(o, c) - abs(rnd.gauss(0, vol * 0.5))
        rows.append({"epoch": now - (n - 1 - i) * step, "open": o, "high": h, "low": l, "close": c})
        p = c
    return rows


def write_csv(path: Path, rows) -> None:
    path.write_text("".join(f"{r['epoch']},{r['open']!r},{r['high']!r},{r['low']!r},{r['close']!r}\n" for r in rows))


def node(script: str, *args: str) -> dict:
    out = subprocess.run(["node", "--input-type=module", "-e", script, *args], check=True, capture_output=True, text=True, cwd=BUILD)
    return json.loads(out.stdout)


JS_API = f"""
import fs from 'node:fs';
const src=fs.readFileSync({json.dumps(str(ENGINE_JS))},'utf8');
const api=new Function('ENGINE_VERSION',src.slice(src.indexOf('const MODES='),src.indexOf('function finalize('))+
 ';return {{inspectCandles,technicalSetup,attachTrendMemory,attachFamilyContext,autonomousDecision,executionAssessment,buildLevels,MODES}};')('qa');
const meta={{market:'FX Vol 40',symbol:'FXVOL40',family:'volatility',spikeBias:'NONE'}};
function decide(mk){{
  const first=api.attachTrendMemory(mk(0),null);
  const prev={{markets:[{{id:'FXVOL40:swing',timing:{{bias:first.trend_memory.current_bias}},trend_memory:first.trend_memory,entry_tf:first.entry_tf}}]}};
  const setup=api.attachFamilyContext(api.attachTrendMemory(mk(1),prev),new Map());
  const engine=api.autonomousDecision(setup);
  const levels=engine.verdict==='ATTENDRE'?null:api.buildLevels(setup,engine.verdict);
  const ex=api.executionAssessment(setup,engine,engine.verdict,levels);
  return {{verdict:engine.verdict,state:ex.state,setup:engine.setup_type,score:engine.score,consensus:engine.consensus,
          conditions:engine.condition_pass_percent,exec:ex.score,cycles:setup.trend_memory.bias_cycles,sl:levels?.sl??0,tp3:levels?.tp3??0}};
}}
"""


def same(a, b) -> bool:
    if isinstance(b, bool) or isinstance(a, bool):
        return bool(a) == bool(b)
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return math.isclose(a, b, rel_tol=1e-6, abs_tol=1e-6)
    return a == b


def run() -> int:
    translate_engine()
    compile_all()
    now = int(time.time()) // 3600 * 3600 - 3600
    errors: list[str] = []

    # 1. indicators
    sets = {}
    for name, seed, drift, vol, base, spikes in (("trend_up", 1, 0.6, 2.0, 1000, False), ("trend_down", 2, -0.5, 2.5, 5000, False),
                                                 ("range", 3, 0.0, 1.5, 300, False), ("spiky", 4, 0.2, 3.0, 20000, True),
                                                 ("fx", 5, 0.00002, 0.0009, 1.1, False)):
        rows = series(random.Random(seed), drift, vol, 3600, base, 300, now, spikes=spikes)
        sets[name] = rows
        write_csv(BUILD / f"{name}.csv", rows)
    (BUILD / "sets.json").write_text(json.dumps(sets))
    js = node(JS_API + "const sets=JSON.parse(fs.readFileSync('sets.json','utf8'));const o={};for(const [k,v] of Object.entries(sets))o[k]=api.inspectCandles(v);console.log(JSON.stringify(o));")
    alias = {"quality": "trendQuality", "macdHistogram": "macdHistogram"}
    checked = 0
    for name in sets:
        mql = json.loads(subprocess.run([str(BUILD / "indicators"), str(BUILD / f"{name}.csv")], check=True, capture_output=True, text=True).stdout)
        for key, value in mql.items():
            if key == "ok":
                continue
            checked += 1
            if not same(value, js[name][alias.get(key, key)]):
                errors.append(f"indicators/{name}/{key}: mql={value} js={js[name][alias.get(key, key)]}")
    print(f"1. indicateurs : {checked - len(errors)}/{checked} identiques")

    # 2. decisions on simulated markets
    before = len(errors)
    scen, total = {}, 0
    for seed in range(40):
        for sign in (1, -1):
            for pull, volh in ((0, 0.5), (9, 0.6), (16, 0.7)):
                k = f"s{len(scen)}"
                rnd = random.Random(seed * 7 + sign)
                scen[k] = {"H1": series(rnd, sign * 1.2, volh, 3600, 60000, 301, now, pull=pull, pullk=2.0),
                           "H4": series(rnd, sign * 5.0, 1.6, 14400, 60000, 300, now),
                           "D1": series(rnd, sign * 20, 5, 86400, 60000, 300, now)}
                for tf, rows in scen[k].items():
                    write_csv(BUILD / f"{k}_{tf}.csv", rows)
    (BUILD / "scen.json").write_text(json.dumps(scen))
    js = node(JS_API + """const scen=JSON.parse(fs.readFileSync('scen.json','utf8'));const o={};
for(const [k,v] of Object.entries(scen)){o[k]=decide(c=>api.technicalSetup(meta,api.inspectCandles(c?v.H1:v.H1.slice(0,-1)),api.inspectCandles(v.H4),api.MODES[1],api.inspectCandles(v.D1)));}
console.log(JSON.stringify(o));""")
    for k in scen:
        mql = json.loads(subprocess.run([str(BUILD / "decision"), k], check=True, capture_output=True, text=True, cwd=BUILD).stdout)
        for key, value in mql.items():
            total += 1
            if not same(value, js[k][key]):
                errors.append(f"decision/{k}/{key}: mql={value} js={js[k][key]}")
    print(f"2. decisions ({len(scen)} marches simules) : {total - (len(errors) - before)}/{total} identiques")

    # 3. signal path on crafted indicators
    before = len(errors)
    fixtures = json.loads((TESTS / "fixtures.json").read_text())
    (BUILD / "fixtures.json").write_text(json.dumps(fixtures))
    js = node(JS_API + """const fx=JSON.parse(fs.readFileSync('fixtures.json','utf8'));const o={};const now=Math.floor(Date.now()/1000);
for(const [k,v] of Object.entries(fx)){
 const tf=(q,adx,rsi,cycle)=>({side:v.side,trendStrong:true,trendQuality:q,regime:'TRENDING',passed:13,bos:true,choch:true,sweep:false,impulse:true,fvg:true,retest:v.retest,orderBlock:true,momentum:true,rejection:true,spikeRisk:false,
  dmiAligned:true,macdAligned:true,donchianBreakout:true,squeeze:false,squeezeRelease:true,marketStructureAligned:true,compression:false,engulfing:true,adx,efficiencyRatio:.55,volatilityExpansion:1.2,
  price:v.price,ema20:v.ema20,atr:v.atr,rsi,swingHigh:v.price+6,swingLow:v.price-6,closedAt:now-7200+cycle*3600,emaSpreadAtr:1,emaSlopeAtr:.3});
 const rH4=v.extH4?74:v.rsi;
 o[k]=decide(c=>api.technicalSetup(meta,tf(94,35,v.rsi,c),tf(92,35,rH4,c),api.MODES[1],tf(88,28,rH4,c)));}
console.log(JSON.stringify(o));""")
    total = 0
    states = set()
    for k in fixtures:
        mql = json.loads(subprocess.run([str(BUILD / "signals"), k], check=True, capture_output=True, text=True).stdout)
        states.add((mql["verdict"], mql["state"]))
        for key, value in mql.items():
            total += 1
            if not same(value, js[k][key]):
                errors.append(f"signals/{k}/{key}: mql={value} js={js[k][key]}")
    for needed in (("BUY", "EXECUTE_NOW"), ("SELL", "EXECUTE_NOW"), ("BUY", "WAIT_RETRACE")):
        if needed not in states:
            errors.append(f"signals: fixture set no longer covers {needed}")
    print(f"3. chemin de signal : {total - (len(errors) - before)}/{total} identiques")

    if errors:
        print("\n".join("ERROR: " + e for e in errors[:25]))
        return 1
    print("SyntX engine equivalence QA passed")
    return 0


if __name__ == "__main__":
    sys.exit(run())
