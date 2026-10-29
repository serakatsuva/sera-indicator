#property copyright "Sera EA Swing Intelligent Deriv"
#property version   "2.51"
#property strict

#include <Trade/Trade.mqh>

input string SignalsUrl="https://serakatsuva.github.io/sera-indicator/data/ea-signals.json";   // flux compact dédié à l'EA (~60 Ko)
input string FallbackSignalsUrl="https://raw.githubusercontent.com/serakatsuva/sera-indicator/main/data/ea-signals.json"; // 2e source, mise a jour des la publication (autoriser aussi https://raw.githubusercontent.com dans WebRequest)
input int SwitchSourceAfterMinutes=8;       // si la 1re source a plus de X min, l'EA compare avec la 2e et garde la plus recente
input bool EnableTrendWatch=true;
input bool EnableTerminalAlert=true;
input bool EnablePushNotification=false;
input bool AllowAutonomousExecution=true;
input bool EnableAutomaticTrading=true;
input bool AllowRealAccount=true;    // compte réel autorisé (choix du propriétaire)
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
input int MaximumSignalAgeMinutes=20;   // le moteur publie en continu (~5 min)
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

// --- v1.90 : exécution plus intelligente
input bool ShowDashboard=true;              // tableau de bord sur le graphique
input int DashboardX=10;
input int DashboardY=22;
input int DashboardMaxOrders=15;            // lignes max. pour les ordres et positions
input int DashboardMaxSetups=8;             // lignes max. pour les positions possibles
input bool ShowEntryChecks=true;            // detail des 11 controles du signal suivi
input bool TradeDaySignals=true;             // prendre aussi les signaux Day M15/H1 (plus fréquents, plus courts)
input bool UseBrokerConfirmation=true;       // tendance H1/H4 du broker alignée avec le signal
input bool CloseOnSignalReversal=true;       // fermer si le serveur inverse le signal de ce setup
input int MaximumSwingHoldingHours=240;      // 10 jours maximum pour un Swing
input int MaximumDayHoldingHours=48;
input bool AvoidForexWeekendGap=true;        // pas de nouvelle entrée Forex du vendredi soir au dimanche

// --- v2.51 : nombre de positions selon la balance et les profits
input bool EnableBalanceScaling=true;          // remplace les limites fixes 1 position / 2 trades par jour
input int MaximumOpenPositionsCap=0;           // 0 = pas de plafond : une position par marché ayant un signal
input double BalancePerPositionUSD=0.0;        // 0 = pas de limite par balance : ce sont les signaux qui décident
input double MaximumTotalOpenRiskPercent=10.0; // somme des pertes possibles jusqu'aux SL, en % de l'équité
input double DailyLossPercentLimit=5.0;        // perte journalière max en % de la balance (au moins MaximumDailyLossUSD)
input bool OnePositionPerSymbol=true;          // une seule position Sera par marché

// --- v2.51 : coupure en cas de retournement du marché
input bool CutOnMarketReversal=true;           // fermer dès qu'un retournement est confirmé

// --- v2.51 : robustesse
input double PartialCloseAtTP1Percent=50.0;    // encaisser cette part de la position à TP1 (0 = désactivé)
input double EmergencyEquityStopPercent=15.0;  // fermer toutes les positions Sera si l'équité chute de X % sous la balance (0 = désactivé)
input int ReversalStructureBars=24;            // cassure du plus bas / plus haut des N dernières bougies H1 (24 = 1 jour)

CTrade trade;
datetime last_poll=0;

// Déclarations anticipées (fonctions définies plus bas, utilisées par l'intelligence locale).
int AllowedOpenPositions();
int AllowedTradesPerDay();
double StoredLevel(const string prefix,const string id);
void StoreLevel(const string prefix,const string id,const double value);
double AdaptiveRiskPercent();
double SafeVolume(const string symbol,const double entry,const double sl);
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

   // v1.90 Forex : EUR/USD, EURUSD-STD ou frxEURUSD -> EURUSD, EURUSD.m, EURUSDm, frxEURUSD...
   string pair=market_name;
   StringReplace(pair,"/","");
   StringToUpper(pair);
   if(StringLen(pair)==6)
   {
      if(SymbolSelect(pair,true)) return pair;
      for(int j=0;j<SymbolsTotal(false);j++)
      {
         string name=SymbolName(j,false);
         string upper=name;
         StringToUpper(upper);
         if(StringFind(upper,pair)==0 || StringFind(upper,"FRX"+pair)==0)
         {
            if(SymbolSelect(name,true)) return name;
         }
      }
   }
   return "";
}

// ===================================================================================
//  TABLEAU DE BORD (v2.51) : etat du bot, flux de signaux et controles avant chaque entree
// ===================================================================================
#define SERA_GATES 11
#define DASH_BAR_COLUMN 114
string g_gate_names[SERA_GATES]={"Signal frais (bougie recente)","Confiance du signal","Conditions validees",
   "Etat d'execution (EXECUTE_NOW / limite)","Consensus des modeles IA","Symbole disponible sur le compte",
   "Marche ouvert (pas de gap week-end)","Capacite (1 position par marche)","Spread et prix d'entree",
   "Tendance H1/H4 du broker","Marge libre et risque total"};

struct PanelRow
{
   string market,symbol,mode,verdict,state,setup_side,decision,detail[SERA_GATES];
   double confidence,conditions,exec_score,engine_score,engine_min;
   int gate[SERA_GATES];      // 1 = OK, 0 = bloque, -1 = non evalue
   bool opened;
};

PanelRow g_rows[];
string   g_feed_status="Connexion aux signaux...";
bool     g_feed_ok=false;
int      g_feed_age_min=-1;
int      g_markets_seen=0,g_setups_seen=0,g_signals_seen=0;
string   g_trade_block="";
datetime g_last_feed_ok=0;
bool     g_4014_logged=false;
string   g_feed_source="";

bool FetchUrl(const string url,string &json)
{
   if(url=="") return false;
   char body[],response[]; string headers;
   ResetLastError();
   int code=WebRequest("GET",url,"","",15000,body,0,response,headers);
   int error=GetLastError();
   if(code==-1 && error==4014)
   {
      g_feed_status="BLOQUES par MT5 (erreur 4014) : Outils > Options > Expert Advisors > WebRequest : ajouter https://serakatsuva.github.io et https://raw.githubusercontent.com";
      if(!g_4014_logged) Print("Sera: WebRequest refuse pour ",url,". Ajoutez https://serakatsuva.github.io et https://raw.githubusercontent.com dans Outils > Options > Expert Advisors > Autoriser WebRequest.");
      g_4014_logged=true;
      return false;
   }
   if(code!=200)
   {
      g_feed_status="indisponibles (HTTP "+IntegerToString(code)+", erreur "+IntegerToString(error)+") : nouvel essai dans 30 s";
      Print("Sera: telechargement impossible ",url," HTTP=",code," erreur=",error);
      return false;
   }
   g_4014_logged=false;
   json=CharArrayToString(response,0,WHOLE_ARRAY,CP_UTF8);
   return StringLen(json)>50 && StringFind(json,"\"markets\"")>=0;
}

