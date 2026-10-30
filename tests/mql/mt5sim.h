// Minimal MT5 simulator: lets the Deriv EA's Evaluate() and dashboard RUN as C++ against a
// published signal feed, with a fake account / broker. Used by scripts/qa_ea_dashboard.py.
#include <string>
#include <vector>
#include <map>
#include <cmath>
#include <ctime>
#include <cstdio>
#include <cstdlib>
#include <climits>
#include <sstream>
#include <iostream>
#include <algorithm>
typedef std::string string; typedef long datetime; typedef unsigned long ulong; typedef unsigned int uint; typedef unsigned short ushort;
typedef unsigned int color;
#define input
enum ENUM_TIMEFRAMES{PERIOD_M1=60,PERIOD_M5=300,PERIOD_M15=900,PERIOD_H1=3600,PERIOD_H4=14400,PERIOD_D1=86400};
enum ENUM_ORDER_TYPE{ORDER_TYPE_BUY,ORDER_TYPE_SELL,ORDER_TYPE_BUY_LIMIT,ORDER_TYPE_SELL_LIMIT};
enum ENUM_POSITION_TYPE{POSITION_TYPE_BUY,POSITION_TYPE_SELL};
enum ENUM_ORDER_TYPE_TIME{ORDER_TIME_SPECIFIED};
enum ENUM_DEAL_ENTRY{DEAL_ENTRY_IN,DEAL_ENTRY_OUT,DEAL_ENTRY_OUT_BY};
enum E_INT{POSITION_MAGIC,POSITION_TYPE,POSITION_TIME,POSITION_TICKET,ORDER_MAGIC,ORDER_TYPE,DEAL_MAGIC,DEAL_ENTRY,SYMBOL_DIGITS,SYMBOL_TRADE_STOPS_LEVEL,ACCOUNT_TRADE_MODE,ACCOUNT_TRADE_MODE_DEMO,TERMINAL_TRADE_ALLOWED,MQL_TRADE_ALLOWED,ACCOUNT_MARGIN_MODE,DEAL_TIME,TERMINAL_SCREEN_DPI};
const long ACCOUNT_MARGIN_MODE_RETAIL_NETTING=0, ACCOUNT_MARGIN_MODE_EXCHANGE=1, ACCOUNT_MARGIN_MODE_RETAIL_HEDGING=2;
enum E_DBL{POSITION_PRICE_OPEN,POSITION_SL,POSITION_TP,POSITION_VOLUME,POSITION_PROFIT,POSITION_SWAP,ORDER_PRICE_OPEN,ORDER_SL,ORDER_TP,ORDER_VOLUME_CURRENT,DEAL_PROFIT,DEAL_SWAP,DEAL_COMMISSION,
  SYMBOL_POINT,SYMBOL_TRADE_TICK_SIZE,SYMBOL_TRADE_TICK_VALUE_LOSS,SYMBOL_TRADE_TICK_VALUE,SYMBOL_VOLUME_MIN,SYMBOL_VOLUME_MAX,SYMBOL_VOLUME_STEP,ACCOUNT_BALANCE,ACCOUNT_EQUITY,ACCOUNT_MARGIN_FREE,ACCOUNT_MARGIN};
enum E_STR{POSITION_SYMBOL,ORDER_SYMBOL};
const int INIT_SUCCEEDED=0; const double EMPTY_VALUE=1e308; const int WHOLE_ARRAY=-1; const int CP_UTF8=65001;
const int INVALID_HANDLE=-1; enum ENUM_MA_METHOD{MODE_EMA}; enum ENUM_APPLIED_PRICE{PRICE_CLOSE};
const long ACCOUNT_TRADE_MODE_REAL=2;
enum ENUM_OBJECT{OBJ_LABEL,OBJ_RECTANGLE_LABEL,OBJ_BUTTON,OBJ_RECTANGLE,OBJ_TREND,OBJ_TEXT};
const int STYLE_SOLID=0,STYLE_DASH=1; const long ANCHOR_LEFT=0;
const int CHARTEVENT_OBJECT_CLICK=1;
enum ENUM_OBJECT_PROPERTY_INTEGER{OBJPROP_CORNER,OBJPROP_SELECTABLE,OBJPROP_HIDDEN,OBJPROP_XDISTANCE,OBJPROP_YDISTANCE,OBJPROP_FONTSIZE,OBJPROP_COLOR,OBJPROP_BORDER_TYPE,OBJPROP_XSIZE,OBJPROP_YSIZE,OBJPROP_BGCOLOR,OBJPROP_STATE,OBJPROP_TIME,OBJPROP_FILL,OBJPROP_BACK,OBJPROP_STYLE,OBJPROP_WIDTH,OBJPROP_RAY_RIGHT,OBJPROP_ANCHOR};
enum ENUM_OBJECT_PROPERTY_DOUBLE{OBJPROP_PRICE};
enum ENUM_OBJECT_PROPERTY_STRING{OBJPROP_FONT,OBJPROP_TEXT};
const long CORNER_LEFT_UPPER=0; const long BORDER_FLAT=0;
struct MqlTick{datetime time;double bid,ask,last;};
struct MqlRates{datetime time;double open,high,low,close;long tick_volume;int spread;long real_volume;};
struct MqlDateTime{int year,mon,day,hour,min,sec,day_of_week,day_of_year;};

