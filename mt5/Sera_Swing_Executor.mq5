#property copyright "Sera Indicator"
#property version   "1.60"
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
input double MaximumLossUSD=1.00;
input double MaximumLot=0.02;
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
input int MaximumTradesPerDay=2;
input double MaximumDailyLossUSD=3.00;
input double MaximumDailyDrawdownPercent=3.00;
input int MaximumConsecutiveLosses=2;
input double MinimumFreeMarginPercent=25.0;
input bool EnforceBrokerStopsLevel=true;
input int PollEverySeconds=30;
input long MagicNumber=26091801;
input int DeviationPoints=30;

CTrade trade;
datetime last_poll=0;

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

double SafeVolume(const string symbol,const double entry,const double sl)
{
   double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   double tick_value=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
   double min_lot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double max_lot=MathMin(SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX),MaximumLot);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(tick_size<=0 || tick_value<=0 || step<=0 || MathAbs(entry-sl)<=0) return 0;
   double risk=MathMin(AccountInfoDouble(ACCOUNT_BALANCE)*RiskPercent/100.0,MaximumLossUSD);
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

void Evaluate(const string json)
{
   string status=JsonString(json,"status");
   if(status!="ai_analyzed" && status!="autonomous_analyzed" && status!="smart_local"){ Comment("Sera: aucun signal final autonome confirme"); return; }
   datetime generated=ParseIsoUtc(JsonString(json,"updated_at"));
   if(generated==0 || TimeGMT()-generated>MaximumSignalAgeMinutes*60){ Comment("Sera Trend Watch: signal global expire"); return; }

   bool source_allows_trade=(status=="ai_analyzed")||(status=="autonomous_analyzed"&&AllowAutonomousExecution)||(status=="smart_local"&&AllowAutonomousExecution);
   bool can_trade=EnableAutomaticTrading&&source_allows_trade&&!RiskCircuitOpen();
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
                     trade.SetExpertMagicNumber(MagicNumber);
                     trade.SetDeviationInPoints(DeviationPoints);
                     bool sent=verdict=="BUY"?trade.Buy(volume,symbol,0,sl,final_tp,"Sera Swing v1.60"):trade.Sell(volume,symbol,0,sl,final_tp,"Sera Swing v1.60");
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
   Comment("Sera v1.60 — "+mode+" — EXECUTE_NOW + OSS + Risk Circuit");
   Print("Sera v1.60: compte ",mode,", auto=",EnableAutomaticTrading,", reel=",AllowRealAccount,", conditions min=",MinimumAutonomousConditionsPercent,"%, execution score min=",MinimumExecutionScore,", OSS guard=",UseOpenSourceModelGuard,", smart management=",EnableSmartPositionManagement,", daily loss max=",MaximumDailyLossUSD);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){ EventKillTimer(); Comment(""); }
void OnTimer(){ string json; if(FetchSignals(json)) Evaluate(json); }