datetime FeedTime(const string json){ return ParseIsoUtc(JsonString(json,"updated_at")); }

// Deux sources (site GitHub Pages et fichier GitHub brut) : l'EA garde toujours la plus recente.
bool FetchSignals(string &json)
{
   string primary="",secondary="";
   bool okPrimary=FetchUrl(SignalsUrl,primary);
   string primaryStatus=g_feed_status;
   bool fresh=okPrimary && TimeGMT()-FeedTime(primary)<=SwitchSourceAfterMinutes*60;
   if(fresh){ json=primary; g_feed_source="site"; return true; }
   string url=FallbackSignalsUrl;
   if(StringFind(url,"raw.githubusercontent.com")>=0) // contourne le cache
   {
      string sep="?";
      if(StringFind(url,"?")>=0) sep="&";
      url=url+sep+"t="+IntegerToString((long)TimeGMT());
   }
   bool okSecondary=FetchUrl(url,secondary);
   if(okPrimary && okSecondary){ json=FeedTime(secondary)>FeedTime(primary)?secondary:primary; g_feed_source=FeedTime(secondary)>FeedTime(primary)?"GitHub direct":"site"; return true; }
   if(okSecondary){ json=secondary; g_feed_source="GitHub direct"; return true; }
   if(okPrimary){ json=primary; g_feed_source="site"; return true; }
   if(primaryStatus!="" && StringFind(g_feed_status,"4014")<0) g_feed_status=primaryStatus;
   return false;
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
      StringFind(s,"STEP")>=0 || StringFind(s,"JUMP")>=0 || StringFind(s,"RANGE")>=0 ||
      StringFind(s,"DEX")>=0 || StringFind(s,"DRIFT")>=0 || StringFind(s,"VOLSWITCH")>=0 ||
      StringFind(s,"BASKET")>=0) return 3; // Synthetic
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

   Print("Sera local H1/H4 ",symbol,": ",side," ",DoubleToString(score,0),"%");

   if(!EnableLocalAutoEntry || side=="WAIT") return;
   if(!EnableAutomaticTrading || RiskCircuitOpen()) return;
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE)!=ACCOUNT_TRADE_MODE_DEMO && !AllowRealAccount) return;
   if(OpenSeraPositions()>=AllowedOpenPositions() || TradesToday()>=AllowedTradesPerDay()) return;
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
      ?trade.Buy(volume,symbol,0,sl,tp3,"Sera Local Swing v2.51")
      :trade.Sell(volume,symbol,0,sl,tp3,"Sera Local Swing v2.51");
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

// ---------- v2.51 : mise à l'échelle selon la balance et les profits ----------

// Perte possible (devise du compte) si le SL d'une position est touché. Une position déjà
// protégée au point mort ou mieux compte pour 0.
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

double OpenSeraFloatingProfit()
{
   double total=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionGetInteger(POSITION_MAGIC)==MagicNumber)
         total+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
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

// Ce sont les signaux qui décident : chaque bon signal (un par marché) peut être pris jusqu'au
// plafond, tant que le risque cumulé reste sous MaximumTotalOpenRiskPercent (TotalRiskAllows).
// Les profits n'entrent pas dans le calcul.
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

// Le risque cumulé (positions ouvertes + nouvelle position) doit rester sous le plafond.
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

void SendTrendAlert(const string market,const string verdict,const double confidence,const string execution_state,const string mode)
{
   if(!EnableTrendWatch) return;
   string message="Sera Trend Watch: "+market+" "+verdict+(mode=="day"?" Day M15/H1 ":" Swing H1/H4/D1 ")+execution_state+" a "+DoubleToString(confidence,0)+"%";
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
      ? trade.BuyLimit(volume,normalized_entry,symbol,normalized_sl,normalized_tp,ORDER_TIME_SPECIFIED,expiration,"Sera Intelligent Swing BUY LIMIT")
      : trade.SellLimit(volume,normalized_entry,symbol,normalized_sl,normalized_tp,ORDER_TIME_SPECIFIED,expiration,"Sera Intelligent Swing SELL LIMIT");

   if(sent)
   {
      StoreState("SERA_PENDINGSTATE_",setup_id,VerdictState(verdict));
      StoreLevel("SERA_ENTRY_",setup_id,normalized_entry);
      Print("Sera EA Swing Intelligent: ",verdict," LIMIT ",symbol," @ ",DoubleToString(normalized_entry,digits)," volume=",volume);
      return true;
   }
   Print("Sera EA Swing Intelligent: pending refuse ",trade.ResultRetcodeDescription());
   return false;
}

// ---------- v1.90 : intelligence d'exécution ----------

bool JsonFlagFalse(const string object,const string key)
{
   string token="\""+key+"\"";
   int p=StringFind(object,token); if(p<0) return false;
   p=StringFind(object,":",p+StringLen(token)); if(p<0) return false;
   p++;
   while(p<StringLen(object) && (StringGetCharacter(object,p)==' ' || StringGetCharacter(object,p)=='\t')) p++;
   return StringSubstr(object,p,5)=="false";
}

// EMA calculée directement sur les bougies clôturées du broker (pas de handle d'indicateur :
// un handle tout juste créé renvoie souvent "pas encore calculé" au premier appel).
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

// Le serveur analyse ses propres données (Deriv / Yahoo). Avant d'engager de l'argent,
// l'EA vérifie que les bougies H1 et H4 du broker racontent la même tendance.
bool BrokerConfirms(const string symbol,const string verdict,string &reason)
{
   if(!UseBrokerConfirmation){ reason="confirmation broker desactivee"; return true; }
   double h1Fast=BrokerCloseEMA(symbol,PERIOD_H1,20);
   double h1Slow=BrokerCloseEMA(symbol,PERIOD_H1,50);
   double h4Fast=BrokerCloseEMA(symbol,PERIOD_H4,20);
   double h4Slow=BrokerCloseEMA(symbol,PERIOD_H4,50);
   if(h1Fast==EMPTY_VALUE || h1Slow==EMPTY_VALUE || h4Fast==EMPTY_VALUE || h4Slow==EMPTY_VALUE)
   {
      reason="historique H1/H4 du broker en cours de chargement";
      return false;
   }
   bool aligned=verdict=="BUY" ? (h1Fast>h1Slow && h4Fast>h4Slow) : (h1Fast<h1Slow && h4Fast<h4Slow);
   if(!aligned){ reason="tendance H1/H4 du broker non alignee avec "+verdict; return false; }
   reason="tendance H1/H4 du broker alignee";
   return true;
}