// ---------------- simulated world ----------------
datetime SIM_NOW=0;
double SIM_BALANCE=1000.0;
bool SIM_ALGO=true;
std::map<string,double> SIM_PRICE;       // symbol -> price
std::map<string,int> SIM_TREND;          // symbol -> +1 up / -1 down (broker candles)
struct SimPos{ulong ticket;string symbol;long type;double open,sl,tp,volume;datetime time;long magic;};
struct SimOrd{ulong ticket;string symbol;ENUM_ORDER_TYPE type;double price,sl,tp,volume;long magic;};
std::vector<SimPos> SIM_POS; std::vector<SimOrd> SIM_ORD; ulong SIM_TICKET=1000; int SIM_SEL_POS=-1, SIM_SEL_ORD=-1;
std::map<string,double> SIM_GV;
struct SimObj{int type; long order=0; std::map<int,long> ints; std::map<int,string> strs; std::map<int,double> prices;};
long SIM_OBJ_SEQ=0;
std::map<string,SimObj> SIM_OBJ;
std::vector<string> SIM_LOG;
string _Symbol="Volatility 75 Index";

template<class T> string sim_str(const T& v){ std::ostringstream o; o<<v; return o.str(); }
inline void sim_join(std::ostringstream&){}
template<class H,class... R> void sim_join(std::ostringstream& o,const H& h,const R&... r){ o<<h; sim_join(o,r...); }
template<class... A> void Print(const A&... a){ std::ostringstream o; sim_join(o,a...); SIM_LOG.push_back(o.str()); }
template<class... A> void Comment(const A&...){}
void Alert(const string& s){ SIM_LOG.push_back("ALERT "+s); }
bool SendNotification(const string&){ return true; }

template<class A,class B> auto MathMax(A a,B b)->decltype(a+b){ return a>b?a:b; }
template<class A,class B> auto MathMin(A a,B b)->decltype(a+b){ return a<b?a:b; }
double MathAbs(double v){ return std::fabs(v); } double MathFloor(double v){ return std::floor(v); }
double MathRound(double v){ return std::round(v); } double MathCeil(double v){ return std::ceil(v); } double MathSqrt(double v){ return std::sqrt(v); }
template<class T> int ArrayResize(std::vector<T>& v,int n){ v.resize(n); return n; }
template<class T> int ArraySize(const std::vector<T>& v){ return (int)v.size(); }
template<class T> bool ArraySetAsSeries(std::vector<T>&,bool){ return true; }

