#property copyright "Sera EA Swing Intelligent"
#property version   "1.80"
#property strict

#include <Trade/Trade.mqh>

input string SignalsUrl="https://serakatsuva.github.io/sera-indicator/data/signals.json";
input bool EnableTrendWatch=true;
input bool EnableTerminalAlert=true;
input bool EnablePushNotification=false;
input bool AllowAutonomousExecution=true;
input bool EnableAutomaticTrading=true;
input bool AllowRealAccount=true;
input double RiskPercent=0.50;
input double MaximumAdaptiveRiskPercent=0.75;
input double MaximumLossUSD=1.00;
input double MaximumAdaptiveLossUSD=1.50;
input double MaximumLot=0.05;
input bool EnableAdaptiveLot=true;
input double EquityGrowthStepPercent=5.0;
input double RiskIncreasePerEquityStep=0.05;
input double DailyProfitBoostThresholdUSD=2.00;
input double DailyProfitRiskBoost=0.05;
input int MinimumConfidence=75;
input int MinimumAutonomousConditionsPercent=80;
input int MinimumExecutionScore=78;
input bool RequireExecuteNow=true;
input bool UseOpenSourceModelGuard=true;
input int MinimumModelConsensus=67;
input bool EnableSmartPositionManagement=true;
input bool DynamicFinalTarget=true;
input int MaximumEntryChaseRiskPercent=35;
input int MaximumSpreadRiskPercent=12;
input int MaximumSignalAgeMinutes=90;
input int MaximumOpenPositions=1;
input int MaximumPendingOrders=1;
input int MaximumTradesPerDay=2;
input double MaximumDailyLossUSD=3.00;
input double MaximumDailyDrawdownPercent=3.00;
input int MaximumConsecutiveLosses=2;
input double MinimumFreeMarginPercent=25.0;
input bool EnforceBrokerStopsLevel=true;
input bool EnableSmartPendingLimits=true;
input int PendingExpirationHours=8;
input int MinimumPendingExecutionScore=72;
input int MinimumPendingConditionsPercent=80;
input int PollEverySeconds=30;
input long MagicNumber=26091801;
input int DeviationPoints=30;

// --- Local multi-asset Swing intelligence (MT5 candles)
input bool EnableLocalSwingIntelligence=true;
input bool EnableLocalAutoEntry=false;
input int LocalMinimumScore=78;
input double LocalMinimumADX=20.0;
input bool EnableAssetAdaptiveProfiles=true;
input double GoldRiskFactor=0.85;
input double CryptoRiskFactor=0.70;
input double ForexRiskFactor=0.90;
input double SyntheticRiskFactor=1.00;
input double GoldATRMultiplier=2.20;
input double CryptoATRMultiplier=2.70;
input double ForexATRMultiplier=1.80;
input double SyntheticATRMultiplier=2.00;
input bool EnableATRProfitTrail=true;
input double ProfitProtectionStartR=1.20;
input double ProfitLockR=0.35;
input double ATRTrailMultiplier=1.60;

CTrade trade;
datetime last_poll=0;
datetime local_last_h1_bar=0;

string JsonString(const string object,const string key)
{
   string token="\""+key+"\"";
   int p=StringFind(object,token); if(p<0) return "";
   p=StringFind(object,":",p+StringLen(token)); if(p<0) return "";
   p=StringFind(object,"\"",p+1); if(p<0) return "";
   int e=StringFind(object,"\"",p+1); if(e<0) return "";
   return StringSubstr(object,p+1,e-p-1);
}

double JsonNumber(const string object,const string key)
{
   string token="\""+key+"\"";
   int p=StringFind(object,token); if(p<0) return 0.0;
   p=StringFind(object,":",p+StringLen(token)); if(p<0) return 0.0;
   p++;
   while(p<StringLen(object) && (StringGetCharacter(object,p)==' ' || StringGetCharacter(object,p)=='\t')) p++;
   int e=p;
   while(e<StringLen(object))
   {
      ushort c=StringGetCharacter(object,e);
      if((c>='0'&&c<='9')||c=='-'||c=='+'||c=='.'||c=='e'||c=='E') e++; else break;
   }
   return StringToDouble(StringSubstr(object,p,e-p));
}

string ExtractObjectAt(const string json,const int start)
{
   int depth=0; bool quoted=false;
   for(int i=start;i<StringLen(json);i++)
   {
      ushort c=StringGetCharacter(json,i);
      if(c=='\"' && (i==0 || StringGetCharacter(json,i-1)!='\\')) quoted=!quoted;
      if(quoted) continue;
      if(c=='{') depth++;
      if(c=='}' && --depth==0) return StringSubstr(json,start,i-start+1);
   }
   return "";
}

datetime ParseIsoUtc(string iso)
{
   if(StringLen(iso)<19) return 0;
   string value=StringSubstr(iso,0,19);
   StringReplace(value,"-","."); StringReplace(value,"T"," ");
   return StringToTime(value);
}

string ResolveTradeSymbol(const string market_name,const string deriv_code)
{
   if(market_name!="" && SymbolSelect(market_name,true)) return market_name;
   if(deriv_code!="" && SymbolSelect(deriv_code,true)) return deriv_code;

   string market_compact=market_name;
   StringReplace(market_compact," ","");
   for(int i=0;i<SymbolsTotal(false);i++)
   {
      string candidate=SymbolName(i,false);
      string compact=candidate;
      StringReplace(compact," ","");
      if(candidate==market_name || candidate==deriv_code || compact==market_compact)
      {
         if(SymbolSelect(candidate,true)) return candidate;
      }
   }
   return "";
}

