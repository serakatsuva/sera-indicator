// Minimal MQL5 -> C++ shim, only for compiling and testing the analysis engine.
#include <string>
#include <vector>
#include <map>
#include <cmath>
#include <cstdio>
#include <algorithm>
#include <type_traits>
typedef std::string string;
typedef long datetime;
enum ENUM_TIMEFRAMES { PERIOD_H1=60, PERIOD_H4=240, PERIOD_D1=1440 };
struct MqlRates { datetime time; double open,high,low,close; long tick_volume; int spread; long real_volume; };
template<class A,class B> auto MathMax(A a,B b)->typename std::common_type<A,B>::type { return a>b?a:b; }
template<class A,class B> auto MathMin(A a,B b)->typename std::common_type<A,B>::type { return a<b?a:b; }
inline double MathAbs(double v){ return std::fabs(v); }
inline double MathRound(double v){ return std::round(v); }
inline double MathSqrt(double v){ return std::sqrt(v); }
template<class T> int ArrayResize(std::vector<T>& v,int n){ v.resize(n); return n; }
template<class T> int ArraySize(const std::vector<T>& v){ return (int)v.size(); }
template<class T> bool ArraySetAsSeries(std::vector<T>&,bool){ return true; }
// test data per timeframe (oldest -> newest, all closed)
std::map<int,std::vector<MqlRates>> g_data;
int CopyRates(const string&,ENUM_TIMEFRAMES tf,int start,int count,std::vector<MqlRates>& out){
  auto& d=g_data[(int)tf]; int n=std::min<int>(count,(int)d.size()); out.assign(d.end()-n,d.end()); return n; }
std::map<std::string,double> g_store;
int StoredState(const string& p,const string& id){ return (int)g_store[p+id]; }
void StoreState(const string& p,const string& id,int v){ g_store[p+id]=v; }
double StoredLevel(const string& p,const string& id){ return g_store[p+id]; }
void StoreLevel(const string& p,const string& id,double v){ g_store[p+id]=v; }
inline void StringToUpper(string& s){ for(auto& ch:s) ch=toupper(ch); }
inline int StringReplace(string& s,const string& a,const string& b){ int n=0; size_t p=0; while((p=s.find(a,p))!=string::npos){ s.replace(p,a.size(),b); p+=b.size(); n++; } return n; }
inline int StringFind(const string& s,const string& sub,int start=0){ auto p=s.find(sub,start); return p==string::npos?-1:(int)p; }
bool TradePainGainX=true,TradeVolIndices=true,TradeRegimeSwitchX=true,TradeFlipX=false,TradeProgressionX=false;
int AnalysisBars=1000;
