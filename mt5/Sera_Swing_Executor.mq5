#property copyright "Sera Indicator"
#property version   "1.30"
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
input int MaximumSignalAgeMinutes=90;
input int MaximumOpenPositions=1;
input int MaximumTradesPerDay=2;
input int PollEverySeconds=60;
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

int TradesToday()
{
   datetime now=TimeCurrent(); MqlDateTime part; TimeToStruct(now,part);
   part.hour=0; part.min=0; part.sec=0; datetime start=StructToTime(part);
   if(!HistorySelect(start,now)) return 0;
   int total=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket>0 && HistoryDealGetInteger(ticket,DEAL_MAGIC)==MagicNumber && HistoryDealGetInteger(ticket,DEAL_ENTRY)==DEAL_ENTRY_IN) total++;
   }
   return total;
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

int VerdictState(const string verdict)
{
   if(verdict=="BUY") return 1;
   if(verdict=="SELL") return -1;
   return 0;
}

void SendTrendAlert(const string market,const string verdict,const double confidence)
{
   if(!EnableTrendWatch) return;
   string message="Sera Trend Watch: "+market+" "+verdict+" Swing H1/H4 confirme a "+DoubleToString(confidence,0)+"%";
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
   bool can_trade=EnableAutomaticTrading&&source_allows_trade;
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
      if(mode=="swing")
      {
         string setup_id=JsonString(object,"id");
         string market_name=JsonString(object,"market");
         string deriv_code=JsonString(object,"symbol");
         string symbol=ResolveTradeSymbol(market_name,deriv_code);
         int state=VerdictState(verdict);
         bool confirmed=(state!=0 && confidence>=MinimumConfidence);

         int previous_alert_state=StoredState("SERA_ALERTSTATE_",setup_id);
         if(confirmed && state!=previous_alert_state) SendTrendAlert(market_name,verdict,confidence);
         if(state!=previous_alert_state) StoreState("SERA_ALERTSTATE_",setup_id,state);

         int previous_trade_state=StoredState("SERA_TRADESTATE_",setup_id);
         if(state==0 && previous_trade_state!=0) StoreState("SERA_TRADESTATE_",setup_id,0);

         if(confirmed && can_trade && state!=previous_trade_state && OpenSeraPositions()<MaximumOpenPositions && TradesToday()<MaximumTradesPerDay)
         {
            if(symbol=="")
            {
               Print("Sera: symbole MT5 introuvable pour ",market_name," / ",deriv_code," — ordre ignore");
            }
            else
            {
               int levels_pos=StringFind(object,"\"levels\"");
               string levels=levels_pos>=0?ExtractObjectAt(object,StringFind(object,"{",levels_pos)):"";
               double sl=JsonNumber(levels,"sl"),tp=JsonNumber(levels,"tp2");
               MqlTick tick;
               if(sl>0 && tp>0 && SymbolInfoTick(symbol,tick))
               {
                  double price=verdict=="BUY"?tick.ask:tick.bid;
                  bool levels_valid=verdict=="BUY"?(sl<price && tp>price):(sl>price && tp<price);
                  double volume=levels_valid?SafeVolume(symbol,price,sl):0;
                  if(volume>0)
                  {
                     trade.SetExpertMagicNumber(MagicNumber);
                     trade.SetDeviationInPoints(DeviationPoints);
                     bool sent=verdict=="BUY"?trade.Buy(volume,symbol,0,sl,tp,"Sera Swing"):trade.Sell(volume,symbol,0,sl,tp,"Sera Swing");
                     if(sent)
                     {
                        StoreState("SERA_TRADESTATE_",setup_id,state);
                        Print("Sera: ",verdict," ",symbol," volume=",volume," SL=",sl," TP=",tp);
                        return;
                     }
                     Print("Sera: ordre refuse: ",trade.ResultRetcodeDescription());
                  }
                  else Print("Sera: volume nul ou niveaux invalides pour ",symbol);
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
   Comment("Sera v1.30 initialise — mode "+mode+" — AutoTrade="+(EnableAutomaticTrading?"ON":"OFF")+" — Risk "+DoubleToString(RiskPercent,2)+"%");
   Print("Sera v1.30: compte ",mode,", trading automatique=",EnableAutomaticTrading,", compte reel autorise=",AllowRealAccount,", AutoEngine=",AllowAutonomousExecution);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){ EventKillTimer(); Comment(""); }
void OnTimer(){ string json; if(FetchSignals(json)) Evaluate(json); }
