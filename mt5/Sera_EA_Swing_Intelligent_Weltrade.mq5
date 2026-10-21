#property copyright "Sera EA Swing Intelligent Weltrade"
#property version   "1.00"
#property strict
#property description "Swing haute conviction H1/H4/D1 sur les indices synthetiques Weltrade (SyntX), analyse directement dans MT5."

#include <Trade/Trade.mqh>

// --- Indices Weltrade
input string SymbolsList="";                 // vide = detection automatique ; sinon "GainX 800,PainX 800,SFX Vol 40"
input bool TradePainGainX=true;              // PainX (monte, chutes) / GainX (baisse, sauts) / MAX PainX-GainX
input bool TradeVolIndices=true;             // FX Vol / SFX Vol
input bool TradeRegimeSwitchX=true;          // SwitchX / BreakX / TrendX
input bool TradeFlipX=false;                 // FlipX : marche sans tendance (50 % de changement par pas)
input bool TradeProgressionX=false;          // PlusX / FiboX / QuadX : progressions mathematiques
input int MaximumScannedSymbols=60;
input int AnalysisBars=1000;                 // bougies cloturees analysees par unite de temps (1000 = EMA200 exacte)
input int DashboardRows=10;

// --- Execution
input bool EnableAutomaticTrading=true;
input bool AllowRealAccount=true;
input bool EnableTrendWatch=true;            // alerte a chaque nouveau signal confirme
input bool EnableTerminalAlert=false;
input bool EnablePushNotification=false;     // notifications sur l'appli MT5 du telephone (MetaQuotes ID)
input bool DynamicFinalTarget=true;          // TP4 au lieu de TP3 si score >= 88
input bool EnableSmartPendingLimits=true;    // ordre limite sur l'EMA20 H1 si le prix est trop etendu
input int PendingExpirationHours=8;
input int MaximumEntryChaseRiskPercent=35;
input int MaximumSpreadRiskPercent=12;
input int PollEverySeconds=30;
input long MagicNumber=26102101;
input int DeviationPoints=50;

// --- Risque par trade (identique a Sera EA)
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
input bool EnableAssetAdaptiveProfiles=true;
input double SyntheticRiskFactor=1.00;

// --- Nombre de positions : les signaux decident, sous un budget de risque total
input bool EnableBalanceScaling=true;
input int MaximumOpenPositions=1;
input int MaximumPendingOrders=1;
input int MaximumTradesPerDay=2;
input int MaximumOpenPositionsCap=50;
input double BalancePerPositionUSD=0.0;
input double MaximumTotalOpenRiskPercent=10.0;
input bool OnePositionPerSymbol=true;

// --- Protection du compte
input double MaximumDailyLossUSD=3.00;
input double DailyLossPercentLimit=5.0;
input double MaximumDailyDrawdownPercent=3.00;
input int MaximumConsecutiveLosses=2;
input double MinimumFreeMarginPercent=25.0;
input bool EnforceBrokerStopsLevel=true;
input double EmergencyEquityStopPercent=15.0;

// --- Gestion des positions
input bool EnableSmartPositionManagement=true;
input double PartialCloseAtTP1Percent=50.0;
input bool CutOnMarketReversal=true;
input int ReversalStructureBars=24;
input int MaximumSwingHoldingHours=240;
input int MaximumDayHoldingHours=48;

CTrade trade;
string last_broker_message="";

double AssetRiskFactor(const string symbol)
{
   return EnableAssetAdaptiveProfiles?SyntheticRiskFactor:1.0;
}

// ===================================================================================
//  MODULES PARTAGES — repris a l'identique de Sera EA Swing Intelligent v2.20
//  (risque, ordres, gestion TP1-TP5, sortie partielle, coupure, arret d'urgence)
// ===================================================================================

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
   if(trade.OrderDelete(ticket)) Print("Sera SyntX: pending supprime ",symbol," - ",reason);
   else Print("Sera SyntX: echec suppression pending ",symbol," - ",trade.ResultRetcodeDescription());
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
         Print("Sera SyntX: echec suppression pending #",ticket," - ",trade.ResultRetcodeDescription());
   }
   Print("Sera SyntX: pending globaux controles - ",reason);
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
   double daily_limit=MaximumDailyLossUSD;
   if(EnableBalanceScaling) daily_limit=MathMax(MaximumDailyLossUSD,AccountInfoDouble(ACCOUNT_BALANCE)*DailyLossPercentLimit/100.0);
   if(daily<=-daily_limit){ Print("Sera circuit breaker: perte journaliere ",daily," / limite ",daily_limit); return true; }

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

double AdaptiveRiskPercent()
{
   double risk=RiskPercent;
   if(!EnableAdaptiveLot) return MathMin(risk,MaximumAdaptiveRiskPercent);

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   string key="SWX_EQUITY_BASELINE";
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

double PositionRiskUSD(const string symbol,const long type,const double open,const double sl,const double volume)
{
   if(sl<=0 || volume<=0) return 0.0;
   double distance=type==POSITION_TYPE_BUY?open-sl:sl-open;
   if(distance<=0) return 0.0;
   double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   double tick_value=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tick_size<=0 || tick_value<=0) return 0.0;
   return distance/tick_size*tick_value*volume;
}

double OpenSeraRiskUSD()
{
   double total=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket<=0 || PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      total+=PositionRiskUSD(PositionGetString(POSITION_SYMBOL),PositionGetInteger(POSITION_TYPE),
                             PositionGetDouble(POSITION_PRICE_OPEN),PositionGetDouble(POSITION_SL),PositionGetDouble(POSITION_VOLUME));
   }
   return total;
}

bool HasSeraPositionOn(const string symbol)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionGetInteger(POSITION_MAGIC)==MagicNumber && PositionGetString(POSITION_SYMBOL)==symbol) return true;
   }
   return false;
}

int AllowedOpenPositions()
{
   if(!EnableBalanceScaling) return MaximumOpenPositions;
   int slots=MaximumOpenPositionsCap;
   if(BalancePerPositionUSD>0)
      slots=(int)MathMin(slots,MathFloor(AccountInfoDouble(ACCOUNT_BALANCE)/BalancePerPositionUSD));
   slots=(int)MathMax(MaximumOpenPositions,slots);
   return (int)MathMax(1,MathMin(MaximumOpenPositionsCap,slots));
}

int AllowedTradesPerDay()
{
   if(!EnableBalanceScaling) return MaximumTradesPerDay;
   return (int)MathMax(MaximumTradesPerDay,MathMin(MaximumOpenPositionsCap*2,AllowedOpenPositions()*2));
}

int AllowedPendingOrders()
{
   if(!EnableBalanceScaling) return MaximumPendingOrders;
   return (int)MathMax(MaximumPendingOrders,AllowedOpenPositions());
}