bool FetchSignals(string &json)
{
   char body[],response[]; string headers;
   ResetLastError();
   int code=WebRequest("GET",SignalsUrl,"","",10000,body,0,response,headers);
   if(code!=200){ Print("Sera: téléchargement impossible, HTTP=",code," erreur=",GetLastError()); return false; }
   json=CharArrayToString(response,0,WHOLE_ARRAY,CP_UTF8);
   return StringLen(json)>50;
}

int OpenSeraPositions()
{
   int total=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionGetInteger(POSITION_MAGIC)==MagicNumber) total++;
   }
   return total;
}

int OpenSeraPendingOrders()
{
   int total=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket>0 && OrderGetInteger(ORDER_MAGIC)==MagicNumber)
      {
         ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         if(type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_SELL_LIMIT) total++;
      }
   }
   return total;
}

ulong FindSeraPendingOrder(const string symbol)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket<=0 || OrderGetInteger(ORDER_MAGIC)!=MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL)!=symbol) continue;
      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_SELL_LIMIT) return ticket;
   }
   return 0;
}

void CancelSeraPendingOrder(const string symbol,const string reason)
{
   ulong ticket=FindSeraPendingOrder(symbol);
   if(ticket<=0) return;
   if(trade.OrderDelete(ticket)) Print("Sera EA Swing Intelligent: pending supprime ",symbol," - ",reason);
   else Print("Sera EA Swing Intelligent: echec suppression pending ",symbol," - ",trade.ResultRetcodeDescription());
}

void CancelAllSeraPendingOrders(const string reason)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket<=0 || OrderGetInteger(ORDER_MAGIC)!=MagicNumber) continue;
      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type!=ORDER_TYPE_BUY_LIMIT && type!=ORDER_TYPE_SELL_LIMIT) continue;
      if(!trade.OrderDelete(ticket))
         Print("Sera EA Swing Intelligent: echec suppression pending #",ticket," - ",trade.ResultRetcodeDescription());
   }
   Print("Sera EA Swing Intelligent: pending globaux controles - ",reason);
}

datetime StartOfDay()
{
   datetime now=TimeCurrent(); MqlDateTime part; TimeToStruct(now,part);
   part.hour=0; part.min=0; part.sec=0;
   return StructToTime(part);
}

int TradesToday()
{
   datetime now=TimeCurrent(); datetime start=StartOfDay();
   if(!HistorySelect(start,now)) return 0;
   int total=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket>0 && HistoryDealGetInteger(ticket,DEAL_MAGIC)==MagicNumber && HistoryDealGetInteger(ticket,DEAL_ENTRY)==DEAL_ENTRY_IN) total++;
   }
   return total;
}

double DailyNetProfit()
{
   datetime now=TimeCurrent(); if(!HistorySelect(StartOfDay(),now)) return 0.0;
   double pnl=0.0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket<=0 || HistoryDealGetInteger(ticket,DEAL_MAGIC)!=MagicNumber) continue;
      long entry=HistoryDealGetInteger(ticket,DEAL_ENTRY);
      if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY)
         pnl+=HistoryDealGetDouble(ticket,DEAL_PROFIT)+HistoryDealGetDouble(ticket,DEAL_SWAP)+HistoryDealGetDouble(ticket,DEAL_COMMISSION);
   }
   return pnl;
}

int ConsecutiveLosses()
{
   datetime now=TimeCurrent(); if(!HistorySelect(StartOfDay(),now)) return 0;
   int losses=0;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
   {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket<=0 || HistoryDealGetInteger(ticket,DEAL_MAGIC)!=MagicNumber) continue;
      long entry=HistoryDealGetInteger(ticket,DEAL_ENTRY);
      if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) continue;
      double pnl=HistoryDealGetDouble(ticket,DEAL_PROFIT)+HistoryDealGetDouble(ticket,DEAL_SWAP)+HistoryDealGetDouble(ticket,DEAL_COMMISSION);
      if(pnl<0) losses++;
      else break;
   }
   return losses;
}

bool RiskCircuitOpen()
{
   double daily=DailyNetProfit();
   if(daily<=-MaximumDailyLossUSD){ Print("Sera circuit breaker: perte journaliere ",daily); return true; }

   double balance=AccountInfoDouble(ACCOUNT_BALANCE),equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(balance>0)
   {
      double dd=MathMax(0.0,(balance-equity)/balance*100.0);
      if(dd>=MaximumDailyDrawdownPercent){ Print("Sera circuit breaker: drawdown ",dd,"%"); return true; }
   }

   if(ConsecutiveLosses()>=MaximumConsecutiveLosses){ Print("Sera circuit breaker: pertes consecutives"); return true; }

   double free=AccountInfoDouble(ACCOUNT_MARGIN_FREE),equityNow=AccountInfoDouble(ACCOUNT_EQUITY);
   double freePct=equityNow>0?free/equityNow*100.0:0.0;
   if(AccountInfoDouble(ACCOUNT_MARGIN)>0 && freePct<MinimumFreeMarginPercent){ Print("Sera circuit breaker: marge libre ",freePct,"%"); return true; }

   return false;
}

bool BrokerStopsValid(const string symbol,const string verdict,const double entry,const double sl,const double tp)
{
   if(!EnforceBrokerStopsLevel) return true;
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   double minDistance=(double)SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL)*point;
   if(minDistance<=0) return true;
   if(verdict=="BUY") return (entry-sl)>=minDistance && (tp-entry)>=minDistance;
   if(verdict=="SELL") return (sl-entry)>=minDistance && (entry-tp)>=minDistance;
   return false;
}


string UpperCopy(string value)
{
   StringToUpper(value);
   return value;
}

