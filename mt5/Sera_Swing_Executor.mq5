#property copyright "Sera Indicator"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

input string SignalsUrl="https://serakatsuva.github.io/sera-indicator/data/signals.json";
input bool EnableAutomaticTrading=false;
input bool AllowRealAccount=false;
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

void MarkHandled(const string id)
{
   uint hash=2166136261;
   for(int i=0;i<StringLen(id);i++){ hash^=(uint)StringGetCharacter(id,i); hash*=16777619; }
   GlobalVariableSet("SERA_"+IntegerToString((int)hash),TimeCurrent());
}

bool WasHandled(const string id)
{
   uint hash=2166136261;
   for(int i=0;i<StringLen(id);i++){ hash^=(uint)StringGetCharacter(id,i); hash*=16777619; }
   return GlobalVariableCheck("SERA_"+IntegerToString((int)hash));
}

void Evaluate(const string json)
{
   if(!EnableAutomaticTrading){ Comment("Sera EA prêt — activez EnableAutomaticTrading sur compte Démo"); return; }
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE)!=ACCOUNT_TRADE_MODE_DEMO && !AllowRealAccount){ Comment("Sera bloque le compte réel — AllowRealAccount=false"); return; }
   if(JsonString(json,"status")!="ai_analyzed"){ Comment("Sera: aucune validation IA active — aucun ordre"); return; }
   if(OpenSeraPositions()>=MaximumOpenPositions || TradesToday()>=MaximumTradesPerDay) return;
   datetime generated=ParseIsoUtc(JsonString(json,"updated_at"));
   if(generated==0 || TimeGMT()-generated>MaximumSignalAgeMinutes*60){ Comment("Sera: signal global expiré"); return; }

   int markets=StringFind(json,"\"markets\""); if(markets<0) return;
   int cursor=StringFind(json,"{",markets);
   while(cursor>=0)
   {
      string object=ExtractObjectAt(json,cursor); if(object=="") break;
      string mode=JsonString(object,"mode"),verdict=JsonString(object,"final_verdict");
      double confidence=JsonNumber(object,"final_confidence");
      if(mode=="swing" && (verdict=="BUY" || verdict=="SELL") && confidence>=MinimumConfidence)
      {
         string signal_id=JsonString(object,"id")+":"+TimeToString(generated,TIME_DATE|TIME_MINUTES);
         string symbol=JsonString(object,"market");
         if(!WasHandled(signal_id) && SymbolSelect(symbol,true))
         {
            int levels_pos=StringFind(object,"\"levels\"");
            string levels=levels_pos>=0?ExtractObjectAt(object,StringFind(object,"{",levels_pos)):"";
            double sl=JsonNumber(levels,"sl"),tp=JsonNumber(levels,"tp2");
            MqlTick tick; if(sl>0 && tp>0 && SymbolInfoTick(symbol,tick))
            {
               double price=verdict=="BUY"?tick.ask:tick.bid;
               bool levels_valid=verdict=="BUY"?(sl<price && tp>price):(sl>price && tp<price);
               double volume=levels_valid?SafeVolume(symbol,price,sl):0;
               if(volume>0)
               {
                  trade.SetExpertMagicNumber(MagicNumber); trade.SetDeviationInPoints(DeviationPoints);
                  bool sent=verdict=="BUY"?trade.Buy(volume,symbol,0,sl,tp,"Sera Swing"):trade.Sell(volume,symbol,0,sl,tp,"Sera Swing");
                  if(sent){ MarkHandled(signal_id); Print("Sera: ",verdict," ",symbol," volume=",volume," SL=",sl," TP=",tp); return; }
                  Print("Sera: ordre refusé: ",trade.ResultRetcodeDescription());
               }
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
   Comment("Sera Swing Executor initialisé — Démo par défaut");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){ EventKillTimer(); Comment(""); }
void OnTimer(){ string json; if(FetchSignals(json)) Evaluate(json); }