bool TotalRiskAllows(const double new_risk_usd)
{
   if(!EnableBalanceScaling) return true;
   double budget=AccountInfoDouble(ACCOUNT_EQUITY)*MaximumTotalOpenRiskPercent/100.0;
   return OpenSeraRiskUSD()+new_risk_usd<=budget;
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

   double tp1=StoredLevel("SWX_TP1_",setup_id);
   double tp2=StoredLevel("SWX_TP2_",setup_id);
   double tp3=StoredLevel("SWX_TP3_",setup_id);
   double tp4=StoredLevel("SWX_TP4_",setup_id);
   double final_tp=StoredLevel("SWX_FINALTP_",setup_id);
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

bool PlaceOrUpdatePendingLimit(const string setup_id,const string symbol,const string verdict,const double entry,const double sl,const double tp,const double volume)
{
   if(!EnableSmartPendingLimits || volume<=0 || entry<=0 || sl<=0 || tp<=0) return false;

   MqlTick tick;
   if(!SymbolInfoTick(symbol,tick)) return false;
   int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   double normalized_entry=NormalizeDouble(entry,digits);
   double normalized_sl=NormalizeDouble(sl,digits);
   double normalized_tp=NormalizeDouble(tp,digits);

   bool valid=verdict=="BUY" ? (normalized_entry<tick.ask && normalized_sl<normalized_entry && normalized_tp>normalized_entry) : (normalized_entry>tick.bid && normalized_sl>normalized_entry && normalized_tp<normalized_entry);
   if(!valid) return false;

   ulong existing=FindSeraPendingOrder(symbol);
   if(existing>0)
   {
      double oldPrice=OrderGetDouble(ORDER_PRICE_OPEN);
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      if(MathAbs(oldPrice-normalized_entry)<=point*2) return true;
      CancelSeraPendingOrder(symbol,"mise a jour zone entree");
   }

   datetime expiration=TimeCurrent()+PendingExpirationHours*3600;
   trade.SetExpertMagicNumber(MagicNumber);
   bool sent=verdict=="BUY"
      ? trade.BuyLimit(volume,normalized_entry,symbol,normalized_sl,normalized_tp,ORDER_TIME_SPECIFIED,expiration,"Sera SyntX BUY LIMIT")
      : trade.SellLimit(volume,normalized_entry,symbol,normalized_sl,normalized_tp,ORDER_TIME_SPECIFIED,expiration,"Sera SyntX SELL LIMIT");

   if(sent)
   {
      StoreState("SWX_PENDINGSTATE_",setup_id,VerdictState(verdict));
      StoreLevel("SWX_ENTRY_",setup_id,normalized_entry);
      Print("Sera SyntX: ",verdict," LIMIT ",symbol," @ ",DoubleToString(normalized_entry,digits)," volume=",volume);
      return true;
   }
   Print("Sera SyntX: pending refuse ",trade.ResultRetcodeDescription());
   return false;
}

double BrokerCloseEMA(const string symbol,const ENUM_TIMEFRAMES tf,const int period)
{
   double closes[];
   ArraySetAsSeries(closes,false);
   int count=CopyClose(symbol,tf,1,period*4,closes);
   if(count<period*2) return EMPTY_VALUE;
   double k=2.0/(period+1.0);
   double ema=closes[0];
   for(int i=1;i<count;i++) ema=ema+k*(closes[i]-ema);
   return ema;
}

void PrintOnce(const string message)
{
   if(message==last_broker_message) return;
   last_broker_message=message;
   Print(message);
}

void StoreTradeLevels(const string setup_id,const string symbol,const double entry,const double tp1,const double tp2,
                      const double tp3,const double tp4,const double tp5,const double final_tp,const string mode)
{
   string keys[2];
   keys[0]=setup_id; keys[1]="SYM:"+symbol;
   for(int k=0;k<2;k++)
   {
      StoreLevel("SWX_ENTRY_",keys[k],entry);
      StoreLevel("SWX_TP1_",keys[k],tp1);
      StoreLevel("SWX_TP2_",keys[k],tp2);
      StoreLevel("SWX_TP3_",keys[k],tp3);
      StoreLevel("SWX_TP4_",keys[k],tp4);
      StoreLevel("SWX_TP5_",keys[k],tp5);
      StoreLevel("SWX_FINALTP_",keys[k],final_tp);
   }
   StoreState("SWX_DAYMODE_","SYM:"+symbol,mode=="day"?1:0);
}

void PartialCloseAtTP1(const string symbol,const double tp1)
{
   if(PartialCloseAtTP1Percent<=0 || tp1<=0 || !SelectSeraPosition(symbol)) return;
   ulong ticket=(ulong)PositionGetInteger(POSITION_TICKET);
   string ticket_key=IntegerToString((long)ticket);
   if(StoredState("SWX_PARTIAL_",ticket_key)==1) return;
   long position_type=PositionGetInteger(POSITION_TYPE);
   MqlTick tick;
   if(!SymbolInfoTick(symbol,tick)) return;
   double price=position_type==POSITION_TYPE_BUY?tick.bid:tick.ask;
   if(!ReachedLevel(position_type,price,tp1)) return;
   double volume=PositionGetDouble(POSITION_VOLUME);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   double min_lot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   if(step<=0) return;
   double part=MathFloor((volume*PartialCloseAtTP1Percent/100.0)/step)*step;
   StoreState("SWX_PARTIAL_",ticket_key,1);   // une seule tentative par position
   if(part<min_lot || volume-part<min_lot)
   {
      Print("Sera TP1: volume trop petit pour une sortie partielle sur ",symbol,", position conservee entiere");
      return;
   }
   trade.SetExpertMagicNumber(MagicNumber);
   if(trade.PositionClosePartial(ticket,part)) Print("Sera TP1: ",DoubleToString(part,2)," lot encaisse sur ",symbol);
   else Print("Sera TP1: sortie partielle refusee ",trade.ResultRetcodeDescription());
}

void ManageAllSeraPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket<=0 || PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      string symbol=PositionGetString(POSITION_SYMBOL);
      datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
      string key="SYM:"+symbol;
      int max_hours=StoredState("SWX_DAYMODE_",key)==1?MaximumDayHoldingHours:MaximumSwingHoldingHours;
      if(max_hours>0 && TimeCurrent()-opened>(long)max_hours*3600)
      {
         trade.SetExpertMagicNumber(MagicNumber);
         if(trade.PositionClose(ticket)) Print("Sera: ",symbol," ferme — duree maximale atteinte");
         continue;
      }
      PartialCloseAtTP1(symbol,StoredLevel("SWX_TP1_",key));
      ManageSeraPosition(key,symbol);
   }
}

bool EmergencyEquityStop()
{
   if(EmergencyEquityStopPercent<=0) return false;
   double balance=AccountInfoDouble(ACCOUNT_BALANCE),equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(balance<=0 || (balance-equity)/balance*100.0<EmergencyEquityStopPercent) return false;
   Print("Sera ARRET D'URGENCE: equite ",DoubleToString(equity,2)," / balance ",DoubleToString(balance,2)," — fermeture de toutes les positions Sera");
   trade.SetExpertMagicNumber(MagicNumber);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionGetInteger(POSITION_MAGIC)==MagicNumber) trade.PositionClose(ticket);
   }
   CancelAllSeraPendingOrders("arret d'urgence equite");
   if(EnablePushNotification) SendNotification("Sera: arret d'urgence, positions fermees (equite -"+DoubleToString(EmergencyEquityStopPercent,0)+"%)");
   return true;
}