int AssetProfile(const string symbol)
{
   string s=UpperCopy(symbol);
   if(StringFind(s,"XAU")>=0 || StringFind(s,"GOLD")>=0) return 1; // Gold
   if(StringFind(s,"BTC")>=0 || StringFind(s,"ETH")>=0 || StringFind(s,"SOL")>=0 ||
      StringFind(s,"XRP")>=0 || StringFind(s,"LTC")>=0 || StringFind(s,"ADA")>=0 ||
      StringFind(s,"DOGE")>=0 || StringFind(s,"BNB")>=0 || StringFind(s,"AVAX")>=0) return 2; // Crypto
   if(StringFind(s,"BOOM")>=0 || StringFind(s,"CRASH")>=0 || StringFind(s,"VOLATILITY")>=0 ||
      StringFind(s,"STEP")>=0 || StringFind(s,"JUMP")>=0 || StringFind(s,"RANGE")>=0) return 3; // Synthetic
   return 4; // Forex / other CFD
}

string AssetProfileName(const string symbol)
{
   int p=AssetProfile(symbol);
   if(p==1) return "GOLD";
   if(p==2) return "CRYPTO";
   if(p==3) return "SYNTHETIC";
   return "FOREX/CFD";
}

double AssetRiskFactor(const string symbol)
{
   if(!EnableAssetAdaptiveProfiles) return 1.0;
   int p=AssetProfile(symbol);
   if(p==1) return GoldRiskFactor;
   if(p==2) return CryptoRiskFactor;
   if(p==3) return SyntheticRiskFactor;
   return ForexRiskFactor;
}

double AssetATRMultiplier(const string symbol)
{
   if(!EnableAssetAdaptiveProfiles) return 2.0;
   int p=AssetProfile(symbol);
   if(p==1) return GoldATRMultiplier;
   if(p==2) return CryptoATRMultiplier;
   if(p==3) return SyntheticATRMultiplier;
   return ForexATRMultiplier;
}

double IndicatorValue(const int handle,const int buffer,const int shift)
{
   if(handle==INVALID_HANDLE) return EMPTY_VALUE;
   double values[];
   ArraySetAsSeries(values,true);
   int copied=CopyBuffer(handle,buffer,shift,1,values);
   if(copied<1) return EMPTY_VALUE;
   return values[0];
}

double EMAValue(const string symbol,ENUM_TIMEFRAMES tf,const int period,const int shift=0)
{
   int h=iMA(symbol,tf,period,0,MODE_EMA,PRICE_CLOSE);
   if(h==INVALID_HANDLE) return EMPTY_VALUE;
   double v=IndicatorValue(h,0,shift);
   IndicatorRelease(h);
   return v;
}

double RSIValue(const string symbol,ENUM_TIMEFRAMES tf,const int period=14,const int shift=0)
{
   int h=iRSI(symbol,tf,period,PRICE_CLOSE);
   if(h==INVALID_HANDLE) return EMPTY_VALUE;
   double v=IndicatorValue(h,0,shift);
   IndicatorRelease(h);
   return v;
}

double ATRValue(const string symbol,ENUM_TIMEFRAMES tf,const int period=14,const int shift=0)
{
   int h=iATR(symbol,tf,period);
   if(h==INVALID_HANDLE) return EMPTY_VALUE;
   double v=IndicatorValue(h,0,shift);
   IndicatorRelease(h);
   return v;
}

double ADXValue(const string symbol,ENUM_TIMEFRAMES tf,const int period=14,const int shift=0)
{
   int h=iADX(symbol,tf,period);
   if(h==INVALID_HANDLE) return EMPTY_VALUE;
   double v=IndicatorValue(h,0,shift);
   IndicatorRelease(h);
   return v;
}

double MACDHistogram(const string symbol,ENUM_TIMEFRAMES tf,const int shift=0)
{
   int h=iMACD(symbol,tf,12,26,9,PRICE_CLOSE);
   if(h==INVALID_HANDLE) return EMPTY_VALUE;
   double main=IndicatorValue(h,0,shift);
   double signal=IndicatorValue(h,1,shift);
   IndicatorRelease(h);
   if(main==EMPTY_VALUE || signal==EMPTY_VALUE) return EMPTY_VALUE;
   return main-signal;
}

bool LocalSwingDecision(const string symbol,string &side,double &score,double &atr)
{
   side="WAIT"; score=0.0;
   double h1Fast=EMAValue(symbol,PERIOD_H1,20,1);
   double h1Slow=EMAValue(symbol,PERIOD_H1,50,1);
   double h4Fast=EMAValue(symbol,PERIOD_H4,20,1);
   double h4Slow=EMAValue(symbol,PERIOD_H4,50,1);
   double rsi=RSIValue(symbol,PERIOD_H1,14,1);
   double adx=ADXValue(symbol,PERIOD_H1,14,1);
   double macdH1=MACDHistogram(symbol,PERIOD_H1,1);
   double macdH4=MACDHistogram(symbol,PERIOD_H4,1);
   atr=ATRValue(symbol,PERIOD_H1,14,1);

   if(h1Fast==EMPTY_VALUE || h1Slow==EMPTY_VALUE || h4Fast==EMPTY_VALUE || h4Slow==EMPTY_VALUE ||
      rsi==EMPTY_VALUE || adx==EMPTY_VALUE || macdH1==EMPTY_VALUE || macdH4==EMPTY_VALUE ||
      atr==EMPTY_VALUE || atr<=0) return false;

   bool buyH1=h1Fast>h1Slow, sellH1=h1Fast<h1Slow;
   bool buyH4=h4Fast>h4Slow, sellH4=h4Fast<h4Slow;
   if(buyH1 && buyH4) side="BUY";
   else if(sellH1 && sellH4) side="SELL";
   else return true;

   score=45.0; // H1/H4 trend alignment
   if(side=="BUY" && rsi>=52.0 && rsi<=72.0) score+=15.0;
   if(side=="SELL" && rsi<=48.0 && rsi>=28.0) score+=15.0;
   if(side=="BUY" && macdH1>0) score+=12.0;
   if(side=="SELL" && macdH1<0) score+=12.0;
   if(side=="BUY" && macdH4>0) score+=13.0;
   if(side=="SELL" && macdH4<0) score+=13.0;
   if(adx>=LocalMinimumADX) score+=15.0;

   score=MathMin(100.0,score);
   if(score<LocalMinimumScore) side="WAIT";
   return true;
}