// Pas de nouvelle entrée Forex/CFD juste avant ou pendant la fermeture du week-end (gap).
bool WeekendGapRisk(const string symbol)
{
   if(!AvoidForexWeekendGap || AssetProfile(symbol)==3) return false;
   MqlDateTime t;
   TimeToStruct(TimeGMT(),t);
   return (t.day_of_week==5 && t.hour>=19) || t.day_of_week==6 || (t.day_of_week==0 && t.hour<22);
}

string last_broker_message="";
void PrintOnce(const string message)
{
   if(message==last_broker_message) return;
   last_broker_message=message;
   Print(message);
}

bool JsonFlagTrue(const string object,const string key)
{
   string token="\""+key+"\"";
   int p=StringFind(object,token); if(p<0) return false;
   p=StringFind(object,":",p+StringLen(token)); if(p<0) return false;
   p++;
   while(p<StringLen(object) && (StringGetCharacter(object,p)==' ' || StringGetCharacter(object,p)=='\t')) p++;
   return StringSubstr(object,p,4)=="true";
}

// Les niveaux d'un trade sont enregistrés par setup ET par symbole : la gestion des positions
// (point mort, verrouillage, sortie partielle) continue même si les signaux n'arrivent plus.
void StoreTradeLevels(const string setup_id,const string symbol,const double entry,const double tp1,const double tp2,
                      const double tp3,const double tp4,const double tp5,const double final_tp,const string mode)
{
   string keys[2];
   keys[0]=setup_id; keys[1]="SYM:"+symbol;
   for(int k=0;k<2;k++)
   {
      StoreLevel("SERA_ENTRY_",keys[k],entry);
      StoreLevel("SERA_TP1_",keys[k],tp1);
      StoreLevel("SERA_TP2_",keys[k],tp2);
      StoreLevel("SERA_TP3_",keys[k],tp3);
      StoreLevel("SERA_TP4_",keys[k],tp4);
      StoreLevel("SERA_TP5_",keys[k],tp5);
      StoreLevel("SERA_FINALTP_",keys[k],final_tp);
   }
   StoreState("SERA_DAYMODE_","SYM:"+symbol,mode=="day"?1:0);
}

// Encaisse une partie de la position la première fois que TP1 est atteint.
void PartialCloseAtTP1(const string symbol,const double tp1)
{
   if(PartialCloseAtTP1Percent<=0 || tp1<=0 || !SelectSeraPosition(symbol)) return;
   ulong ticket=(ulong)PositionGetInteger(POSITION_TICKET);
   string ticket_key=IntegerToString((long)ticket);
   if(StoredState("SERA_PARTIAL_",ticket_key)==1) return;
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
   StoreState("SERA_PARTIAL_",ticket_key,1);   // une seule tentative par position
   if(part<min_lot || volume-part<min_lot)
   {
      Print("Sera TP1: volume trop petit pour une sortie partielle sur ",symbol,", position conservee entiere");
      return;
   }
   trade.SetExpertMagicNumber(MagicNumber);
   if(trade.PositionClosePartial(ticket,part)) Print("Sera TP1: ",DoubleToString(part,2)," lot encaisse sur ",symbol);
   else Print("Sera TP1: sortie partielle refusee ",trade.ResultRetcodeDescription());
}

// Gère TOUTES les positions Sera à chaque cycle, indépendamment de la réception des signaux.
void ManageAllSeraPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket<=0 || PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      string symbol=PositionGetString(POSITION_SYMBOL);
      datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
      string key="SYM:"+symbol;
      int max_hours=StoredState("SERA_DAYMODE_",key)==1?MaximumDayHoldingHours:MaximumSwingHoldingHours;
      if(max_hours>0 && TimeCurrent()-opened>(long)max_hours*3600)
      {
         trade.SetExpertMagicNumber(MagicNumber);
         if(trade.PositionClose(ticket)) Print("Sera: ",symbol," ferme — duree maximale atteinte");
         continue;
      }
      PartialCloseAtTP1(symbol,StoredLevel("SERA_TP1_",key));
      ManageSeraPosition(key,symbol);
   }
}

// Arrêt d'urgence : si l'équité chute trop sous la balance (gap, crash), tout est fermé.
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

// Objet JSON d'une clé, ou "" si la valeur n'est pas un objet (null, absent...).
string JsonObject(const string object,const string key)
{
   string token="\""+key+"\"";
   int p=StringFind(object,token); if(p<0) return "";
   p=StringFind(object,":",p+StringLen(token)); if(p<0) return "";
   p++;
   while(p<StringLen(object) && (StringGetCharacter(object,p)==' ' || StringGetCharacter(object,p)=='\t' || StringGetCharacter(object,p)=='\n' || StringGetCharacter(object,p)=='\r')) p++;
   if(p>=StringLen(object) || StringGetCharacter(object,p)!='{') return "";
   return ExtractObjectAt(object,p);
}

// Retournement lu sur les bougies H1 clôturées du broker, uniquement sur des bougies
// ouvertes APRÈS l'entrée : EMA20 repassée de l'autre côté de l'EMA50 avec une clôture du
// mauvais côté de l'EMA50, ou cassure du plus bas / plus haut des N dernières bougies.
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

// Vérifie toutes les positions Sera à chaque cycle et coupe celles dont le marché s'est retourné.
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

