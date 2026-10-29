#property copyright "Sera EA Swing Intelligent Weltrade"
#property version   "1.60"
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
input bool ShowDashboard=true;              // tableau de bord sur le graphique
input int DashboardX=10;
input int DashboardY=22;
input int DashboardMaxOrders=15;            // lignes max. pour les ordres et positions
input int DashboardMaxSetups=10;            // lignes max. pour les positions possibles
input bool ShowEntryChecks=true;            // detail des 12 controles de l'indice suivi

// --- Execution
input bool EnableAutomaticTrading=true;
input bool AllowRealAccount=true;
input bool EnableTrendWatch=true;            // alerte a chaque nouveau signal confirme
input bool EnableTerminalAlert=false;
input bool EnablePushNotification=false;     // notifications sur l'appli MT5 du telephone (MetaQuotes ID)
input bool DynamicFinalTarget=true;          // TP4 au lieu de TP3 si score >= 88
input bool EnableSmartPendingLimits=true;
// --- Entree rapide : signal confirme (2 bougies H1 deja exigees) et tres confiant, prix pas etendu -> au marche sans attendre EXECUTE_NOW
input bool EnableFastEntry=true;
input int FastEntryMinimumConfidence=85;
input int FastEntryMinimumExecutionScore=72;
input bool PendingWhileConfirming=true;      // v1.60 : ordre limite (zone EMA20 H1) des que le signal est confirme
input bool CancelPendingOnRisk=true;         // v1.60 : annuler l'ordre limite AVANT son execution si le signal se degrade    // ordre limite sur l'EMA20 H1 si le prix est trop etendu
input int PendingExpirationHours=8;
input int MaximumEntryChaseRiskPercent=35;
input int MaximumSpreadRiskPercent=12;
input int PollEverySeconds=30;
input long MagicNumber=26102101;
input int DeviationPoints=50;

// --- Risque par trade (identique a Sera EA)
input double RiskPercent=0.50;
input double MaximumAdaptiveRiskPercent=0.75;
input double MaximumLossUSD=0.0;         // 0 = pas de plafond en USD : le risque suit la balance (RiskPercent)
input double MaximumAdaptiveLossUSD=0.0;
input double MaximumLot=0.0;             // 0 = lot maximum du broker
input bool UseMinimumLotWhenRiskTooSmall=true;   // prendre le lot minimum si le lot calculé est plus petit
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
input int MaximumOpenPositionsCap=0;           // 0 = pas de plafond : une position par indice ayant un signal
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
//  MODULES PARTAGES — repris a l'identique de Sera EA Swing Intelligent Deriv (controle par scripts/qa_ea.py)
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
   int deleted=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket<=0 || OrderGetInteger(ORDER_MAGIC)!=MagicNumber) continue;
      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type!=ORDER_TYPE_BUY_LIMIT && type!=ORDER_TYPE_SELL_LIMIT) continue;
      if(trade.OrderDelete(ticket)) deleted++;
      else Print("Sera SyntX: echec suppression pending #",ticket," - ",trade.ResultRetcodeDescription());
   }
   if(deleted>0) Print("Sera SyntX: ",deleted," ordre(s) limite(s) annule(s) - ",reason);
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

// Plafond de perte en USD par trade. 0 = pas de plafond : le risque suit la balance (RiskPercent).
double AdaptiveLossCap()
{
   if(MaximumLossUSD<=0) return 0.0;
   if(!EnableAdaptiveLot) return MaximumLossUSD;
   double risk=AdaptiveRiskPercent();
   double ratio=RiskPercent>0?risk/RiskPercent:1.0;
   double cap=MaximumLossUSD*MathMax(1.0,ratio);
   return MaximumAdaptiveLossUSD>0?MathMin(MaximumAdaptiveLossUSD,cap):cap;
}

double SafeVolume(const string symbol,const double entry,const double sl)
{
   double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   double tick_value=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
   double min_lot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double max_lot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   if(MaximumLot>0) max_lot=MathMin(max_lot,MaximumLot);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(tick_size<=0 || tick_value<=0 || step<=0 || MathAbs(entry-sl)<=0) return 0;
   double adaptiveRisk=AdaptiveRiskPercent()*AssetRiskFactor(symbol);
   double lossCap=AdaptiveLossCap()*AssetRiskFactor(symbol);
   // Lot proportionnel à l'équité : RiskPercent de l'équité perdus si le SL est touché.
   double risk=AccountInfoDouble(ACCOUNT_EQUITY)*adaptiveRisk/100.0;
   if(lossCap>0) risk=MathMin(risk,lossCap);
   double loss_per_lot=(MathAbs(entry-sl)/tick_size)*tick_value;
   double volume=MathFloor((risk/loss_per_lot)/step)*step;
   // Petit compte : si le lot calculé est sous le minimum du broker, on prend le lot minimum
   // (le budget de risque total TotalRiskAllows reste le garde-fou).
   if(volume<min_lot)
   {
      if(!UseMinimumLotWhenRiskTooSmall) return 0;
      volume=min_lot;
   }
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
   int cap=MaximumOpenPositionsCap>0?MaximumOpenPositionsCap:100000;   // 0 = pas de plafond
   int slots=cap;
   if(BalancePerPositionUSD>0)
      slots=(int)MathMin(slots,MathFloor(AccountInfoDouble(ACCOUNT_BALANCE)/BalancePerPositionUSD));
   slots=(int)MathMax(MaximumOpenPositions,slots);
   return (int)MathMax(1,MathMin(cap,slots));
}