void ManageLocalATRProfit(const string symbol)
{
   if(!EnableATRProfitTrail || !PositionSelect(symbol)) return;
   if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber) return;

   long type=PositionGetInteger(POSITION_TYPE);
   double open=PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL=PositionGetDouble(POSITION_SL);
   double currentTP=PositionGetDouble(POSITION_TP);
   double initialRisk=StoredLevel("SERA_LOCALRISK_",symbol);
   if(initialRisk<=0) return;

   MqlTick tick;
   if(!SymbolInfoTick(symbol,tick)) return;
   double price=type==POSITION_TYPE_BUY?tick.bid:tick.ask;
   double profitDistance=type==POSITION_TYPE_BUY?price-open:open-price;
   double r=profitDistance/initialRisk;
   if(r<ProfitProtectionStartR) return;

   double atr=ATRValue(symbol,PERIOD_H1,14,0);
   if(atr==EMPTY_VALUE || atr<=0) return;

   double locked=initialRisk*ProfitLockR;
   double protective=type==POSITION_TYPE_BUY?open+locked:open-locked;
   double atrTrail=type==POSITION_TYPE_BUY?price-atr*ATRTrailMultiplier:price+atr*ATRTrailMultiplier;
   double desired=type==POSITION_TYPE_BUY?MathMax(protective,atrTrail):MathMin(protective,atrTrail);

   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   double stopDistance=(double)SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL)*point;
   bool valid=type==POSITION_TYPE_BUY?desired<tick.bid-stopDistance:desired>tick.ask+stopDistance;
   bool improves=type==POSITION_TYPE_BUY?(currentSL<=0 || desired>currentSL+point):(currentSL<=0 || desired<currentSL-point);
   if(!valid || !improves) return;

   int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   desired=NormalizeDouble(desired,digits);
   if(trade.PositionModify(symbol,desired,currentTP))
      Print("Sera ATR Profit Guard: ",symbol," R=",DoubleToString(r,2)," SL=",DoubleToString(desired,digits));
}

void RunLocalSwingIntelligence()
{
   if(!EnableLocalSwingIntelligence) return;
   string symbol=_Symbol;
   ManageLocalATRProfit(symbol);

   datetime bar=iTime(symbol,PERIOD_H1,0);
   if(bar<=0 || bar==local_last_h1_bar) return;
   local_last_h1_bar=bar;

   string side; double score=0.0,atr=0.0;
   if(!LocalSwingDecision(symbol,side,score,atr)) return;

   Comment("Sera EA Swing Intelligent v1.80 | ",AssetProfileName(symbol),
           " | Local Swing H1/H4: ",side," ",DoubleToString(score,0),"%",
           " | Risk ",DoubleToString(AdaptiveRiskPercent()*AssetRiskFactor(symbol),2),"%");

   if(!EnableLocalAutoEntry || side=="WAIT") return;
   if(!EnableAutomaticTrading || RiskCircuitOpen()) return;
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE)!=ACCOUNT_TRADE_MODE_DEMO && !AllowRealAccount) return;
   if(OpenSeraPositions()>=MaximumOpenPositions || TradesToday()>=MaximumTradesPerDay) return;
   if(PositionSelect(symbol)) return;

   MqlTick tick;
   if(!SymbolInfoTick(symbol,tick)) return;
   double entry=side=="BUY"?tick.ask:tick.bid;
   double riskDistance=atr*AssetATRMultiplier(symbol);
   if(riskDistance<=0) return;

   double sl=side=="BUY"?entry-riskDistance:entry+riskDistance;
   double tp1=side=="BUY"?entry+riskDistance*1.5:entry-riskDistance*1.5;
   double tp2=side=="BUY"?entry+riskDistance*2.4:entry-riskDistance*2.4;
   double tp3=side=="BUY"?entry+riskDistance*3.6:entry-riskDistance*3.6;
   int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   sl=NormalizeDouble(sl,digits); tp1=NormalizeDouble(tp1,digits);
   tp2=NormalizeDouble(tp2,digits); tp3=NormalizeDouble(tp3,digits);

   if(!BrokerStopsValid(symbol,side,entry,sl,tp3)) return;
   double volume=SafeVolume(symbol,entry,sl);
   if(volume<=0) return;

   double requiredMargin=0.0;
   bool marginOk=OrderCalcMargin(side=="BUY"?ORDER_TYPE_BUY:ORDER_TYPE_SELL,symbol,volume,entry,requiredMargin)
      && requiredMargin<=AccountInfoDouble(ACCOUNT_MARGIN_FREE)*0.50;
   if(!marginOk) return;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(DeviationPoints);
   bool sent=side=="BUY"
      ?trade.Buy(volume,symbol,0,sl,tp3,"Sera Local Swing v1.80")
      :trade.Sell(volume,symbol,0,sl,tp3,"Sera Local Swing v1.80");
   if(sent)
   {
      StoreLevel("SERA_LOCALRISK_",symbol,riskDistance);
      StoreLevel("SERA_TP1_","LOCAL_"+symbol,tp1);
      StoreLevel("SERA_TP2_","LOCAL_"+symbol,tp2);
      StoreLevel("SERA_TP3_","LOCAL_"+symbol,tp3);
      StoreLevel("SERA_FINALTP_","LOCAL_"+symbol,tp3);
      Print("Sera Local Swing: ",AssetProfileName(symbol)," ",side," ",symbol,
            " score=",DoubleToString(score,0)," volume=",DoubleToString(volume,2),
            " SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp3,digits));
   }
}