// Ferme une position Sera si le serveur inverse le signal de CE setup (verdict final opposé,
// ou tendance H1 ET H4 du serveur retournées), ou si elle a dépassé la durée maximale.
void SmartExit(const string setup_id,const string symbol,const string mode,const string verdict,const double confidence,const string object)
{
   if(symbol=="" || StoredState("SERA_OPEN_",setup_id)!=1) return;
   if(!SelectSeraPosition(symbol)){ StoreState("SERA_OPEN_",setup_id,0); return; }
   long position_type=PositionGetInteger(POSITION_TYPE);
   string verdict_note="";
   bool reversal=CloseOnSignalReversal && confidence>=MinimumConfidence &&
      ((position_type==POSITION_TYPE_BUY && verdict=="SELL") || (position_type==POSITION_TYPE_SELL && verdict=="BUY"));
   if(!reversal && CutOnMarketReversal)
   {
      string confirmation=JsonObject(object,"confirmation_tf");
      string entry_side=JsonString(JsonObject(object,"entry_tf"),"side");
      string confirmation_side=JsonString(confirmation,"side");
      string against=position_type==POSITION_TYPE_BUY?"SELL":"BUY";
      // Un simple repli (clôture sous l'EMA20) ne suffit pas : la tendance H4 doit être cassée.
      if(entry_side==against && confirmation_side==against && JsonFlagTrue(confirmation,"trendStrong"))
      {
         reversal=true;
         verdict_note="tendance serveur H1 et H4 retournees ("+against+")";
      }
   }
   datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
   int max_hours=mode=="day"?MaximumDayHoldingHours:MaximumSwingHoldingHours;
   bool expired=max_hours>0 && TimeCurrent()-opened>(long)max_hours*3600;
   if(!reversal && !expired) return;
   trade.SetExpertMagicNumber(MagicNumber);
   if(trade.PositionClose(symbol))
   {
      StoreState("SERA_OPEN_",setup_id,0);
      Print("Sera Smart Exit: ",symbol," ferme — ",reversal?(verdict_note!=""?verdict_note:"signal serveur inverse ("+verdict+")"):"duree maximale atteinte");
   }
   else Print("Sera Smart Exit: fermeture refusee ",trade.ResultRetcodeDescription());
}

// ---------- Tableau de bord : affichage ----------
color Rgb(const int r,const int g,const int b){ return (color)(r|(g<<8)|(b<<16)); }

void PanelReset(PanelRow &r,const string market,const string mode,const string verdict,const string state,
                const double confidence,const double conditions,const double exec_score)
{
   r.market=market; r.symbol=""; r.mode=mode; r.verdict=verdict; r.state=state; r.setup_side=""; r.decision="";
   r.confidence=confidence; r.conditions=conditions; r.exec_score=exec_score; r.engine_score=0; r.engine_min=0; r.opened=false;
   for(int i=0;i<SERA_GATES;i++){ r.gate[i]=-1; r.detail[i]=""; }
}

void PanelGate(PanelRow &r,const int index,const bool ok,const string detail)
{
   r.gate[index]=ok?1:0;
   r.detail[index]=detail;
}

string PanelFirstBlock(const PanelRow &r)
{
   for(int i=0;i<SERA_GATES;i++) if(r.gate[i]==0) return g_gate_names[i]+(r.detail[i]!=""?" ("+r.detail[i]+")":"");
   return "";
}

int g_panel_maxlen=0;
void PanelText(const int line,const string text,const color clr,const int size=9)
{
   if(StringLen(text)>g_panel_maxlen) g_panel_maxlen=StringLen(text);
   string name="SERA_PANEL_L"+IntegerToString(line);
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
   string name="SERA_PANEL_BG";
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

void PanelClear(){ ObjectsDeleteAll(0,"SERA_PANEL_"); }

// Signal mis en avant : position ouverte ce cycle, sinon EXECUTE_NOW, sinon le plus confiant.
int PanelFocus()
{
   int best=-1;
   double bestScore=-1;
   for(int i=0;i<ArraySize(g_rows);i++)
   {
      double score=g_rows[i].confidence;
      if(g_rows[i].verdict=="BUY" || g_rows[i].verdict=="SELL") score+=1000;
      if(g_rows[i].state=="EXECUTE_NOW") score+=2000;
      if(g_rows[i].opened) score+=10000;
      if(score>bestScore){ bestScore=score; best=i; }
   }
   return best;
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
   int x=DashboardX+10+DASH_BAR_COLUMN*7;
   int y=DashboardY+8+line*16+3;
   string names[2];
   names[0]="SERA_PANEL_B"+IntegerToString(g_bar_count)+"_BG";
   names[1]="SERA_PANEL_B"+IntegerToString(g_bar_count)+"_FG";
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
   if(DASH_BAR_COLUMN+16>g_panel_maxlen) g_panel_maxlen=DASH_BAR_COLUMN+16;
}

color CertaintyColor(const double pct)
{
   if(pct>=85) return Rgb(56,232,187);
   if(pct>=75) return Rgb(77,163,255);
   return Rgb(255,190,80);
}

// Certitude d'un ordre / d'une position : signal actuel du meme marche, sinon celle enregistree a l'entree.
double SymbolCertainty(const string symbol)
{
   double best=-1;
   for(int i=0;i<ArraySize(g_rows);i++)
      if(g_rows[i].symbol==symbol && g_rows[i].confidence>best) best=g_rows[i].confidence;
   if(best>=0) return best;
   return StoredLevel("SERA_CONF_",symbol);
}

string FormatPrice(const string symbol,const double price)
{
   return DoubleToString(price,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS));
}