bool BrokerReversal(const string symbol,const long position_type,const datetime opened,string &reason)
{
   int need=(int)MathMax(ReversalStructureBars+2,3);
   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   if(CopyRates(symbol,PERIOD_H1,1,need,rates)<need) return false;
   if(rates[0].time<opened) return false;
   double fast=BrokerCloseEMA(symbol,PERIOD_H1,20);
   double slow=BrokerCloseEMA(symbol,PERIOD_H1,50);
   if(fast==EMPTY_VALUE || slow==EMPTY_VALUE) return false;
   bool buy=position_type==POSITION_TYPE_BUY;
   double close=rates[0].close;
   double extreme=buy?rates[1].low:rates[1].high;
   for(int i=2;i<=ReversalStructureBars && i<need;i++)
      extreme=buy?MathMin(extreme,rates[i].low):MathMax(extreme,rates[i].high);
   double h4_ema=BrokerCloseEMA(symbol,PERIOD_H4,20);
   double h4_close[];
   bool h4_against=false;
   if(h4_ema!=EMPTY_VALUE && CopyClose(symbol,PERIOD_H4,1,1,h4_close)==1)
      h4_against=buy?(h4_close[0]<h4_ema):(h4_close[0]>h4_ema);
   bool ema_flip=h4_against && (buy?(fast<slow && close<slow):(fast>slow && close>slow));
   bool structure_break=buy?(close<extreme):(close>extreme);
   if(ema_flip){ reason="EMA20/EMA50 H1 retournees, confirme par la cloture H4"; return true; }
   if(structure_break){ reason="cassure de structure H1 sur "+IntegerToString(ReversalStructureBars)+" bougies"; return true; }
   return false;
}

void CutReversedPositions()
{
   if(!CutOnMarketReversal) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket<=0 || PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      string symbol=PositionGetString(POSITION_SYMBOL);
      long position_type=PositionGetInteger(POSITION_TYPE);
      datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
      string reason="";
      if(!BrokerReversal(symbol,position_type,opened,reason)) continue;
      trade.SetExpertMagicNumber(MagicNumber);
      if(trade.PositionClose(ticket)) Print("Sera Reversal Cut: ",symbol," ferme — ",reason);
      else Print("Sera Reversal Cut: fermeture refusee ",symbol," ",trade.ResultRetcodeDescription());
   }
}

// ===================================================================================
//  MOTEUR D'ANALYSE — portage MQL5 de Sera Autonomous Engine v4.1 (Swing H1/H4/D1)
// ===================================================================================

struct TfInfo
{
   bool     ok;
   string   side;
   string   regime;
   datetime barTime;
   int      passed;
   double   price,ema20,ema50,ema200,rsi,atr,adx,plusDI,minusDI,macdHist,er;
   double   swingHigh,swingLow,volExp,emaSpreadAtr,emaSlopeAtr,quality;
   bool     trendStrong,bos,choch,sweep,impulse,fvg,retest,orderBlock,momentum,rejection;
   bool     spikeRisk,dmiAligned,macdAligned,donchian,squeeze,squeezeRelease,structureAligned,compression,engulfing;
};

struct SwxDecision
{
   bool     valid;
   string   symbol;
   string   family;
   string   side;        // BUY / SELL / NEUTRE (biais aligné H1/H4/D1)
   string   verdict;     // BUY / SELL / ATTENDRE (signal final haute conviction)
   string   state;       // EXECUTE_NOW / WAIT_RETRACE / WAIT_CONFIRMATION / BLOCKED_RISK
   string   setupType;
   string   entrySide;   // côté H1
   string   confSide;    // côté H4
   bool     confTrendStrong;
   int      cycles;
   int      conditionPct;
   double   score,consensus,execScore,confidence;
   double   entry,sl,tp1,tp2,tp3,tp4,tp5,zoneEntry;
   datetime barTime;
};

double Clamp(const double v,const double lo,const double hi){ return MathMax(lo,MathMin(hi,v)); }

double EmaLast(const double &v[],const int count,const int period)
{
   if(count<=0) return 0.0;
   double k=2.0/(period+1.0);
   double e=v[0];
   for(int i=1;i<count;i++) e+=k*(v[i]-e);
   return e;
}

double WilderRsi(const double &c[],const int n,const int period)
{
   if(n<=period+1) return 50.0;
   double g=0.0,l=0.0;
   for(int i=1;i<=period;i++){ double d=c[i]-c[i-1]; if(d>0) g+=d; else l-=d; }
   g/=period; l/=period;
   for(int i=period+1;i<n;i++)
   {
      double d=c[i]-c[i-1];
      double up=d>0?d:0.0, dn=d<0?-d:0.0;
      g=(g*(period-1)+up)/period;
      l=(l*(period-1)+dn)/period;
   }
   if(l==0.0) return g==0.0?50.0:100.0;
   return 100.0-100.0/(1.0+g/l);
}

// Moyenne de Wilder sur src[from..to] (inclus) : graine = moyenne des 'period' premiers.
double WilderLast(const double &src[],const int from,const int to,const int period)
{
   if(to-from+1<period) return 0.0;
   double v=0.0;
   for(int i=from;i<from+period;i++) v+=src[i];
   v/=period;
   for(int i=from+period;i<=to;i++) v=(v*(period-1)+src[i])/period;
   return v;
}

double Mean(const double &v[],const int from,const int to)
{
   if(to<from) return 0.0;
   double s=0.0;
   for(int i=from;i<=to;i++) s+=v[i];
   return s/(to-from+1);
}

double StdDev(const double &v[],const int from,const int to)
{
   if(to<from) return 0.0;
   double m=Mean(v,from,to),s=0.0;
   for(int i=from;i<=to;i++) s+=(v[i]-m)*(v[i]-m);
   return MathSqrt(s/(to-from+1));
}