int StringFind(const string& s,const string& sub,int start=0){ if(start<0) start=0; auto p=s.find(sub,start); return p==string::npos?-1:(int)p; }
string StringSubstr(const string& s,int start,int len=-1){ if(start<0||start>=(int)s.size()) return ""; return len<0?s.substr(start):s.substr(start,len); }
int StringLen(const string& s){ return (int)s.size(); }
int StringReplace(string& s,const string& a,const string& b){ int n=0; size_t p=0; if(a.empty()) return 0; while((p=s.find(a,p))!=string::npos){ s.replace(p,a.size(),b); p+=b.size(); n++; } return n; }
bool StringToUpper(string& s){ for(auto& c:s) c=toupper(c); return true; }
int StringTrimLeft(string& s){ size_t p=s.find_first_not_of(" \t"); s=p==string::npos?"":s.substr(p); return 0; }
int StringTrimRight(string& s){ size_t p=s.find_last_not_of(" \t"); s=p==string::npos?"":s.substr(0,p+1); return 0; }
int StringSplit(const string& s,ushort sep,std::vector<string>& out){ out.clear(); std::stringstream ss(s); string it; while(std::getline(ss,it,(char)sep)) out.push_back(it); return (int)out.size(); }
ushort StringGetCharacter(const string& s,int i){ return i>=0&&i<(int)s.size()?(unsigned char)s[i]:0; }
double StringToDouble(const string& s){ return atof(s.c_str()); }
datetime StringToTime(const string& s){ struct tm t{}; if(sscanf(s.c_str(),"%d.%d.%d %d:%d:%d",&t.tm_year,&t.tm_mon,&t.tm_mday,&t.tm_hour,&t.tm_min,&t.tm_sec)<6) return 0; t.tm_year-=1900; t.tm_mon-=1; return timegm(&t); }
string IntegerToString(long v){ return std::to_string(v); }
string DoubleToString(double v,int d=8){ char b[64]; snprintf(b,sizeof b,"%.*f",d,v); return b; }
string CharArrayToString(const std::vector<char>& a,int,int,int){ return string(a.begin(),a.end()); }

double SIM_VOLMIN=0.01;
double SymbolInfoDouble(const string& s,E_DBL p){
  switch(p){ case SYMBOL_POINT: return 0.001; case SYMBOL_TRADE_TICK_SIZE: return 0.001; case SYMBOL_TRADE_TICK_VALUE_LOSS: return 0.001;
    case SYMBOL_VOLUME_MIN: return SIM_VOLMIN; case SYMBOL_VOLUME_MAX: return 100; case SYMBOL_VOLUME_STEP: return 0.01; default: return 0; } }
long SymbolInfoInteger(const string&,E_INT p){ return p==SYMBOL_DIGITS?3:0; }
std::map<string,double> SIM_SPREAD;   // ecart fixe ask-bid (sinon 0,002 %)
bool SymbolInfoTick(const string& s,MqlTick& t){ auto it=SIM_PRICE.find(s); if(it==SIM_PRICE.end()) return false; t.bid=it->second; t.ask=SIM_SPREAD.count(s)?it->second+SIM_SPREAD[s]:it->second*1.00002; t.last=t.bid; t.time=SIM_NOW; return true; }
bool SymbolSelect(const string& s,bool){ return SIM_PRICE.count(s)>0; }
int SymbolsTotal(bool){ return (int)SIM_PRICE.size(); }
string SymbolName(int i,bool){ auto it=SIM_PRICE.begin(); std::advance(it,i); return it->first; }

double sim_floating(){ double f=0; for(auto& p:SIM_POS){ double px=SIM_PRICE[p.symbol]; f+=(p.type==POSITION_TYPE_BUY?px-p.open:p.open-px)/0.001*0.001*p.volume; } return f; }
double AccountInfoDouble(E_DBL p){ double eq=SIM_BALANCE+sim_floating(); double m=0; for(auto& x:SIM_POS) m+=x.volume*x.open*0.01;
  switch(p){ case ACCOUNT_BALANCE: return SIM_BALANCE; case ACCOUNT_EQUITY: return eq; case ACCOUNT_MARGIN_FREE: return eq-m; case ACCOUNT_MARGIN: return m; default: return 0; } }
long SIM_MARGIN_MODE=2;
long AccountInfoInteger(E_INT p){ return p==ACCOUNT_TRADE_MODE?ACCOUNT_TRADE_MODE_REAL:p==ACCOUNT_MARGIN_MODE?SIM_MARGIN_MODE:0; }
long TerminalInfoInteger(E_INT){ return SIM_ALGO?1:0; } long MQLInfoInteger(E_INT){ return SIM_ALGO?1:0; }

int PositionsTotal(){ return (int)SIM_POS.size(); }
ulong PositionGetTicket(int i){ if(i<0||i>=(int)SIM_POS.size()) return 0; SIM_SEL_POS=i; return SIM_POS[i].ticket; }
bool PositionSelect(const string& s){ for(int i=0;i<(int)SIM_POS.size();i++) if(SIM_POS[i].symbol==s){ SIM_SEL_POS=i; return true; } return false; }
long PositionGetInteger(E_INT p){ if(SIM_SEL_POS<0||SIM_SEL_POS>=(int)SIM_POS.size()) return 0; auto& x=SIM_POS[SIM_SEL_POS];
  switch(p){ case POSITION_MAGIC: return x.magic; case POSITION_TYPE: return x.type; case POSITION_TIME: return x.time; case POSITION_TICKET: return (long)x.ticket; default: return 0; } }
