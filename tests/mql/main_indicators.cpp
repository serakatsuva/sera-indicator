#include "build/engine.cpp"
#include <fstream>
#include <sstream>
int main(int argc,char**argv){
  std::ifstream f(argv[1]); std::string line;
  auto& d=g_data[(int)PERIOD_H1];
  while(std::getline(f,line)){ MqlRates r{}; std::stringstream ss(line); char c; ss>>r.time>>c>>r.open>>c>>r.high>>c>>r.low>>c>>r.close; d.push_back(r); }
  TfInfo t; bool ok=InspectTf("X",PERIOD_H1,t);
  printf("{\"ok\":%s,\"side\":\"%s\",\"regime\":\"%s\",\"passed\":%d,\"quality\":%.6f,\"ema20\":%.9g,\"ema50\":%.9g,\"ema200\":%.9g,\"rsi\":%.9g,\"atr\":%.9g,\"adx\":%.9g,\"plusDI\":%.9g,\"minusDI\":%.9g,\"macdHistogram\":%.9g,\"efficiencyRatio\":%.9g,\"swingHigh\":%.9g,\"swingLow\":%.9g,\"volatilityExpansion\":%.9g,"
    "\"trendStrong\":%d,\"bos\":%d,\"choch\":%d,\"sweep\":%d,\"impulse\":%d,\"fvg\":%d,\"retest\":%d,\"orderBlock\":%d,\"momentum\":%d,\"rejection\":%d,\"spikeRisk\":%d,\"dmiAligned\":%d,\"macdAligned\":%d,\"donchianBreakout\":%d,\"squeeze\":%d,\"squeezeRelease\":%d,\"marketStructureAligned\":%d,\"compression\":%d,\"engulfing\":%d}\n",
    ok?"true":"false",t.side.c_str(),t.regime.c_str(),t.passed,t.quality,t.ema20,t.ema50,t.ema200,t.rsi,t.atr,t.adx,t.plusDI,t.minusDI,t.macdHist,t.er,t.swingHigh,t.swingLow,t.volExp,
    t.trendStrong,t.bos,t.choch,t.sweep,t.impulse,t.fvg,t.retest,t.orderBlock,t.momentum,t.rejection,t.spikeRisk,t.dmiAligned,t.macdAligned,t.donchian,t.squeeze,t.squeezeRelease,t.structureAligned,t.compression,t.engulfing);
}