// Analyse d'une unité de temps sur ses bougies CLÔTURÉES (fidèle à inspectCandles du moteur).
bool InspectTf(const string symbol,const ENUM_TIMEFRAMES tf,TfInfo &r)
{
   r.ok=false; r.side="NEUTRE"; r.regime="TRANSITION"; r.passed=0; r.barTime=0;
   MqlRates rates[];
   ArraySetAsSeries(rates,false);
   int n=CopyRates(symbol,tf,1,AnalysisBars,rates);
   if(n<120) return false;

   double o[],h[],l[],c[],tr[];
   ArrayResize(o,n); ArrayResize(h,n); ArrayResize(l,n); ArrayResize(c,n); ArrayResize(tr,n);
   for(int i=0;i<n;i++)
   {
      o[i]=rates[i].open; h[i]=rates[i].high; l[i]=rates[i].low; c[i]=rates[i].close;
      if(c[i]<=0 || l[i]<=0) return false;
      tr[i]=i==0?h[i]-l[i]:MathMax(h[i]-l[i],MathMax(MathAbs(h[i]-c[i-1]),MathAbs(l[i]-c[i-1])));
   }
   int last=n-1;
   r.barTime=rates[last].time;
   r.price=c[last];
   r.ema20=EmaLast(c,n,20);
   r.ema50=EmaLast(c,n,50);
   r.ema200=EmaLast(c,n,(int)MathMin(200,n));
   double ema20Prev=EmaLast(c,n-6,20);
   r.rsi=WilderRsi(c,n,14);
   r.atr=WilderLast(tr,1,last,14);
   if(r.atr<=0) return false;

   // Structure récente : swing high / low sur les bougies n-22..n-3
   r.swingHigh=h[n-22]; r.swingLow=l[n-22];
   for(int i=n-22;i<=n-3;i++){ r.swingHigh=MathMax(r.swingHigh,h[i]); r.swingLow=MathMin(r.swingLow,l[i]); }

   bool bullish=r.ema20>r.ema50 && c[last]>r.ema20;
   r.side=bullish?"BUY":"SELL";
   r.bos=bullish?c[last]>r.swingHigh:c[last]<r.swingLow;
   double hi8=h[n-8],lo8=l[n-8];
   for(int i=n-8;i<=n-3;i++){ hi8=MathMax(hi8,h[i]); lo8=MathMin(lo8,l[i]); }
   r.choch=bullish?c[last]>hi8:c[last]<lo8;
   r.sweep=bullish?(l[last]<r.swingLow && c[last]>r.swingLow):(h[last]>r.swingHigh && c[last]<r.swingHigh);

   double body=MathAbs(c[last]-o[last]);
   double range=MathMax(h[last]-l[last],0.00001);
   r.impulse=body/range>0.55;
   r.fvg=bullish?l[last]>h[n-3]:h[last]<l[n-3];
   r.retest=bullish?(l[last]<=r.ema20 && c[last]>r.ema20):(h[last]>=r.ema20 && c[last]<r.ema20);
   r.orderBlock=false;
   for(int i=n-8;i<=n-3;i++)
   {
      bool big=(h[i]-l[i])>r.atr;
      if(bullish && c[i]<o[i] && big) r.orderBlock=true;
      if(!bullish && c[i]>o[i] && big) r.orderBlock=true;
   }
   r.momentum=bullish?(r.rsi>52 && r.rsi<78):(r.rsi<48 && r.rsi>22);
   r.trendStrong=bullish?(r.ema20>r.ema50 && r.ema50>=r.ema200):(r.ema20<r.ema50 && r.ema50<=r.ema200);

   // ADX(14) de Wilder
   int m=n-1;
   double pdm[],mdm[],trr[];
   ArrayResize(pdm,m); ArrayResize(mdm,m); ArrayResize(trr,m);
   for(int i=1;i<n;i++)
   {
      double up=h[i]-h[i-1],dn=l[i-1]-l[i];
      pdm[i-1]=(up>dn && up>0)?up:0.0;
      mdm[i-1]=(dn>up && dn>0)?dn:0.0;
      trr[i-1]=tr[i];
   }
   int p=14;
   double sP=0,sM=0,sT=0;
   for(int i=0;i<p;i++){ sP+=pdm[i]; sM+=mdm[i]; sT+=trr[i]; }
   sP/=p; sM/=p; sT/=p;
   double dx[];
   ArrayResize(dx,m);
   int dxCount=0;
   for(int i=p-1;i<m;i++)
   {
      if(i>=p){ sP=(sP*(p-1)+pdm[i])/p; sM=(sM*(p-1)+mdm[i])/p; sT=(sT*(p-1)+trr[i])/p; }
      double t=MathMax(sT,0.0000001);
      r.plusDI=100.0*sP/t; r.minusDI=100.0*sM/t;
      dx[dxCount++]=100.0*MathAbs(r.plusDI-r.minusDI)/MathMax(r.plusDI+r.minusDI,0.0000001);
   }
   r.adx=dxCount>=p?WilderLast(dx,0,dxCount-1,p):(dxCount>0?dx[dxCount-1]:0.0);
   r.dmiAligned=bullish?r.plusDI>r.minusDI:r.minusDI>r.plusDI;

   // MACD(12,26,9) : histogramme
   double macd=EmaLast(c,n,12)-EmaLast(c,n,26);
   double ms[];
   int msCount=0;
   ArrayResize(ms,40);
   for(int i=(int)MathMax(30,n-30);i<=n;i++) ms[msCount++]=EmaLast(c,i,12)-EmaLast(c,i,26);
   int sigFrom=(int)MathMax(0,msCount-9);
   double sig[];
   int sigCount=msCount-sigFrom;
   ArrayResize(sig,sigCount);
   for(int i=0;i<sigCount;i++) sig[i]=ms[sigFrom+i];
   r.macdHist=macd-EmaLast(sig,sigCount,(int)MathMin(9,sigCount));
   r.macdAligned=bullish?r.macdHist>0:r.macdHist<0;

   // Bollinger squeeze / release
   double bbMean=Mean(c,n-20,last);
   double width=bbMean!=0?StdDev(c,n-20,last)*4.0/MathAbs(bbMean):0.0;
   double widths[];
   int wCount=0;
   ArrayResize(widths,60);
   for(int i=(int)MathMax(25,n-45);i<=n;i++)
   {
      int from=(int)MathMax(0,i-20);
      double mm=Mean(c,from,i-1);
      widths[wCount++]=mm!=0?StdDev(c,from,i-1)*4.0/MathAbs(mm):0.0;
   }
   double baseline=wCount>5?Mean(widths,0,wCount-6):width;
   if(baseline<=0) baseline=width;
   r.squeeze=width<baseline*0.72;
   r.squeezeRelease=width>baseline*0.95 && !r.squeeze;

   // Donchian 20, efficience, structure HH/HL – LH/LL, englobante, rejet
   double dHi=h[n-21],dLo=l[n-21];
   for(int i=n-21;i<=n-2;i++){ dHi=MathMax(dHi,h[i]); dLo=MathMin(dLo,l[i]); }
   r.donchian=bullish?c[last]>dHi:c[last]<dLo;
   double net=MathAbs(c[last]-c[n-21]),path=0.0;
   for(int i=n-20;i<=last;i++) path+=MathAbs(c[i]-c[i-1]);
   r.er=path>0?net/path:0.0;
   double oHi=h[n-18],oLo=l[n-18],nHi=h[n-9],nLo=l[n-9];
   for(int i=n-18;i<=n-11;i++){ oHi=MathMax(oHi,h[i]); oLo=MathMin(oLo,l[i]); }
   for(int i=n-9;i<=n-2;i++){ nHi=MathMax(nHi,h[i]); nLo=MathMin(nLo,l[i]); }
   bool hhhl=nHi>oHi && nLo>oLo, lhll=nHi<oHi && nLo<oLo;
   r.structureAligned=bullish?hhhl:lhll;
   int pv=n-2;
   bool bullEng=c[last]>o[last] && c[pv]<o[pv] && c[last]>=o[pv] && o[last]<=c[pv];
   bool bearEng=c[last]<o[last] && c[pv]>o[pv] && o[last]>=c[pv] && c[last]<=o[pv];
   r.engulfing=bullish?bullEng:bearEng;
   double lowerWick=MathMin(o[last],c[last])-l[last],upperWick=h[last]-MathMax(o[last],c[last]);
   r.rejection=bullish?(lowerWick/range>0.28 && c[last]>o[last]):(upperWick/range>0.28 && c[last]<o[last]);
   r.spikeRisk=body>r.atr*2.2 || range>r.atr*2.8;

   r.emaSpreadAtr=MathAbs(r.ema20-r.ema50)/r.atr;
   r.emaSlopeAtr=(r.ema20-ema20Prev)/r.atr;
   double rr[];
   ArrayResize(rr,n);
   for(int i=0;i<n;i++) rr[i]=h[i]-l[i];
   double recentRange=Mean(rr,n-12,last);
   double baseRange=Mean(rr,n-48,n-13);
   if(baseRange<=0) baseRange=recentRange;
   r.volExp=baseRange>0?recentRange/baseRange:1.0;
   r.compression=r.volExp<0.75;

   if(r.spikeRisk) r.regime="SPIKE_RISK";
   else if(r.trendStrong && MathAbs(r.emaSlopeAtr)>0.14 && r.emaSpreadAtr>0.38) r.regime="TRENDING";
   else if(r.compression) r.regime="COMPRESSION";
   else if(r.emaSpreadAtr<0.24 && MathAbs(r.emaSlopeAtr)<0.10) r.regime="RANGE";

   bool checks[15];
   checks[0]=r.trendStrong; checks[1]=r.momentum; checks[2]=r.bos||r.choch; checks[3]=r.sweep; checks[4]=r.impulse;
   checks[5]=r.fvg; checks[6]=r.retest; checks[7]=r.orderBlock; checks[8]=r.rejection; checks[9]=!r.spikeRisk;
   checks[10]=r.adx>=20 && r.dmiAligned; checks[11]=r.macdAligned; checks[12]=r.donchian||r.squeezeRelease;
   checks[13]=r.er>=0.30; checks[14]=r.structureAligned;
   for(int i=0;i<15;i++) if(checks[i]) r.passed++;

   double structureScore=(r.bos||r.choch?18:0)+(r.sweep?11:0)+(r.retest?11:0)+(r.orderBlock?8:0)+(r.fvg?6:0);
   double trendScore=(r.trendStrong?20:5)+Clamp(r.emaSpreadAtr*8,0,11)+Clamp(MathAbs(r.emaSlopeAtr)*14,0,9)
      +(r.adx>=20 && r.dmiAligned?7:0)+(r.structureAligned?5:0)+(r.er>=0.30?4:0);
   double momentumScore=(r.momentum?9:3)+(r.macdAligned?5:0)+(r.donchian?4:0)+(r.squeezeRelease?3:0);
   double executionScore=(r.impulse?7:2)+(r.rejection?6:1);
   double regimePenalty=r.regime=="SPIKE_RISK"?24:r.regime=="RANGE"?12:r.regime=="COMPRESSION"?6:0;
   r.quality=MathRound(Clamp(trendScore+momentumScore+executionScore+structureScore-regimePenalty,0,100));
   r.ok=true;
   return true;
}

