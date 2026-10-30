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
  { std::map<long,std::vector<std::pair<long,string>>> rows; std::map<long,long> rowcol;
    for(auto& kv:SIM_OBJ) if(kv.second.type==OBJ_LABEL){ long y=kv.second.ints[OBJPROP_YDISTANCE]; rows[y].push_back({kv.second.ints[OBJPROP_XDISTANCE],kv.second.strs[OBJPROP_TEXT]});
      rowcol[y]=kv.second.ints[OBJPROP_COLOR]; }   // les morceaux d'une ligne ont la meme couleur
    for(auto& r:rows){ std::sort(r.second.begin(),r.second.end()); string txt; for(auto& part:r.second) txt+=part.second; while(!txt.empty() && txt.back()==' ') txt.pop_back(); lines.push_back({r.first,string("[")+colname(rowcol[r.first])+"] "+txt}); } }
  for(auto& kv:SIM_OBJ) if(kv.second.type==OBJ_BUTTON) lines.push_back({kv.second.ints[OBJPROP_YDISTANCE]+1,string("BTN ")+kv.second.strs[OBJPROP_TEXT]});
  for(auto& kv:SIM_OBJ) if(kv.second.type==OBJ_RECTANGLE_LABEL && kv.first.find("_FG")!=string::npos)
    lines.push_back({kv.second.ints[OBJPROP_YDISTANCE]-3,string("BAR ")+std::to_string(kv.second.ints[OBJPROP_XSIZE])+" "+
      std::to_string(kv.second.ints[OBJPROP_XDISTANCE])+" "+colname(kv.second.ints[OBJPROP_BGCOLOR])});
  std::sort(lines.begin(),lines.end(),[](auto&a,auto&b){ return a.first<b.first || (a.first==b.first && a.second.rfind("[",0)==0 && b.second.rfind("[",0)!=0); });
  for(auto& l:lines) printf("%s\n",l.second.c_str());
  long bg=SIM_OBJ.count("SERA_PANEL_BG")?SIM_OBJ["SERA_PANEL_BG"].order:-1; long first=LONG_MAX;
  for(auto& kv:SIM_OBJ) if(kv.first!="SERA_PANEL_BG" && kv.first.rfind("SERA_PANEL_",0)==0) first=std::min(first,kv.second.order);
  printf("ZORDER %s\n",bg>0 && bg<first?"OK":"BAD");
  for(auto& kv:SIM_OBJ) if(kv.second.type==OBJ_LABEL){ const string& s=kv.second.strs[OBJPROP_TEXT];
    if(s.size()>63) printf("LABEL TOO LONG %s (%zu)\n",kv.first.c_str(),s.size()); if(s.empty()) printf("LABEL EMPTY %s\n",kv.first.c_str()); }
  printf("--- positions %zu, ordres limites %zu\n",SIM_POS.size(),SIM_ORD.size());
  for(auto& p:SIM_POS) printf("POS %s %s vol=%.2f sl=%.3f\n",p.symbol.c_str(),p.type==POSITION_TYPE_BUY?"BUY":"SELL",p.volume,p.sl);
  for(auto& o:SIM_ORD) printf("ORD %s %s @%.3f vol=%.2f\n",o.symbol.c_str(),o.type==ORDER_TYPE_BUY_LIMIT?"BUY_LIMIT":"SELL_LIMIT",o.price,o.volume);
}
static void click(const char* name){ long l=0; double d=0; string s=string("SERA_PANEL_BTN_")+name; OnChartEvent(CHARTEVENT_OBJECT_CLICK,l,d,s); }
int main(int argc,char** argv){
  std::ifstream w(argv[2]); string sym; double px; int tr;
  while(w>>std::quoted(sym)>>px>>tr){ SIM_PRICE[sym]=px; SIM_TREND[sym]=tr; }
  SIM_NOW=atol(argv[3]);
  string json=slurp(argv[1]);
  string json2=argc>4?slurp(argv[4]):json;
  string mode=argc>5?argv[5]:"";
  // "conflict" : un ancien EA Sera a marque le signal comme deja trade et tourne sur un autre graphique.
  if(mode=="conflict"){ GlobalVariableSet(StateKey("SERA_TRADESTATE_",argv[6]),atof(argv[7])); SIM_GV["SERA_HB_424242"]=SIM_NOW; }
  OnInit();
  Evaluate(json);
  dump("CYCLE 1 (flux publie)");
  if(mode=="conflict"){ for(auto& kv:SIM_GV) if(kv.first.rfind("SERA_ALERTSTATE_",0)==0) kv.second=12345; SIM_GV["SERA_HB_424242"]=SIM_NOW+30; }
  SIM_NOW+=30; Evaluate(json2);
  dump("CYCLE 2 (30 s plus tard)");
  click("PLUS"); dump("BOUTON + (5 marches de plus)");
  click("MINUS"); click("MINUS"); click("MINUS"); dump("BOUTON - (liste repliee)");
  click("PLUS"); click("PLUS");
  SIM_CHART_H=720; click("PLUS"); dump("PAGE 1 (graphique de 720 px)");
  click("NEXT"); dump("PAGE 2 (bouton >)");
  click("NEXT"); click("PREV"); dump("PAGE 2 (boutons > puis <)");
  SIM_CHART_H=0;
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
    if "[red] Signaux :" in c1:
        errors.append("a red 'Signaux' line is shown although the feed is fine")
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
    if "LABEL TOO LONG" in text or "LABEL EMPTY" in text:
        errors.append("a chart label is longer than 63 characters (MT5 cuts it) or empty (MT5 shows 'Label')")
    if "ZORDER BAD" in text:
        errors.append("dashboard background created after texts/bars: it would hide them")
    c2s = sections.get("CYCLE 2 (30 s plus tard)", "")
    if "ORDRES ET POSITIONS SERA" not in c2s or "POSITIONS POSSIBLES" not in c2s:
        errors.append("orders / possible positions tables missing")
    if re.search(r"ordres limites [1-9]", c2s) and not re.search(r"\[blue\]\s+\S.*(BUY|SELL) LIMIT", c2s):
        errors.append("open limit orders are not listed in the dashboard")
    if "BAR " not in c2s:
        errors.append("certainty bars not drawn")
    def possible_rows(sec: str) -> int:
        part = sec.split("POSITIONS POSSIBLES", 1)[-1].split("\n[grey] \n", 1)[0]
        return len(re.findall(r"^\[(white|cyan)\]   \S", part, re.M))
    plus, minus = sections.get("BOUTON + (5 marches de plus)", ""), sections.get("BOUTON - (liste repliee)", "")
    if "BTN +" not in c2s or "BTN -" not in c2s:
        errors.append("+ / - buttons not drawn on the possible positions table")
    if possible_rows(plus) <= possible_rows(c2s) and "autre(s)" in c2s:
        errors.append(f"button + did not show more markets ({possible_rows(c2s)} -> {possible_rows(plus)})")
    if possible_rows(minus) != 0 or "bouton + pour les afficher" not in minus:
        errors.append(f"button - did not fold the list ({possible_rows(minus)} rows left)")
    p1, p2, p2b = (sections.get(k, "") for k in ("PAGE 1 (graphique de 720 px)", "PAGE 2 (bouton >)", "PAGE 2 (boutons > puis <)"))
    def first_market(sec: str) -> str:
        part = sec.split("POSITIONS POSSIBLES", 1)[-1]
        mm = re.search(r"^\[(?:white|cyan)\]   (.{27})", part, re.M)
        return mm.group(1).strip() if mm else ""
    def lowest_label(sec: str) -> int:
        return max((int(y) for y in re.findall(r"^Y(\d+)", sec, re.M)), default=0)
    if "BTN <" not in p1 or "BTN >" not in p1:
        errors.append("page buttons < > not drawn")
    if "page 1/" not in p1 or "page 2/" not in p2 or "page 2/" not in p2b:
        errors.append("page navigation does not work (< / > buttons)")
    if first_market(p1) == first_market(p2) or not first_market(p2):
        errors.append("page 2 shows the same markets as page 1")
    if possible_rows(p1) > 30:
        errors.append(f"the list does not fit a 720 px chart ({possible_rows(p1)} rows)")
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

        # Scenario: very confident signal (>= ModelVetoBelowConfidence = 90 %) -> the AI models cannot veto it.
        opposite = "SELL" if target["final_verdict"] == "BUY" else "BUY"
        target.update(model_ensemble_direction=opposite, model_ensemble_consensus=100, model_models_available=4, final_confidence=95)
        forced_path.write_text(json.dumps(forced, separators=(",", ":")), encoding="utf-8")
        out6 = subprocess.run([str(exe), str(forced_path), str(world(forced)), str(now)], capture_output=True, text=True, timeout=120)
        if "POS " + target["market"] not in out6.stdout.split("=== CYCLE 2")[0]:
            errors.append(f"a 95 % signal on {target['market']} was vetoed by the AI models (veto only below 90 %)")

        # Scenario: same EXECUTE_NOW signal at 85 % confidence, AI models strongly disagree -> no position.
        target.update(final_confidence=85)
        forced_path.write_text(json.dumps(forced, separators=(",", ":")), encoding="utf-8")
        out3 = subprocess.run([str(exe), str(forced_path), str(world(forced)), str(now)], capture_output=True, text=True, timeout=120)
        c3 = out3.stdout.split("=== CYCLE 2")[0]
        if not quiet:
            print("=== SCENARIO VETO IA (" + target["market"] + ", modeles " + opposite + " 100%) ===")
            print("\n".join(l for l in c3.splitlines() if "DECISION" in l or "Consensus" in l))
        log3 = out3.stdout.split("=== LOG ===")[-1]
        if "POS " + target["market"] in c3 or f"{target['market']} {target['final_verdict']} non execute - les modeles IA" not in log3:
            errors.append(f"AI veto on {target['market']} did not block the entry")
    # Scenario: fast entry — a confirmed, very confident Day signal still in WAIT_CONFIRMATION enters at market.
    day_rows = [m for m in feed["markets"] if m["mode"] == "day" and m["final_verdict"] in ("BUY", "SELL") and m.get("levels")]
    if day_rows:
        fast = json.loads(json.dumps(feed))
        target = next(m for m in fast["markets"] if m["id"] == day_rows[0]["id"])
        target.update(execution_state="WAIT_CONFIRMATION", execution_score=76, final_confidence=max(90, target["final_confidence"]),
                      condition_pass_percent=max(80, target["condition_pass_percent"]),
                      model_ensemble_direction=target["final_verdict"], model_ensemble_consensus=80, model_models_available=4)
        fast_path = BUILD / "ea-signals-fast-entry.json"
        fast_path.write_text(json.dumps(fast, separators=(",", ":")), encoding="utf-8")
        out4 = subprocess.run([str(exe), str(fast_path), str(world(fast)), str(now)], capture_output=True, text=True, timeout=120)
        c4 = out4.stdout.split("=== CYCLE 2")[0]
        if not quiet:
            print("=== SCENARIO ENTREE RAPIDE (" + target["market"] + ", Day WAIT_CONFIRMATION) ===")
            print("\n".join(l for l in c4.splitlines() if "DECISION" in l or l.startswith("POS ")))
        if out4.returncode != 0 or "POS " + target["market"] not in c4 or "(entree rapide)" not in c4:
            errors.append(f"fast entry on {target['market']} did not open a market position")
    log = text.split("=== LOG ===")[-1]
    if "contre ATTENDRE" in log:
        errors.append("model veto logged for markets without a signal (ATTENDRE)")
    vetoes = re.findall(r"non execute - les modeles IA", log)
    if len(vetoes) > len(set(re.findall(r"Sera: (.+?) (?:BUY|SELL) non execute", log))):
        errors.append("the same model veto is logged on every cycle")
    # Scenario: an old Sera EA on another chart marked the signal as already traded and rewrites the shared memory
    # -> no position, the reason is written once in the journal and the dashboard warns about the other EA.
    if rows:
        clash = json.loads(json.dumps(feed))
        target = next(m for m in clash["markets"] if m["id"] == rows[0]["id"])
        target.update(execution_state="EXECUTE_NOW", execution_score=92, final_confidence=92,
                      condition_pass_percent=max(85, target["condition_pass_percent"]),
                      model_ensemble_direction=target["final_verdict"], model_ensemble_consensus=80, model_models_available=4)
        cp = BUILD / "ea-signals-conflict.json"
        cp.write_text(json.dumps(clash, separators=(",", ":")), encoding="utf-8")
        state = "1" if target["final_verdict"] == "BUY" else "-1"
        out7 = subprocess.run([str(exe), str(cp), str(world(clash)), str(now), str(cp), "conflict", target["id"], state],
                              capture_output=True, text=True, timeout=120)
        log7 = out7.stdout.split("=== LOG ===")[-1]
        cyc2 = out7.stdout.split("=== CYCLE 2")[-1].split("=== BOUTON")[0]
        if not quiet:
            print(f"=== SCENARIO AUTRE EA SERA ({target['market']}) ===")
            print("\n".join(l for l in (cyc2 + log7).splitlines() if "ATTENTION" in l or "non execute" in l))
        if "POS " + target["market"] in out7.stdout.split("=== CYCLE 2")[0]:
            errors.append("conflict scenario: the signal marked as traded by another EA was traded again")
        if log7.count(f"{target['market']} {target['final_verdict']} pret mais non execute - ce signal est deja marque") != 1:
            errors.append("conflict scenario: the reason is not written exactly once in the journal")
        if "[red] ATTENTION :" not in cyc2:
            errors.append("conflict scenario: the dashboard does not warn about the other Sera EA")
        if len(re.findall(rf"^Sera Trend Watch: {re.escape(target['market'])} ", log7, re.M)) > 1:
            errors.append("conflict scenario: the trend alert is repeated although nothing changed for this chart")

    # Scenario: confirmed Day signal waiting for confirmation (not confident enough for the fast entry)
    # -> a limit order is placed at once; next cycle the AI models turn against it -> cancelled before it fills.
    if day_rows:
        wait = json.loads(json.dumps(feed))
        target = next(m for m in wait["markets"] if m["id"] == day_rows[0]["id"])
        lv = target["levels"]
        risk = abs(lv["entry"] - lv["sl"])
        sign = 1 if target["final_verdict"] == "BUY" else -1
        zone = lv["entry"] - sign * risk * 0.3
        target.update(execution_state="WAIT_CONFIRMATION", execution_score=75, final_confidence=80,
                      condition_pass_percent=max(80, target["condition_pass_percent"]), setup_detected=1,
                      setup_direction=target["final_verdict"],
                      setup_entry_plan={"suggested_entry": zone, "zone_min": min(zone, zone - sign * risk * 0.1), "zone_max": max(zone, zone - sign * risk * 0.1)},
                      model_ensemble_direction=target["final_verdict"], model_ensemble_consensus=80, model_models_available=4)
        turned = json.loads(json.dumps(wait))
        t2 = next(m for m in turned["markets"] if m["id"] == target["id"])
        t2.update(model_ensemble_direction="SELL" if target["final_verdict"] == "BUY" else "BUY", model_ensemble_consensus=100)
        p1, p2 = BUILD / "ea-signals-wait.json", BUILD / "ea-signals-turned.json"
        p1.write_text(json.dumps(wait, separators=(",", ":")), encoding="utf-8")
        p2.write_text(json.dumps(turned, separators=(",", ":")), encoding="utf-8")
        out5 = subprocess.run([str(exe), str(p1), str(world(wait)), str(now), str(p2)], capture_output=True, text=True, timeout=120)
        first, second = out5.stdout.split("=== CYCLE 2")[0], out5.stdout.split("=== CYCLE 2")[-1].split("=== BOUTON")[0]
        name = target["market"]
        if not quiet:
            print(f"=== SCENARIO LIMITE PENDANT LA CONFIRMATION PUIS ANNULATION ({name}) ===")
            print("\n".join(l for l in (first + second).splitlines() if l.startswith("ORD ") or "ORDRE LIMITE" in l))
        if out5.returncode != 0 or not re.search(rf"^ORD {re.escape(name)} (BUY|SELL)_LIMIT", first, re.M):
            errors.append(f"no limit order placed while {name} waits for confirmation")
        log5 = out5.stdout.split("=== LOG ===")[-1]
        if re.search(rf"^ORD {re.escape(name)} ", second, re.M) or f"pending supprime {name} - risque de changement : les modeles IA" not in log5:
            errors.append(f"the limit order on {name} was not cancelled before execution when the AI models turned")
    if errors:
        print("\n".join("ERROR: " + e for e in errors))
        return 1
    print(f"EA dashboard simulation passed ({len(traded)} signal(s) BUY/SELL in the feed)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