double PositionGetDouble(E_DBL p){ if(SIM_SEL_POS<0||SIM_SEL_POS>=(int)SIM_POS.size()) return 0; auto& x=SIM_POS[SIM_SEL_POS];
  switch(p){ case POSITION_PRICE_OPEN: return x.open; case POSITION_SL: return x.sl; case POSITION_TP: return x.tp; case POSITION_VOLUME: return x.volume;
    case POSITION_PROFIT: { double px=SIM_PRICE[x.symbol]; return (x.type==POSITION_TYPE_BUY?px-x.open:x.open-px)*x.volume; } default: return 0; } }
string PositionGetString(E_STR){ return SIM_SEL_POS>=0&&SIM_SEL_POS<(int)SIM_POS.size()?SIM_POS[SIM_SEL_POS].symbol:""; }
int OrdersTotal(){ return (int)SIM_ORD.size(); }
ulong OrderGetTicket(int i){ if(i<0||i>=(int)SIM_ORD.size()) return 0; SIM_SEL_ORD=i; return SIM_ORD[i].ticket; }
long OrderGetInteger(E_INT p){ if(SIM_SEL_ORD<0||SIM_SEL_ORD>=(int)SIM_ORD.size()) return 0; auto& o=SIM_ORD[SIM_SEL_ORD]; return p==ORDER_MAGIC?o.magic:p==ORDER_TYPE?(long)o.type:0; }
string OrderGetString(E_STR){ return SIM_SEL_ORD>=0&&SIM_SEL_ORD<(int)SIM_ORD.size()?SIM_ORD[SIM_SEL_ORD].symbol:""; }
double OrderGetDouble(E_DBL p){ if(SIM_SEL_ORD<0||SIM_SEL_ORD>=(int)SIM_ORD.size()) return 0; auto& o=SIM_ORD[SIM_SEL_ORD];
  switch(p){ case ORDER_PRICE_OPEN: return o.price; case ORDER_SL: return o.sl; case ORDER_TP: return o.tp; case ORDER_VOLUME_CURRENT: return o.volume; default: return 0; } }
bool OrderCalcMargin(ENUM_ORDER_TYPE,const string&,double v,double px,double& m){ m=v*px*0.01; return true; }
bool HistorySelect(datetime,datetime){ return false; } int HistoryDealsTotal(){ return 0; }
ulong HistoryDealGetTicket(int){ return 0; } long HistoryDealGetInteger(ulong,E_INT){ return 0; } double HistoryDealGetDouble(ulong,E_DBL){ return 0; }