int AllowedTradesPerDay()
{
   if(!EnableBalanceScaling) return MaximumTradesPerDay;
   if(MaximumOpenPositionsCap<=0) return 100000;   // pas de plafond : les signaux et le budget de risque décident
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
   // controles affiches sur le tableau de bord
   bool     gAligned,gQuality,gConfirm,gSetup,gStructure,gRisk,gScore;
   string   dailySide;
   double   qH1,qH4,qD1;
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
   d.gAligned=false; d.gQuality=false; d.gConfirm=false; d.gSetup=false; d.gStructure=false; d.gRisk=false; d.gScore=false;
   d.dailySide=""; d.qH1=0; d.qH4=0; d.qD1=0;

   TfInfo e,cf,dd;
   if(!InspectTf(symbol,PERIOD_H1,e) || !InspectTf(symbol,PERIOD_H4,cf) || !InspectTf(symbol,PERIOD_D1,dd)) return;
   d.valid=true; d.barTime=e.barTime; d.entrySide=e.side; d.confSide=cf.side; d.confTrendStrong=cf.trendStrong;
   d.dailySide=dd.side; d.qH1=e.quality; d.qH4=cf.quality; d.qD1=dd.quality;

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
   d.gAligned=aligned; d.gQuality=qualityGate; d.gConfirm=confirmationGate; d.gSetup=continuationGate;
   d.gStructure=structureGate && momentumGate; d.gRisk=riskGate && adverseGate;
   d.gScore=d.conditionPct>=80 && d.consensus>=0.72 && d.score>=84;
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

// ---------- Tableau de bord (depuis v1.20) : etat du bot, analyses et controles avant chaque entree ----------
#define SWX_GATES 12
#define SWX_BAR_COLUMN 114
string g_gate_names[SWX_GATES]={"Tendance alignee H1/H4/D1","Qualite des 3 unites de temps","Confirmation H4/D1 (ADX, DMI)",
   "Setup de continuation (cassure / retest)","Structure et momentum","Risque (spike, epuisement, famille)",
   "Confirmation sur 2 bougies H1","Score, consensus et conditions","Etat d'execution (marche / limite)",
   "Capacite (1 position par indice)","Spread, prix et stops du broker","Marge libre et risque total"};

struct PanelRow
{
   string symbol,verdict,side,state,setup,decision,detail[SWX_GATES];
   double score,consensus,conditions,exec_score,confidence;
   int    cycles;
   int    gate[SWX_GATES];      // 1 = OK, 0 = bloque, -1 = non evalue
   bool   opened,valid;
};

PanelRow g_rows[];
string   g_trade_block="";
datetime g_last_analysis=0;
bool     g_dash_can_trade=false;
string   g_dash_mode="";

string F0(const double v){ return DoubleToString(v,0); }

// "3/12", ou "3 (pas de plafond)" quand le nombre de positions n'est limite que par le risque total.
string PositionsText()
{
   int allowed=AllowedOpenPositions();
   return IntegerToString(OpenSeraPositions())+(allowed>=1000?" (pas de plafond)":"/"+IntegerToString(allowed));
}

string FormatPrice(const string symbol,const double price)
{
   return DoubleToString(price,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS));
}

void PanelGate(PanelRow &r,const int index,const bool ok,const string detail)
{
   r.gate[index]=ok?1:0;
   r.detail[index]=detail;
}

string PanelFirstBlock(const PanelRow &r)
{
   for(int i=0;i<SWX_GATES;i++) if(r.gate[i]==0) return g_gate_names[i]+(r.detail[i]!=""?" ("+r.detail[i]+")":"");
   return "";
}

bool IsSignal(const string verdict){ return verdict=="BUY" || verdict=="SELL"; }

bool FastEntryOk(const SwxDecision &d)
{
   return EnableFastEntry && IsSignal(d.verdict) && d.state=="WAIT_CONFIRMATION"
      && d.confidence>=FastEntryMinimumConfidence && d.execScore>=FastEntryMinimumExecutionScore;
}

// Les 8 controles de l'analyse (moteur Sera v4.1 dans MT5) et l'etat d'execution.
void PanelFromDecision(PanelRow &r,const SwxDecision &d)
{
   r.symbol=d.symbol; r.verdict=d.verdict; r.side=d.side; r.state=d.state; r.setup=d.setupType; r.decision="";
   r.score=d.score; r.consensus=d.consensus*100.0; r.conditions=d.conditionPct; r.exec_score=d.execScore;
   r.confidence=d.confidence; r.cycles=d.cycles; r.opened=false; r.valid=d.valid;
   for(int i=0;i<SWX_GATES;i++){ r.gate[i]=-1; r.detail[i]=""; }
   if(!d.valid){ r.decision="ANALYSE IMPOSSIBLE : historique H1/H4/D1 insuffisant chez le broker"; return; }
   PanelGate(r,0,d.gAligned,"H1 "+d.entrySide+" / H4 "+d.confSide+" / D1 "+d.dailySide);
   PanelGate(r,1,d.gQuality,"H1 "+F0(d.qH1)+"/72  H4 "+F0(d.qH4)+"/75  D1 "+F0(d.qD1)+"/65");
   PanelGate(r,2,d.gConfirm,d.gConfirm?"":(d.confTrendStrong?"ADX/DMI pas encore alignes":"tendance H4 pas assez forte"));
   PanelGate(r,3,d.gSetup,d.gSetup?d.setupType:"pas de cassure ni de retest propre");
   PanelGate(r,4,d.gStructure,"");
   PanelGate(r,5,d.gRisk,d.gRisk?"":(d.state=="BLOCKED_RISK"?"spike ou retournement recent":"marche epuise ou contre la famille"));
   PanelGate(r,6,d.cycles>=2,IntegerToString((int)MathMin(d.cycles,2))+"/2 bougies");
   PanelGate(r,7,d.gScore,"score "+F0(d.score)+"/84  consensus "+F0(d.consensus*100.0)+"/72%  conditions "+IntegerToString(d.conditionPct)+"/80%");
   if(IsSignal(d.verdict))
   {
      bool exec=d.state=="EXECUTE_NOW";
      bool limit=d.state=="WAIT_RETRACE" && EnableSmartPendingLimits;
      bool fast=FastEntryOk(d);
      PanelGate(r,8,exec||limit||fast,d.state+" score "+F0(d.execScore)+(exec?" : entree immediate":fast?" : entree rapide":limit?" : ordre limite EMA20 H1":""));
   }
}

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
   ArrayResize(g_rows,n+1);
   PanelFromDecision(g_rows[n],g_decisions[n]);
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

