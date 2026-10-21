#include "build/engine_fake.cpp"
#include <cstring>
const char* g_case;
int g_cycle=0;
bool FakeInspect(ENUM_TIMEFRAMES tf,TfInfo &r){
  r.ok=true; r.regime="TRENDING"; r.passed=13; r.quality=tf==PERIOD_H1?94:(tf==PERIOD_H4?92:88);
  r.trendStrong=true; r.bos=true; r.choch=true; r.sweep=false; r.impulse=true; r.fvg=true; r.orderBlock=true; r.momentum=true; r.rejection=true;
  r.spikeRisk=false; r.dmiAligned=true; r.macdAligned=true; r.donchian=true; r.squeeze=false; r.squeezeRelease=true; r.structureAligned=true; r.compression=false; r.engulfing=true;
  r.adx=tf==PERIOD_D1?28:35; r.er=0.55; r.volExp=1.2; r.barTime=1700000000+g_cycle*3600;
  if(!strcmp(g_case,"exec_now")){ r.side="BUY"; r.price=1000; r.ema20=999.2; r.atr=4; r.rsi=tf==PERIOD_H1?58:(58); r.retest=true; r.swingHigh=1006; r.swingLow=994; }
  if(!strcmp(g_case,"retrace")){ r.side="BUY"; r.price=1010; r.ema20=999.0; r.atr=4; r.rsi=tf==PERIOD_H1?64:(64); r.retest=false; r.swingHigh=1016; r.swingLow=1004; }
  if(!strcmp(g_case,"sell_now")){ r.side="SELL"; r.price=1000; r.ema20=1000.9; r.atr=4; r.rsi=tf==PERIOD_H1?42:(42); r.retest=true; r.swingHigh=1006; r.swingLow=994; }
  if(!strcmp(g_case,"exhausted")){ r.side="BUY"; r.price=1000; r.ema20=999.2; r.atr=4; r.rsi=tf==PERIOD_H1?58:(74); r.retest=true; r.swingHigh=1006; r.swingLow=994; }
  return true; }
int main(int argc,char**argv){ g_case=argv[1]; SwxDecision d; g_cycle=0; Decide("FX Vol 40",d); g_cycle=1; Decide("FX Vol 40",d);
  printf("{\"verdict\":\"%s\",\"state\":\"%s\",\"setup\":\"%s\",\"score\":%.0f,\"consensus\":%.0f,\"conditions\":%d,\"exec\":%.0f,\"cycles\":%d,\"sl\":%.6f,\"tp3\":%.6f}\n",
  d.verdict.c_str(),d.state.c_str(),d.setupType.c_str(),d.score,d.consensus*100,d.conditionPct,d.execScore,d.cycles,d.sl,d.tp3); }