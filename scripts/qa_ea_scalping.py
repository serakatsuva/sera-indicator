#!/usr/bin/env python3
"""Runs Sera EA Scalping Intelligent (compiled as C++ against the MT5 simulator tests/mql/mt5sim.h)
through a full scalping session and checks:
  - only Volatility / Forex / crypto symbols are traded (Boom, Crash, Jump, other indices excluded),
  - entries follow the candle and the trend (BUY in up-trends, SELL in down-trends),
  - several positions per symbol, added only once the previous ones are secured, never more than the maximum,
  - profit is locked (stop moved to entry / trailing) while the trend continues,
  - a reversal cuts the positions, a fading move takes the profit,
  - the dashboard is drawn (background under the texts, lines fit the panel).
Usage: qa_ea_scalping.py [--quiet]"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from qa_mql_cpp import to_cpp  # noqa: E402

BUILD = ROOT / "tests" / "mql" / "build"
EA = next((ROOT / "mt5").glob("Sera_EA_Scalping_Intelligent_v*.mq5"))

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
  std::sort(lines.begin(),lines.end());
  for(auto& l:lines) printf("%s\n",l.second.c_str());
  long bg=SIM_OBJ.count("SCALP_PANEL_BG")?SIM_OBJ["SCALP_PANEL_BG"].order:-1; long first=LONG_MAX;
  for(auto& kv:SIM_OBJ) if(kv.first!="SCALP_PANEL_BG" && kv.first.rfind("SCALP_PANEL_",0)==0) first=std::min(first,kv.second.order);
  printf("ZORDER %s\n",bg>0 && bg<first?"OK":"BAD");
  for(auto& kv:SIM_OBJ) if(kv.second.type==OBJ_LABEL){ const string& s=kv.second.strs[OBJPROP_TEXT];
    if(s.size()>63) printf("LABEL TOO LONG %s (%zu)\n",kv.first.c_str(),s.size()); if(s.empty()) printf("LABEL EMPTY %s\n",kv.first.c_str()); }
  for(auto& p:SIM_POS) printf("POS %s %s vol=%.2f open=%.5f sl=%.5f\n",p.symbol.c_str(),p.type==POSITION_TYPE_BUY?"BUY":"SELL",p.volume,p.open,p.sl);
}
static void move(const string& s,double pct){ SIM_PRICE[s]*=1.0+pct; }
// Le broker execute les stops : une position dont le SL est touche est fermee au prix du SL.
static void hit_stops(){
  for(size_t i=0;i<SIM_POS.size();){ auto& p=SIM_POS[i]; double px=SIM_PRICE[p.symbol];
    bool hit=p.sl>0 && (p.type==POSITION_TYPE_BUY?px<=p.sl:px>=p.sl);
    if(hit){ double pnl=(p.type==POSITION_TYPE_BUY?p.sl-p.open:p.open-p.sl)*p.volume; printf("STOPHIT %s %.2f\n",p.symbol.c_str(),pnl); SIM_BALANCE+=pnl; SIM_POS.erase(SIM_POS.begin()+i); }
    else i++; } }
int main(int argc,char** argv){
  string mode=argc>1?argv[1]:"";
  if(mode=="netting") SIM_MARGIN_MODE=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
  if(mode=="be" || mode=="tp") SIM_VOLMIN=0.67;
  if(mode=="grow") SIM_GV["SCALP_BASE_26103001"]=988.0;     // +12 $ de gain net depuis le demarrage -> 3 x le lot minimum                            // lot minimum 0,67 : 1 point = 0,67 $
  if(mode=="small"){ SIM_BALANCE=49.22; SIM_VOLMIN=0.3; }   // petit compte et lot minimum eleve
  // spread fixe type indices (1s) Deriv : ~30 % de l'ATR M1 (= ~20 % du SL) accepte, ~60 % de l'ATR (~40 % du SL) refuse
  if(mode=="spread"){ SIM_SPREAD["Volatility 75 Index"]=0.9; SIM_SPREAD["Volatility 100 (1s) Index"]=1.4; }
  struct W{ const char* name; double px; int dir; };
  W world[]={{"Volatility 75 Index",1000,1},{"Volatility 100 (1s) Index",800,-1},{"EURUSD",1.085,-1},{"BTCUSD",60000,1},
             {"Volatility 50 Index",500,1},{"Volatility 25 Index",700,1},{"Boom 1000 Index",12000,1},{"Crash 500 Index",3000,-1},{"Jump 25 Index",900,1},{"US Tech 100",18000,1}};
  for(auto& w:world){ SIM_PRICE[w.name]=w.px; SIM_TREND[w.name]=w.dir; SIM_WAVE[w.name]=true; }
  SIM_PULL["Volatility 50 Index"]=1;        // derniere bougie hesitante : pas d'entree a la cloture
  SIM_HAMMER["Volatility 25 Index"]=0.004;  // retour sur l'EMA21 + longue meche basse : rebond dans la tendance
  SIM_NOW=1793182830;                       // mercredi 28/10/2026 10:00:30 UTC
  OnInit();
  dump("DEMARRAGE");
  for(int i=0;i<ArraySize(g_views);i++) printf("VIEW %s class=%s score=%d side=%d reason=%s\n",g_views[i].symbol.c_str(),g_views[i].klass.c_str(),g_views[i].score,g_views[i].side,g_views[i].reason.c_str());
  if(mode=="tp"){
    double open=0,vol=1; for(auto& p:SIM_POS) if(p.symbol=="Volatility 75 Index"){ open=p.open; vol=p.volume; }
    SIM_PRICE["Volatility 75 Index"]=open+0.35/vol; SIM_NOW+=10; OnTimer(); dump("OBJECTIF +0,35 $");
    printf("=== LOG ===\n"); for(auto& l:SIM_LOG) printf("%s\n",l.c_str());
    return 0;
  }
  if(mode=="be"){
    // petit gain (+0,20 $ : entre le seuil de securisation 0,15 $ et l'objectif 0,30 $) -> SL au prix d'entree ;
    // puis chute brutale -> la position sort a 0 ou en gain
    double open=0,vol=1; for(auto& p:SIM_POS) if(p.symbol=="Volatility 75 Index"){ open=p.open; vol=p.volume; }
    SIM_PRICE["Volatility 75 Index"]=open+0.20/vol; SIM_NOW+=10; OnTimer(); dump("PETIT GAIN");
    SIM_PRICE["Volatility 75 Index"]=open*0.99; hit_stops(); SIM_NOW+=10; OnTimer(); dump("CHUTE APRES PETIT GAIN");
    printf("=== LOG ===\n"); for(auto& l:SIM_LOG) printf("%s\n",l.c_str());
    return 0;
  }
  if(mode==""){ SIM_PRICE["Volatility 50 Index"]*=1.004; SIM_NOW+=20; OnTimer(); dump("CASSURE PENDANT LA BOUGIE"); }
  for(int step=1;step<=4;step++){
    move("Volatility 75 Index",0.0025); move("BTCUSD",0.0025); move("EURUSD",-0.0025); move("Volatility 100 (1s) Index",-0.0025);
    SIM_NOW+=60; OnTimer();
    char t[64]; snprintf(t,sizeof t,"TENDANCE QUI CONTINUE %d",step); dump(t);
  }
  if(mode=="crash"){
    // chute brutale contre toutes les positions : l'equite perd plus de 15 % -> arret d'urgence
    for(auto& p:SIM_POS){ SIM_PRICE[p.symbol]=p.type==POSITION_TYPE_BUY?p.open*0.5:p.open*1.5; }
    SIM_BALANCE=1000; SIM_NOW+=1; OnTimer(); dump("CHUTE BRUTALE");
    SIM_NOW+=60; OnTimer(); dump("APRES ARRET D'URGENCE");
    printf("=== LOG ===\n"); for(auto& l:SIM_LOG) printf("%s\n",l.c_str());
    return 0;
  }
  SIM_TREND["EURUSD"]=1; SIM_NOW+=60; OnTimer(); dump("RETOURNEMENT EURUSD");
  SIM_PULL_SIZE=0.004; SIM_PULL["Volatility 75 Index"]=1;    // une bougie M1 rouge franche, tendance M5 encore haussiere
  SIM_NOW+=60; OnTimer(); dump("ESSOUFFLEMENT VOLATILITY 75");
  printf("=== LOG ===\n"); for(auto& l:SIM_LOG) printf("%s\n",l.c_str());
  return 0;
}
'''


def build() -> Path:
    BUILD.mkdir(parents=True, exist_ok=True)
    src = to_cpp(EA.read_text(encoding="utf-8")).replace('#include "../mt5stubs.h"', '#include "../mt5sim.h"')
    cpp = BUILD / "scalping_sim.cpp"
    cpp.write_text(src + MAIN, encoding="utf-8")
    exe = BUILD / "scalping_sim"
    subprocess.run(["g++", "-std=c++17", "-O1", "-w", "-o", str(exe), str(cpp)], check=True)
    return exe


def main() -> int:
    quiet = "--quiet" in sys.argv
    out = subprocess.run([str(build())], capture_output=True, text=True, timeout=300)
    if out.returncode != 0:
        print(out.stdout[-3000:], out.stderr[-3000:])
        print("ERROR: scalping EA simulation crashed")
        return 1
    text = out.stdout
    if not quiet:
        print(text)
    sections = dict(re.findall(r"=== (.+?) ===\n(.*?)(?==== |\Z)", text, re.S))
    log = sections.get("LOG", "")
    errors = []
    allowed = {"Volatility 75 Index", "Volatility 100 (1s) Index", "EURUSD", "BTCUSD", "Volatility 50 Index", "Volatility 25 Index"}
    traded = set(re.findall(r"^POS (.+?) (?:BUY|SELL) ", text, re.M))
    if traded - allowed:
        errors.append(f"excluded symbols were traded: {sorted(traded - allowed)}")
    for name in ("Boom 1000 Index", "Crash 500 Index", "Jump 25 Index", "US Tech 100"):
        if f"VIEW {name} " in text:
            errors.append(f"{name} should not be scanned")
    for name, side in (("Volatility 75 Index", "BUY"), ("BTCUSD", "BUY"), ("EURUSD", "SELL"), ("Volatility 100 (1s) Index", "SELL")):
        if not re.search(rf"^POS {re.escape(name)} {side} ", text, re.M):
            errors.append(f"no {side} position on {name} although the candle and the trend agree")
        before_flip = text.split("=== RETOURNEMENT")[0]
        if re.search(rf"^POS {re.escape(name)} {'SELL' if side == 'BUY' else 'BUY'} ", before_flip, re.M):
            errors.append(f"position against the trend on {name}")
    start = sections.get("DEMARRAGE", "")
    brk = sections.get("CASSURE PENDANT LA BOUGIE", "")
    if re.search(r"^POS Volatility 50 Index", start, re.M):
        errors.append("Volatility 50 Index entered at the close although its last candle was not clear")
    if not re.search(r"^POS Volatility 50 Index BUY", brk, re.M) or "BUY Volatility 50 Index lot" not in log or "cassure score" not in log:
        errors.append("no intrabar breakout entry on Volatility 50 Index when the price broke the previous candle")
    if not re.search(r"BUY Volatility 25 Index lot \S+  SL \S+  rebond score", log):
        errors.append("no 'rebond' BUY on Volatility 25 Index (pull-back to the EMA21 with a hammer candle in an up-trend)")
    counts = [len(re.findall(r"^POS Volatility 75 Index BUY", sec, re.M)) for sec in sections.values()]
    if max(counts or [0]) < 2:
        errors.append("no second position added on Volatility 75 Index while the trend continued")
    if max(counts or [0]) > 3:
        errors.append("more than MaximumPositionsPerSymbol (3) positions on one symbol")
    if "position securisee" not in log and "SL suiveur" not in log:
        errors.append("profits were never locked (no stop moved to entry / trailing)")
    rev = sections.get("RETOURNEMENT EURUSD", "")
    if re.search(r"^POS EURUSD SELL", rev, re.M) or "EURUSD ferme" not in log or "retournement detecte" not in log:
        errors.append("EURUSD SELL positions were not cut in the cycle where the market turned")
    if re.search(r"^POS EURUSD BUY", rev, re.M):
        errors.append("a BUY was opened on EURUSD on the same candle as the reversal cut")
    fade = sections.get("ESSOUFFLEMENT VOLATILITY 75", "")
    # positions already in profit are closed; a position just opened (no gain yet) stays under its stop loss
    kept = [float(r) for r in re.findall(r"^\[\w+\]   Volatility 75 Index +BUY +\S+ +\S+ +\S+ +\S+ +(-?[0-9.]+) ", fade, re.M)]
    if any(r >= 1.0 for r in kept):
        errors.append(f"Volatility 75 Index positions in profit kept although a red candle ended the move (R={kept})")
    if not re.search(r"Volatility 75 Index ferme \([0-9.]+ R\) - benefice encaisse", log):
        errors.append("the Volatility 75 Index profit was not taken when the move faded")
    for sec in sections.values():
        for line in sec.splitlines():
            if line.startswith("[") and len(line.split("] ", 1)[-1]) > 135:
                errors.append(f"dashboard line too long: {line[:70]}...")
                break
    if "LABEL TOO LONG" in text or "LABEL EMPTY" in text:
        errors.append("a chart label is longer than 63 characters (MT5 cuts it) or empty (MT5 shows 'Label')")
    if "ZORDER BAD" in text:
        errors.append("dashboard background drawn over the texts")
    if "SERA EA SCALPING INTELLIGENT" not in sections.get("DEMARRAGE", ""):
        errors.append("dashboard not drawn")
    exe = BUILD / "scalping_sim"
    net = subprocess.run([str(exe), "netting"], capture_output=True, text=True, timeout=300).stdout
    net_counts = [len(re.findall(r"^POS Volatility 75 Index ", sec, re.M)) for sec in re.split(r"^=== ", net, flags=re.M)]
    if max(net_counts or [0]) != 1:
        errors.append(f"netting account: expected exactly 1 position per symbol, saw up to {max(net_counts or [0])}")
    crash = subprocess.run([str(exe), "crash"], capture_output=True, text=True, timeout=300).stdout
    after = crash.split("=== APRES ARRET D'URGENCE ===")[-1].split("=== LOG ===")[0]
    if "toutes les positions fermees - arret d'urgence" not in crash or "POS " in after:
        errors.append("emergency stop did not close every position after a -15 % equity drop")
    if "BOT EN PAUSE  |  arret d'urgence" not in after:
        errors.append("no new entries should be allowed after the emergency stop (dashboard must show the pause)")
    small = subprocess.run([str(exe), "small"], capture_output=True, text=True, timeout=300).stdout
    first = small.split("=== TENDANCE")[0]
    if not re.search(r"^POS Volatility 75 Index BUY vol=0.30", first, re.M):
        errors.append("small account (49 $): the minimum lot risking < 3 % of the equity was refused")
    if re.search(r"^POS BTCUSD", first, re.M):
        errors.append("small account: a minimum lot risking more than 3 % of the equity was accepted")
    if "BTCUSD pret mais pas d'entree - BUY : lot min. risque" not in small:
        errors.append("small account: the refused entry is not explained in the journal")
    be = subprocess.run([str(exe), "be"], capture_output=True, text=True, timeout=300).stdout
    small_gain = be.split("=== PETIT GAIN ===")[-1].split("=== CHUTE")[0]
    m = re.search(r"^POS Volatility 75 Index BUY vol=\S+ open=([0-9.]+) sl=([0-9.]+)", small_gain, re.M)
    if not m or float(m.group(2)) < float(m.group(1)):
        errors.append("after a +0.20 $ gain the stop loss was not moved to the entry price")
    hits = [float(x) for x in re.findall(r"^STOPHIT Volatility 75 Index (-?[0-9.]+)", be, re.M)]
    if not hits or min(hits) < 0:
        errors.append(f"a position that was in gain finished with a loss after the market turned ({hits})")
    tp = subprocess.run([str(exe), "tp"], capture_output=True, text=True, timeout=300).stdout
    if not re.search(r"Volatility 75 Index ferme \([0-9.]+ R\) - benefice encaisse \+0\.3\d \$ \(objectif atteint\)", tp) or \
            "POS Volatility 75 Index" in tp.split("=== OBJECTIF")[-1].split("=== LOG")[0]:
        errors.append("a +0.35 $ gain was not taken at once (target 0.30 $)")
    lots = re.findall(r"^POS \S.* vol=([0-9.]+) ", tp.split("=== OBJECTIF")[0], re.M)
    if any(float(v) != 0.67 for v in lots):
        errors.append(f"entries must use the minimum lot (0.67 here), saw {sorted(set(lots))}")
    grow = subprocess.run([str(exe), "grow"], capture_output=True, text=True, timeout=300).stdout.split("=== CASSURE")[0]
    grow_lots = set(re.findall(r"^POS \S.* vol=([0-9.]+) ", grow, re.M))
    if grow_lots != {"0.03"} or "lot minimum x3" not in grow:
        errors.append(f"after +12 $ of gains the lot must be 3 x the minimum (0.03), saw {sorted(grow_lots)}")
    spread = subprocess.run([str(exe), "spread"], capture_output=True, text=True, timeout=300).stdout
    first = spread.split("=== TENDANCE")[0].split("=== CASSURE")[0]
    if not re.search(r"^POS Volatility 75 Index BUY", first, re.M):
        errors.append("spread of ~20 % of the stop loss was refused (Deriv 1s indices must trade)")
    if re.search(r"^POS Volatility 100 \(1s\) Index", first, re.M) or "Volatility 100 (1s) Index pret mais pas d'entree - SELL pret mais spread =" not in spread:
        errors.append("a spread of ~40 % of the stop loss was accepted, or the refusal is not explained")
    if errors:
        print("\n".join("ERROR: " + e for e in errors))
        return 1
    print(f"Scalping EA simulation passed ({len(traded)} symbols traded, up to {max(counts)} positions on Volatility 75 Index)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