bool TryMarketEntry(const SwxDecision &d,const bool can_trade,PanelRow &r)
{
   bool fast=d.state!="EXECUTE_NOW" && FastEntryOk(d);
   if(!can_trade || !IsSignal(d.verdict) || (d.state!="EXECUTE_NOW" && !fast)) return false;
   if(StoredLevel("SWX_TRADEDBAR_",d.symbol)==(double)d.barTime)   // un trade par signal
   { if(r.decision=="") r.decision="SIGNAL DEJA TRADE : une seule entree par bougie H1 de signal"; return false; }
   bool on_symbol=OnePositionPerSymbol && HasSeraPositionOn(d.symbol);
   bool capacity=OpenSeraPositions()<AllowedOpenPositions() && TradesToday()<AllowedTradesPerDay() && !on_symbol;
   PanelGate(r,9,capacity,on_symbol?"deja une position Sera sur cet indice":
             OpenSeraPositions()>=AllowedOpenPositions()?"positions max "+IntegerToString(AllowedOpenPositions())+" (selon la balance)":
             TradesToday()>=AllowedTradesPerDay()?"trades du jour max "+IntegerToString(AllowedTradesPerDay()):
             "positions "+PositionsText());
   if(!capacity) return false;
   MqlTick tick;
   if(!SymbolInfoTick(d.symbol,tick)){ PanelGate(r,10,false,"pas de prix du broker"); return false; }
   double price=d.verdict=="BUY"?tick.ask:tick.bid;
   double risk_distance=MathAbs(d.entry-d.sl);
   if(risk_distance<=0){ PanelGate(r,10,false,"stop loss invalide"); return false; }
   double spread=MathAbs(tick.ask-tick.bid);
   bool spread_ok=spread<=risk_distance*(MaximumSpreadRiskPercent/100.0);
   bool chase_ok=d.verdict=="BUY"?price<=d.entry+risk_distance*(MaximumEntryChaseRiskPercent/100.0)
                                 :price>=d.entry-risk_distance*(MaximumEntryChaseRiskPercent/100.0);
   double final_tp=(DynamicFinalTarget && d.score>=88 && d.tp4>0)?d.tp4:d.tp3;
   bool levels_ok=d.verdict=="BUY"?(d.sl<price && final_tp>price):(d.sl>price && final_tp<price);
   bool stops_ok=levels_ok && BrokerStopsValid(d.symbol,d.verdict,price,d.sl,final_tp);
   PanelGate(r,10,spread_ok && chase_ok && stops_ok,!spread_ok?"spread trop large pour le risque":!chase_ok?"prix trop loin de l'entree calculee":
             !levels_ok?"niveaux depasses par le prix":!stops_ok?"SL/TP trop proches pour le broker":"prix "+FormatPrice(d.symbol,price));
   if(!spread_ok){ PrintOnce("SyntX: "+d.symbol+" spread trop large pour le risque"); return false; }
   if(!chase_ok){ PrintOnce("SyntX: "+d.symbol+" prix trop eloigne de l'entree calculee"); return false; }
   if(!stops_ok) return false;
   double volume=SafeVolume(d.symbol,price,d.sl);
   if(volume<=0)
   { PanelGate(r,11,false,"volume nul (lot minimum superieur au risque)"); PrintOnce("SyntX: "+d.symbol+" volume nul (lot minimum superieur au risque autorise)"); return false; }
   double margin=0.0;
   if(!OrderCalcMargin(d.verdict=="BUY"?ORDER_TYPE_BUY:ORDER_TYPE_SELL,d.symbol,volume,price,margin) || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)*0.50)
   { PanelGate(r,11,false,"marge libre insuffisante"); PrintOnce("SyntX: "+d.symbol+" marge libre insuffisante"); return false; }
   if(!TotalRiskAllows(PositionRiskUSD(d.symbol,d.verdict=="BUY"?POSITION_TYPE_BUY:POSITION_TYPE_SELL,price,d.sl,volume)))
   { PanelGate(r,11,false,"risque total maximum atteint"); PrintOnce("SyntX: "+d.symbol+" reporte — risque cumule maximum atteint"); return false; }
   PanelGate(r,11,true,"lot "+DoubleToString(volume,2));

   CancelSeraPendingOrder(d.symbol,"ordre au marche EXECUTE_NOW");
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(DeviationPoints);
   bool sent=d.verdict=="BUY"?trade.Buy(volume,d.symbol,0,d.sl,final_tp,"Sera Weltrade v1.60"):trade.Sell(volume,d.symbol,0,d.sl,final_tp,"Sera Weltrade v1.60");
   if(!sent)
   {
      r.decision="ORDRE REFUSE PAR LE BROKER : "+trade.ResultRetcodeDescription();
      Print("SyntX: ordre refuse ",d.symbol," ",trade.ResultRetcodeDescription());
      return false;
   }
   StoreLevel("SWX_TRADEDBAR_",d.symbol,(double)d.barTime);
   StoreLevel("SWX_CONF_",d.symbol,d.confidence);
   StoreTradeLevels(d.symbol,d.symbol,d.entry,d.tp1,d.tp2,d.tp3,d.tp4,d.tp5,final_tp,"swing");
   r.opened=true;
   r.decision="POSITION "+d.verdict+" OUVERTE"+(fast?" (entree rapide)":"")+" : lot "+DoubleToString(volume,2)+"  SL "+FormatPrice(d.symbol,d.sl)+"  TP "+FormatPrice(d.symbol,final_tp);
   SendSwxAlert("SyntX: "+d.verdict+" "+d.symbol+" "+DoubleToString(volume,2)+" lot · SL "+FormatPrice(d.symbol,d.sl)+" · score "+DoubleToString(d.score,0));
   return true;
}