double AdaptiveRiskPercent()
{
   double risk=RiskPercent;
   if(!EnableAdaptiveLot) return MathMin(risk,MaximumAdaptiveRiskPercent);

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   string key="SERA_EQUITY_BASELINE";
   if(!GlobalVariableCheck(key) || GlobalVariableGet(key)<=0)
      GlobalVariableSet(key,equity);

   double baseline=GlobalVariableGet(key);
   if(equity>baseline && baseline>0 && EquityGrowthStepPercent>0)
   {
      double growthPct=(equity-baseline)/baseline*100.0;
      int steps=(int)MathFloor(growthPct/EquityGrowthStepPercent);
      if(steps>0) risk+=steps*RiskIncreasePerEquityStep;
   }

   double daily=DailyNetProfit();
   if(daily>=DailyProfitBoostThresholdUSD) risk+=DailyProfitRiskBoost;

   if(ConsecutiveLosses()>=1) risk=MathMin(risk,RiskPercent*0.75);

   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance>0)
   {
      double dd=MathMax(0.0,(balance-equity)/balance*100.0);
      if(dd>=1.0) risk=MathMin(risk,RiskPercent*0.65);
      if(dd>=2.0) risk=MathMin(risk,RiskPercent*0.50);
   }

   return MathMax(0.10,MathMin(risk,MaximumAdaptiveRiskPercent));
}

double AdaptiveLossCap()
{
   if(!EnableAdaptiveLot) return MaximumLossUSD;
   double risk=AdaptiveRiskPercent();
   double ratio=RiskPercent>0?risk/RiskPercent:1.0;
   return MathMin(MaximumAdaptiveLossUSD,MaximumLossUSD*MathMax(1.0,ratio));
}

double SafeVolume(const string symbol,const double entry,const double sl)
{
   double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   double tick_value=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
   double min_lot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double max_lot=MathMin(SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX),MaximumLot);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(tick_size<=0 || tick_value<=0 || step<=0 || MathAbs(entry-sl)<=0) return 0;
   double adaptiveRisk=AdaptiveRiskPercent()*AssetRiskFactor(symbol);
   double lossCap=AdaptiveLossCap()*AssetRiskFactor(symbol);
   double risk=MathMin(AccountInfoDouble(ACCOUNT_EQUITY)*adaptiveRisk/100.0,lossCap);
   double loss_per_lot=(MathAbs(entry-sl)/tick_size)*tick_value;
   double volume=MathFloor((risk/loss_per_lot)/step)*step;
   if(volume<min_lot) return 0;
   return MathMax(min_lot,MathMin(volume,max_lot));
}

uint SeraHash(const string id)
{
   uint hash=2166136261;
   for(int i=0;i<StringLen(id);i++){ hash^=(uint)StringGetCharacter(id,i); hash*=16777619; }
   return hash;
}

string StateKey(const string prefix,const string id)
{
   return prefix+IntegerToString((int)SeraHash(id));
}

int StoredState(const string prefix,const string id)
{
   string key=StateKey(prefix,id);
   if(!GlobalVariableCheck(key)) return 0;
   return (int)GlobalVariableGet(key);
}

void StoreState(const string prefix,const string id,const int state)
{
   GlobalVariableSet(StateKey(prefix,id),(double)state);
}

double StoredLevel(const string prefix,const string id)
{
   string key=StateKey(prefix,id);
   if(!GlobalVariableCheck(key)) return 0.0;
   return GlobalVariableGet(key);
}

void StoreLevel(const string prefix,const string id,const double value)
{
   GlobalVariableSet(StateKey(prefix,id),value);
}

bool SelectSeraPosition(const string symbol)
{
   if(!PositionSelect(symbol)) return false;
   return PositionGetInteger(POSITION_MAGIC)==MagicNumber;
}

bool ReachedLevel(const long position_type,const double price,const double level)
{
   if(level<=0) return false;
   if(position_type==POSITION_TYPE_BUY) return price>=level;
   if(position_type==POSITION_TYPE_SELL) return price<=level;
   return false;
}

void ManageSeraPosition(const string setup_id,const string symbol)
{
   if(!EnableSmartPositionManagement || symbol=="" || !SelectSeraPosition(symbol)) return;

   double tp1=StoredLevel("SERA_TP1_",setup_id);
   double tp2=StoredLevel("SERA_TP2_",setup_id);
   double tp3=StoredLevel("SERA_TP3_",setup_id);
   double tp4=StoredLevel("SERA_TP4_",setup_id);
   double final_tp=StoredLevel("SERA_FINALTP_",setup_id);
   if(tp1<=0 || final_tp<=0) return;

   long position_type=PositionGetInteger(POSITION_TYPE);
   double open_price=PositionGetDouble(POSITION_PRICE_OPEN);
   double current_sl=PositionGetDouble(POSITION_SL);
   double current_tp=PositionGetDouble(POSITION_TP);

   MqlTick tick;
   if(!SymbolInfoTick(symbol,tick)) return;
   double price=position_type==POSITION_TYPE_BUY?tick.bid:tick.ask;

   double desired_sl=0.0;
   int stage=0;
   if(ReachedLevel(position_type,price,tp1)){ desired_sl=open_price; stage=1; }
   if(ReachedLevel(position_type,price,tp2)){ desired_sl=tp1; stage=2; }
   if(ReachedLevel(position_type,price,tp3)){ desired_sl=tp2; stage=3; }
   if(ReachedLevel(position_type,price,tp4)){ desired_sl=tp3; stage=4; }
   if(desired_sl<=0) return;

   int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   double stop_distance=(double)SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL)*point;
   desired_sl=NormalizeDouble(desired_sl,digits);
   final_tp=NormalizeDouble(final_tp,digits);

   bool valid_stop=position_type==POSITION_TYPE_BUY
      ? desired_sl < tick.bid-stop_distance
      : desired_sl > tick.ask+stop_distance;
   bool improves=position_type==POSITION_TYPE_BUY
      ? (current_sl<=0 || desired_sl>current_sl+point)
      : (current_sl<=0 || desired_sl<current_sl-point);

   if(valid_stop && improves)
   {
      double target=current_tp>0?current_tp:final_tp;
      if(trade.PositionModify(symbol,desired_sl,target))
         Print("Sera Smart Manage: ",symbol," stage TP",stage," -> SL ",DoubleToString(desired_sl,digits)," final TP ",DoubleToString(target,digits));
      else
         Print("Sera Smart Manage: modification refusee ",trade.ResultRetcodeDescription());
   }
}