bool GlobalVariableCheck(const string& k){ return SIM_GV.count(k)>0; } double GlobalVariableGet(const string& k){ return SIM_GV[k]; }
datetime GlobalVariableSet(const string& k,double v){ SIM_GV[k]=v; return SIM_NOW; }
int GlobalVariablesTotal(){ return (int)SIM_GV.size(); }
string GlobalVariableName(int i){ auto it=SIM_GV.begin(); std::advance(it,i); return it->first; }
bool GlobalVariableDel(const string& k){ return SIM_GV.erase(k)>0; }
long SIM_CHART_ID=1001; long ChartID(){ return SIM_CHART_ID; }
datetime TimeCurrent(){ return SIM_NOW; } datetime TimeGMT(){ return SIM_NOW; }
bool TimeToStruct(datetime t,MqlDateTime& s){ time_t tt=t; struct tm g; gmtime_r(&tt,&g); s.year=g.tm_year+1900; s.mon=g.tm_mon+1; s.day=g.tm_mday; s.hour=g.tm_hour; s.min=g.tm_min; s.sec=g.tm_sec; s.day_of_week=g.tm_wday; s.day_of_year=g.tm_yday; return true; }
datetime StructToTime(MqlDateTime& s){ struct tm g{}; g.tm_year=s.year-1900; g.tm_mon=s.mon-1; g.tm_mday=s.day; g.tm_hour=s.hour; g.tm_min=s.min; g.tm_sec=s.sec; return timegm(&g); }
datetime iTime(const string&,ENUM_TIMEFRAMES tf,int shift){ return (SIM_NOW/(long)tf-shift)*(long)tf; }
// Broker candles: a clean trend per symbol (SIM_TREND) ending at the current price.
// "Wave" symbols (scalping tests): trend of SIM_STEP per bar + a wave peaking on the last closed bar + wicks.
std::map<string,bool> SIM_WAVE; double SIM_STEP=0.0002, SIM_AMP=0.0016, SIM_WICK=0.0003, SIM_PULL_SIZE=0.002;
std::map<string,int> SIM_PULL, SIM_PULLDIR;
std::map<string,double> SIM_HAMMER;   // longue meche basse sur la derniere bougie (rebond sur la moyenne)   // last N bars pulled back against the trend (essoufflement)
int CopyClose(const string& s,ENUM_TIMEFRAMES tf,int start,int count,std::vector<double>& out){
  double px=SIM_PRICE.count(s)?SIM_PRICE[s]:100; int dir=SIM_TREND.count(s)?SIM_TREND[s]:1; out.resize(count);
  if(SIM_WAVE.count(s)){ int pull=SIM_PULL.count(s)?SIM_PULL[s]:0; int tdir=SIM_PULLDIR.count(s)?SIM_PULLDIR[s]:dir;
    for(int i=0;i<count;i++){ int k=count-1-i; out[i]=px*(1.0-dir*SIM_STEP*k+dir*SIM_AMP*(std::cos(0.9*k)-1.0)+tdir*SIM_PULL_SIZE*std::min(k,pull)); } return count; }
  for(int i=0;i<count;i++) out[i]=px*(1.0-dir*0.002*(count-i)); return count; }
int CopyRates(const string& s,ENUM_TIMEFRAMES tf,int start,int count,std::vector<MqlRates>& out){
  std::vector<double> c; CopyClose(s,tf,start,count,c); out.resize(count);
  double px=SIM_PRICE.count(s)?SIM_PRICE[s]:100; bool wave=SIM_WAVE.count(s)>0;
  for(int i=0;i<count;i++){ out[i].time=iTime(s,tf,start+count-1-i); out[i].open=i?c[i-1]:c[i]; out[i].close=c[i];
    out[i].high=wave?std::max(out[i].open,c[i])+px*SIM_WICK:std::max(out[i].open,c[i])*1.0005;
    out[i].low=wave?std::min(out[i].open,c[i])-px*SIM_WICK:std::min(out[i].open,c[i])*0.9995;
    if(wave && i==count-1 && SIM_HAMMER.count(s)) out[i].low=std::min(out[i].open,c[i])-px*SIM_HAMMER[s]; }
  return count; }
std::string SymbolInfoString(const string&,int){ return ""; }
int iMA(const string&,ENUM_TIMEFRAMES,int,int,ENUM_MA_METHOD,ENUM_APPLIED_PRICE){ return INVALID_HANDLE; }
int iRSI(const string&,ENUM_TIMEFRAMES,int,ENUM_APPLIED_PRICE){ return INVALID_HANDLE; }
int iATR(const string&,ENUM_TIMEFRAMES,int){ return INVALID_HANDLE; } int iADX(const string&,ENUM_TIMEFRAMES,int){ return INVALID_HANDLE; }
int iMACD(const string&,ENUM_TIMEFRAMES,int,int,int,ENUM_APPLIED_PRICE){ return INVALID_HANDLE; }
int CopyBuffer(int,int,int,int,std::vector<double>&){ return 0; } bool IndicatorRelease(int){ return true; }
bool EventSetTimer(int){ return true; } void EventKillTimer(){}
int g_last_error=0; int GetLastError(){ return g_last_error; } void ResetLastError(){ g_last_error=0; }
double NormalizeDouble(double v,int d){ double f=std::pow(10.0,d); return std::round(v*f)/f; }
int WebRequest(const string&,const string&,const string&,const string&,int,const std::vector<char>&,int,std::vector<char>&,string&){ g_last_error=4014; return -1; }