// Tableau des ordres limites et positions Sera ouverts. Renvoie la ligne suivante.
int RenderOrders(int line)
{
   color white=Rgb(220,232,245),grey=Rgb(130,148,168),green=Rgb(56,232,187),red=Rgb(255,95,118),blue=Rgb(77,163,255);
   int sera=0,foreign=0;
   for(int i=0;i<PositionsTotal();i++){ ulong t=PositionGetTicket(i); if(t>0){ if(PositionGetInteger(POSITION_MAGIC)==MagicNumber) sera++; else foreign++; } }
   for(int i=0;i<OrdersTotal();i++){ ulong t=OrderGetTicket(i); if(t>0){ if(OrderGetInteger(ORDER_MAGIC)==MagicNumber) sera++; else foreign++; } }
   PanelText(line++,"",grey);
   PanelText(line++,"ORDRES ET POSITIONS SERA ("+IntegerToString(sera)+")",Rgb(255,190,80));
   if(sera==0) PanelText(line++,"  Aucun ordre ni position Sera pour le moment.",grey);
   else PanelText(line++,"  "+Pad("Marche",27)+Pad("Type",11)+Pad("Entree",12)+Pad("SL",12)+Pad("TP",12)+Pad("Lot",6)+Pad("Etat / resultat",19)+"Certitude",grey);
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

double RowProgress(const PanelRow &r)
{
   double score=r.engine_score>0?r.engine_score:r.confidence;
   double byScore=r.engine_min>0?score/r.engine_min*100.0:score;
   double byConditions=MinimumAutonomousConditionsPercent>0?r.conditions/MinimumAutonomousConditionsPercent*100.0:100.0;
   return MathMin(100.0,MathMin(byScore,byConditions));
}

double RowCertainty(const PanelRow &r)
{
   double bonus=(r.verdict=="BUY"||r.verdict=="SELL")?1000:0;
   return bonus+RowProgress(r)*10+(r.engine_score>0?r.engine_score:r.confidence)/100.0;
}

// Ce qui manque encore avant une entree, en quelques mots.
string MissingShort(const PanelRow &r)
{
   bool signal=r.verdict=="BUY" || r.verdict=="SELL";
   if(!signal)
   {
      if(r.conditions<MinimumAutonomousConditionsPercent) return "conditions ("+DoubleToString(r.conditions,0)+"/"+IntegerToString(MinimumAutonomousConditionsPercent)+"%)";
      return "score du moteur";
   }
   if(r.state=="WAIT_CONFIRMATION") return "bougie de confirmation";
   if(r.state=="WAIT_RETRACE") return "retour dans la zone";
   if(r.state=="BLOCKED_RISK") return "risque spike/retournement";
   for(int i=0;i<SERA_GATES;i++) if(r.gate[i]==0) return StringSubstr(g_gate_names[i],0,24);
   return "entree au prochain cycle";
}

// Positions possibles : signaux et setups qui n'ont pas encore d'ordre ni de position.
int RenderPossible(int line)
{
   color white=Rgb(220,232,245),grey=Rgb(130,148,168),cyan=Rgb(84,216,255);
   int count=0;
   for(int i=0;i<ArraySize(g_rows);i++)
      if(g_rows[i].symbol=="" || (FindSeraPendingOrder(g_rows[i].symbol)==0 && !HasSeraPositionOn(g_rows[i].symbol))) count++;
   PanelText(line++,"",grey);
   PanelText(line++,"POSITIONS POSSIBLES ("+IntegerToString(count)+") : signaux et setups en preparation",Rgb(255,190,80));
   if(count==0){ PanelText(line++,g_feed_ok?"  Aucun setup en preparation pour le moment.":"  En attente de signaux frais.",grey); return line; }
   PanelText(line++,"  "+Pad("Marche",27)+Pad("Horizon",8)+Pad("Sens",6)+Pad("Etat",19)+Pad("Conditions",11)+Pad("Ce qu'il manque",24)+"Score / seuil",grey);
   // les plus avances d'abord
   int order[];
   ArrayResize(order,ArraySize(g_rows));
   for(int i=0;i<ArraySize(g_rows);i++) order[i]=i;
   for(int a=0;a<ArraySize(order);a++)
      for(int b=a+1;b<ArraySize(order);b++)
         if(RowCertainty(g_rows[order[b]])>RowCertainty(g_rows[order[a]])){ int t=order[a]; order[a]=order[b]; order[b]=t; }
   int shown=0;
   for(int k=0;k<ArraySize(order) && shown<DashboardMaxSetups;k++)
   {
      PanelRow r=g_rows[order[k]];
      if(r.symbol!="" && (FindSeraPendingOrder(r.symbol)>0 || HasSeraPositionOn(r.symbol))) continue;
      bool signal=r.verdict=="BUY" || r.verdict=="SELL";
      string side=signal?r.verdict:r.setup_side;
      double score=r.engine_score>0?r.engine_score:r.confidence;
      string scoreText=DoubleToString(score,0)+" / "+DoubleToString(r.engine_min,0);
      PanelText(line,"  "+Pad(r.market,27)+Pad(r.mode=="day"?"Day":"Swing",8)+Pad(side,6)+Pad(r.state,19)+
                Pad(DoubleToString(r.conditions,0)+"%",11)+Pad(MissingShort(r),24)+scoreText,signal?white:cyan);
      // barre : avancement vers un signal tradable = le plus faible entre score/seuil et conditions/minimum
      double progress=RowProgress(r);
      PanelBar(line,progress,progress>=100?Rgb(56,232,187):progress>=90?Rgb(77,163,255):Rgb(255,190,80));
      line++; shown++;
   }
   if(count>shown) PanelText(line++,"  ... et "+IntegerToString(count-shown)+" autre(s)",grey);
   return line;
}

void RenderDashboard()
{
   if(!ShowDashboard){ PanelClear(); return; }
   color white=Rgb(220,232,245),grey=Rgb(130,148,168),green=Rgb(56,232,187),red=Rgb(255,95,118),
         amber=Rgb(255,190,80),cyan=Rgb(84,216,255),blue=Rgb(77,163,255);
   int line=0;
   g_panel_maxlen=0;
   g_bar_count=0;
   // Le fond est cree en premier (MT5 dessine le dernier objet cree au-dessus) puis redimensionne a la fin.
   if(ObjectFind(0,"SERA_PANEL_BG")<0){ PanelClear(); PanelBackground(1); }
   bool algo=TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED);
   bool demo=AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO;
   bool active=algo && EnableAutomaticTrading && (demo || AllowRealAccount) && g_trade_block=="";

   string account=demo?"DEMO":"REEL";
   string horizons=TradeDaySignals?"Swing H1/H4/D1 + Day M15/H1":"Swing H1/H4/D1";
   PanelText(line++,"SERA EA SWING INTELLIGENT DERIV v2.51",amber,10);
   if(active && !g_feed_ok) PanelText(line++,"BOT ACTIF  |  compte "+account+"  |  en attente des signaux (voir ci-dessous)",amber);
   else if(active) PanelText(line++,"BOT ACTIF  |  compte "+account+"  |  trading automatique autorise",green);
   else if(!algo) PanelText(line++,"BOT EN PAUSE  |  activez le bouton Algo Trading de MT5",red);
   else if(g_trade_block!="") PanelText(line++,"BOT EN PAUSE  |  "+g_trade_block,red);
   else PanelText(line++,"BOT EN PAUSE  |  trading automatique desactive dans les parametres",red);

   if(g_feed_ok)
      PanelText(line++,"Signaux : recus il y a "+IntegerToString(MathMax(0,g_feed_age_min))+" min ("+g_feed_source+")  |  "+IntegerToString(g_markets_seen)+
                " analyses  |  "+IntegerToString(g_setups_seen)+" setups  |  "+IntegerToString(g_signals_seen)+" signaux",green);
   else
   {
      int cut=StringFind(g_feed_status," : ");
      PanelText(line++,"Signaux : "+(cut>0?StringSubstr(g_feed_status,0,cut):g_feed_status),red);
      if(cut>0) PanelText(line++,"  -> "+StringSubstr(g_feed_status,cut+3),amber);
   }

   double balance=AccountInfoDouble(ACCOUNT_BALANCE),equity=AccountInfoDouble(ACCOUNT_EQUITY),risk=OpenSeraRiskUSD();
   PanelText(line++,"Compte : balance "+DoubleToString(balance,2)+"  equite "+DoubleToString(equity,2)+"  |  positions "+
             IntegerToString(OpenSeraPositions())+"  |  risque ouvert "+DoubleToString(risk,2)+" ("+
             DoubleToString(equity>0?risk/equity*100.0:0.0,1)+"% / max "+DoubleToString(MaximumTotalOpenRiskPercent,0)+"%)",white);
   PanelText(line++,"Horizons : "+horizons+"  |  risque "+DoubleToString(RiskPercent,2)+
             "% par trade  |  analyse toutes les "+IntegerToString(MathMax(15,PollEverySeconds))+" s",grey);

   line=RenderOrders(line);
   line=RenderPossible(line);

   int focus=ShowEntryChecks?PanelFocus():-1;
   if(!ShowEntryChecks){}
   else if(focus<0)
   {
      PanelText(line++,"",grey);
      if(g_feed_ok) PanelText(line++,"Aucun signal BUY/SELL en cours : le bot surveille les marches et attend un setup valide.",cyan);
      else PanelText(line++,"Aucune nouvelle entree sans signaux frais. Positions et ordres existants restent geres.",amber);
   }
   else
   {
      PanelRow r=g_rows[focus];
      PanelText(line++,"",grey);
      string horizon=r.mode=="day"?"Day M15/H1":"Swing H1/H4/D1";
      string side=(r.verdict=="BUY"||r.verdict=="SELL")?r.verdict:"setup";
      PanelText(line++,"SIGNAL SUIVI (detail des controles) : "+r.market+"  |  "+horizon+"  |  "+side+"  |  "+r.state,
                r.verdict=="BUY"?blue:r.verdict=="SELL"?red:cyan);
      PanelText(line++,"Confiance "+DoubleToString(r.confidence,0)+"%   conditions "+DoubleToString(r.conditions,0)+
                "%   score d'execution "+DoubleToString(r.exec_score,0),white);
      PanelText(line++,"Controles avant d'ouvrir la position :",grey);
      for(int g=0;g<SERA_GATES;g++)
      {
         string mark=r.gate[g]==1?"[OK] ":r.gate[g]==0?"[NON]":"[ - ]";
         color c=r.gate[g]==1?green:r.gate[g]==0?red:grey;
         string detail=r.detail[g]!=""?" : "+r.detail[g]:"";
         PanelText(line++,"  "+mark+" "+g_gate_names[g]+detail,c);
      }
      PanelText(line++,"DECISION : "+r.decision,r.opened?green:(StringFind(r.decision,"LIMITE")>=0?blue:amber),10);

   }
   PanelBackground(line);
   for(int k=line;k<120;k++){ string name="SERA_PANEL_L"+IntegerToString(k); if(ObjectFind(0,name)>=0) ObjectDelete(0,name); }
   for(int k=g_bar_count;k<120;k++)
   {
      string bg="SERA_PANEL_B"+IntegerToString(k)+"_BG",fg="SERA_PANEL_B"+IntegerToString(k)+"_FG";
      if(ObjectFind(0,bg)>=0) ObjectDelete(0,bg);
      if(ObjectFind(0,fg)>=0) ObjectDelete(0,fg);
   }
   ChartRedraw(0);
}