// Signal confirme mais prix etendu : ordre limite dans la zone EMA20 H1.
bool ManagePendingEntry(const SwxDecision &d,const bool can_trade,PanelRow &r)
{
   if(!EnableSmartPendingLimits) return false;
   bool confirming=PendingWhileConfirming && d.state=="WAIT_CONFIRMATION" && !FastEntryOk(d);
   bool limit_state=can_trade && (d.state=="WAIT_RETRACE" || confirming) && IsSignal(d.verdict);
   bool on_symbol=OnePositionPerSymbol && HasSeraPositionOn(d.symbol);
   bool capacity=OpenSeraPositions()<AllowedOpenPositions() && !on_symbol
      && (FindSeraPendingOrder(d.symbol)>0 || OpenSeraPendingOrders()<AllowedPendingOrders());
   if(limit_state) PanelGate(r,9,capacity,on_symbol?"deja une position Sera sur cet indice":!capacity?"nombre maximum d'ordres / positions atteint":"");
   if(!limit_state || !capacity)
   {
      if(FindSeraPendingOrder(d.symbol)>0)
      {
         // Risque de changement detecte avant l'execution de l'ordre : on annule d'abord.
         string risk="";
         if(d.state=="BLOCKED_RISK") risk="risque de spike ou de retournement";
         else if(!IsSignal(d.verdict)) risk="le signal a disparu"+(PanelFirstBlock(r)!=""?" ("+PanelFirstBlock(r)+")":"");
         else if(CancelPendingOnRisk && (d.entrySide!=d.verdict || d.confSide!=d.verdict)) risk="H1/H4 se retournent";
         if(risk!="")
         {
            CancelSeraPendingOrder(d.symbol,"risque de changement : "+risk);
            r.decision="ORDRE LIMITE ANNULE avant execution : "+risk;
         }
         else if(d.state=="EXECUTE_NOW") CancelSeraPendingOrder(d.symbol,"passage EXECUTE_NOW");
      }
      return false;
   }
   double entry=d.zoneEntry;
   double final_tp=(DynamicFinalTarget && d.score>=88 && d.tp4>0)?d.tp4:d.tp3;
   bool stops_ok=BrokerStopsValid(d.symbol,d.verdict,entry,d.sl,final_tp);
   PanelGate(r,10,stops_ok,stops_ok?"entree limite "+FormatPrice(d.symbol,entry):"SL/TP trop proches pour le broker");
   if(!stops_ok) return false;
   double volume=SafeVolume(d.symbol,entry,d.sl);
   bool had_order=FindSeraPendingOrder(d.symbol)>0;
   bool risk_ok=volume>0 && (had_order ||
      TotalRiskAllows(PositionRiskUSD(d.symbol,d.verdict=="BUY"?POSITION_TYPE_BUY:POSITION_TYPE_SELL,entry,d.sl,volume)));
   PanelGate(r,11,risk_ok,volume<=0?"volume nul (lot minimum ou SL)":!risk_ok?"risque total maximum atteint":"lot "+DoubleToString(volume,2));
   if(!risk_ok) return false;
   if(PlaceOrUpdatePendingLimit(d.symbol,d.symbol,d.verdict,entry,d.sl,final_tp,volume))
   {
      StoreTradeLevels(d.symbol,d.symbol,entry,d.tp1,d.tp2,d.tp3,d.tp4,d.tp5,final_tp,"swing");
      StoreLevel("SWX_CONF_",d.symbol,d.confidence);
      r.decision="ORDRE LIMITE "+d.verdict+(had_order?" EN PLACE":" PLACE")+" a "+FormatPrice(d.symbol,entry)+" (lot "+DoubleToString(volume,2)+")";
      return true;
   }
   r.decision="ORDRE LIMITE NON PLACE : le prix a deja atteint la zone ou le broker refuse";
   return false;
}

// ---------- Tableau de bord : affichage ----------
color Rgb(const int r,const int g,const int b){ return (color)(r|(g<<8)|(b<<16)); }

int g_panel_maxlen=0;
void PanelText(const int line,const string text,const color clr,const int size=9)
{
   if(StringLen(text)>g_panel_maxlen) g_panel_maxlen=StringLen(text);
   string name="SWX_PANEL_L"+IntegerToString(line);
   if(ObjectFind(0,name)<0)
   {
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
   }
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,DashboardX+10);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,DashboardY+8+line*16);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
}

void PanelBackground(const int lines)
{
   string name="SWX_PANEL_BG";
   if(ObjectFind(0,name)<0)
   {
      ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   }
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,DashboardX);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,DashboardY);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,(int)MathMax(420,g_panel_maxlen*7+24));
   ObjectSetInteger(0,name,OBJPROP_YSIZE,lines*16+14);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,Rgb(10,20,32));
   ObjectSetInteger(0,name,OBJPROP_COLOR,Rgb(40,70,100));
}

void PanelClear(){ ObjectsDeleteAll(0,"SWX_PANEL_"); }

// Boutons + / - du tableau : nombre de positions possibles affichees (memorise dans MT5 par EA).
#define PANEL_STEP 5
string PanelShownKey(){ return "SWX_PANEL_SHOWN_"+IntegerToString((long)MagicNumber); }

int PanelSetupsShown()
{
   if(GlobalVariableCheck(PanelShownKey())) return (int)GlobalVariableGet(PanelShownKey());
   return (int)MathMax(0,DashboardMaxSetups);
}

void PanelButton(const string name,const string text,const int x,const int line)
{
   if(ObjectFind(0,name)<0)
   {
      ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,10);
   }
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,DashboardY+8+line*16-1);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,28);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,17);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,Rgb(32,60,92));
   ObjectSetInteger(0,name,OBJPROP_COLOR,Rgb(220,232,245));
   ObjectSetInteger(0,name,OBJPROP_STATE,false);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
}