bool ObjectCreate(long,const string& n,ENUM_OBJECT t,int,datetime t1,double p1,datetime t2=0,double p2=0){ SIM_OBJ[n].type=t; SIM_OBJ[n].order=++SIM_OBJ_SEQ; SIM_OBJ[n].prices[0]=p1; SIM_OBJ[n].prices[1]=p2; return true; }
bool ObjectSetInteger(long,const string& n,ENUM_OBJECT_PROPERTY_INTEGER p,int idx,long v){ SIM_OBJ[n].ints[p*10+idx]=v; return true; }
bool ObjectSetDouble(long,const string& n,ENUM_OBJECT_PROPERTY_DOUBLE,int idx,double v){ SIM_OBJ[n].prices[idx]=v; return true; }
bool ObjectSetInteger(long,const string& n,ENUM_OBJECT_PROPERTY_INTEGER p,long v){ SIM_OBJ[n].ints[p]=v; return true; }
bool ObjectSetString(long,const string& n,ENUM_OBJECT_PROPERTY_STRING p,const string& v){ SIM_OBJ[n].strs[p]=v; return true; }
int ObjectFind(long,const string& n){ return SIM_OBJ.count(n)?0:-1; }
bool ObjectDelete(long,const string& n){ return SIM_OBJ.erase(n)>0; }
int ObjectsDeleteAll(long,const string& prefix){ int k=0; for(auto it=SIM_OBJ.begin();it!=SIM_OBJ.end();){ if(it->first.rfind(prefix,0)==0){ it=SIM_OBJ.erase(it); k++; } else ++it; } return k; }
void ChartRedraw(long){}
bool TextSetFont(const string&,int){ return true; }
bool TextGetSize(const string& s,uint& w,uint& h){ w=(uint)(s.size()*7); h=14; return true; }
long ChartOpen(const string& s,ENUM_TIMEFRAMES tf){ SIM_LOG.push_back("CHARTOPEN "+s+" "+std::to_string((long)tf)); return 1; }
long SIM_CHART_H=0; const int CHART_HEIGHT_IN_PIXELS=1; long ChartGetInteger(long,int,int=0){ return SIM_CHART_H; }

struct CTrade{
  long magic=0;
  void SetExpertMagicNumber(long m){ magic=m; } void SetDeviationInPoints(ulong){} void SetAsyncMode(bool){}
  string ResultRetcodeDescription(){ return "done"; }
  bool open(long type,double v,const string& s,double sl,double tp){ SIM_POS.push_back({++SIM_TICKET,s,type,SIM_PRICE[s],sl,tp,v,SIM_NOW,magic}); return true; }
  bool Buy(double v,const string& s,double,double sl,double tp,const string&){ return open(POSITION_TYPE_BUY,v,s,sl,tp); }
  bool Sell(double v,const string& s,double,double sl,double tp,const string&){ return open(POSITION_TYPE_SELL,v,s,sl,tp); }
  bool BuyLimit(double v,double px,const string& s,double sl,double tp,ENUM_ORDER_TYPE_TIME,datetime,const string&){ SIM_ORD.push_back({++SIM_TICKET,s,ORDER_TYPE_BUY_LIMIT,px,sl,tp,v,magic}); return true; }
  bool SellLimit(double v,double px,const string& s,double sl,double tp,ENUM_ORDER_TYPE_TIME,datetime,const string&){ SIM_ORD.push_back({++SIM_TICKET,s,ORDER_TYPE_SELL_LIMIT,px,sl,tp,v,magic}); return true; }
  bool PositionClose(const string& s){ for(size_t i=0;i<SIM_POS.size();i++) if(SIM_POS[i].symbol==s){ SIM_POS.erase(SIM_POS.begin()+i); return true; } return false; }
  bool PositionClose(ulong t){ for(size_t i=0;i<SIM_POS.size();i++) if(SIM_POS[i].ticket==t){ SIM_POS.erase(SIM_POS.begin()+i); return true; } return false; }
  bool PositionClosePartial(ulong t,double v){ for(auto& p:SIM_POS) if(p.ticket==t){ p.volume-=v; return true; } return false; }
  bool PositionModify(ulong t,double sl,double tp){ for(auto& p:SIM_POS) if(p.ticket==t){ p.sl=sl; p.tp=tp; return true; } return false; }
  bool PositionModify(const string& s,double sl,double tp){ for(auto& p:SIM_POS) if(p.symbol==s){ p.sl=sl; p.tp=tp; return true; } return false; }
  bool OrderDelete(ulong t){ for(size_t i=0;i<SIM_ORD.size();i++) if(SIM_ORD[i].ticket==t){ SIM_ORD.erase(SIM_ORD.begin()+i); return true; } return false; }
};