int VerdictState(const string verdict)
{
   if(verdict=="BUY") return 1;
   if(verdict=="SELL") return -1;
   return 0;
}

void SendTrendAlert(const string market,const string verdict,const double confidence,const string execution_state)
{
   if(!EnableTrendWatch) return;
   string message="Sera Trend Watch: "+market+" "+verdict+" Swing H1/H4 "+execution_state+" a "+DoubleToString(confidence,0)+"%";
   if(EnableTerminalAlert) Alert(message);
   if(EnablePushNotification)
   {
      ResetLastError();
      if(!SendNotification(message)) Print("Sera: notification push non envoyee, erreur=",GetLastError());
   }
   Print(message);
}

bool PlaceOrUpdatePendingLimit(const string setup_id,const string symbol,const string verdict,const double entry,const double sl,const double tp,const double volume)
{
   if(!EnableSmartPendingLimits || volume<=0 || entry<=0 || sl<=0 || tp<=0) return false;

   MqlTick tick;
   if(!SymbolInfoTick(symbol,tick)) return false;
   int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   entry=NormalizeDouble(entry,digits);
   sl=NormalizeDouble(sl,digits);
   tp=NormalizeDouble(tp,digits);

   bool valid=verdict=="BUY" ? (entry<tick.ask && sl<entry && tp>entry) : (entry>tick.bid && sl>entry && tp<entry);
   if(!valid) return false;

   ulong existing=FindSeraPendingOrder(symbol);
   if(existing>0)
   {
      double oldPrice=OrderGetDouble(ORDER_PRICE_OPEN);
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      if(MathAbs(oldPrice-entry)<=point*2) return true;
      CancelSeraPendingOrder(symbol,"mise a jour zone entree");
   }

   datetime expiration=TimeCurrent()+PendingExpirationHours*3600;
   trade.SetExpertMagicNumber(MagicNumber);
   bool sent=verdict=="BUY"
      ? trade.BuyLimit(volume,entry,symbol,sl,tp,ORDER_TIME_SPECIFIED,expiration,"Sera Intelligent Swing BUY LIMIT")
      : trade.SellLimit(volume,entry,symbol,sl,tp,ORDER_TIME_SPECIFIED,expiration,"Sera Intelligent Swing SELL LIMIT");

   if(sent)
   {
      StoreState("SERA_PENDINGSTATE_",setup_id,VerdictState(verdict));
      StoreLevel("SERA_ENTRY_",setup_id,entry);
      Print("Sera EA Swing Intelligent: ",verdict," LIMIT ",symbol," @ ",DoubleToString(entry,digits)," volume=",volume);
      return true;
   }
   Print("Sera EA Swing Intelligent: pending refuse ",trade.ResultRetcodeDescription());
   return false;
}