// Familles Weltrade (support.weltrade.com) : PainX monte avec des chutes (≈ Crash),
// GainX baisse avec des sauts (≈ Boom), SFX Vol a des spikes dans les deux sens.
string SyntXFamily(const string symbol)
{
   string s=symbol;
   StringToUpper(s);
   StringReplace(s," ","");
   StringReplace(s,"_","");
   if(StringFind(s,"SFXVOL")>=0) return "SFXVOL";
   if(StringFind(s,"FXVOL")>=0) return "FXVOL";
   if(StringFind(s,"PAINX")>=0) return "PAINX";
   if(StringFind(s,"GAINX")>=0) return "GAINX";
   if(StringFind(s,"FLIPX")>=0) return "FLIPX";
   if(StringFind(s,"SWITCHX")>=0) return "SWITCHX";
   if(StringFind(s,"BREAKX")>=0) return "BREAKX";
   if(StringFind(s,"TRENDX")>=0) return "TRENDX";
   if(StringFind(s,"PLUSX")>=0) return "PLUSX";
   if(StringFind(s,"FIBOX")>=0) return "FIBOX";
   if(StringFind(s,"QUADX")>=0) return "QUADX";
   return "";
}

bool FamilyEnabled(const string family)
{
   if(family=="PAINX" || family=="GAINX") return TradePainGainX;
   if(family=="FXVOL" || family=="SFXVOL") return TradeVolIndices;
   if(family=="SWITCHX" || family=="BREAKX" || family=="TRENDX") return TradeRegimeSwitchX;
   if(family=="FLIPX") return TradeFlipX;
   if(family=="PLUSX" || family=="FIBOX" || family=="QUADX") return TradeProgressionX;
   return false;
}

// Mémoire du biais : un cycle = une NOUVELLE bougie H1 clôturée avec le même biais aligné.
void UpdateBiasMemory(const string symbol,const string bias,const datetime barTime,int &cycles,bool &persistence,bool &flip)
{
   int code=bias=="BUY"?1:bias=="SELL"?-1:0;
   int previous=StoredState("SWX_BIAS_",symbol);
   double previousBar=StoredLevel("SWX_BIASBAR_",symbol);
   int previousCycles=StoredState("SWX_CYCLES_",symbol);
   bool newBar=(double)barTime!=previousBar;
   persistence=code!=0 && code==previous;
   flip=code!=0 && previous!=0 && code!=previous;
   if(code==0) cycles=0;
   else if(code==previous) cycles=newBar?(int)MathMin(previousCycles+1,24):(int)MathMax(1,previousCycles);
   else cycles=1;
   StoreState("SWX_BIAS_",symbol,code);
   StoreLevel("SWX_BIASBAR_",symbol,(double)barTime);
   StoreState("SWX_CYCLES_",symbol,cycles);
}

