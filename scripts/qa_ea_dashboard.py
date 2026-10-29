#!/usr/bin/env python3
"""Runs the Deriv EA's real Evaluate() + dashboard code (compiled as C++ against the MT5
simulator tests/mql/mt5sim.h) on the published data/ea-signals.json, then checks:
  - no crash, the dashboard is drawn, every line fits the panel,
  - every confirmed BUY/SELL is listed with a decision, EXECUTE_NOW rows end up as positions,
  - the WebRequest 4014 case shows the fix in the panel,
and prints the dashboard as it would appear on the MT5 chart.
Usage: qa_ea_dashboard.py [--quiet]"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from ea_files import ea_path          # noqa: E402
from qa_mql_cpp import to_cpp         # noqa: E402

BUILD = ROOT / "tests" / "mql" / "build"
FEED = ROOT / "data" / "ea-signals.json"

MAIN = r'''
#include <fstream>
static string slurp(const char* p){ std::ifstream f(p); std::stringstream b; b<<f.rdbuf(); return b.str(); }
static const char* colname(long c){
  switch(c){ case 0xBBE838: return "green"; case 0x765FFF: return "red"; case 0x50BEFF: return "amber"; case 0xFFD854: return "cyan";
             case 0xFFA34D: return "blue"; case 0xF5E8DC: return "white"; default: return "grey"; } }
static void dump(const char* title){
  printf("=== %s ===\n",title);
  std::vector<std::pair<long,string>> lines;
  for(auto& kv:SIM_OBJ) if(kv.second.type==OBJ_LABEL) lines.push_back({kv.second.ints[OBJPROP_YDISTANCE],
      string("[")+colname(kv.second.ints[OBJPROP_COLOR])+"] "+kv.second.strs[OBJPROP_TEXT]});
  for(auto& kv:SIM_OBJ) if(kv.second.type==OBJ_RECTANGLE_LABEL && kv.first.find("_FG")!=string::npos)
    lines.push_back({kv.second.ints[OBJPROP_YDISTANCE]-3,string("BAR ")+std::to_string(kv.second.ints[OBJPROP_XSIZE])+" "+
      std::to_string(kv.second.ints[OBJPROP_XDISTANCE])+" "+colname(kv.second.ints[OBJPROP_BGCOLOR])});
  std::sort(lines.begin(),lines.end(),[](auto&a,auto&b){ return a.first<b.first || (a.first==b.first && a.second.rfind("BAR",0)!=0 && b.second.rfind("BAR",0)==0); });
  for(auto& l:lines) printf("%s\n",l.second.c_str());
  long bg=SIM_OBJ.count("SERA_PANEL_BG")?SIM_OBJ["SERA_PANEL_BG"].order:-1; long first=LONG_MAX;
  for(auto& kv:SIM_OBJ) if(kv.first!="SERA_PANEL_BG" && kv.first.rfind("SERA_PANEL_",0)==0) first=std::min(first,kv.second.order);
  printf("ZORDER %s\n",bg>0 && bg<first?"OK":"BAD");
  printf("--- positions %zu, ordres limites %zu\n",SIM_POS.size(),SIM_ORD.size());
  for(auto& p:SIM_POS) printf("POS %s %s vol=%.2f sl=%.3f\n",p.symbol.c_str(),p.type==POSITION_TYPE_BUY?"BUY":"SELL",p.volume,p.sl);
  for(auto& o:SIM_ORD) printf("ORD %s %s @%.3f vol=%.2f\n",o.symbol.c_str(),o.type==ORDER_TYPE_BUY_LIMIT?"BUY_LIMIT":"SELL_LIMIT",o.price,o.volume);
}
int main(int argc,char** argv){
  std::ifstream w(argv[2]); string sym; double px; int tr;
  while(w>>std::quoted(sym)>>px>>tr){ SIM_PRICE[sym]=px; SIM_TREND[sym]=tr; }
  SIM_NOW=atol(argv[3]);
  string json=slurp(argv[1]);
  OnInit();
  Evaluate(json);
  dump("CYCLE 1 (flux publie)");
  SIM_NOW+=30; Evaluate(json);
  dump("CYCLE 2 (30 s plus tard)");
  SIM_OBJ.clear(); OnTimer();
  dump("WEBREQUEST NON AUTORISE (erreur 4014)");
  printf("=== LOG ===\n"); for(auto& l:SIM_LOG) printf("%s\n",l.c_str());
  return 0;
}
'''


def build() -> Path:
    BUILD.mkdir(parents=True, exist_ok=True)
    src = to_cpp(ea_path("Deriv").read_text(encoding="utf-8")).replace('#include "../mt5stubs.h"', '#include "../mt5sim.h"\n#include <iomanip>')
    cpp = BUILD / "dashboard_sim.cpp"
    cpp.write_text(src + MAIN, encoding="utf-8")
    exe = BUILD / "dashboard_sim"
    subprocess.run(["g++", "-std=c++17", "-O0", "-w", "-o", str(exe), str(cpp)], check=True)
    return exe


def world(feed: dict) -> Path:
    # One price per symbol: a market appears twice (Swing + Day); the row carrying a signal wins.
    path = BUILD / "world.txt"
    symbols: dict[str, tuple[float, int, bool]] = {}
    for m in feed["markets"]:
        name = m["market"].replace("/", "") if m.get("asset_class") == "forex" else m["market"]
        has_signal = m["final_verdict"] in ("BUY", "SELL") and bool(m.get("levels"))
        if name in symbols and symbols[name][2] and not has_signal:
            continue
        price = (m.get("levels") or {}).get("entry") or 100.0
        side = m["final_verdict"] if has_signal else (m.get("entry_tf") or {}).get("side", "BUY")
        symbols[name] = (price, 1 if side == "BUY" else -1, has_signal)
    with path.open("w") as f:
        for name, (price, trend, _) in symbols.items():
            f.write(f'"{name}" {price} {trend}\n')
    return path


def main() -> int:
    quiet = "--quiet" in sys.argv
    feed = json.loads(FEED.read_text(encoding="utf-8"))
    exe = build()
    from datetime import datetime
    now = int(datetime.fromisoformat(feed["updated_at"].replace("Z", "+00:00")).timestamp()) + 120
    out = subprocess.run([str(exe), str(FEED), str(world(feed)), str(now)], capture_output=True, text=True, timeout=120)
    if out.returncode != 0:
        print(out.stdout[-3000:], out.stderr[-3000:])
        print("ERROR: EA simulation crashed")
        return 1
    text = out.stdout
    if not quiet:
        print(text.split("=== LOG ===")[0])
    errors = []
    sections = dict(re.findall(r"=== (.+?) ===\n(.*?)(?==== |\Z)", text, re.S))
    c1 = sections.get("CYCLE 1 (flux publie)", "")
    if "SERA EA SWING INTELLIGENT DERIV" not in c1:
        errors.append("dashboard not drawn on cycle 1")
    if "[green] BOT ACTIF" not in c1:
        errors.append("bot should be shown ACTIVE with algo trading allowed")
    if "[green] Signaux : recus" not in c1:
        errors.append("fresh feed should be shown as received")
    traded = [m for m in feed["markets"] if m["final_verdict"] in ("BUY", "SELL") and (m["mode"] == "swing" or m["mode"] == "day")]
    if traded and "SIGNAL SUIVI" not in c1:
        errors.append("a confirmed signal exists but no SIGNAL SUIVI block")
    if traded and "DECISION :" not in c1:
        errors.append("missing DECISION line")
    for line in c1.splitlines():
        if line.startswith("[") and len(line.split("] ", 1)[-1]) > 130:
            errors.append(f"dashboard line too long for the panel: {line[:80]}...")
    if "positions 0, ordres limites 0" in sections.get("CYCLE 2 (30 s plus tard)", "") and any(
            m["execution_state"] == "EXECUTE_NOW" and m["final_verdict"] in ("BUY", "SELL") for m in traded):
        errors.append("an EXECUTE_NOW signal did not lead to a position in the simulation")
    if "ZORDER BAD" in text:
        errors.append("dashboard background created after texts/bars: it would hide them")
    c2s = sections.get("CYCLE 2 (30 s plus tard)", "")
    if "ORDRES ET POSITIONS SERA" not in c2s or "POSITIONS POSSIBLES" not in c2s:
        errors.append("orders / possible positions tables missing")
    if re.search(r"ordres limites [1-9]", c2s) and not re.search(r"\[blue\]\s+\S.*(BUY|SELL) LIMIT", c2s):
        errors.append("open limit orders are not listed in the dashboard")
    if "BAR " not in c2s:
        errors.append("certainty bars not drawn")
    c4014 = sections.get("WEBREQUEST NON AUTORISE (erreur 4014)", "")
    if "erreur 4014" not in c4014 or "https://serakatsuva.github.io" not in c4014:
        errors.append("4014 case does not explain the WebRequest fix on the dashboard")
    if "SIGNAL SUIVI" in c4014:
        errors.append("stale signals must not be shown when the feed is unreachable")
    # Limit orders placed by a Day setup must survive the Swing row of the same symbol.
    c2 = sections.get("CYCLE 2 (30 s plus tard)", "")
    placed = len(re.findall(r"ORDRE LIMITE \w+ PLACE", c1))
    m = re.search(r"ordres limites (\d+)", c2)
    if placed and (not m or int(m.group(1)) == 0):
        errors.append("limit orders placed on cycle 1 were cancelled by another setup of the same symbol")
    # Scenario: one confirmed signal switches to EXECUTE_NOW -> a market position must open.
    rows = [m for m in feed["markets"] if m["final_verdict"] in ("BUY", "SELL") and m.get("levels")]
    if rows:
        forced = json.loads(json.dumps(feed))
        target = next(m for m in forced["markets"] if m["id"] == rows[0]["id"])
        # The open-source models must agree, otherwise the EA rightly refuses (checked separately below).
        target.update(execution_state="EXECUTE_NOW", execution_score=92, final_confidence=max(90, target["final_confidence"]),
                      condition_pass_percent=max(85, target["condition_pass_percent"]),
                      model_ensemble_direction=target["final_verdict"], model_ensemble_consensus=80, model_models_available=4)
        forced_path = BUILD / "ea-signals-execute-now.json"
        forced_path.write_text(json.dumps(forced, separators=(",", ":")), encoding="utf-8")
        out2 = subprocess.run([str(exe), str(forced_path), str(world(forced)), str(now)], capture_output=True, text=True, timeout=120)
        c = out2.stdout.split("=== CYCLE 2")[0]
        if not quiet:
            print("=== SCENARIO ENTREE IMMEDIATE (" + target["market"] + ") ===")
            print("\n".join(l for l in c.splitlines() if "DECISION" in l or l.startswith("POS ") or "SIGNAL SUIVI" in l or "positions" in l))
        if out2.returncode != 0 or "POSITION " + target["final_verdict"] + " OUVERTE" not in c or "POS " + target["market"] not in c:
            errors.append(f"EXECUTE_NOW on {target['market']} did not open a market position")

        # Scenario: same EXECUTE_NOW signal, but the AI models strongly disagree -> no position.
        opposite = "SELL" if target["final_verdict"] == "BUY" else "BUY"
        target.update(model_ensemble_direction=opposite, model_ensemble_consensus=100, model_models_available=4)
        forced_path.write_text(json.dumps(forced, separators=(",", ":")), encoding="utf-8")
        out3 = subprocess.run([str(exe), str(forced_path), str(world(forced)), str(now)], capture_output=True, text=True, timeout=120)
        c3 = out3.stdout.split("=== CYCLE 2")[0]
        if not quiet:
            print("=== SCENARIO VETO IA (" + target["market"] + ", modeles " + opposite + " 100%) ===")
            print("\n".join(l for l in c3.splitlines() if "DECISION" in l or "Consensus" in l))
        if "POS " + target["market"] in c3 or "[NON] Consensus des modeles IA" not in c3:
            errors.append(f"AI veto on {target['market']} did not block the entry")
    if errors:
        print("\n".join("ERROR: " + e for e in errors))
        return 1
    print(f"EA dashboard simulation passed ({len(traded)} signal(s) BUY/SELL in the feed)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