void Evaluate(const string json)
{
   string status=JsonString(json,"status");
   if(status!="ai_analyzed" && status!="autonomous_analyzed" && status!="smart_local"){ Comment("Sera: aucun signal final autonome confirme"); return; }
   datetime generated=ParseIsoUtc(JsonString(json,"updated_at"));
   if(generated==0 || TimeGMT()-generated>MaximumSignalAgeMinutes*60){ Comment("Sera Trend Watch: signal global expire"); return; }

   bool source_allows_trade=(status=="ai_analyzed")||(status=="autonomous_analyzed"&&AllowAutonomousExecution)||(status=="smart_local"&&AllowAutonomousExecution);
   bool circuit_open=RiskCircuitOpen();
   if(circuit_open) CancelAllSeraPendingOrders("circuit risque actif");
   bool can_trade=EnableAutomaticTrading&&source_allows_trade&&!circuit_open;
   if(can_trade && AccountInfoInteger(ACCOUNT_TRADE_MODE)!=ACCOUNT_TRADE_MODE_DEMO && !AllowRealAccount)
   {
      can_trade=false;
      Comment("Sera Trend Watch actif — trading reel bloque (AllowRealAccount=false)");
   }
   else if((status=="autonomous_analyzed"||status=="smart_local") && !AllowAutonomousExecution) Comment("Sera autonome actif — alertes seulement; execution autonome bloquee");
   else if(EnableTrendWatch && !EnableAutomaticTrading) Comment("Sera Trend Watch actif — alertes seulement");
   else if(EnableTrendWatch && EnableAutomaticTrading)
   {
      string account_mode=AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO?"DEMO":"REEL";
      Comment("Sera Trend Watch + Auto-trade actifs — "+account_mode+" — risque "+DoubleToString(RiskPercent,2)+"% / max "+DoubleToString(MaximumLossUSD,2)+" USD");
   }

   int markets=StringFind(json,"\"markets\""); if(markets<0) return;
   int cursor=StringFind(json,"{",markets);
   while(cursor>=0)
   {
      string object=ExtractObjectAt(json,cursor); if(object=="") break;
      string mode=JsonString(object,"mode"),verdict=JsonString(object,"final_verdict");
      double confidence=JsonNumber(object,"final_confidence");
      double conditions_percent=JsonNumber(object,"condition_pass_percent");
      string execution_state=JsonString(object,"execution_state");
      double execution_score=JsonNumber(object,"execution_score");
      string setup_direction=JsonString(object,"setup_direction");
      double setup_detected=JsonNumber(object,"setup_detected");
      string model_direction=JsonString(object,"model_ensemble_direction");
      double model_consensus=JsonNumber(object,"model_ensemble_consensus");
      double models_available=JsonNumber(object,"model_models_available");
      if(mode=="swing")
      {
         string setup_id=JsonString(object,"id");
         string market_name=JsonString(object,"market");
         string deriv_code=JsonString(object,"symbol");
         string symbol=ResolveTradeSymbol(market_name,deriv_code);
         if(symbol!="") ManageSeraPosition(setup_id,symbol);
         int state=VerdictState(verdict);
         bool directional_confirmed=(state!=0 && confidence>=MinimumConfidence && conditions_percent>=MinimumAutonomousConditionsPercent);
         bool model_guard_ok=true;
         string opposite=verdict=="BUY"?"SELL":"BUY";
         if(UseOpenSourceModelGuard && models_available>=2 && model_direction==opposite && model_consensus>=MinimumModelConsensus)
         {
            model_guard_ok=false;
            Print("Sera: execution bloquee par ensemble open-source ",model_direction," ",DoubleToString(model_consensus,0),"% contre ",verdict);
         }
         bool execution_ready=((!RequireExecuteNow)||(execution_state=="EXECUTE_NOW"&&execution_score>=MinimumExecutionScore)) && model_guard_ok;
         int alert_state=state*10+(execution_ready?1:0);

         int previous_alert_state=StoredState("SERA_ALERTSTATE_",setup_id);
         if(directional_confirmed && alert_state!=previous_alert_state) SendTrendAlert(market_name,verdict,confidence,execution_state);
         if(alert_state!=previous_alert_state) StoreState("SERA_ALERTSTATE_",setup_id,alert_state);

         int previous_trade_state=StoredState("SERA_TRADESTATE_",setup_id);
         if(state==0 && previous_trade_state!=0) StoreState("SERA_TRADESTATE_",setup_id,0);

         // Pending LIMIT management: only a confirmed BUY/SELL may create a retracement order.
         if(symbol!="" && EnableSmartPendingLimits)
         {
            bool pending_candidate=directional_confirmed
               && execution_state=="WAIT_RETRACE"
               && execution_score>=MinimumPendingExecutionScore
               && conditions_percent>=MinimumPendingConditionsPercent
               && can_trade
               && OpenSeraPositions()<MaximumOpenPositions
               && (FindSeraPendingOrder(symbol)>0 || OpenSeraPendingOrders()<MaximumPendingOrders);

            if(pending_candidate)
            {
               int levels_pos_pending=StringFind(object,"\"levels\"");
               string levels_pending=levels_pos_pending>=0?ExtractObjectAt(object,StringFind(object,"{",levels_pos_pending)):"";
               int plan_pos=StringFind(object,"\"setup_entry_plan\"");
               string plan=plan_pos>=0?ExtractObjectAt(object,StringFind(object,"{",plan_pos)):"";
               double pending_entry=JsonNumber(plan,"suggested_entry");
               if(pending_entry<=0) pending_entry=JsonNumber(levels_pending,"entry");
               double pending_sl=JsonNumber(levels_pending,"sl");
               double pending_tp3=JsonNumber(levels_pending,"tp3");
               double pending_tp4=JsonNumber(levels_pending,"tp4");
               double pending_tp5=JsonNumber(levels_pending,"tp5");

               double pending_final_tp=pending_tp3;
               bool strong_pending_model=(models_available>=2 && model_direction==verdict && model_consensus>=75);
               if(DynamicFinalTarget && confidence>=90 && execution_score>=90 && strong_pending_model && pending_tp5>0) pending_final_tp=pending_tp5;
               else if(DynamicFinalTarget && confidence>=85 && execution_score>=85 && pending_tp4>0) pending_final_tp=pending_tp4;

               bool pending_stops_ok=BrokerStopsValid(symbol,verdict,pending_entry,pending_sl,pending_final_tp);
               double pending_volume=pending_stops_ok?SafeVolume(symbol,pending_entry,pending_sl):0;
               double pending_margin=0.0;
               bool pending_margin_ok=pending_volume>0 && OrderCalcMargin(verdict=="BUY"?ORDER_TYPE_BUY:ORDER_TYPE_SELL,symbol,pending_volume,pending_entry,pending_margin)
                  && pending_margin<=AccountInfoDouble(ACCOUNT_MARGIN_FREE)*0.50;

               if(pending_margin_ok)
                  PlaceOrUpdatePendingLimit(setup_id,symbol,verdict,pending_entry,pending_sl,pending_final_tp,pending_volume);
            }
            else
            {
               ulong existing_pending=FindSeraPendingOrder(symbol);
               if(existing_pending>0)
               {
                  bool invalidated=(state==0)||(execution_state=="BLOCKED_RISK")||(setup_detected<=0)||(setup_direction!="" && setup_direction!=verdict);
                  bool now_market=directional_confirmed&&execution_state=="EXECUTE_NOW";
                  if(invalidated || now_market) CancelSeraPendingOrder(symbol,invalidated?"setup invalide":"passage EXECUTE_NOW");
               }
            }
         }

         if(directional_confirmed && execution_ready && can_trade && state!=previous_trade_state && OpenSeraPositions()<MaximumOpenPositions && TradesToday()<MaximumTradesPerDay)
         {
            if(symbol=="")
            {
               Print("Sera: symbole MT5 introuvable pour ",market_name," / ",deriv_code," — ordre ignore");
            }
            else
            {
               int levels_pos=StringFind(object,"\"levels\"");
               string levels=levels_pos>=0?ExtractObjectAt(object,StringFind(object,"{",levels_pos)):"";
               double signal_entry=JsonNumber(levels,"entry");
               double sl=JsonNumber(levels,"sl");
               double tp1=JsonNumber(levels,"tp1"),tp2=JsonNumber(levels,"tp2"),tp3=JsonNumber(levels,"tp3");
               double tp4=JsonNumber(levels,"tp4"),tp5=JsonNumber(levels,"tp5");
               MqlTick tick;
               if(sl>0 && tp3>0 && SymbolInfoTick(symbol,tick))
               {
                  double price=verdict=="BUY"?tick.ask:tick.bid;
                  double risk_distance=MathAbs(signal_entry-sl);
                  double spread=MathAbs(tick.ask-tick.bid);
                  bool levels_valid=verdict=="BUY"?(sl<price && tp3>price):(sl>price && tp3<price);
                  bool spread_ok=risk_distance>0 && spread<=risk_distance*(MaximumSpreadRiskPercent/100.0);
                  bool chase_ok=risk_distance>0 && (verdict=="BUY"
                     ? price<=signal_entry+risk_distance*(MaximumEntryChaseRiskPercent/100.0)
                     : price>=signal_entry-risk_distance*(MaximumEntryChaseRiskPercent/100.0));

                  double final_tp=tp3;
                  bool strong_model=(models_available>=2 && model_direction==verdict && model_consensus>=75);
                  if(DynamicFinalTarget && confidence>=90 && execution_score>=90 && strong_model && tp5>0) final_tp=tp5;
                  else if(DynamicFinalTarget && confidence>=85 && execution_score>=85 && tp4>0) final_tp=tp4;

                  bool final_valid=verdict=="BUY"?final_tp>price:final_tp<price;
                  bool broker_stops_ok=BrokerStopsValid(symbol,verdict,price,sl,final_tp);
                  double trial_volume=(levels_valid&&spread_ok&&chase_ok&&final_valid&&broker_stops_ok)?SafeVolume(symbol,price,sl):0;
                  double required_margin=0.0;
                  bool margin_ok=trial_volume>0 && OrderCalcMargin(verdict=="BUY"?ORDER_TYPE_BUY:ORDER_TYPE_SELL,symbol,trial_volume,price,required_margin)
                     && required_margin<=AccountInfoDouble(ACCOUNT_MARGIN_FREE)*0.50;
                  double volume=margin_ok?trial_volume:0;
                  if(!spread_ok) Print("Sera: entree ignoree, spread trop grand par rapport au risque.");
                  if(!chase_ok) Print("Sera: entree ignoree, prix trop eloigne de l'entree calculee.");
                  if(!broker_stops_ok) Print("Sera: entree ignoree, SL/TP trop proches pour les regles du broker.");
                  if(trial_volume>0 && !margin_ok) Print("Sera: entree ignoree, marge libre insuffisante.");
                  if(volume>0)
                  {
                     CancelSeraPendingOrder(symbol,"ordre marche EXECUTE_NOW");
                     trade.SetExpertMagicNumber(MagicNumber);
                     trade.SetDeviationInPoints(DeviationPoints);
                     bool sent=verdict=="BUY"?trade.Buy(volume,symbol,0,sl,final_tp,"Sera EA Swing Intelligent v1.80"):trade.Sell(volume,symbol,0,sl,final_tp,"Sera EA Swing Intelligent v1.80");
                     if(sent)
                     {
                        StoreState("SERA_TRADESTATE_",setup_id,state);
                        StoreLevel("SERA_ENTRY_",setup_id,signal_entry);
                        StoreLevel("SERA_TP1_",setup_id,tp1);
                        StoreLevel("SERA_TP2_",setup_id,tp2);
                        StoreLevel("SERA_TP3_",setup_id,tp3);
                        StoreLevel("SERA_TP4_",setup_id,tp4);
                        StoreLevel("SERA_TP5_",setup_id,tp5);
                        StoreLevel("SERA_FINALTP_",setup_id,final_tp);
                        Print("Sera: ",verdict," ",symbol," volume=",volume," SL=",sl," final TP=",final_tp," management TP1-TP5 actif");
                        return;
                     }
                     Print("Sera: ordre refuse: ",trade.ResultRetcodeDescription());
                  }
                  else Print("Sera: volume nul ou entree bloquee par les gardes spread/chase/niveaux pour ",symbol);
               }
               else Print("Sera: SL/TP ou tick invalide pour ",symbol);
            }
         }
      }
      cursor=StringFind(json,"{",cursor+StringLen(object));
   }
}