void Evaluate(const string json)
{
   string status=JsonString(json,"status");
   ArrayResize(g_rows,0);
   g_markets_seen=0; g_setups_seen=0; g_signals_seen=0; g_trade_block="";
   if(status!="ai_analyzed" && status!="autonomous_analyzed" && status!="smart_local")
   { g_feed_ok=false; g_feed_status="format de signaux inconnu ("+status+")"; RenderDashboard(); return; }
   datetime generated=ParseIsoUtc(JsonString(json,"updated_at"));
   g_feed_age_min=generated>0?(int)((TimeGMT()-generated)/60):-1;
   if(generated==0 || TimeGMT()-generated>MaximumSignalAgeMinutes*60)
   {
      g_feed_ok=false;
      g_feed_status="trop anciens ("+IntegerToString(g_feed_age_min)+" min > "+IntegerToString(MaximumSignalAgeMinutes)+") : le moteur serveur est en retard, aucune entree";
      RenderDashboard();
      return;
   }
   g_feed_ok=true; g_last_feed_ok=TimeCurrent();
   bool opened_this_cycle=false;

   bool source_allows_trade=(status=="ai_analyzed")||(status=="autonomous_analyzed"&&AllowAutonomousExecution)||(status=="smart_local"&&AllowAutonomousExecution);
   bool circuit_open=RiskCircuitOpen();
   if(circuit_open) CancelAllSeraPendingOrders("circuit risque actif");
   bool can_trade=EnableAutomaticTrading&&source_allows_trade&&!circuit_open;
   if(can_trade && AccountInfoInteger(ACCOUNT_TRADE_MODE)!=ACCOUNT_TRADE_MODE_DEMO && !AllowRealAccount)
   {
      can_trade=false;
      g_trade_block="compte reel bloque (AllowRealAccount=false)";
   }
   else if((status=="autonomous_analyzed"||status=="smart_local") && !AllowAutonomousExecution) g_trade_block="execution autonome desactivee (AllowAutonomousExecution=false)";
   if(circuit_open) g_trade_block="protection du compte active (perte du jour, drawdown, pertes consecutives ou marge)";

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
      if(mode=="swing" || mode=="day") g_markets_seen++;
      if(setup_detected>0) g_setups_seen++;
      if(verdict=="BUY" || verdict=="SELL") g_signals_seen++;
      if(mode=="swing" || (TradeDaySignals && mode=="day"))
      {
         PanelRow pr;
         PanelReset(pr,JsonString(object,"market"),mode,verdict,execution_state,confidence,conditions_percent,execution_score);
         string setup_id=JsonString(object,"id");
         string market_name=JsonString(object,"market");
         string deriv_code=JsonString(object,"symbol");
         string symbol=ResolveTradeSymbol(market_name,deriv_code);
         if(symbol!="") ManageSeraPosition(setup_id,symbol);
         int state=VerdictState(verdict);
         if(symbol!="") SmartExit(setup_id,symbol,mode,verdict,confidence,object);
         bool row_fresh=!JsonFlagFalse(object,"freshness_gate");
         bool directional_confirmed=(row_fresh && state!=0 && confidence>=MinimumConfidence && conditions_percent>=MinimumAutonomousConditionsPercent);
         bool symbol_can_trade=can_trade && (symbol=="" || !WeekendGapRisk(symbol));
         PanelGate(pr,0,row_fresh,row_fresh?"":"derniere bougie trop ancienne");
         PanelGate(pr,1,confidence>=MinimumConfidence,DoubleToString(confidence,0)+"% / min "+IntegerToString(MinimumConfidence)+"%");
         PanelGate(pr,2,conditions_percent>=MinimumAutonomousConditionsPercent,DoubleToString(conditions_percent,0)+"% / min "+IntegerToString(MinimumAutonomousConditionsPercent)+"%");
         pr.symbol=symbol;
         pr.setup_side=setup_direction;
         pr.engine_score=JsonNumber(object,"engine_score");
         pr.engine_min=JsonNumber(object,"engine_minimum_score");
         if(pr.engine_min<=0) pr.engine_min=mode=="day"?76:84;
         PanelGate(pr,5,symbol!="",symbol!=""?symbol:"introuvable sur ce compte");
         if(symbol!="") PanelGate(pr,6,!WeekendGapRisk(symbol),WeekendGapRisk(symbol)?"pause Forex du week-end":"");
         bool model_guard_ok=true;
         string opposite=verdict=="BUY"?"SELL":"BUY";
         if(UseOpenSourceModelGuard && models_available>=2 && model_direction==opposite && model_consensus>=MinimumModelConsensus)
         {
            model_guard_ok=false;
            Print("Sera: execution bloquee par ensemble open-source ",model_direction," ",DoubleToString(model_consensus,0),"% contre ",verdict);
         }
         bool execution_ready=((!RequireExecuteNow)||(execution_state=="EXECUTE_NOW"&&execution_score>=MinimumExecutionScore)) && model_guard_ok;
         PanelGate(pr,4,model_guard_ok,models_available>=2?(model_direction+" "+DoubleToString(model_consensus,0)+"%"):"moins de 2 modeles disponibles");
         bool exec_ok=execution_state=="EXECUTE_NOW"&&execution_score>=MinimumExecutionScore;
         bool limit_ok=execution_state=="WAIT_RETRACE"&&execution_score>=MinimumPendingExecutionScore;
         PanelGate(pr,3,exec_ok||limit_ok,execution_state+" score "+DoubleToString(execution_score,0)+(exec_ok?" : entree immediate":limit_ok?" : ordre limite":""));
         bool capacity_ok=OpenSeraPositions()<AllowedOpenPositions() && TradesToday()<AllowedTradesPerDay() && (symbol=="" || !OnePositionPerSymbol || !HasSeraPositionOn(symbol));
         PanelGate(pr,7,capacity_ok,symbol!="" && OnePositionPerSymbol && HasSeraPositionOn(symbol)?"deja une position Sera sur ce marche":"");
         int alert_state=state*10+(execution_ready?1:0);

         int previous_alert_state=StoredState("SERA_ALERTSTATE_",setup_id);
         if(directional_confirmed && alert_state!=previous_alert_state) SendTrendAlert(market_name,verdict,confidence,execution_state,mode);
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
               && symbol_can_trade
               && OpenSeraPositions()<AllowedOpenPositions()
               && (!OnePositionPerSymbol || !HasSeraPositionOn(symbol))
               && (FindSeraPendingOrder(symbol)>0 || OpenSeraPendingOrders()<AllowedPendingOrders());

            if(pending_candidate)
            {
               string levels_pending=JsonObject(object,"levels");
               string plan=JsonObject(object,"setup_entry_plan");
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

               string pending_why="";
               bool pending_broker_ok=pending_margin_ok && BrokerConfirms(symbol,verdict,pending_why);
               PanelGate(pr,8,pending_stops_ok,pending_stops_ok?"entree limite "+DoubleToString(pending_entry,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS)):"SL/TP trop proches pour le broker");
               if(pending_margin_ok) PanelGate(pr,9,pending_broker_ok,pending_why);
               bool pending_risk_ok=FindSeraPendingOrder(symbol)>0 ||
                  TotalRiskAllows(PositionRiskUSD(symbol,verdict=="BUY"?POSITION_TYPE_BUY:POSITION_TYPE_SELL,pending_entry,pending_sl,pending_volume));
               if(pending_broker_ok && !pending_risk_ok)
               {
                  pending_broker_ok=false;
                  PrintOnce("Sera: limite "+symbol+" en attente — risque cumule maximum atteint");
               }
               if(pending_margin_ok && !pending_broker_ok) PrintOnce("Sera: limite "+symbol+" en attente — "+pending_why);
               PanelGate(pr,10,pending_margin_ok && pending_risk_ok,pending_volume<=0?"volume nul (lot minimum ou SL)":!pending_margin_ok?"marge libre insuffisante":!pending_risk_ok?"risque total maximum atteint":"lot "+DoubleToString(pending_volume,2));
               if(pending_broker_ok && PlaceOrUpdatePendingLimit(setup_id,symbol,verdict,pending_entry,pending_sl,pending_final_tp,pending_volume))
               {
                  StoreState("SERA_PENDOWNER_",symbol,(int)SeraHash(setup_id));
                  StoreLevel("SERA_CONF_",symbol,confidence);
                  pr.decision="ORDRE LIMITE "+verdict+" EN PLACE a "+DoubleToString(pending_entry,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS))+" (lot "+DoubleToString(pending_volume,2)+")";
                  StoreState("SERA_OPEN_",setup_id,1);
                  StoreTradeLevels(setup_id,symbol,pending_entry,JsonNumber(levels_pending,"tp1"),JsonNumber(levels_pending,"tp2"),
                                   pending_tp3,pending_tp4,pending_tp5,pending_final_tp,mode);
               }
            }
            else
            {
               ulong existing_pending=FindSeraPendingOrder(symbol);
               // Swing et Day partagent le meme symbole : seul le setup qui a place l'ordre peut l'annuler.
               int pending_owner=StoredState("SERA_PENDOWNER_",symbol);
               if(existing_pending>0 && (pending_owner==0 || pending_owner==(int)SeraHash(setup_id)))
               {
                  bool invalidated=(state==0)||(execution_state=="BLOCKED_RISK")||(setup_detected<=0)||(setup_direction!="" && setup_direction!=verdict);
                  bool now_market=directional_confirmed&&execution_state=="EXECUTE_NOW";
                  if(invalidated || now_market) CancelSeraPendingOrder(symbol,invalidated?"setup invalide":"passage EXECUTE_NOW");
               }
            }
         }

         if(!opened_this_cycle && directional_confirmed && execution_ready && symbol_can_trade && state!=previous_trade_state && OpenSeraPositions()<AllowedOpenPositions() && TradesToday()<AllowedTradesPerDay() && (!OnePositionPerSymbol || !HasSeraPositionOn(symbol)))
         {
            if(symbol=="")
            {
               Print("Sera: symbole MT5 introuvable pour ",market_name," / ",deriv_code," — ordre ignore");
            }
            else
            {
               string levels=JsonObject(object,"levels");
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
                  PanelGate(pr,8,spread_ok&&chase_ok&&levels_valid&&final_valid&&broker_stops_ok,
                            !spread_ok?"spread trop large":!chase_ok?"prix trop loin de l'entree calculee":!broker_stops_ok?"SL/TP trop proches pour le broker":!(levels_valid&&final_valid)?"niveaux depasses":"");
                  string broker_why="";
                  bool broker_trend_ok=trial_volume>0 && BrokerConfirms(symbol,verdict,broker_why);
                  if(trial_volume>0) PanelGate(pr,9,broker_trend_ok,broker_why);
                  bool risk_ok=volume>0 && TotalRiskAllows(PositionRiskUSD(symbol,verdict=="BUY"?POSITION_TYPE_BUY:POSITION_TYPE_SELL,price,sl,volume));
                  if(trial_volume>0) PanelGate(pr,10,margin_ok&&risk_ok,!margin_ok?"marge libre insuffisante":!risk_ok?"risque total maximum atteint":"lot "+DoubleToString(volume,2));
                  if(volume>0 && !broker_trend_ok)
                  {
                     PrintOnce("Sera: entree "+verdict+" "+symbol+" reportee — "+broker_why);
                     volume=0;
                     broker_why="skip";
                  }
                  if(volume>0 && !TotalRiskAllows(PositionRiskUSD(symbol,verdict=="BUY"?POSITION_TYPE_BUY:POSITION_TYPE_SELL,price,sl,volume)))
                  {
                     PrintOnce("Sera: entree "+verdict+" "+symbol+" reportee — risque cumule maximum atteint ("+DoubleToString(MaximumTotalOpenRiskPercent,1)+"% de l'equite)");
                     volume=0;
                     broker_why="skip";
                  }
                  if(volume>0)
                  {
                     CancelSeraPendingOrder(symbol,"ordre marche EXECUTE_NOW");
                     trade.SetExpertMagicNumber(MagicNumber);
                     trade.SetDeviationInPoints(DeviationPoints);
                     bool sent=verdict=="BUY"?trade.Buy(volume,symbol,0,sl,final_tp,"Sera EA Swing Intelligent v2.51"):trade.Sell(volume,symbol,0,sl,final_tp,"Sera EA Swing Intelligent v2.51");
                     if(sent)
                     {
                        StoreState("SERA_TRADESTATE_",setup_id,state);
                        StoreState("SERA_OPEN_",setup_id,1);
                        StoreTradeLevels(setup_id,symbol,signal_entry,tp1,tp2,tp3,tp4,tp5,final_tp,mode);
                        Print("Sera: ",verdict," ",symbol," volume=",volume," SL=",sl," final TP=",final_tp," management TP1-TP5 actif");
                        pr.opened=true;
                        StoreLevel("SERA_CONF_",symbol,confidence);
                        pr.decision="POSITION "+verdict+" OUVERTE : lot "+DoubleToString(volume,2)+", SL "+DoubleToString(sl,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS));
                        opened_this_cycle=true;
                     }
                     Print("Sera: ordre refuse: ",trade.ResultRetcodeDescription());
                     if(!pr.opened) pr.decision="ORDRE REFUSE PAR LE BROKER : "+trade.ResultRetcodeDescription();
                  }
                  else if(broker_why!="skip") Print("Sera: volume nul ou entree bloquee par les gardes spread/chase/niveaux pour ",symbol);
               }
               else Print("Sera: SL/TP ou tick invalide pour ",symbol);
            }
         }
         if(verdict=="BUY" || verdict=="SELL" || setup_detected>0)
         {
            if(pr.decision=="")
            {
               if(verdict!="BUY" && verdict!="SELL") pr.decision="SETUP "+setup_direction+" EN FORMATION : attendre le signal final";
               else if(!can_trade) pr.decision="BOT EN PAUSE : "+(g_trade_block!=""?g_trade_block:"trading automatique desactive");
               else if(FindSeraPendingOrder(symbol)>0) pr.decision="ORDRE LIMITE DEJA EN PLACE : attente du retour du prix";
               else if(symbol!="" && HasSeraPositionOn(symbol)) pr.decision="POSITION DEJA OUVERTE SUR CE MARCHE : gestion TP1-TP5 active";
               else if(execution_state=="WAIT_CONFIRMATION") pr.decision="ATTENTE : le moteur attend la confirmation (bougie suivante)";
               else if(execution_state=="BLOCKED_RISK") pr.decision="BLOQUE : risque de spike ou retournement recent";
               else
               {
                  string block=PanelFirstBlock(pr);
                  pr.decision=block!=""?"ATTENTE : "+block:"ATTENTE : entree au prochain cycle";
               }
            }
            int n=ArraySize(g_rows);
            ArrayResize(g_rows,n+1);
            g_rows[n]=pr;
         }
      }
      cursor=StringFind(json,"{",cursor+StringLen(object));
   }
   RenderDashboard();
}