// Décision Swing haute conviction (fidèle à autonomousDecision + executionAssessment).
void Decide(const string symbol,SwxDecision &d)
{
   d.valid=false; d.symbol=symbol; d.family=SyntXFamily(symbol); d.side="NEUTRE"; d.verdict="ATTENDRE";
   d.state="WAIT_CONFIRMATION"; d.setupType="GENERIC"; d.entrySide=""; d.confSide=""; d.confTrendStrong=false;
   d.cycles=0; d.conditionPct=0; d.score=0; d.consensus=0; d.execScore=0; d.confidence=0;
   d.entry=0; d.sl=0; d.tp1=0; d.tp2=0; d.tp3=0; d.tp4=0; d.tp5=0; d.zoneEntry=0; d.barTime=0;

   TfInfo e,cf,dd;
   if(!InspectTf(symbol,PERIOD_H1,e) || !InspectTf(symbol,PERIOD_H4,cf) || !InspectTf(symbol,PERIOD_D1,dd)) return;
   d.valid=true; d.barTime=e.barTime; d.entrySide=e.side; d.confSide=cf.side; d.confTrendStrong=cf.trendStrong;

   string side=e.side;
   bool aligned=side==cf.side && side==dd.side;
   d.side=aligned?side:"NEUTRE";
   bool adverse=(d.family=="PAINX" && side=="BUY") || (d.family=="GAINX" && side=="SELL");
   bool persistence=false,flip=false;
   int cycles=0;
   UpdateBiasMemory(symbol,d.side,e.barTime,cycles,persistence,flip);
   d.cycles=cycles;

   bool trending=e.regime=="TRENDING" || cf.regime=="TRENDING";
   bool exhaustion=side=="BUY"?(cf.rsi>68 || dd.rsi>70):(cf.rsi<32 || dd.rsi<30);
   bool macroTrendOk=dd.trendStrong && dd.regime!="RANGE" && dd.regime!="SPIKE_RISK";
   bool breakout=trending && aligned && macroTrendOk && e.trendStrong && cf.trendStrong && (e.bos||e.choch) && e.impulse;
   bool pullback=trending && aligned && macroTrendOk && e.trendStrong && cf.trendStrong && e.retest;
   d.setupType=breakout?"BREAKOUT_CONTINUATION":pullback?"PULLBACK_CONTINUATION":"GENERIC";
   bool generic=d.setupType=="GENERIC";
   bool pullbackType=d.setupType=="PULLBACK_CONTINUATION";   // une cassure prime sur un retest, comme le serveur

   // Stratégies pondérées : {poids, applicable, validée}
   double wt[21]; bool ap[21]; bool su[21];
   int k=0;
   wt[k]=18; ap[k]=trending;                         su[k]=aligned && e.trendStrong && cf.trendStrong && macroTrendOk; k++;
   wt[k]=18; ap[k]=true;                             su[k]=side==dd.side && dd.trendStrong && dd.quality>=65 && dd.adx>=18 && dd.dmiAligned; k++;
   wt[k]=15; ap[k]=true;                             su[k]=e.bos || e.choch; k++;
   wt[k]=10; ap[k]=pullbackType;                         su[k]=e.sweep; k++;
   wt[k]=11; ap[k]=breakout || (trending && generic); su[k]=(e.bos||e.choch) && e.impulse; k++;
   wt[k]=11; ap[k]=pullback || (trending && generic); su[k]=e.retest && e.trendStrong; k++;
   wt[k]=10; ap[k]=true;                             su[k]=e.momentum && e.impulse; k++;
   wt[k]=8;  ap[k]=true;                             su[k]=e.fvg || e.orderBlock; k++;
   wt[k]=6;  ap[k]=pullbackType;                         su[k]=e.rejection; k++;
   wt[k]=12; ap[k]=true;                             su[k]=cycles>=2; k++;
   wt[k]=8;  ap[k]=true;                             su[k]=!e.spikeRisk && !cf.spikeRisk && !dd.spikeRisk && e.volExp>0.55 && e.volExp<2.6; k++;
   wt[k]=12; ap[k]=true;                             su[k]=!exhaustion; k++;
   wt[k]=8;  ap[k]=true;                             su[k]=!adverse || (e.sweep && (e.bos||e.choch)); k++;
   wt[k]=10; ap[k]=trending;                         su[k]=e.adx>=20 && e.dmiAligned && cf.adx>=22 && cf.dmiAligned && dd.adx>=18 && dd.dmiAligned; k++;
   wt[k]=8;  ap[k]=trending || breakout;             su[k]=e.macdAligned && cf.macdAligned; k++;
   wt[k]=8;  ap[k]=breakout || (trending && generic); su[k]=e.donchian; k++;
   wt[k]=7;  ap[k]=e.compression || breakout;        su[k]=e.squeezeRelease; k++;
   wt[k]=7;  ap[k]=trending;                         su[k]=e.er>=0.30 && cf.er>=0.25; k++;
   wt[k]=10; ap[k]=true;                             su[k]=e.structureAligned && cf.structureAligned; k++;
   wt[k]=5;  ap[k]=pullbackType;                         su[k]=e.engulfing; k++;

   double possible=0,supported=0;
   int applicable=0,passedCount=0;
   for(int i=0;i<k;i++)
   {
      if(!ap[i]) continue;
      applicable++; possible+=wt[i];
      if(su[i]){ passedCount++; supported+=wt[i]; }
   }
   d.consensus=possible>0?supported/possible:0.0;
   d.conditionPct=applicable>0?(int)MathRound(100.0*passedCount/applicable):0;

   double techQuality=e.quality*0.34+cf.quality*0.34+dd.quality*0.20+e.passed*1.2;
   double localScore=MathRound(Clamp(techQuality+(aligned?7:-12)-(adverse?3:0),0,97));   // arrondi comme le moteur serveur
   double quality=e.quality*0.30+cf.quality*0.30+dd.quality*0.24+localScore*0.16;
   double score=d.consensus*68.0+quality*0.32;
   score+=aligned?4:-14;
   if(persistence) score+=3;
   if(flip) score-=14;
   if(e.spikeRisk) score-=24;
   if(cf.spikeRisk || dd.spikeRisk) score-=20;
   if(exhaustion) score-=16;
   if(e.regime=="RANGE") score-=10;
   if(adverse) score-=5;
   d.score=MathRound(Clamp(score,0,97));

   bool qualityGate=e.quality>=72 && cf.quality>=75 && dd.quality>=65;
   bool confirmationGate=cf.trendStrong && dd.trendStrong && cf.adx>=22 && cf.dmiAligned && dd.adx>=18 && dd.dmiAligned;
   bool adverseGate=!adverse || (d.score>=84 && e.sweep && (e.bos||e.choch));
   bool riskGate=!e.spikeRisk && !cf.spikeRisk && !dd.spikeRisk && !exhaustion && !flip;
   bool continuationGate=breakout || pullback;
   bool structureGate=(e.bos||e.choch||e.retest) && e.structureAligned && cf.structureAligned;
   bool momentumGate=e.momentum && cf.dmiAligned && dd.dmiAligned;
   bool signal=aligned && qualityGate && confirmationGate && adverseGate && riskGate && d.conditionPct>=80
      && continuationGate && structureGate && momentumGate && cycles>=2 && d.consensus>=0.72 && d.score>=84;
   d.verdict=signal?side:"ATTENDRE";
   d.confidence=signal?Clamp(d.score,84,96):Clamp(d.score,18,83);

   // Exécution : extension par rapport à l'EMA20, épuisement RSI, poursuite de cassure
   double ext=MathAbs(e.price-e.ema20)/e.atr;
   bool stretched=side=="BUY"?e.rsi>=66:e.rsi<=34;
   bool extreme=side=="BUY"?e.rsi>=72:e.rsi<=28;
   double familyAdj=(d.family=="PAINX" || d.family=="GAINX")?0.10:(d.family=="FXVOL"?0.0:0.05);
   double maxExt=MathMax(0.85,1.15+familyAdj-(adverse?0.18:0.0));
   bool chase=breakout && !e.retest && ext>0.90 && stretched;
   bool overextended=ext>maxExt || extreme || chase;
   bool structuralEntry=e.retest || e.rejection || (breakout && ext<=0.90);
   double es=d.score+(cycles>=2?4:-12)+(signal?4:-12)+(structuralEntry?5:-2)-(overextended?18:0)-(e.spikeRisk?28:0)-(flip?18:0);
   d.execScore=MathRound(Clamp(es,0,98));
   if(!signal) d.state=(flip || e.spikeRisk)?"BLOCKED_RISK":"WAIT_CONFIRMATION";
   else if(overextended) d.state="WAIT_RETRACE";
   else if(d.execScore>=84 && d.conditionPct>=80) d.state="EXECUTE_NOW";
   else d.state="WAIT_CONFIRMATION";

   if(signal)
   {
      double dir=side=="BUY"?1.0:-1.0;
      d.entry=e.price;
      d.sl=side=="BUY"?MathMin(e.price-e.atr*1.5,e.swingLow):MathMax(e.price+e.atr*1.5,e.swingHigh);
      double dist=MathMax(MathAbs(d.entry-d.sl),e.atr);
      d.tp1=d.entry+dir*dist*1.5; d.tp2=d.entry+dir*dist*2.4; d.tp3=d.entry+dir*dist*3.6;
      d.tp4=d.entry+dir*dist*4.8; d.tp5=d.entry+dir*dist*6.0;
      d.zoneEntry=e.ema20;
   }
}