// [-] [+] (lignes par page) et [<] [>] (pages) sur la ligne de titre des positions possibles.
void PanelSetupButtons(const int line)
{
   int x=DashboardX+10+SWX_BAR_COLUMN*7;
   PanelButton("SWX_PANEL_BTN_MINUS","-",x,line);
   PanelButton("SWX_PANEL_BTN_PLUS","+",x+34,line);
   PanelButton("SWX_PANEL_BTN_PREV","<",x+76,line);
   PanelButton("SWX_PANEL_BTN_NEXT",">",x+110,line);
   if(SWX_BAR_COLUMN+22>g_panel_maxlen) g_panel_maxlen=SWX_BAR_COLUMN+22;
}

string PanelPageKey(){ return "SWX_PANEL_PAGE_"+IntegerToString((long)MagicNumber); }

int PanelPage()
{
   if(GlobalVariableCheck(PanelPageKey())) return (int)MathMax(0,GlobalVariableGet(PanelPageKey()));
   return 0;
}

// MT5 ne fait pas defiler les objets du graphique : la liste est limitee a ce qui tient a l'ecran.
int PanelFitRows(const int line_now)
{
   long height=ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   if(height<=0) return 1000;
   int total=(int)((height-DashboardY-8)/16);
   int reserve=ShowEntryChecks?19:2;          // ligne "autres pages" + detail des controles
   return (int)MathMax(3,total-line_now-reserve);
}

// Page affichee (bornee au nombre de pages) et texte du titre.
int PanelClampPage(const int limit,const int count)
{
   int pages=limit>0?(count+limit-1)/limit:1;
   int page=(int)MathMin(PanelPage(),MathMax(0,pages-1));
   if(page!=PanelPage()) GlobalVariableSet(PanelPageKey(),page);
   return page;
}

string PanelPageText(const int limit,const int count,const int page)
{
   if(limit<=0) return "liste repliee (bouton +)";
   int pages=(count+limit-1)/limit;
   return "page "+IntegerToString(page+1)+"/"+IntegerToString((int)MathMax(1,pages))+" ("+IntegerToString(limit)+" par page)";
}


string Pad(const string text,const int width)
{
   string out=StringLen(text)>width?StringSubstr(text,0,width):text;
   while(StringLen(out)<width) out+=" ";
   return out;
}

// Barre de certitude : fond gris + remplissage proportionnel, alignee a droite des lignes du tableau.
int g_bar_count=0;
void PanelBar(const int line,const double percent,const color clr)
{
   int x=DashboardX+10+SWX_BAR_COLUMN*7;
   int y=DashboardY+8+line*16+3;
   string names[2];
   names[0]="SWX_PANEL_B"+IntegerToString(g_bar_count)+"_BG";
   names[1]="SWX_PANEL_B"+IntegerToString(g_bar_count)+"_FG";
   g_bar_count++;
   for(int k=0;k<2;k++)
   {
      if(ObjectFind(0,names[k])<0)
      {
         ObjectCreate(0,names[k],OBJ_RECTANGLE_LABEL,0,0,0);
         ObjectSetInteger(0,names[k],OBJPROP_CORNER,CORNER_LEFT_UPPER);
         ObjectSetInteger(0,names[k],OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,names[k],OBJPROP_HIDDEN,true);
         ObjectSetInteger(0,names[k],OBJPROP_BORDER_TYPE,BORDER_FLAT);
      }
      double pct=MathMax(0.0,MathMin(100.0,percent));
      ObjectSetInteger(0,names[k],OBJPROP_XDISTANCE,x);
      ObjectSetInteger(0,names[k],OBJPROP_YDISTANCE,y);
      ObjectSetInteger(0,names[k],OBJPROP_XSIZE,k==0?100:(int)MathMax(1,pct));
      ObjectSetInteger(0,names[k],OBJPROP_YSIZE,9);
      ObjectSetInteger(0,names[k],OBJPROP_BGCOLOR,k==0?Rgb(32,44,60):clr);
      ObjectSetInteger(0,names[k],OBJPROP_COLOR,k==0?Rgb(32,44,60):clr);
   }
   if(SWX_BAR_COLUMN+16>g_panel_maxlen) g_panel_maxlen=SWX_BAR_COLUMN+16;
}

color CertaintyColor(const double pct)
{
   if(pct>=85) return Rgb(56,232,187);
   if(pct>=75) return Rgb(77,163,255);
   return Rgb(255,190,80);
}

// Certitude d'un ordre / d'une position : analyse actuelle de l'indice, sinon celle enregistree a l'entree.
double SymbolCertainty(const string symbol)
{
   for(int i=0;i<ArraySize(g_rows);i++)
      if(g_rows[i].symbol==symbol && g_rows[i].valid && IsSignal(g_rows[i].verdict)) return g_rows[i].confidence;
   return StoredLevel("SWX_CONF_",symbol);
}

// Avancement vers un signal tradable : le plus faible entre score/84, consensus/72 % et conditions/80 %.
double RowProgress(const PanelRow &r)
{
   if(!r.valid) return 0;
   return MathMin(100.0,MathMin(r.score/84.0*100.0,MathMin(r.consensus/72.0*100.0,r.conditions/80.0*100.0)));
}

double RowRank(const PanelRow &r)
{
   double bonus=IsSignal(r.verdict)?1000:0;
   if(r.state=="EXECUTE_NOW") bonus+=2000;
   if(r.opened) bonus+=10000;
   return bonus+RowProgress(r)*10+r.score/100.0;
}

// Ce qui manque encore avant une entree, en quelques mots.
string MissingShort(const PanelRow &r)
{
   if(!r.valid) return "historique insuffisant";
   if(IsSignal(r.verdict))
   {
      if(r.state=="WAIT_RETRACE") return "retour zone EMA20 H1";
      if(r.state=="WAIT_CONFIRMATION") return "score d'execution";
   }
   for(int i=0;i<SWX_GATES;i++) if(r.gate[i]==0) return StringSubstr(g_gate_names[i],0,24);
   return "entree au prochain cycle";
}

