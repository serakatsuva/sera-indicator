#include <string>
#include <vector>
#include <cmath>
#include <climits>
typedef std::string string; typedef long datetime; typedef unsigned long ulong; typedef unsigned int uint; typedef unsigned short ushort;
#define input
enum ENUM_TIMEFRAMES{PERIOD_H1,PERIOD_H4,PERIOD_D1};
enum ENUM_ORDER_TYPE{ORDER_TYPE_BUY,ORDER_TYPE_SELL,ORDER_TYPE_BUY_LIMIT,ORDER_TYPE_SELL_LIMIT};
enum ENUM_POSITION_TYPE{POSITION_TYPE_BUY,POSITION_TYPE_SELL};
enum ENUM_ORDER_TYPE_TIME{ORDER_TIME_SPECIFIED};
enum ENUM_DEAL_ENTRY{DEAL_ENTRY_IN,DEAL_ENTRY_OUT,DEAL_ENTRY_OUT_BY};
enum E_INT{POSITION_MAGIC,POSITION_TYPE,POSITION_TIME,POSITION_TICKET,ORDER_MAGIC,ORDER_TYPE,DEAL_MAGIC,DEAL_ENTRY,SYMBOL_DIGITS,SYMBOL_TRADE_STOPS_LEVEL,ACCOUNT_TRADE_MODE,ACCOUNT_TRADE_MODE_DEMO,TERMINAL_TRADE_ALLOWED,MQL_TRADE_ALLOWED};
enum E_DBL{POSITION_PRICE_OPEN,POSITION_SL,POSITION_TP,POSITION_VOLUME,POSITION_PROFIT,POSITION_SWAP,ORDER_PRICE_OPEN,DEAL_PROFIT,DEAL_SWAP,DEAL_COMMISSION,
  SYMBOL_POINT,SYMBOL_TRADE_TICK_SIZE,SYMBOL_TRADE_TICK_VALUE_LOSS,SYMBOL_VOLUME_MIN,SYMBOL_VOLUME_MAX,SYMBOL_VOLUME_STEP,ACCOUNT_BALANCE,ACCOUNT_EQUITY,ACCOUNT_MARGIN_FREE,ACCOUNT_MARGIN};
enum E_STR{POSITION_SYMBOL,ORDER_SYMBOL};
const int INIT_SUCCEEDED=0; const double EMPTY_VALUE=1e308; const int WHOLE_ARRAY=-1; const int CP_UTF8=65001;
struct MqlTick{datetime time;double bid,ask,last;};
struct MqlRates{datetime time;double open,high,low,close;long tick_volume;int spread;long real_volume;};
struct MqlDateTime{int year,mon,day,hour,min,sec,day_of_week,day_of_year;};
struct CTrade{bool Buy(double,const string&,double,double,double,const string&);bool Sell(double,const string&,double,double,double,const string&);
 bool BuyLimit(double,double,const string&,double,double,ENUM_ORDER_TYPE_TIME,datetime,const string&);bool SellLimit(double,double,const string&,double,double,ENUM_ORDER_TYPE_TIME,datetime,const string&);
 bool PositionClose(const string&);bool PositionClose(ulong);bool PositionClosePartial(ulong,double);bool PositionModify(const string&,double,double);bool OrderDelete(ulong);
 void SetExpertMagicNumber(long);void SetDeviationInPoints(ulong);void SetAsyncMode(bool);string ResultRetcodeDescription();};
template<class A,class B> auto MathMax(A a,B b)->decltype(a+b); template<class A,class B> auto MathMin(A a,B b)->decltype(a+b);
double MathAbs(double);double MathFloor(double);double MathRound(double);double MathSqrt(double);
template<class T> int ArrayResize(std::vector<T>&,int); template<class T> int ArraySize(const std::vector<T>&); template<class T> bool ArraySetAsSeries(std::vector<T>&,bool);
int CopyRates(const string&,ENUM_TIMEFRAMES,int,int,std::vector<MqlRates>&); int CopyClose(const string&,ENUM_TIMEFRAMES,int,int,std::vector<double>&);
void Print(...); void Alert(const string&); void Comment(...); bool SendNotification(const string&);
int StringFind(const string&,const string&,int=0); string StringSubstr(const string&,int,int=-1); int StringLen(const string&); int StringReplace(string&,const string&,const string&);
bool StringToUpper(string&); int StringTrimLeft(string&); int StringTrimRight(string&); int StringSplit(const string&,ushort,std::vector<string>&); ushort StringGetCharacter(const string&,int);
double StringToDouble(const string&); datetime StringToTime(const string&); string IntegerToString(long); string DoubleToString(double,int=8);
double SymbolInfoDouble(const string&,E_DBL); long SymbolInfoInteger(const string&,E_INT); bool SymbolInfoTick(const string&,MqlTick&); bool SymbolSelect(const string&,bool);
int SymbolsTotal(bool); string SymbolName(int,bool); double AccountInfoDouble(E_DBL); long AccountInfoInteger(E_INT);
int PositionsTotal(); ulong PositionGetTicket(int); long PositionGetInteger(E_INT); double PositionGetDouble(E_DBL); string PositionGetString(E_STR); bool PositionSelect(const string&);
int OrdersTotal(); ulong OrderGetTicket(int); long OrderGetInteger(E_INT); string OrderGetString(E_STR); double OrderGetDouble(E_DBL); bool OrderCalcMargin(ENUM_ORDER_TYPE,const string&,double,double,double&);
bool HistorySelect(datetime,datetime); int HistoryDealsTotal(); ulong HistoryDealGetTicket(int); long HistoryDealGetInteger(ulong,E_INT); double HistoryDealGetDouble(ulong,E_DBL);
bool GlobalVariableCheck(const string&); double GlobalVariableGet(const string&); datetime GlobalVariableSet(const string&,double);
datetime TimeCurrent(); datetime TimeGMT(); bool TimeToStruct(datetime,MqlDateTime&); datetime StructToTime(MqlDateTime&); datetime iTime(const string&,ENUM_TIMEFRAMES,int);
bool EventSetTimer(int); void EventKillTimer(); int GetLastError(); void ResetLastError(); long TerminalInfoInteger(E_INT); long MQLInfoInteger(E_INT);
double NormalizeDouble(double,int); string CharArrayToString(const std::vector<char>&,int,int,int);
const int INVALID_HANDLE=-1; enum ENUM_MA_METHOD{MODE_EMA}; enum ENUM_APPLIED_PRICE{PRICE_CLOSE};
int iMA(const string&,ENUM_TIMEFRAMES,int,int,ENUM_MA_METHOD,ENUM_APPLIED_PRICE); int iRSI(const string&,ENUM_TIMEFRAMES,int,ENUM_APPLIED_PRICE);
int iATR(const string&,ENUM_TIMEFRAMES,int); int iADX(const string&,ENUM_TIMEFRAMES,int); int iMACD(const string&,ENUM_TIMEFRAMES,int,int,int,ENUM_APPLIED_PRICE);
int CopyBuffer(int,int,int,int,std::vector<double>&); bool IndicatorRelease(int);
int WebRequest(const string&,const string&,const string&,const string&,int,const std::vector<char>&,int,std::vector<char>&,string&);
extern string _Symbol; const long ACCOUNT_TRADE_MODE_REAL=2;
// Forward use already present in the original v1.80 code (MQL5 allows it, C++ needs prototypes):
double StoredLevel(const string&,const string&); void StoreLevel(const string&,const string&,const double); double AdaptiveRiskPercent(); double SafeVolume(const string&,const double,const double);