// ===================================================================================
//  SCANNER, EXÉCUTION ET TABLEAU DE BORD
// ===================================================================================

string      g_symbols[];
SwxDecision g_decisions[];
datetime    g_lastBar[];
datetime    g_lastSymbolRefresh=0;

void AddSymbol(const string name)
{
   for(int i=0;i<ArraySize(g_symbols);i++) if(g_symbols[i]==name) return;
   if(!SymbolSelect(name,true)) return;
   int n=ArraySize(g_symbols);
   ArrayResize(g_symbols,n+1);
   ArrayResize(g_decisions,n+1);
   ArrayResize(g_lastBar,n+1);
   g_symbols[n]=name;
   g_decisions[n].valid=false;
   g_decisions[n].symbol=name;
   g_decisions[n].verdict="ATTENDRE";
   g_decisions[n].side="NEUTRE";
   g_decisions[n].state="WAIT_CONFIRMATION";
   g_decisions[n].score=0;
   g_decisions[n].cycles=0;
   g_decisions[n].conditionPct=0;
   g_lastBar[n]=0;
}

// Liste des indices Weltrade : liste manuelle, sinon détection automatique chez le broker.
void RefreshSymbols()
{
   g_lastSymbolRefresh=TimeCurrent();
   if(StringLen(SymbolsList)>0)
   {
      string parts[];
      int count=StringSplit(SymbolsList,',',parts);
      for(int i=0;i<count;i++)
      {
         string name=parts[i];
         StringTrimLeft(name); StringTrimRight(name);
         if(name!="") AddSymbol(name);
      }
      return;
   }
   for(int i=0;i<SymbolsTotal(false) && ArraySize(g_symbols)<MaximumScannedSymbols;i++)
   {
      string name=SymbolName(i,false);
      string family=SyntXFamily(name);
      if(family!="" && FamilyEnabled(family)) AddSymbol(name);
   }
}

void SendSwxAlert(const string message)
{
   Print(message);
   if(EnableTerminalAlert) Alert(message);
   if(EnablePushNotification && !SendNotification(message)) Print("SyntX: notification non envoyee, erreur=",GetLastError());
}

// Coupe une position si l'analyse du nouveau H1 montre H1 et H4 retournés avec la tendance H4 cassée.
void AnalysisReversalExit(const SwxDecision &d)
{
   if(!CutOnMarketReversal || !d.valid || !SelectSeraPosition(d.symbol)) return;
   long type=PositionGetInteger(POSITION_TYPE);
   string against=type==POSITION_TYPE_BUY?"SELL":"BUY";
   if(d.entrySide!=against || d.confSide!=against || !d.confTrendStrong) return;
   ulong ticket=(ulong)PositionGetInteger(POSITION_TICKET);
   trade.SetExpertMagicNumber(MagicNumber);
   if(trade.PositionClose(ticket)) SendSwxAlert("SyntX: "+d.symbol+" ferme — tendance H1 et H4 retournees ("+against+")");
}

bool TryMarketEntry(const SwxDecision &d,const bool can_trade)
{
   if(!can_trade || d.state!="EXECUTE_NOW" || (d.verdict!="BUY" && d.verdict!="SELL")) return false;
   if(StoredLevel("SWX_TRADEDBAR_",d.symbol)==(double)d.barTime) return false;   // un trade par signal
   if(OpenSeraPositions()>=AllowedOpenPositions() || TradesToday()>=AllowedTradesPerDay()) return false;
   if(OnePositionPerSymbol && HasSeraPositionOn(d.symbol)) return false;
   MqlTick tick;
   if(!SymbolInfoTick(d.symbol,tick)) return false;
   double price=d.verdict=="BUY"?tick.ask:tick.bid;
   double risk_distance=MathAbs(d.entry-d.sl);
   if(risk_distance<=0) return false;
   double spread=MathAbs(tick.ask-tick.bid);
   bool spread_ok=spread<=risk_distance*(MaximumSpreadRiskPercent/100.0);
   bool chase_ok=d.verdict=="BUY"?price<=d.entry+risk_distance*(MaximumEntryChaseRiskPercent/100.0)
                                 :price>=d.entry-risk_distance*(MaximumEntryChaseRiskPercent/100.0);
   double final_tp=(DynamicFinalTarget && d.score>=88 && d.tp4>0)?d.tp4:d.tp3;
   bool levels_ok=d.verdict=="BUY"?(d.sl<price && final_tp>price):(d.sl>price && final_tp<price);
   if(!spread_ok){ PrintOnce("SyntX: "+d.symbol+" spread trop large pour le risque"); return false; }
   if(!chase_ok){ PrintOnce("SyntX: "+d.symbol+" prix trop eloigne de l'entree calculee"); return false; }
   if(!levels_ok || !BrokerStopsValid(d.symbol,d.verdict,price,d.sl,final_tp)) return false;
   double volume=SafeVolume(d.symbol,price,d.sl);
   if(volume<=0){ PrintOnce("SyntX: "+d.symbol+" volume nul (lot minimum superieur au risque autorise)"); return false; }
   double margin=0.0;
   if(!OrderCalcMargin(d.verdict=="BUY"?ORDER_TYPE_BUY:ORDER_TYPE_SELL,d.symbol,volume,price,margin) || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)*0.50)
   { PrintOnce("SyntX: "+d.symbol+" marge libre insuffisante"); return false; }
   if(!TotalRiskAllows(PositionRiskUSD(d.symbol,d.verdict=="BUY"?POSITION_TYPE_BUY:POSITION_TYPE_SELL,price,d.sl,volume)))
   { PrintOnce("SyntX: "+d.symbol+" reporte — risque cumule maximum atteint"); return false; }

   CancelSeraPendingOrder(d.symbol,"ordre au marche EXECUTE_NOW");
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(DeviationPoints);
   bool sent=d.verdict=="BUY"?trade.Buy(volume,d.symbol,0,d.sl,final_tp,"Sera Weltrade v1.00"):trade.Sell(volume,d.symbol,0,d.sl,final_tp,"Sera Weltrade v1.00");
   if(!sent){ Print("SyntX: ordre refuse ",d.symbol," ",trade.ResultRetcodeDescription()); return false; }
   StoreLevel("SWX_TRADEDBAR_",d.symbol,(double)d.barTime);
   StoreTradeLevels(d.symbol,d.symbol,d.entry,d.tp1,d.tp2,d.tp3,d.tp4,d.tp5,final_tp,"swing");
   SendSwxAlert("SyntX: "+d.verdict+" "+d.symbol+" "+DoubleToString(volume,2)+" lot · SL "+DoubleToString(d.sl,(int)SymbolInfoInteger(d.symbol,SYMBOL_DIGITS))+" · score "+DoubleToString(d.score,0));
   return true;
}