int OnInit()
{
   trade.SetAsyncMode(false);
   EventSetTimer(MathMax(15,PollEverySeconds));
   long trade_mode=AccountInfoInteger(ACCOUNT_TRADE_MODE);
   string mode=trade_mode==ACCOUNT_TRADE_MODE_REAL?"REEL":trade_mode==ACCOUNT_TRADE_MODE_DEMO?"DEMO":"CONTEST";
   Comment("Sera EA Swing Intelligent v1.80 — "+mode+" — "+AssetProfileName(_Symbol)+" — H1/H4 Adaptive Swing");
   Print("Sera EA Swing Intelligent v1.80: compte ",mode,", actif=",AssetProfileName(_Symbol),
         ", auto serveur=",EnableAutomaticTrading,", auto local=",EnableLocalAutoEntry,
         ", reel=",AllowRealAccount,", risk=",DoubleToString(RiskPercent,2),
         "%, asset factor=",DoubleToString(AssetRiskFactor(_Symbol),2),
         ", OSS guard=",UseOpenSourceModelGuard,", smart management=",EnableSmartPositionManagement);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){ EventKillTimer(); Comment(""); }
void OnTimer()
{
   RunLocalSwingIntelligence();
   string json;
   if(FetchSignals(json)) Evaluate(json);
}