// Tableau des ordres limites et positions Sera ouverts. Renvoie la ligne suivante.
int RenderOrders(int line)
{
   color grey=Rgb(130,148,168),green=Rgb(56,232,187),red=Rgb(255,95,118),blue=Rgb(77,163,255);
   int sera=0,foreign=0;
   for(int i=0;i<PositionsTotal();i++){ ulong t=PositionGetTicket(i); if(t>0){ if(PositionGetInteger(POSITION_MAGIC)==MagicNumber) sera++; else foreign++; } }
   for(int i=0;i<OrdersTotal();i++){ ulong t=OrderGetTicket(i); if(t>0){ if(OrderGetInteger(ORDER_MAGIC)==MagicNumber) sera++; else foreign++; } }
   PanelText(line++,"",grey);
   PanelText(line++,"ORDRES ET POSITIONS SERA WELTRADE ("+IntegerToString(sera)+")",Rgb(255,190,80));
   if(sera==0) PanelText(line++,"  Aucun ordre ni position Sera pour le moment.",grey);
   else PanelText(line++,"  "+Pad("Indice",27)+Pad("Type",11)+Pad("Entree",12)+Pad("SL",12)+Pad("TP",12)+Pad("Lot",6)+Pad("Etat / resultat",19)+"Certitude",grey);
   int shown=0;
   for(int i=0;i<PositionsTotal() && shown<DashboardMaxOrders;i++)
   {
      ulong t=PositionGetTicket(i);
      if(t<=0 || PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      string sym=PositionGetString(POSITION_SYMBOL);
      bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
      double profit=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      double open=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL);
      bool secured=sl>0 && (buy?sl>=open:sl<=open);
      string state=(profit>=0?"+":"")+DoubleToString(profit,2)+(secured?" SL securise":"");
      double cert=SymbolCertainty(sym);
      PanelText(line,"  "+Pad(sym,27)+Pad(buy?"BUY":"SELL",11)+Pad(FormatPrice(sym,open),12)+Pad(FormatPrice(sym,sl),12)+
                Pad(FormatPrice(sym,PositionGetDouble(POSITION_TP)),12)+Pad(DoubleToString(PositionGetDouble(POSITION_VOLUME),2),6)+
                Pad(state,19)+(cert>0?DoubleToString(cert,0)+"%":"-"),profit>=0?green:red);
      if(cert>0) PanelBar(line,cert,CertaintyColor(cert));
      line++; shown++;
   }
   for(int i=0;i<OrdersTotal() && shown<DashboardMaxOrders;i++)
   {
      ulong t=OrderGetTicket(i);
      if(t<=0 || OrderGetInteger(ORDER_MAGIC)!=MagicNumber) continue;
      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type!=ORDER_TYPE_BUY_LIMIT && type!=ORDER_TYPE_SELL_LIMIT) continue;
      string sym=OrderGetString(ORDER_SYMBOL);
      double entry=OrderGetDouble(ORDER_PRICE_OPEN);
      MqlTick tick;
      string state="en attente";
      if(SymbolInfoTick(sym,tick) && entry>0)
      {
         double px=type==ORDER_TYPE_BUY_LIMIT?tick.ask:tick.bid;
         state="prix a "+DoubleToString(MathAbs(px-entry)/entry*100.0,2)+"%";
      }
      double cert=SymbolCertainty(sym);
      PanelText(line,"  "+Pad(sym,27)+Pad(type==ORDER_TYPE_BUY_LIMIT?"BUY LIMIT":"SELL LIMIT",11)+Pad(FormatPrice(sym,entry),12)+
                Pad(FormatPrice(sym,OrderGetDouble(ORDER_SL)),12)+Pad(FormatPrice(sym,OrderGetDouble(ORDER_TP)),12)+
                Pad(DoubleToString(OrderGetDouble(ORDER_VOLUME_CURRENT),2),6)+Pad(state,19)+(cert>0?DoubleToString(cert,0)+"%":"-"),blue);
      if(cert>0) PanelBar(line,cert,CertaintyColor(cert));
      line++; shown++;
   }
   if(sera>shown) PanelText(line++,"  ... et "+IntegerToString(sera-shown)+" autre(s)",grey);
   if(foreign>0) PanelText(line++,"  Attention : "+IntegerToString(foreign)+" ordre(s)/position(s) d'un autre EA ou manuel(s) sur ce compte",red);
   return line;
}

// Positions possibles : indices analyses qui n'ont pas encore d'ordre ni de position.
int RenderPossible(int line)
{
   color white=Rgb(220,232,245),grey=Rgb(130,148,168),cyan=Rgb(84,216,255);
   int count=0;
   for(int i=0;i<ArraySize(g_rows);i++)
      if(g_rows[i].valid && FindSeraPendingOrder(g_rows[i].symbol)==0 && !HasSeraPositionOn(g_rows[i].symbol)) count++;
   PanelText(line++,"",grey);
   int limit=(int)MathMin(PanelSetupsShown(),PanelFitRows(line+3));
   int page=PanelClampPage(limit,count);
   int skip=page*limit;
   PanelSetupButtons(line);
   PanelText(line++,"POSITIONS POSSIBLES ("+IntegerToString(count)+") : indices analyses, les plus avances d'abord  |  "+PanelPageText(limit,count,page),Rgb(255,190,80));
   if(count==0){ PanelText(line++,"  Aucun indice analyse sans ordre pour le moment.",grey); return line; }
   PanelText(line++,"  "+Pad("Indice",23)+Pad("Sens",12)+Pad("Etat",19)+Pad("Conditions",11)+Pad("Consensus",10)+Pad("Ce qu'il manque",24)+"Score / 84",grey);
   int order[];
   ArrayResize(order,ArraySize(g_rows));
   for(int i=0;i<ArraySize(g_rows);i++) order[i]=i;
   for(int a=0;a<ArraySize(order);a++)
      for(int b=a+1;b<ArraySize(order);b++)
         if(RowRank(g_rows[order[b]])>RowRank(g_rows[order[a]])){ int t=order[a]; order[a]=order[b]; order[b]=t; }
   int shown=0;
   for(int k=0;k<ArraySize(order) && shown<limit;k++)
   {
      PanelRow r=g_rows[order[k]];
      if(!r.valid || FindSeraPendingOrder(r.symbol)>0 || HasSeraPositionOn(r.symbol)) continue;
      if(skip>0){ skip--; continue; }
      bool signal=IsSignal(r.verdict);
      string side=signal?r.verdict:(r.side!="NEUTRE"?"biais "+r.side:"neutre");
      PanelText(line,"  "+Pad(r.symbol,23)+Pad(side,12)+Pad(r.state,19)+Pad(DoubleToString(r.conditions,0)+"%",11)+
                Pad(DoubleToString(r.consensus,0)+"%",10)+Pad(MissingShort(r),24)+DoubleToString(r.score,0)+" / 84",signal?white:cyan);
      double progress=RowProgress(r);
      PanelBar(line,progress,progress>=100?Rgb(56,232,187):progress>=90?Rgb(77,163,255):Rgb(255,190,80));
      line++; shown++;
   }
   if(count>shown)
      PanelText(line++,"  ... et "+IntegerToString(count-shown)+" autre(s)"+(limit<=0?" : bouton + pour les afficher":" sur les autres pages : boutons < et >"),grey);
   return line;
}