// Signal confirmé mais prix étendu : ordre limite dans la zone EMA20 H1.
void ManagePendingEntry(const SwxDecision &d,const bool can_trade)
{
   if(!EnableSmartPendingLimits) return;
   bool wanted=can_trade && d.state=="WAIT_RETRACE" && (d.verdict=="BUY" || d.verdict=="SELL")
      && OpenSeraPositions()<AllowedOpenPositions() && (!OnePositionPerSymbol || !HasSeraPositionOn(d.symbol))
      && (FindSeraPendingOrder(d.symbol)>0 || OpenSeraPendingOrders()<AllowedPendingOrders());
   if(!wanted)
   {
      if(FindSeraPendingOrder(d.symbol)>0 && (d.verdict=="ATTENDRE" || d.state=="EXECUTE_NOW" || d.state=="BLOCKED_RISK"))
         CancelSeraPendingOrder(d.symbol,d.state=="EXECUTE_NOW"?"passage EXECUTE_NOW":"signal invalide");
      return;
   }
   double entry=d.zoneEntry;
   double final_tp=(DynamicFinalTarget && d.score>=88 && d.tp4>0)?d.tp4:d.tp3;
   if(!BrokerStopsValid(d.symbol,d.verdict,entry,d.sl,final_tp)) return;
   double volume=SafeVolume(d.symbol,entry,d.sl);
   if(volume<=0) return;
   if(FindSeraPendingOrder(d.symbol)==0 &&
      !TotalRiskAllows(PositionRiskUSD(d.symbol,d.verdict=="BUY"?POSITION_TYPE_BUY:POSITION_TYPE_SELL,entry,d.sl,volume))) return;
   if(PlaceOrUpdatePendingLimit(d.symbol,d.symbol,d.verdict,entry,d.sl,final_tp,volume))
      StoreTradeLevels(d.symbol,d.symbol,entry,d.tp1,d.tp2,d.tp3,d.tp4,d.tp5,final_tp,"swing");
}

void RenderDashboard(const bool can_trade,const string mode_label)
{
   int order[];
   int n=ArraySize(g_symbols);
   ArrayResize(order,n);
   for(int i=0;i<n;i++) order[i]=i;
   for(int i=0;i<n;i++)
      for(int j=i+1;j<n;j++)
         if(g_decisions[order[j]].score>g_decisions[order[i]].score){ int t=order[i]; order[i]=order[j]; order[j]=t; }
   int signals=0;
   for(int i=0;i<n;i++) if(g_decisions[i].verdict=="BUY" || g_decisions[i].verdict=="SELL") signals++;
   string text="Sera EA Swing Intelligent Weltrade v1.00 — "+mode_label+(can_trade?" — auto-trade ACTIF":" — alertes seulement")+
      "\nIndices suivis: "+IntegerToString(n)+" · signaux confirmes: "+IntegerToString(signals)+
      " · positions "+IntegerToString(OpenSeraPositions())+"/"+IntegerToString(AllowedOpenPositions())+
      " · risque ouvert "+DoubleToString(OpenSeraRiskUSD(),2)+
      "\n—— Meilleurs setups H1/H4/D1 ——";
   for(int i=0;i<n && i<DashboardRows;i++)
   {
      SwxDecision d=g_decisions[order[i]];
      if(!d.valid) continue;
      text+="\n"+d.symbol+"  "+(d.verdict!="ATTENDRE"?d.verdict:("biais "+d.side))+"  score "+DoubleToString(d.score,0)+
            "  "+IntegerToString(d.conditionPct)+"%  "+IntegerToString((int)MathMin(d.cycles,2))+"/2  "+d.state;
   }
   Comment(text);
}

void ScanAndTrade()
{
   if(TimeCurrent()-g_lastSymbolRefresh>3600 || ArraySize(g_symbols)==0) RefreshSymbols();

   bool circuit=RiskCircuitOpen();
   if(circuit) CancelAllSeraPendingOrders("circuit risque actif");
   bool real=AccountInfoInteger(ACCOUNT_TRADE_MODE)!=ACCOUNT_TRADE_MODE_DEMO;
   bool can_trade=EnableAutomaticTrading && !circuit && (!real || AllowRealAccount)
      && TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED);
   string mode_label=real?"REEL":"DEMO";

   bool entered=false;
   for(int i=0;i<ArraySize(g_symbols);i++)
   {
      string symbol=g_symbols[i];
      datetime bar=iTime(symbol,PERIOD_H1,1);
      if(bar==0) continue;
      if(bar!=g_lastBar[i] || !g_decisions[i].valid)
      {
         string before=g_decisions[i].verdict;
         Decide(symbol,g_decisions[i]);
         g_lastBar[i]=bar;
         if(g_decisions[i].valid)
         {
            AnalysisReversalExit(g_decisions[i]);
            string now=g_decisions[i].verdict;
            if(EnableTrendWatch && now!=before && (now=="BUY" || now=="SELL"))
               SendSwxAlert("SyntX: signal "+now+" "+symbol+" · score "+DoubleToString(g_decisions[i].score,0)+" · "+g_decisions[i].state);
         }
      }
      if(!g_decisions[i].valid) continue;
      ManagePendingEntry(g_decisions[i],can_trade);
      if(!entered) entered=TryMarketEntry(g_decisions[i],can_trade);   // au plus une entrée au marché par cycle
   }
   RenderDashboard(can_trade,mode_label);
}

int OnInit()
{
   trade.SetAsyncMode(false);
   RefreshSymbols();
   EventSetTimer(MathMax(15,PollEverySeconds));
   Print("Sera EA Swing Intelligent Weltrade v1.00: ",ArraySize(g_symbols)," indices detectes, auto=",EnableAutomaticTrading,
         ", reel=",AllowRealAccount,", plafond positions=",MaximumOpenPositionsCap,
         ", risque cumule max=",DoubleToString(MaximumTotalOpenRiskPercent,1),"%");
   if(ArraySize(g_symbols)==0)
      Print("SyntX: aucun indice Weltrade trouve. Renseignez SymbolsList (ex: GainX 800,PainX 800,SFX Vol 40).");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){ EventKillTimer(); Comment(""); }

void OnTimer()
{
   if(EmergencyEquityStop()) return;
   ManageAllSeraPositions();
   CutReversedPositions();
   ScanAndTrade();
}
