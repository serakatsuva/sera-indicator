#include "build/engine.cpp"
#include <fstream>
#include <sstream>
void load(const char* path,ENUM_TIMEFRAMES tf){ std::ifstream f(path); std::string line; auto& d=g_data[(int)tf]; d.clear();
  while(std::getline(f,line)){ MqlRates r{}; std::stringstream ss(line); char c; ss>>r.time>>c>>r.open>>c>>r.high>>c>>r.low>>c>>r.close; d.push_back(r);} }
int main(int argc,char**argv){
  std::string k=argv[1];
  load((k+"_H1.csv").c_str(),PERIOD_H1); load((k+"_H4.csv").c_str(),PERIOD_H4); load((k+"_D1.csv").c_str(),PERIOD_D1);
  // cycle 1 on the previous H1 bar, cycle 2 on the last one (same bias) -> 2/2
  SwxDecision d;
  auto full=g_data[(int)PERIOD_H1]; g_data[(int)PERIOD_H1].pop_back(); Decide("FX Vol 40",d);
  g_data[(int)PERIOD_H1]=full; Decide("FX Vol 40",d);
  printf("{\"verdict\":\"%s\",\"state\":\"%s\",\"setup\":\"%s\",\"score\":%.0f,\"consensus\":%.0f,\"conditions\":%d,\"exec\":%.0f,\"cycles\":%d,\"sl\":%.6f,\"tp3\":%.6f}\n",
    d.verdict.c_str(),d.state.c_str(),d.setupType.c_str(),d.score,d.consensus*100,d.conditionPct,d.execScore,d.cycles,d.sl,d.tp3);
}