// Indice mis en avant : position ouverte ce cycle, sinon EXECUTE_NOW, sinon le plus avance.
int PanelFocus()
{
   int best=-1;
   double bestRank=-1;
   for(int i=0;i<ArraySize(g_rows);i++)
   {
      if(!g_rows[i].valid) continue;
      double rank=RowRank(g_rows[i]);
      if(rank>bestRank){ bestRank=rank; best=i; }
   }
   return best;
}

void RenderDashboard(const bool can_trade,const string mode_label)
{
   if(!ShowDashboard){ PanelClear(); return; }
   color white=Rgb(220,232,245),grey=Rgb(130,148,168),green=Rgb(56,232,187),red=Rgb(255,95,118),
         amber=Rgb(255,190,80),cyan=Rgb(84,216,255),blue=Rgb(77,163,255);
   int line=0;
   g_panel_maxlen=0;
   g_bar_count=0;
   // Le fond est cree en premier (MT5 dessine le dernier objet cree au-dessus) puis redimensionne a la fin.
   if(ObjectFind(0,"SWX_PANEL_BG")<0){ PanelClear(); PanelBackground(1); }
   bool algo=TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED);

   PanelText(line++,"SERA EA SWING INTELLIGENT WELTRADE v1.60",amber,10);
   if(can_trade) PanelText(line++,"BOT ACTIF  |  compte "+mode_label+"  |  trading automatique autorise",green);
   else if(!algo) PanelText(line++,"BOT EN PAUSE  |  activez le bouton Algo Trading de MT5",red);
   else if(g_trade_block!="") PanelText(line++,"BOT EN PAUSE  |  "+g_trade_block,red);
   else PanelText(line++,"BOT EN PAUSE  |  trading automatique desactive dans les parametres",red);

   int n=ArraySize(g_rows),valid=0,setups=0,signals=0;
   for(int i=0;i<n;i++)
   {
      if(!g_rows[i].valid) continue;
      valid++;
      if(g_rows[i].side!="NEUTRE") setups++;
      if(IsSignal(g_rows[i].verdict)) signals++;
   }
   if(n==0) PanelText(line++,"Analyse : aucun indice Weltrade trouve -> renseignez SymbolsList (ex: GainX 800,PainX 800)",red);
   else
   {
      MqlDateTime t; TimeToStruct(g_last_analysis,t);
      string at="-";
      if(g_last_analysis>0) at=(t.hour<10?"0":"")+IntegerToString(t.hour)+":"+(t.min<10?"0":"")+IntegerToString(t.min);
      PanelText(line++,"Analyse dans MT5 (sans internet) : "+IntegerToString(valid)+"/"+IntegerToString(n)+" indices  |  "+IntegerToString(setups)+
                " tendances alignees  |  "+IntegerToString(signals)+" signaux  |  derniere bougie H1 "+at,valid>0?green:amber);
   }
   double balance=AccountInfoDouble(ACCOUNT_BALANCE),equity=AccountInfoDouble(ACCOUNT_EQUITY),risk=OpenSeraRiskUSD();
   PanelText(line++,"Compte : balance "+DoubleToString(balance,2)+"  equite "+DoubleToString(equity,2)+"  |  positions "+
             PositionsText()+"  |  risque ouvert "+DoubleToString(risk,2)+" ("+
             DoubleToString(equity>0?risk/equity*100.0:0.0,1)+"% / max "+DoubleToString(MaximumTotalOpenRiskPercent,0)+"%)",white);
   PanelText(line++,"Horizon : Swing H1/H4/D1  |  risque "+DoubleToString(RiskPercent,2)+"% par trade  |  controle toutes les "+
             IntegerToString(MathMax(15,PollEverySeconds))+" s",grey);

   line=RenderOrders(line);
   line=RenderPossible(line);

   int focus=ShowEntryChecks?PanelFocus():-1;
   if(ShowEntryChecks && focus>=0)
   {
      PanelRow r=g_rows[focus];
      PanelText(line++,"",grey);
      string side=IsSignal(r.verdict)?r.verdict:(r.side!="NEUTRE"?"biais "+r.side:"setup");
      PanelText(line++,"INDICE SUIVI (detail des controles) : "+r.symbol+"  |  "+side+"  |  "+r.state+"  |  "+r.setup,
                r.verdict=="BUY"?blue:r.verdict=="SELL"?red:cyan);
      PanelText(line++,"Score "+DoubleToString(r.score,0)+"   confiance "+DoubleToString(r.confidence,0)+"%   consensus "+DoubleToString(r.consensus,0)+
                "%   conditions "+DoubleToString(r.conditions,0)+"%   score d'execution "+DoubleToString(r.exec_score,0),white);
      PanelText(line++,"Controles avant d'ouvrir la position :",grey);
      for(int g=0;g<SWX_GATES;g++)
      {
         string mark=r.gate[g]==1?"[OK] ":r.gate[g]==0?"[NON]":"[ - ]";
         color c=r.gate[g]==1?green:r.gate[g]==0?red:grey;
         string detail=r.detail[g]!=""?" : "+r.detail[g]:"";
         PanelText(line++,"  "+mark+" "+g_gate_names[g]+detail,c);
      }
      PanelText(line++,"DECISION : "+r.decision,r.opened?green:(StringFind(r.decision,"LIMITE")>=0?blue:amber),10);
   }
   PanelBackground(line);
   for(int k=line;k<400;k++){ string name="SWX_PANEL_L"+IntegerToString(k); if(ObjectFind(0,name)>=0) ObjectDelete(0,name); }
   for(int k=g_bar_count;k<400;k++)
   {
      string bg="SWX_PANEL_B"+IntegerToString(k)+"_BG",fg="SWX_PANEL_B"+IntegerToString(k)+"_FG";
      if(ObjectFind(0,bg)>=0) ObjectDelete(0,bg);
      if(ObjectFind(0,fg)>=0) ObjectDelete(0,fg);
   }
   ChartRedraw(0);
}

