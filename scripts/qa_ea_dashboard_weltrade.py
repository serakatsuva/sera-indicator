#!/usr/bin/env python3
"""Runs the Weltrade EA's real scanner + dashboard code (compiled as C++ against the MT5
simulator tests/mql/mt5sim.h) and checks:
  - the indices are detected and analysed, the dashboard is drawn and every line fits the panel,
  - an EXECUTE_NOW signal opens a market position, a WAIT_RETRACE signal places a limit order,
  - a confident WAIT_CONFIRMATION signal opens through the fast entry (one market entry per cycle),
  - orders, possible positions, certainty bars and the 12 entry checks are shown,
and prints the dashboard as it would appear on the MT5 chart.
Usage: qa_ea_dashboard_weltrade.py [--quiet]"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from ea_files import ea_path          # noqa: E402
from qa_mql_cpp import to_cpp         # noqa: E402

BUILD = ROOT / "tests" / "mql" / "build"

MAIN = r'''
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
    lines.push_back({kv.second.ints[OBJPROP_YDISTANCE]-3,string("BAR ")+std::to_string(kv.second.ints[OBJPROP_XSIZE])});
  std::sort(lines.begin(),lines.end(),[](auto&a,auto&b){ return a.first<b.first || (a.first==b.first && a.second.rfind("[",0)==0 && b.second.rfind("[",0)!=0); });
  for(auto& l:lines) printf("%s\n",l.second.c_str());
  long bg=SIM_OBJ.count("SWX_PANEL_BG")?SIM_OBJ["SWX_PANEL_BG"].order:-1; long first=LONG_MAX;
  for(auto& kv:SIM_OBJ) if(kv.first!="SWX_PANEL_BG" && kv.first.rfind("SWX_PANEL_",0)==0) first=std::min(first,kv.second.order);
  printf("ZORDER %s\n",bg>0 && bg<first?"OK":"BAD");
  for(auto& kv:SIM_OBJ) if(kv.second.type==OBJ_LABEL){ const string& s=kv.second.strs[OBJPROP_TEXT];
    if(s.size()>63) printf("LABEL TOO LONG %s (%zu)\n",kv.first.c_str(),s.size()); if(s.empty()) printf("LABEL EMPTY %s\n",kv.first.c_str()); }
  printf("--- positions %zu, ordres limites %zu\n",SIM_POS.size(),SIM_ORD.size());
  for(auto& p:SIM_POS) printf("POS %s %s vol=%.2f\n",p.symbol.c_str(),p.type==POSITION_TYPE_BUY?"BUY":"SELL",p.volume);
  for(auto& o:SIM_ORD) printf("ORD %s %s @%.3f vol=%.2f\n",o.symbol.c_str(),o.type==ORDER_TYPE_BUY_LIMIT?"BUY_LIMIT":"SELL_LIMIT",o.price,o.volume);
}
// Signal confirme injecte (meme forme que la sortie de Decide) pour tester l'execution.
static void force(const string& name,const string& side,const string& state,double exec=-1){
  int i=0; while(i<ArraySize(g_symbols) && g_symbols[i]!=name) i++;
  if(i>=ArraySize(g_symbols)){ printf("MISSING %s\n",name.c_str()); return; }
  SwxDecision& d=g_decisions[i]; double px=SIM_PRICE[d.symbol], dir=side=="BUY"?1:-1, dist=px*0.01;
  d.valid=true; d.verdict=side; d.side=side; d.state=state; d.setupType="BREAKOUT_CONTINUATION";
  d.entrySide=side; d.confSide=side; d.dailySide=side; d.confTrendStrong=true; d.cycles=3; d.conditionPct=88;
  d.score=89; d.consensus=0.81; d.execScore=state=="EXECUTE_NOW"?90:state=="WAIT_CONFIRMATION"?76:70; d.confidence=89; d.qH1=80; d.qH4=82; d.qD1=74;
  d.gAligned=d.gQuality=d.gConfirm=d.gSetup=d.gStructure=d.gRisk=d.gScore=true;
  d.entry=px; d.sl=px-dir*dist; d.tp1=px+dir*dist*1.5; d.tp2=px+dir*dist*2.4; d.tp3=px+dir*dist*3.6; d.tp4=px+dir*dist*4.8; d.tp5=px+dir*dist*6;
  d.zoneEntry=px-dir*dist*0.4; d.barTime=iTime(d.symbol,PERIOD_H1,1);
  if(exec>=0) d.execScore=exec;
  g_lastBar[i]=d.barTime;
}
static void click(const char* name){ long l=0; double d=0; string s=string("SWX_PANEL_BTN_")+name; OnChartEvent(CHARTEVENT_OBJECT_CLICK,l,d,s); }
int main(int argc,char** argv){
  const char* names[]={"GainX 800","PainX 800","GainX 1200","PainX 600","FX Vol 20","SFX Vol 40","SwitchX 600","BreakX 1200","EURUSD"};
  int trend=1; for(auto n:names){ SIM_PRICE[n]=trend>0?50000:1000; SIM_TREND[n]=trend; trend=-trend; }
  SIM_NOW=1793000000;
  OnInit();
  dump("DEMARRAGE (analyse des bougies du broker)");
  printf("SYMBOLS %d\n",ArraySize(g_symbols));
  for(int i=0;i<ArraySize(g_symbols);i++) printf("SYM %s valid=%d verdict=%s state=%s score=%.0f\n",g_symbols[i].c_str(),g_decisions[i].valid,g_decisions[i].verdict.c_str(),g_decisions[i].state.c_str(),g_decisions[i].score);
  force("GainX 800","SELL","EXECUTE_NOW");
  force("PainX 800","BUY","WAIT_RETRACE");
  force("SFX Vol 40","SELL","WAIT_CONFIRMATION");
  SIM_NOW+=30; OnTimer();
  dump("CYCLE AVEC SIGNAUX (GainX 800 EXECUTE_NOW, PainX 800 WAIT_RETRACE)");
  SIM_NOW+=30; OnTimer();
  dump("CYCLE SUIVANT (30 s plus tard)");
  SIM_NOW+=30; OnTimer();
  dump("CYCLE 3 (entree rapide)");
  click("OPEN_0");
  click("MINUS"); click("MINUS"); dump("BOUTON - (liste repliee)");
  click("PLUS"); dump("BOUTON + (liste depliee)");
  force("BreakX 1200","SELL","WAIT_CONFIRMATION",70);   // pas assez fort pour l'entree rapide
  SIM_NOW+=30; OnTimer(); dump("LIMITE PENDANT LA CONFIRMATION");
  for(int i=0;i<ArraySize(g_symbols);i++) if(g_symbols[i]=="BreakX 1200"){ g_decisions[i].verdict="ATTENDRE"; g_decisions[i].entrySide="BUY"; }
  SIM_NOW+=30; OnTimer(); dump("ANNULATION AVANT EXECUTION");
  printf("=== LOG ===\n"); for(auto& l:SIM_LOG) printf("%s\n",l.c_str());
  return 0;
}
'''


def build() -> Path:
    BUILD.mkdir(parents=True, exist_ok=True)
    src = to_cpp(ea_path("Weltrade").read_text(encoding="utf-8")).replace('#include "../mt5stubs.h"', '#include "../mt5sim.h"')
    cpp = BUILD / "dashboard_sim_weltrade.cpp"
    cpp.write_text(src + MAIN, encoding="utf-8")
    exe = BUILD / "dashboard_sim_weltrade"
    subprocess.run(["g++", "-std=c++17", "-O0", "-w", "-o", str(exe), str(cpp)], check=True)
    return exe


def main() -> int:
    quiet = "--quiet" in sys.argv
    exe = build()
    out = subprocess.run([str(exe)], capture_output=True, text=True, timeout=300)
    if out.returncode != 0:
        print(out.stdout[-3000:], out.stderr[-3000:])
        print("ERROR: Weltrade EA simulation crashed")
        return 1
    text = out.stdout
    if not quiet:
        print(text.split("=== LOG ===")[0])
    errors = []
    sections = dict(re.findall(r"=== (.+?) ===\n(.*?)(?==== |\Z)", text, re.S))
    start = next((v for k, v in sections.items() if k.startswith("DEMARRAGE")), "")
    signal = next((v for k, v in sections.items() if k.startswith("CYCLE AVEC")), "")
    after = next((v for k, v in sections.items() if k.startswith("CYCLE SUIVANT")), "")
    m = re.search(r"SYMBOLS (\d+)", text)
    if not m or int(m.group(1)) != 8:
        errors.append(f"expected 8 Weltrade indices detected (EURUSD excluded), got {m.group(1) if m else '?'}")
    if "valid=1" not in text:
        errors.append("no index could be analysed from the broker candles")
    if "SERA EA SWING INTELLIGENT WELTRADE v" not in start or "[green] BOT ACTIF" not in start:
        errors.append("dashboard not drawn as ACTIVE at start-up")
    if "Analyse dans MT5" not in start:
        errors.append("analysis status line missing")
    for line in (start + signal + after).splitlines():
        if line.startswith("[") and len(line.split("] ", 1)[-1]) > 130:
            errors.append(f"dashboard line too long for the panel: {line[:80]}...")
    if "POS GainX 800 SELL" not in signal or "POSITION SELL OUVERTE" not in signal:
        errors.append("EXECUTE_NOW signal did not open a market position")
    if "ORD PainX 800 BUY_LIMIT" not in signal:
        errors.append("WAIT_RETRACE signal did not place a limit order")
    if not re.search(r"\[blue\]\s+PainX 800\s+BUY LIMIT", after) or not re.search(r"\[(green|red)\]\s+GainX 800\s+SELL", after):
        errors.append("orders / positions not listed on the dashboard")
    if "POSITIONS POSSIBLES" not in after or "BAR " not in after:
        errors.append("possible positions table or certainty bars missing")
    if "[OK]  Tendance alignee H1/H4/D1" not in signal and "[OK]  Tendance alignee H1/H4/D1" not in after:
        errors.append("entry checks not shown")
    fast = next((v for k, v in sections.items() if k.startswith("CYCLE 3")), "")
    if "POS SFX Vol 40 SELL" not in fast:
        errors.append("fast entry (confirmed signal, WAIT_CONFIRMATION, confidence >= 85) did not open a position")
    if "POSITION SELL OUVERTE (entree rapide)" not in after + fast:
        errors.append("fast entry decision not shown on the dashboard")
    if "positions 2, ordres limites 1" not in fast:
        errors.append("expected 2 positions (immediate + fast entry, one market entry per cycle) and 1 limit order, "
                      "and no second trade on the same signal")
    folded = sections.get("BOUTON - (liste repliee)", "")
    unfolded = sections.get("BOUTON + (liste depliee)", "")
    if "BTN +" not in after or "BTN -" not in after:
        errors.append("+ / - buttons not drawn")
    if "liste repliee" not in folded or "bouton + pour les afficher" not in folded:
        errors.append("button - did not fold the possible positions list")
    if "page 1/" not in unfolded or not re.search(r"\[cyan\]   \S", unfolded):
        errors.append("button + did not show the markets again")
    waiting = sections.get("LIMITE PENDANT LA CONFIRMATION", "")
    cancelled = sections.get("ANNULATION AVANT EXECUTION", "")
    if "ORD BreakX 1200 SELL_LIMIT" not in waiting:
        errors.append("no limit order placed while the signal waits for confirmation")
    log = text.split("=== LOG ===")[-1]
    if "ORD BreakX 1200" in cancelled or "pending supprime BreakX 1200 - risque de changement" not in log:
        errors.append("the limit order was not cancelled before execution when the signal disappeared")
    if "LABEL TOO LONG" in text or "LABEL EMPTY" in text:
        errors.append("a chart label is longer than 63 characters (MT5 cuts it) or empty (MT5 shows 'Label')")
    if "SIGNAUX EN COURS (" not in signal or not re.search(r"^\[green\]   PainX 800 +H1 +\^ BUY", signal, re.M) or "BTN Ouvrir" not in signal:
        errors.append("signals table (indice, H1, BUY/SELL, levels, Ouvrir) missing")
    if "CHARTOPEN " not in text.split("=== LOG ===")[-1]:
        errors.append("the 'Ouvrir' button did not open the chart")
    if "ZORDER BAD" in text:
        errors.append("dashboard background created after texts/bars: it would hide them")
    if errors:
        print("\n".join("ERROR: " + e for e in errors))
        return 1
    print("Weltrade EA dashboard simulation passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