int OnInit()
{
   trade.SetAsyncMode(false);
   EventSetTimer(MathMax(15,PollEverySeconds));
   long trade_mode=AccountInfoInteger(ACCOUNT_TRADE_MODE);
   string mode=trade_mode==ACCOUNT_TRADE_MODE_REAL?"REEL":trade_mode==ACCOUNT_TRADE_MODE_DEMO?"DEMO":"CONTEST";
   Comment("");
   RenderDashboard();
   Print("Sera EA Swing Intelligent Deriv v2.51: compte ",mode,", actif=",AssetProfileName(_Symbol),
         ", auto serveur=",EnableAutomaticTrading,", auto local=",EnableLocalAutoEntry,
         ", reel=",AllowRealAccount,", risk=",DoubleToString(RiskPercent,2),
         "%, asset factor=",DoubleToString(AssetRiskFactor(_Symbol),2),
         ", OSS guard=",UseOpenSourceModelGuard,", smart management=",EnableSmartPositionManagement);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){ EventKillTimer(); Comment(""); PanelClear(); }
void OnTimer()
{
   if(EmergencyEquityStop()) return;
   ManageAllSeraPositions();
   CutReversedPositions();
   RunLocalSwingIntelligence();
   string json;
   if(FetchSignals(json)) Evaluate(json);
   else { g_feed_ok=false; ArrayResize(g_rows,0); RenderDashboard(); }
}