// Controles, ordres et decision d'un indice deja analyse. entered : une seule entree au marche par cycle.
void ProcessDecision(const int i,const bool can_trade,bool &entered)
{
   PanelFromDecision(g_rows[i],g_decisions[i]);
   if(!g_decisions[i].valid) return;
   bool signal=IsSignal(g_decisions[i].verdict);
   ManagePendingEntry(g_decisions[i],can_trade,g_rows[i]);
   if(!entered) entered=TryMarketEntry(g_decisions[i],can_trade,g_rows[i]);
   else if(signal && (g_decisions[i].state=="EXECUTE_NOW" || FastEntryOk(g_decisions[i])) && g_rows[i].decision=="")
      g_rows[i].decision="ENTREE AU PROCHAIN CYCLE (une entree au marche par cycle)";
   if(g_rows[i].decision!="") return;
   if(HasSeraPositionOn(g_rows[i].symbol)) g_rows[i].decision="POSITION SERA OUVERTE : geree (TP1, break-even, coupure si retournement)";
   else if(!signal) g_rows[i].decision="PAS D'ENTREE : "+PanelFirstBlock(g_rows[i]);
   else if(!can_trade) g_rows[i].decision="SIGNAL "+g_decisions[i].verdict+" : alerte seulement (trading automatique en pause)";
   else if(PanelFirstBlock(g_rows[i])!="") g_rows[i].decision="EN ATTENTE : "+PanelFirstBlock(g_rows[i]);
   else g_rows[i].decision="EN ATTENTE : "+g_decisions[i].state;
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
   g_trade_block=circuit?"limite de perte du jour / pertes consecutives atteinte (reprise automatique)":
                 (real && !AllowRealAccount)?"compte reel non autorise (AllowRealAccount)":"";

   bool entered=false;
   for(int i=0;i<ArraySize(g_symbols);i++)
   {
      string symbol=g_symbols[i];
      datetime bar=iTime(symbol,PERIOD_H1,1);
      if(bar==0){ PanelFromDecision(g_rows[i],g_decisions[i]); continue; }
      if(bar!=g_lastBar[i] || !g_decisions[i].valid)
      {
         string before=g_decisions[i].verdict;
         Decide(symbol,g_decisions[i]);
         g_lastBar[i]=bar;
         if(bar>g_last_analysis) g_last_analysis=bar;
         if(g_decisions[i].valid)
         {
            AnalysisReversalExit(g_decisions[i]);
            string now=g_decisions[i].verdict;
            if(EnableTrendWatch && now!=before && IsSignal(now))
               SendSwxAlert("SyntX: signal "+now+" "+symbol+" · score "+DoubleToString(g_decisions[i].score,0)+" · "+g_decisions[i].state);
         }
      }
      ProcessDecision(i,can_trade,entered);
   }
   g_dash_can_trade=can_trade; g_dash_mode=mode_label;
   RenderDashboard(can_trade,mode_label);
}

int OnInit()
{
   trade.SetAsyncMode(false);
   RefreshSymbols();
   EventSetTimer(MathMax(15,PollEverySeconds));
   Print("Sera EA Swing Intelligent Weltrade v1.60: ",ArraySize(g_symbols)," indices detectes, auto=",EnableAutomaticTrading,
         ", reel=",AllowRealAccount,", plafond positions=",MaximumOpenPositionsCap,
         ", risque cumule max=",DoubleToString(MaximumTotalOpenRiskPercent,1),"%");
   if(ArraySize(g_symbols)==0)
      Print("SyntX: aucun indice Weltrade trouve. Renseignez SymbolsList (ex: GainX 800,PainX 800,SFX Vol 40).");
   ScanAndTrade();   // tableau de bord affiche tout de suite
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){ EventKillTimer(); PanelClear(); Comment(""); }

void OnTimer()
{
   if(EmergencyEquityStop()) return;
   ManageAllSeraPositions();
   CutReversedPositions();
   ScanAndTrade();
}

void RedrawDashboard(){ RenderDashboard(g_dash_can_trade,g_dash_mode); }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id!=CHARTEVENT_OBJECT_CLICK) return;
   if(StringFind(sparam,"SWX_PANEL_BTN_")!=0) return;
   if(sparam=="SWX_PANEL_BTN_NEXT") GlobalVariableSet(PanelPageKey(),PanelPage()+1);
   else if(sparam=="SWX_PANEL_BTN_PREV") GlobalVariableSet(PanelPageKey(),MathMax(0,PanelPage()-1));
   else
   {
      int shown=PanelSetupsShown();
      if(sparam=="SWX_PANEL_BTN_PLUS") shown=(int)MathMin(shown+PANEL_STEP,MathMax(PANEL_STEP,ArraySize(g_rows)));
      else shown=(int)MathMax(0,shown-PANEL_STEP);
      GlobalVariableSet(PanelShownKey(),shown);
      GlobalVariableSet(PanelPageKey(),0);
   }
   ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
   RedrawDashboard();
}
