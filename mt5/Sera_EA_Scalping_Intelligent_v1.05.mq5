#property copyright "Sera EA Scalping Intelligent"
#property version   "1.05"
#property strict
#property description "Scalping M1 qui suit la bougie et la tendance (M5, M15) sur les indices Volatility, le Forex et la crypto (sans Boom/Crash). Plusieurs positions, benefice encaisse ou laisse courir, coupure au retournement."

#include <Trade/Trade.mqh>

// --- Marches
input string SymbolsList="";                 // vide = symboles de la Market Watch ; sinon "Volatility 75 Index,EURUSD,BTCUSD"
input bool TradeVolatilityIndices=true;      // Volatility 10..300 (et 1s) Deriv, FX Vol / SFX Vol Weltrade
input bool TradeForex=true;
input bool TradeCrypto=true;                 // BTC, ETH, LTC, XRP, SOL...
input bool TradeMetals=false;                // XAUUSD, XAGUSD
input bool TradeJumpStepIndices=false;       // Jump / Step (sauts de prix)
input int MaximumScannedSymbols=40;

// --- Trading
input bool EnableAutomaticTrading=true;
input bool AllowRealAccount=true;
input long MagicNumber=26103001;
input int DeviationPoints=30;
input int TimerSeconds=2;                    // controle des positions toutes les 2 s

// --- Analyse (M1 entree, M5 confirmation, M15 tendance)
input int MinimumScore=60;                   // score 0-100 pour entrer (v1.02 : 60, plus actif)
input bool RequireM15Trend=false;            // v1.02 : false = M15 ne doit pas etre CONTRE (neutre accepte)
input bool EnterIntraBar=true;               // v1.02 : entrer pendant la bougie des que le prix casse la bougie precedente
input double MinimumADX=18.0;                // force de tendance M5
input double MaximumSpreadRiskPercent=25.0;  // v1.03 : le spread ne doit pas couter plus de 25 % de la distance du SL
input double MaximumExtensionATR=2.5;        // pas d'entree si le prix est trop loin de l'EMA21 M1

// --- Risque
input double RiskPercent=0.30;               // risque par position (% de l'equite)
input double MaximumLot=0.0;                 // 0 = lot maximum du broker
input bool UseMinimumLotWhenRiskTooSmall=true;
input double MinimumLotMaxRiskPercent=3.0;   // petit compte : lot minimum accepte si son risque <= 3 % de l'equite
input double StopLossATR=1.5;                // SL = 1,5 x ATR M1 (ou sous/sur la derniere meche)
input double SafetyTakeProfitR=4.0;          // TP de securite chez le broker (en R = distance du SL)
input int MaximumPositionsPerSymbol=3;       // ajout seulement si les positions precedentes sont securisees
input int MaximumOpenPositions=0;            // 0 = pas de plafond : le risque total decide
input double MaximumTotalRiskPercent=10.0;   // risque cumule maximum (positions non securisees)
input int MinimumSecondsBetweenEntries=60;   // par symbole

// --- Sortie intelligente
input double TakeProfitMoney=0.50;           // v1.04 : objectif de gain par position en $ (0 = desactive) - encaisser des +0,50 $
input double BreakEvenMoney=0.20;            // v1.04 : des +0,20 $ le SL passe au prix d'entree + spread : plus de perte possible
input double SecureAtR=0.3;                  // ou des +0,3 R (le premier atteint)
input double TakeProfitR=1.0;                // objectif aussi atteint a +1 R (le premier atteint : $ ou R)
input bool LetProfitsRun=true;               // a l'objectif, si la tendance continue : rester, mais LockProfitPercent du gain verrouille
input double LockProfitPercent=70.0;         // part du gain garantie par le SL quand on laisse courir
input double TrailATR=1.0;                   // tendance qui continue : SL suiveur a 1 ATR M1 (jamais sous le gain verrouille)
input double GiveBackPercent=40.0;           // fermer si la position rend plus de 40 % de son meilleur gain
input bool CutOnReversal=true;               // couper des que la bougie et la tendance M5 se retournent
input int MaximumMinutesWithoutProgress=15;  // fermer une position qui n'avance pas

// --- Protection du compte
input double DailyLossLimitPercent=0.0;      // v1.05 : 0 = pas d'arret apres les pertes du jour (bot actif 24h/24)
input int MaximumConsecutiveLosses=0;        // v1.05 : 0 = pas de pause apres des pertes de suite
input int PauseAfterLossesMinutes=30;
input double EmergencyEquityStopPercent=15.0;
input bool AvoidForexRollover=false;         // v1.05 : false = Forex aussi autour de minuit serveur (24h/24)
input bool AvoidWeekendGap=true;             // pas d'entree Forex/metaux le vendredi soir

// --- Tableau de bord
input bool ShowDashboard=true;
input int DashboardX=10;
input int DashboardY=22;
input int DashboardMaxMarkets=12;

CTrade trade;

// ===================================================================================
//  ANALYSE DES BOUGIES (indicateurs calcules dans l'EA : aucun indicateur externe)
// ===================================================================================
struct TfState
{
   bool     ok;
   datetime barTime;
   double   open,high,low,close,prevHigh,prevLow;
   double   emaFast,emaSlow,emaTrend,emaTrendPrev;
   double   rsi,atr,adx,pdi,mdi;
   double   swingHigh,swingLow;
};

struct ScalpView
{
   string   symbol,klass,reason;
   bool     valid,fresh;
   int      t15,t5,c1,side,score,buyScore,sellScore;
   double   atr,spread,rsi,adx,price;
   double   lastHigh,lastLow,ema9;         // derniere bougie M1 cloturee (cassure pendant la bougie suivante)
   datetime bar;
   string   trigger;                       // "cloture" ou "cassure"
};

double EmaAt(const double &v[],const int n,const int period,const int back)
{
   double k=2.0/(period+1.0);
   double e=v[0];
   int last=n-1-back;
   for(int i=1;i<=last;i++) e=v[i]*k+e*(1.0-k);
   return e;
}

double RsiLast(const double &c[],const int n,const int period)
{
   if(n<=period+1) return 50.0;
   double gain=0,loss=0;
   for(int i=1;i<=period;i++){ double d=c[i]-c[i-1]; if(d>0) gain+=d; else loss-=d; }
   gain/=period; loss/=period;
   for(int i=period+1;i<n;i++)
   {
      double d=c[i]-c[i-1];
      gain=(gain*(period-1)+(d>0?d:0.0))/period;
      loss=(loss*(period-1)+(d<0?-d:0.0))/period;
   }
   if(loss<=0) return gain<=0?50.0:100.0;
   return 100.0-100.0/(1.0+gain/loss);
}

double AtrLast(const double &h[],const double &l[],const double &c[],const int n,const int period)
{
   if(n<=period+1) return 0;
   double atr=0;
   for(int i=1;i<=period;i++) atr+=MathMax(h[i]-l[i],MathMax(MathAbs(h[i]-c[i-1]),MathAbs(l[i]-c[i-1])));
   atr/=period;
   for(int i=period+1;i<n;i++)
   {
      double tr=MathMax(h[i]-l[i],MathMax(MathAbs(h[i]-c[i-1]),MathAbs(l[i]-c[i-1])));
      atr=(atr*(period-1)+tr)/period;
   }
   return atr;
}

void AdxLast(const double &h[],const double &l[],const double &c[],const int n,const int period,double &adx,double &pdi,double &mdi)
{
   adx=0; pdi=0; mdi=0;
   if(n<=period*2+1) return;
   double trS=0,pS=0,mS=0,dxS=0;
   int count=0;
   for(int i=1;i<n;i++)
   {
      double up=h[i]-h[i-1],down=l[i-1]-l[i];
      double pdm=(up>down && up>0)?up:0.0;
      double mdm=(down>up && down>0)?down:0.0;
      double tr=MathMax(h[i]-l[i],MathMax(MathAbs(h[i]-c[i-1]),MathAbs(l[i]-c[i-1])));
      if(i<=period){ trS+=tr; pS+=pdm; mS+=mdm; if(i<period) continue; }
      else { trS=trS-trS/period+tr; pS=pS-pS/period+pdm; mS=mS-mS/period+mdm; }
      if(trS<=0) continue;
      pdi=100.0*pS/trS; mdi=100.0*mS/trS;
      double dx=(pdi+mdi)>0?100.0*MathAbs(pdi-mdi)/(pdi+mdi):0.0;
      count++;
      if(count<=period){ dxS+=dx; if(count==period) adx=dxS/period; }
      else adx=(adx*(period-1)+dx)/period;
   }
}

bool Inspect(const string symbol,const ENUM_TIMEFRAMES tf,TfState &s)
{
   s.ok=false; s.barTime=0;
   MqlRates rates[];
   ArraySetAsSeries(rates,false);
   int n=CopyRates(symbol,tf,1,300,rates);     // bougies cloturees seulement
   if(n<120) return false;
   double h[],l[],c[];
   ArrayResize(h,n); ArrayResize(l,n); ArrayResize(c,n);
   for(int i=0;i<n;i++)
   {
      h[i]=rates[i].high; l[i]=rates[i].low; c[i]=rates[i].close;
      if(c[i]<=0 || l[i]<=0) return false;
   }
   s.barTime=rates[n-1].time;
   s.open=rates[n-1].open; s.high=h[n-1]; s.low=l[n-1]; s.close=c[n-1];
   s.prevHigh=h[n-2]; s.prevLow=l[n-2];
   s.emaFast=EmaAt(c,n,9,0);
   s.emaSlow=EmaAt(c,n,21,0);
   s.emaTrend=EmaAt(c,n,50,0);
   s.emaTrendPrev=EmaAt(c,n,50,5);
   s.rsi=RsiLast(c,n,14);
   s.atr=AtrLast(h,l,c,n,14);
   AdxLast(h,l,c,n,14,s.adx,s.pdi,s.mdi);
   s.swingHigh=h[n-1]; s.swingLow=l[n-1];
   for(int i=n-5;i<n;i++){ if(h[i]>s.swingHigh) s.swingHigh=h[i]; if(l[i]<s.swingLow) s.swingLow=l[i]; }
   s.ok=s.atr>0;
   return s.ok;
}

// Tendance M15 : prix et EMA50 dans le meme sens. Tendance M5 : EMA9/EMA21. Bougie M1 : corps franc au-dela de l'EMA9.
int TrendM15(const TfState &s)
{
   if(s.close>s.emaTrend && s.emaTrend>s.emaTrendPrev) return 1;
   if(s.close<s.emaTrend && s.emaTrend<s.emaTrendPrev) return -1;
   return 0;
}

int TrendM5(const TfState &s)
{
   if(s.emaFast>s.emaSlow && s.close>s.emaSlow) return 1;
   if(s.emaFast<s.emaSlow && s.close<s.emaSlow) return -1;
   return 0;
}

int CandleM1(const TfState &s)
{
   double range=s.high-s.low;
   if(range<=0) return 0;
   double body=MathAbs(s.close-s.open);
   if(body<range*0.5) return 0;
   if(s.close>s.open && s.close>s.emaFast) return 1;
   if(s.close<s.open && s.close<s.emaFast) return -1;
   return 0;
}

int ScoreFor(const int dir,const TfState &m1,const TfState &m5,const TfState &m15)
{
   int score=0;
   if(TrendM15(m15)==dir) score+=25;
   if(dir>0?m15.emaSlow>m15.emaTrend:m15.emaSlow<m15.emaTrend) score+=5;
   if(TrendM5(m5)==dir) score+=20;
   if(m5.adx>=MinimumADX && (dir>0?m5.pdi>m5.mdi:m5.mdi>m5.pdi)) score+=15;
   if(CandleM1(m1)==dir) score+=15;
   if(dir>0?m1.close>m1.prevHigh:m1.close<m1.prevLow) score+=10;
   if(dir>0?(m1.rsi>=52 && m1.rsi<=72):(m1.rsi<=48 && m1.rsi>=28)) score+=10;
   if(dir>0?m1.rsi>78:m1.rsi<22) score-=20;                                   // epuisement
   if(m1.atr>0 && MathAbs(m1.close-m1.emaSlow)/m1.atr>MaximumExtensionATR) score-=15;   // poursuite du prix
   return (int)MathMax(0,MathMin(100,score));
}

// ===================================================================================
//  MARCHES : indices Volatility, Forex, crypto (Boom / Crash / GainX / PainX exclus)
// ===================================================================================
string ScalpClass(const string name)
{
   string up=name;
   StringToUpper(up);
   if(StringFind(up,"BOOM")>=0 || StringFind(up,"CRASH")>=0 || StringFind(up,"GAINX")>=0 || StringFind(up,"PAINX")>=0) return "";
   if(StringFind(up,"JUMP")>=0 || StringFind(up,"STEP")>=0) return "JUMP";
   if(StringFind(up,"VOLATILITY")>=0 || StringFind(up,"FX VOL")>=0 || StringFind(up,"SFX VOL")>=0 || StringFind(up,"1HZ")==0 || StringFind(up,"R_")==0) return "VOL";
   string clean=up;
   if(StringFind(clean,"FRX")==0) clean=StringSubstr(clean,3);
   string crypto[];
   int coins=StringSplit("BTC,ETH,LTC,XRP,BCH,ADA,DOT,SOL,DOGE,BNB,XLM,EOS,TRX,LINK,AVAX,MATIC,UNI,SHIB,TON,XMR",',',crypto);
   for(int i=0;i<coins;i++) if(StringFind(clean,crypto[i])==0) return "CRYPTO";
   if(StringFind(clean,"XAU")==0 || StringFind(clean,"XAG")==0 || StringFind(clean,"XPT")==0 || StringFind(clean,"XPD")==0) return "METAL";
   string letters="";
   for(int i=0;i<StringLen(clean) && StringLen(letters)<6;i++)
   {
      ushort ch=StringGetCharacter(clean,i);
      if(ch>='A' && ch<='Z') letters+=StringSubstr(clean,i,1);
      else if(StringLen(letters)>0 && StringLen(letters)<6) break;
   }
   if(StringLen(letters)!=6) return "";
   string ccy="USD EUR GBP JPY CHF CAD AUD NZD SEK NOK DKK SGD HKD ZAR MXN TRY PLN CNH HUF CZK";
   if(StringFind(ccy,StringSubstr(letters,0,3))>=0 && StringFind(ccy,StringSubstr(letters,3,3))>=0) return "FX";
   return "";
}

bool ClassEnabled(const string klass)
{
   if(klass=="VOL") return TradeVolatilityIndices;
   if(klass=="FX") return TradeForex;
   if(klass=="CRYPTO") return TradeCrypto;
   if(klass=="METAL") return TradeMetals;
   if(klass=="JUMP") return TradeJumpStepIndices;
   return false;
}

string ClassLabel(const string klass)
{
   if(klass=="VOL") return "Volatility";
   if(klass=="FX") return "Forex";
   if(klass=="CRYPTO") return "Crypto";
   if(klass=="METAL") return "Metal";
   if(klass=="JUMP") return "Jump/Step";
   return "-";
}

ScalpView g_views[];
datetime  g_last_symbol_refresh=0;
string    g_events[];
string    g_pause_reason="";
string    g_blocked_logged[];

// Journal : pourquoi un signal pret n'a pas donne d'entree (une fois par symbole et par raison).
void LogBlockedOnce(const string symbol,const string reason)
{
   string key=reason;
   int cut=StringFind(key,"(");
   if(cut<0) cut=StringFind(key,"%");
   if(cut>0) key=StringSubstr(key,0,cut);
   key=symbol+"|"+key;
   for(int i=0;i<ArraySize(g_blocked_logged);i++) if(g_blocked_logged[i]==key) return;
   int n=ArraySize(g_blocked_logged);
   if(n>=300){ ArrayResize(g_blocked_logged,0); n=0; }
   ArrayResize(g_blocked_logged,n+1);
   g_blocked_logged[n]=key;
   Print("Sera Scalping: ",symbol," pret mais pas d'entree - ",reason);
}
double    g_day_pnl=0;
int       g_consecutive_losses=0;
datetime  g_last_loss_time=0;
datetime  g_last_stats=0;
bool      g_emergency_today=false;
int       g_emergency_day=-1;

void Note(const string message)
{
   Print("Sera Scalping: ",message);
   MqlDateTime t;
   TimeToStruct(TimeCurrent(),t);
   string stamp=(t.hour<10?"0":"")+IntegerToString(t.hour)+":"+(t.min<10?"0":"")+IntegerToString(t.min)+":"+(t.sec<10?"0":"")+IntegerToString(t.sec);
   int n=ArraySize(g_events);
   if(n>=6)
   {
      for(int i=1;i<n;i++) g_events[i-1]=g_events[i];
      n=5;
   }
   ArrayResize(g_events,n+1);
   g_events[n]=stamp+"  "+message;
}

void AddSymbol(const string name)
{
   for(int i=0;i<ArraySize(g_views);i++) if(g_views[i].symbol==name) return;
   string klass=ScalpClass(name);
   if(klass=="" || !ClassEnabled(klass) || !SymbolSelect(name,true)) return;
   int n=ArraySize(g_views);
   ArrayResize(g_views,n+1);
   g_views[n].symbol=name; g_views[n].klass=klass; g_views[n].reason="analyse en cours";
   g_views[n].valid=false; g_views[n].fresh=false; g_views[n].bar=0;
   g_views[n].t15=0; g_views[n].t5=0; g_views[n].c1=0; g_views[n].side=0; g_views[n].score=0;
   g_views[n].buyScore=0; g_views[n].sellScore=0;
   g_views[n].atr=0; g_views[n].spread=0; g_views[n].rsi=50; g_views[n].adx=0; g_views[n].price=0;
   g_views[n].lastHigh=0; g_views[n].lastLow=0; g_views[n].ema9=0; g_views[n].trigger="";
}

void RefreshSymbols()
{
   g_last_symbol_refresh=TimeCurrent();
   if(StringLen(SymbolsList)>0)
   {
      string parts[];
      int count=StringSplit(SymbolsList,',',parts);
      for(int i=0;i<count && ArraySize(g_views)<MaximumScannedSymbols;i++)
      {
         string name=parts[i];
         StringTrimLeft(name); StringTrimRight(name);
         if(name!="") AddSymbol(name);
      }
      return;
   }
   for(int i=0;i<SymbolsTotal(true) && ArraySize(g_views)<MaximumScannedSymbols;i++) AddSymbol(SymbolName(i,true));
}

int ViewIndex(const string symbol)
{
   for(int i=0;i<ArraySize(g_views);i++) if(g_views[i].symbol==symbol) return i;
   return -1;
}

// Forex et metaux : pas d'entree autour de minuit serveur (spreads larges) ni le vendredi soir / week-end.
string SessionBlock(const string klass)
{
   if(klass!="FX" && klass!="METAL") return "";
   MqlDateTime t;
   TimeToStruct(TimeCurrent(),t);
   if(AvoidWeekendGap && ((t.day_of_week==5 && t.hour>=21) || t.day_of_week==6 || t.day_of_week==0)) return "fermeture du week-end";
   if(AvoidForexRollover && ((t.hour==23 && t.min>=50) || (t.hour==0 && t.min<15))) return "minuit serveur (spreads larges)";
   return "";
}

// Analyse d'un symbole a chaque nouvelle bougie M1 cloturee.
void Analyze(ScalpView &v)
{
   TfState m1,m5,m15;
   v.valid=false;
   if(!Inspect(v.symbol,PERIOD_M1,m1) || !Inspect(v.symbol,PERIOD_M5,m5) || !Inspect(v.symbol,PERIOD_M15,m15))
   { v.reason="historique M1/M5/M15 insuffisant"; v.score=0; v.side=0; return; }
   v.valid=true;
   v.bar=m1.barTime;
   v.fresh=true;
   v.t15=TrendM15(m15); v.t5=TrendM5(m5); v.c1=CandleM1(m1);
   v.atr=m1.atr; v.rsi=m1.rsi; v.adx=m5.adx;
   v.lastHigh=m1.high; v.lastLow=m1.low; v.ema9=m1.emaFast; v.trigger="cloture";
   v.buyScore=ScoreFor(1,m1,m5,m15);
   v.sellScore=ScoreFor(-1,m1,m5,m15);
   v.side=0;
   int dir=v.buyScore>=v.sellScore?1:-1;
   v.score=dir>0?v.buyScore:v.sellScore;
   string sideText=dir>0?"BUY":"SELL";
   bool m15ok=RequireM15Trend?v.t15==dir:v.t15!=-dir;
   if(!m15ok) v.reason="tendance M15 "+(v.t15==0?"neutre":"contre "+sideText);
   else if(v.t5!=dir) v.reason="tendance M5 pas encore "+sideText;
   else if(v.c1!=dir) v.reason="attente d'une bougie M1 "+sideText+" franche";
   else if(v.score<MinimumScore) v.reason="score "+IntegerToString(v.score)+" < "+IntegerToString(MinimumScore);
   else { v.side=dir; v.reason=sideText+" pret (score "+IntegerToString(v.score)+")"; }
}

// ===================================================================================
//  POSITIONS, RISQUE ET LOTS
// ===================================================================================
double TickValue(const string symbol)
{
   double value=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(value<=0) value=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
   return value;
}

double LossMoney(const string symbol,const double distance,const double volume)
{
   double tickSize=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickSize<=0) return 0;
   return MathAbs(distance)/tickSize*TickValue(symbol)*volume;
}

double NormalizeVolume(const string symbol,const double lots)
{
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   double minLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   if(MaximumLot>0) maxLot=MathMin(maxLot,MaximumLot);
   if(step<=0) step=0.01;
   double v=MathFloor(lots/step)*step;
   if(v>maxLot) v=maxLot;
   if(v<minLot) return 0;
   return NormalizeDouble(v,8);
}

double LotForRisk(const string symbol,const double entry,const double sl)
{
   double riskMoney=AccountInfoDouble(ACCOUNT_EQUITY)*RiskPercent/100.0;
   double perLot=LossMoney(symbol,entry-sl,1.0);
   if(perLot<=0 || riskMoney<=0) return 0;
   double lots=NormalizeVolume(symbol,riskMoney/perLot);
   if(lots>0) return lots;
   double minLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   // petit compte : le lot minimum est accepte tant que son risque reste sous MinimumLotMaxRiskPercent de l'equite
   if(UseMinimumLotWhenRiskTooSmall && minLot>0 && perLot*minLot<=AccountInfoDouble(ACCOUNT_EQUITY)*MinimumLotMaxRiskPercent/100.0) return minLot;
   return 0;
}

string RKey(const ulong ticket){ return "SCALP_R_"+IntegerToString((long)ticket); }
string LastKey(const string symbol){ return "SCALP_LAST_"+symbol; }
string BarKey(const string symbol){ return "SCALP_BAR_"+symbol; }
datetime FormingBar(const string symbol){ return iTime(symbol,PERIOD_M1,0); }
string MaxRKey(const ulong ticket){ return "SCALP_MAXR_"+IntegerToString((long)ticket); }

int SeraPositions(const string symbol,const int dir)
{
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t<=0 || PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(symbol!="" && PositionGetString(POSITION_SYMBOL)!=symbol) continue;
      int d=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      if(dir==0 || d==dir) count++;
   }
   return count;
}

// Position "securisee" : son stop loss est au prix d'entree ou au-dela (plus de perte possible).
bool AllSecured(const string symbol,const int dir)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t<=0 || PositionGetInteger(POSITION_MAGIC)!=MagicNumber || PositionGetString(POSITION_SYMBOL)!=symbol) continue;
      double open=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL);
      if(sl<=0) return false;
      if(dir>0 && sl<open) return false;
      if(dir<0 && sl>open) return false;
   }
   return true;
}

// Argent perdu si tous les SL non securises etaient touches.
double OpenRiskMoney()
{
   double total=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t<=0 || PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      string sym=PositionGetString(POSITION_SYMBOL);
      bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
      double open=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL),vol=PositionGetDouble(POSITION_VOLUME);
      double loss=0;
      if(sl>0) loss=buy?open-sl:sl-open;
      else if(GlobalVariableCheck(RKey(t))) loss=GlobalVariableGet(RKey(t));
      if(loss>0) total+=LossMoney(sym,loss,vol);
   }
   return total;
}

bool Netting(){ return AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING; }

double StopsDistance(const string symbol)
{
   return (double)SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL)*SymbolInfoDouble(symbol,SYMBOL_POINT);
}

// ===================================================================================
//  PROTECTION DU COMPTE
// ===================================================================================
datetime DayStart()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(),t);
   t.hour=0; t.min=0; t.sec=0;
   return StructToTime(t);
}

void UpdateDailyStats()
{
   if(TimeCurrent()-g_last_stats<30) return;
   g_last_stats=TimeCurrent();
   g_day_pnl=0;
   g_consecutive_losses=0;
   if(!HistorySelect(DayStart()-86400*3,TimeCurrent())) return;
   int deals=HistoryDealsTotal();
   bool streak_open=true;
   for(int i=deals-1;i>=0;i--)
   {
      ulong d=HistoryDealGetTicket(i);
      if(d<=0 || HistoryDealGetInteger(d,DEAL_MAGIC)!=MagicNumber) continue;
      long entry=HistoryDealGetInteger(d,DEAL_ENTRY);
      if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) continue;
      double pnl=HistoryDealGetDouble(d,DEAL_PROFIT)+HistoryDealGetDouble(d,DEAL_SWAP)+HistoryDealGetDouble(d,DEAL_COMMISSION);
      datetime when=(datetime)HistoryDealGetInteger(d,DEAL_TIME);
      if(when>=DayStart()) g_day_pnl+=pnl;
      if(streak_open)
      {
         if(pnl<0){ g_consecutive_losses++; if(g_last_loss_time<when) g_last_loss_time=when; }
         else streak_open=false;
      }
   }
}

double FloatingPnl()
{
   double total=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t<=0 || PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      total+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   }
   return total;
}

void CloseAll(const string reason)
{
   trade.SetExpertMagicNumber(MagicNumber);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t<=0 || PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      trade.PositionClose(t);
   }
   Note("toutes les positions fermees - "+reason);
}

// Renvoie la raison de la pause des nouvelles entrees ("" = entrees autorisees).
string AccountPause()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(),t);
   if(g_emergency_day!=t.day_of_year) g_emergency_today=false;
   double balance=AccountInfoDouble(ACCOUNT_BALANCE),equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(EmergencyEquityStopPercent>0 && balance>0 && (balance-equity)/balance*100.0>=EmergencyEquityStopPercent && !g_emergency_today)
   {
      CloseAll("arret d'urgence : equite -"+DoubleToString((balance-equity)/balance*100.0,1)+"%");
      g_emergency_today=true; g_emergency_day=t.day_of_year;
   }
   if(g_emergency_today) return "arret d'urgence declenche aujourd'hui";
   UpdateDailyStats();
   double dayLoss=-(g_day_pnl+FloatingPnl());
   if(DailyLossLimitPercent>0 && balance>0 && dayLoss>=balance*DailyLossLimitPercent/100.0)
      return "perte du jour -"+DoubleToString(DailyLossLimitPercent,1)+"% atteinte (reprise demain)";
   if(MaximumConsecutiveLosses>0 && g_consecutive_losses>=MaximumConsecutiveLosses
      && TimeCurrent()-g_last_loss_time<PauseAfterLossesMinutes*60)
      return IntegerToString(g_consecutive_losses)+" pertes de suite : pause "+IntegerToString(PauseAfterLossesMinutes)+" min";
   return "";
}

// ===================================================================================
//  GESTION DES POSITIONS : securiser, encaisser, laisser courir, couper au retournement
// ===================================================================================
// Retournement : bougie M1 franche contre la position ET (tendance M5 contre OU RSI de l'autre cote de 50),
// ou tendances M15 et M5 toutes les deux contre.
bool ReversalAgainst(const ScalpView &v,const int dir)
{
   if(!v.valid) return false;
   if(v.c1==-dir && (v.t5==-dir || (dir>0?v.rsi<45:v.rsi>55))) return true;
   if(v.t15==-dir && v.t5==-dir) return true;
   return false;
}

// La tendance continue : M5 dans le sens, pas de bougie contre, RSI pas epuise.
bool MomentumWith(const ScalpView &v,const int dir)
{
   if(!v.valid) return false;
   return v.t5==dir && v.c1!=-dir && (dir>0?v.rsi<80:v.rsi>20);
}

bool ClosePosition(const ulong ticket,const string symbol,const string why,const double r)
{
   trade.SetExpertMagicNumber(MagicNumber);
   if(!trade.PositionClose(ticket)){ Print("Sera Scalping: fermeture refusee ",symbol," ",trade.ResultRetcodeDescription()); return false; }
   Note(symbol+" ferme ("+DoubleToString(r,2)+" R) - "+why);
   GlobalVariableDel(RKey(ticket));
   GlobalVariableDel(MaxRKey(ticket));
   GlobalVariableDel("SCALP_MAXM_"+IntegerToString((long)ticket));
   return true;
}

void MoveStop(const ulong ticket,const string symbol,const double sl,const double tp,const string why)
{
   trade.SetExpertMagicNumber(MagicNumber);
   int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   if(trade.PositionModify(ticket,NormalizeDouble(sl,digits),tp)) Note(symbol+" "+why+" (SL "+DoubleToString(sl,digits)+")");
}

string MaxMKey(const ulong ticket){ return "SCALP_MAXM_"+IntegerToString((long)ticket); }

// Priorite au gain : un gain atteint est encaisse ou verrouille, une position en gain ne repasse jamais en perte.
void ManagePositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket<=0 || PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      string symbol=PositionGetString(POSITION_SYMBOL);
      int dir=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      double open=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
      double money=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
      MqlTick tick;
      if(!SymbolInfoTick(symbol,tick)) continue;
      double price=dir>0?tick.bid:tick.ask;
      double spread=tick.ask-tick.bid;
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);

      int vi=ViewIndex(symbol);
      if(vi<0){ AddSymbol(symbol); vi=ViewIndex(symbol); }
      if(vi<0) continue;
      double atr=g_views[vi].atr;

      if(!GlobalVariableCheck(RKey(ticket)))
      {
         double initial=sl>0?MathAbs(open-sl):atr*StopLossATR;
         GlobalVariableSet(RKey(ticket),initial);
      }
      double r=GlobalVariableGet(RKey(ticket));
      if(r<=0) r=atr>0?atr*StopLossATR:MathAbs(open)*0.001;
      double pr=(dir>0?price-open:open-price)/r;
      double best=GlobalVariableCheck(MaxRKey(ticket))?GlobalVariableGet(MaxRKey(ticket)):0.0;
      if(pr>best){ best=pr; GlobalVariableSet(MaxRKey(ticket),best); }
      double bestMoney=GlobalVariableCheck(MaxMKey(ticket))?GlobalVariableGet(MaxMKey(ticket)):0.0;
      if(money>bestMoney){ bestMoney=money; GlobalVariableSet(MaxMKey(ticket),bestMoney); }
      string gain=(money>=0?"+":"")+DoubleToString(money,2)+" $";

      // 1. Changement de direction detecte : on coupe tout de suite (en gain on encaisse, en perte on limite).
      if(CutOnReversal && ReversalAgainst(g_views[vi],dir))
      {
         string why="retournement detecte (bougie M1 et tendance contre) "+gain;
         if(money>0) why="gain encaisse : "+why;
         if(ClosePosition(ticket,symbol,why,pr))
            GlobalVariableSet(BarKey(symbol),(double)FormingBar(symbol));   // pas de nouvelle entree sur cette bougie
         continue;
      }

      bool target=(TakeProfitMoney>0 && money>=TakeProfitMoney) || pr>=TakeProfitR;
      bool wasTarget=(TakeProfitMoney>0 && bestMoney>=TakeProfitMoney) || best>=TakeProfitR;

      // 2. Le gain retombe : on encaisse ce qui reste avant qu'il disparaisse.
      if(wasTarget && money>0 && money<bestMoney*(1.0-GiveBackPercent/100.0))
      { ClosePosition(ticket,symbol,"gain protege "+gain+" (meilleur +"+DoubleToString(bestMoney,2)+" $)",pr); continue; }

      // 3. Objectif atteint ($ ou R) : encaisser, sauf si la tendance continue (alors gain verrouille + SL suiveur).
      if(target)
      {
         if(!LetProfitsRun || !MomentumWith(g_views[vi],dir))
         { ClosePosition(ticket,symbol,"benefice encaisse "+gain+" (objectif atteint)",pr); continue; }
         double locked=open+(price-open)*LockProfitPercent/100.0;      // LockProfitPercent du gain actuel
         double trail=price-dir*atr*TrailATR;
         double want=dir>0?MathMax(locked,trail):MathMin(locked,trail);
         bool better=dir>0?(sl<=0 || want>sl+point):(sl<=0 || want<sl-point);
         if(better && MathAbs(price-want)>StopsDistance(symbol))
            MoveStop(ticket,symbol,want,tp,"objectif atteint "+gain+", la tendance continue : "+DoubleToString(LockProfitPercent,0)+"% du gain verrouille");
         else if(better)
         { ClosePosition(ticket,symbol,"benefice encaisse "+gain+" (SL impossible a rapprocher)",pr); continue; }
         continue;
      }

      // 4. Des le premier petit gain : SL au prix d'entree + spread -> la position ne peut plus finir en perte.
      if((BreakEvenMoney>0 && money>=BreakEvenMoney) || pr>=SecureAtR)
      {
         double be=open+dir*(spread+2*point);
         bool better=dir>0?(sl<=0 || be>sl+point):(sl<=0 || be<sl-point);
         if(better && MathAbs(price-be)>StopsDistance(symbol)) MoveStop(ticket,symbol,be,tp,"position securisee "+gain+" (SL au prix d'entree)");
         continue;
      }

      // 5. Position qui n'avance pas : on sort, en petit gain si possible.
      if(MaximumMinutesWithoutProgress>0 && TimeCurrent()-opened>=MaximumMinutesWithoutProgress*60 && pr<0.3)
         ClosePosition(ticket,symbol,"pas de progression en "+IntegerToString(MaximumMinutesWithoutProgress)+" min ("+gain+")",pr);
   }
}

// ===================================================================================
//  ENTREES
// ===================================================================================

bool TryEntry(ScalpView &v,const bool can_trade)
{
   int dir=v.side;
   if(dir==0) return false;
   string sideText=dir>0?"BUY":"SELL";
   if(!can_trade){ v.reason=sideText+" pret : trading automatique en pause"; return false; }
   string session=SessionBlock(v.klass);
   if(session!=""){ v.reason=sideText+" pret mais "+session; return false; }
   if(SeraPositions(v.symbol,-dir)>0){ v.reason=sideText+" pret : position inverse encore ouverte"; return false; }
   int same=SeraPositions(v.symbol,dir);
   int perSymbol=Netting()?1:MathMax(1,MaximumPositionsPerSymbol);
   if(same>=perSymbol){ v.reason=sideText+" : "+IntegerToString(same)+" position(s) deja ouverte(s), maximum atteint"; return false; }
   if(same>0 && !AllSecured(v.symbol,dir)){ v.reason=sideText+" : ajout quand la position est securisee"; return false; }
   if(MaximumOpenPositions>0 && SeraPositions("",0)>=MaximumOpenPositions){ v.reason=sideText+" : nombre maximum de positions atteint"; return false; }
   if(GlobalVariableCheck(BarKey(v.symbol)) && (datetime)GlobalVariableGet(BarKey(v.symbol))==FormingBar(v.symbol)) return false;   // une entree par bougie
   if(GlobalVariableCheck(LastKey(v.symbol)) && TimeCurrent()-(datetime)GlobalVariableGet(LastKey(v.symbol))<MinimumSecondsBetweenEntries)
   { v.reason=sideText+" : delai entre deux entrees"; return false; }

   MqlTick tick;
   if(!SymbolInfoTick(v.symbol,tick) || tick.bid<=0){ v.reason="pas de prix"; return false; }
   if(v.klass!="VOL" && v.klass!="JUMP" && TimeCurrent()-tick.time>180){ v.reason="marche ferme (pas de cotation)"; return false; }
   double spread=tick.ask-tick.bid;
   v.spread=spread;
   if(v.atr<=0){ v.reason="ATR M1 indisponible"; return false; }

   double price=dir>0?tick.ask:tick.bid;
   TfState m1;
   if(!Inspect(v.symbol,PERIOD_M1,m1)) return false;
   double sl=dir>0?MathMin(price-v.atr*StopLossATR,m1.swingLow-v.atr*0.2):MathMax(price+v.atr*StopLossATR,m1.swingHigh+v.atr*0.2);
   double dist=MathAbs(price-sl);
   if(dist>v.atr*3.0){ dist=v.atr*3.0; sl=price-dir*dist; }
   double room=StopsDistance(v.symbol)+spread;
   if(dist<=room){ dist=room*1.5; sl=price-dir*dist; }
   // Le spread est un cout fixe a chaque entree : il ne doit pas manger plus de MaximumSpreadRiskPercent du risque (SL).
   if(spread>dist*MaximumSpreadRiskPercent/100.0)
   { v.reason=sideText+" pret mais spread = "+DoubleToString(spread/dist*100.0,0)+"% du SL (max "+DoubleToString(MaximumSpreadRiskPercent,0)+"%)"; return false; }
   double tp=price+dir*dist*SafetyTakeProfitR;
   int digits=(int)SymbolInfoInteger(v.symbol,SYMBOL_DIGITS);
   sl=NormalizeDouble(sl,digits); tp=NormalizeDouble(tp,digits);

   double volume=LotForRisk(v.symbol,price,sl);
   if(volume<=0)
   {
      double minLot=SymbolInfoDouble(v.symbol,SYMBOL_VOLUME_MIN);
      double equity=AccountInfoDouble(ACCOUNT_EQUITY);
      double pct=equity>0?LossMoney(v.symbol,dist,minLot)/equity*100.0:0;
      v.reason=sideText+" : lot min. risque "+DoubleToString(pct,1)+"% (max "+DoubleToString(MinimumLotMaxRiskPercent,1)+"%)";
      return false;
   }
   double margin=0;
   if(!OrderCalcMargin(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,v.symbol,volume,price,margin) || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)*0.5)
   { v.reason=sideText+" : marge libre insuffisante"; return false; }
   double budget=AccountInfoDouble(ACCOUNT_EQUITY)*MaximumTotalRiskPercent/100.0;
   if(OpenRiskMoney()+LossMoney(v.symbol,dist,volume)>budget)
   { v.reason=sideText+" : risque total maximum ("+DoubleToString(MaximumTotalRiskPercent,0)+"%) atteint"; return false; }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(DeviationPoints);
   string comment="Sera Scalping v1.05";
   bool sent=dir>0?trade.Buy(volume,v.symbol,0,sl,tp,comment):trade.Sell(volume,v.symbol,0,sl,tp,comment);
   if(!sent){ v.reason="ordre refuse : "+trade.ResultRetcodeDescription(); Print("Sera Scalping: ordre refuse ",v.symbol," ",trade.ResultRetcodeDescription()); return false; }
   GlobalVariableSet(LastKey(v.symbol),(double)TimeCurrent());
   GlobalVariableSet(BarKey(v.symbol),(double)FormingBar(v.symbol));
   // memorise le risque initial (R) de la nouvelle position
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t>0 && PositionGetInteger(POSITION_MAGIC)==MagicNumber && PositionGetString(POSITION_SYMBOL)==v.symbol && !GlobalVariableCheck(RKey(t)))
         GlobalVariableSet(RKey(t),dist);
   }
   v.reason=sideText+" ouvert ("+v.trigger+", score "+IntegerToString(v.score)+")";
   Note(sideText+" "+v.symbol+" lot "+DoubleToString(volume,2)+"  SL "+DoubleToString(sl,digits)+"  "+v.trigger+" score "+IntegerToString(v.score)+
        (same>0?"  (ajout n."+IntegerToString(same+1)+")":""));
   return true;
}

// Analyse de chaque symbole des qu'une nouvelle bougie M1 est cloturee (avant de gerer les positions).
void RefreshAnalysis()
{
   if(TimeCurrent()-g_last_symbol_refresh>600 || ArraySize(g_views)==0) RefreshSymbols();
   for(int i=0;i<ArraySize(g_views);i++)
   {
      datetime bar=iTime(g_views[i].symbol,PERIOD_M1,1);
      if(bar==0){ g_views[i].reason="pas de bougies"; g_views[i].valid=false; continue; }
      if(bar!=g_views[i].bar || !g_views[i].valid) Analyze(g_views[i]);
      MqlTick tick;
      if(SymbolInfoTick(g_views[i].symbol,tick)){ g_views[i].price=tick.bid; g_views[i].spread=tick.ask-tick.bid; }
   }
}

// Cassure pendant la bougie : le prix depasse le haut (BUY) / le bas (SELL) de la derniere bougie cloturee,
// au-dela de l'EMA9, dans le sens de la tendance M5, M15 pas contre, RSI pas epuise, score suffisant.
int BreakoutSide(ScalpView &v)
{
   if(!EnterIntraBar || !v.valid || v.atr<=0) return 0;
   MqlTick tick;
   if(!SymbolInfoTick(v.symbol,tick)) return 0;
   double buffer=MathMax(tick.ask-tick.bid,v.atr*0.05);
   for(int dir=1;dir>=-1;dir-=2)
   {
      if(v.t5!=dir) continue;
      if(RequireM15Trend?v.t15!=dir:v.t15==-dir) continue;
      int score=dir>0?v.buyScore:v.sellScore;
      if(score<MinimumScore-10) continue;
      if(dir>0?v.rsi>75:v.rsi<25) continue;
      bool broke=dir>0?(tick.bid>v.lastHigh+buffer && tick.bid>v.ema9):(tick.ask<v.lastLow-buffer && tick.ask<v.ema9);
      if(broke) return dir;
   }
   return 0;
}

void ScanAndTrade(const bool can_trade)
{
   int n=ArraySize(g_views);
   // les meilleurs scores d'abord
   int order[];
   ArrayResize(order,n);
   for(int i=0;i<n;i++) order[i]=i;
   for(int a=0;a<n;a++)
      for(int b=a+1;b<n;b++)
         if(g_views[order[b]].score>g_views[order[a]].score){ int t=order[a]; order[a]=order[b]; order[b]=t; }
   for(int k=0;k<n;k++)
   {
      int i=order[k];
      if(!g_views[i].valid) continue;
      if(g_views[i].side!=0 && g_views[i].fresh)
      {
         g_views[i].trigger="cloture";
         if(!TryEntry(g_views[i],can_trade) && StringFind(g_views[i].reason,"ouvert")<0)
            LogBlockedOnce(g_views[i].symbol,g_views[i].reason);
         g_views[i].fresh=false;     // une tentative a la cloture de chaque bougie M1
         continue;
      }
      // Pendant la bougie : cassure de la bougie precedente (une entree maximum par bougie)
      int breakout=BreakoutSide(g_views[i]);
      if(breakout!=0 && !(GlobalVariableCheck(BarKey(g_views[i].symbol)) && (datetime)GlobalVariableGet(BarKey(g_views[i].symbol))==FormingBar(g_views[i].symbol)))
      {
         int saved=g_views[i].side;
         g_views[i].side=breakout;
         g_views[i].trigger="cassure";
         if(!TryEntry(g_views[i],can_trade) && StringFind(g_views[i].reason,"ouvert")<0)
            LogBlockedOnce(g_views[i].symbol,g_views[i].reason);
         if(StringFind(g_views[i].reason,"ouvert")<0) g_views[i].side=saved;
      }
   }
}

// ===================================================================================
//  TABLEAU DE BORD
// ===================================================================================
color Rgb(const int r,const int g,const int b){ return (color)(r|(g<<8)|(b<<16)); }
// MT5 coupe le texte d'un label a 63 caracteres : chaque ligne est ecrite en morceaux de 60 caracteres
// places cote a cote (police a chasse fixe). Une ligne vide recoit un espace (sinon MT5 affiche "Label").
int PanelCharWidth()
{
   long dpi=TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   if(dpi<72) dpi=96;
   return (int)MathRound(7.0*dpi/96.0);
}

int g_panel_maxlen=0;
int g_bar_count=0;

void PanelText(const int line,const string text,const color clr,const int size=9)
{
   if(StringLen(text)>g_panel_maxlen) g_panel_maxlen=StringLen(text);
   string shown=text==""?" ":text;
   int parts=(StringLen(shown)+59)/60;
   for(int p=0;p<4;p++)
   {
      string name="SCALP_PANEL_L"+IntegerToString(line);
      if(p>0) name+="_"+IntegerToString(p);
      if(p>=parts){ if(ObjectFind(0,name)>=0) ObjectDelete(0,name); continue; }
      if(ObjectFind(0,name)<0)
      {
         ObjectCreate(0,name,OBJ_LABEL,0,0,0);
         ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
         ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
         ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
      }
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,DashboardX+10+p*60*PanelCharWidth());
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,DashboardY+8+line*16);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
      ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
      ObjectSetString(0,name,OBJPROP_TEXT,StringSubstr(shown,p*60,60));
   }
}

void PanelBackground(const int lines)
{
   string name="SCALP_PANEL_BG";
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
   ObjectSetInteger(0,name,OBJPROP_XSIZE,(int)MathMax(420,g_panel_maxlen*PanelCharWidth()+24));
   ObjectSetInteger(0,name,OBJPROP_YSIZE,lines*16+14);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,Rgb(10,20,32));
   ObjectSetInteger(0,name,OBJPROP_COLOR,Rgb(40,70,100));
}

#define SCALP_BAR_COLUMN 118
void PanelBar(const int line,const double percent,const color clr)
{
   string names[2];
   names[0]="SCALP_PANEL_B"+IntegerToString(g_bar_count)+"_BG";
   names[1]="SCALP_PANEL_B"+IntegerToString(g_bar_count)+"_FG";
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
      ObjectSetInteger(0,names[k],OBJPROP_XDISTANCE,DashboardX+10+SCALP_BAR_COLUMN*PanelCharWidth());
      ObjectSetInteger(0,names[k],OBJPROP_YDISTANCE,DashboardY+8+line*16+3);
      ObjectSetInteger(0,names[k],OBJPROP_XSIZE,k==0?100:(int)MathMax(1,pct));
      ObjectSetInteger(0,names[k],OBJPROP_YSIZE,9);
      ObjectSetInteger(0,names[k],OBJPROP_BGCOLOR,k==0?Rgb(32,44,60):clr);
      ObjectSetInteger(0,names[k],OBJPROP_COLOR,k==0?Rgb(32,44,60):clr);
   }
   if(SCALP_BAR_COLUMN+16>g_panel_maxlen) g_panel_maxlen=SCALP_BAR_COLUMN+16;
}

void PanelClear(){ ObjectsDeleteAll(0,"SCALP_PANEL_"); }

string Pad(const string text,const int width)
{
   string out=StringLen(text)>width?StringSubstr(text,0,width):text;
   while(StringLen(out)<width) out+=" ";
   return out;
}

string TrendText(const int t){ if(t>0) return "hausse"; if(t<0) return "baisse"; return "neutre"; }

int g_fit_lines=1000;
void FitToChart()
{
   long height=ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   g_fit_lines=height>0?(int)((height-DashboardY-8)/16):1000;
}

void RenderDashboard(const bool can_trade,const string pause)
{
   if(!ShowDashboard){ PanelClear(); return; }
   color white=Rgb(220,232,245),grey=Rgb(130,148,168),green=Rgb(56,232,187),red=Rgb(255,95,118),
         amber=Rgb(255,190,80),cyan=Rgb(84,216,255),blue=Rgb(77,163,255);
   g_panel_maxlen=0; g_bar_count=0;
   if(ObjectFind(0,"SCALP_PANEL_BG")<0){ PanelClear(); PanelBackground(1); }   // le fond d'abord (dessine dessous)
   FitToChart();
   int line=0;
   bool algo=TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED);
   bool demo=AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO;
   string account=demo?"DEMO":"REEL";
   PanelText(line++,"SERA EA SCALPING INTELLIGENT v1.05",amber,10);
   if(can_trade) PanelText(line++,"BOT ACTIF  |  compte "+account+"  |  scalping M1 : cloture + cassure"+(EnterIntraBar?"":" (cassure off)"),green);
   else if(!algo) PanelText(line++,"BOT EN PAUSE  |  activez le bouton Algo Trading de MT5",red);
   else if(pause!="") PanelText(line++,"BOT EN PAUSE  |  "+pause,red);
   else PanelText(line++,"BOT EN PAUSE  |  trading automatique desactive dans les parametres",red);

   double balance=AccountInfoDouble(ACCOUNT_BALANCE),equity=AccountInfoDouble(ACCOUNT_EQUITY),risk=OpenRiskMoney();
   PanelText(line++,"Compte : balance "+DoubleToString(balance,2)+"  equite "+DoubleToString(equity,2)+"  |  positions "+IntegerToString(SeraPositions("",0))+
             "  |  risque ouvert "+DoubleToString(risk,2)+" ("+DoubleToString(equity>0?risk/equity*100.0:0.0,1)+"% / max "+DoubleToString(MaximumTotalRiskPercent,0)+"%)",white);
   double day=g_day_pnl+FloatingPnl();
   string dayText=day>=0?"+":"";
   string lossText="";
   if(MaximumConsecutiveLosses>0) lossText="  |  pertes de suite "+IntegerToString(g_consecutive_losses)+"/"+IntegerToString(MaximumConsecutiveLosses);
   string limitText=DailyLossLimitPercent>0?" (limite -"+DoubleToString(DailyLossLimitPercent,1)+"%)":" (actif 24h/24, pas de pause)";
   PanelText(line++,"Jour : "+dayText+DoubleToString(day,2)+limitText+"  |  objectif +"+DoubleToString(TakeProfitMoney,2)+
             " $ par position, SL a l'entree des +"+DoubleToString(BreakEvenMoney,2)+" $"+lossText+
             (Netting()?"  |  compte netting : 1 position par symbole":""),grey);

   // Positions
   PanelText(line++,"",grey);
   int open=SeraPositions("",0);
   PanelText(line++,"POSITIONS SCALPING ("+IntegerToString(open)+")",amber);
   if(open==0) PanelText(line++,"  Aucune position pour le moment.",grey);
   else PanelText(line++,"  "+Pad("Symbole",27)+Pad("Sens",6)+Pad("Lot",8)+Pad("Entree",13)+Pad("SL",13)+Pad("Resultat",11)+Pad("R",7)+"Etat",grey);
   int shown=0;
   for(int i=PositionsTotal()-1;i>=0 && shown<12;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t<=0 || PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      string sym=PositionGetString(POSITION_SYMBOL);
      bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
      int digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
      double op=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL);
      double pnl=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      double r=GlobalVariableCheck(RKey(t))?GlobalVariableGet(RKey(t)):0;
      MqlTick tick;
      double pr=0;
      if(r>0 && SymbolInfoTick(sym,tick)) pr=(buy?tick.bid-op:op-tick.ask)/r;
      bool secured=sl>0 && (buy?sl>=op:sl<=op);
      bool reached=pr>=TakeProfitR || (TakeProfitMoney>0 && pnl>=TakeProfitMoney);
      string state=secured?(reached?"gain verrouille, il court":"securisee (plus de perte)"):"en cours";
      PanelText(line++,"  "+Pad(sym,27)+Pad(buy?"BUY":"SELL",6)+Pad(DoubleToString(PositionGetDouble(POSITION_VOLUME),2),8)+Pad(DoubleToString(op,digits),13)+
                Pad(DoubleToString(sl,digits),13)+Pad((pnl>=0?"+":"")+DoubleToString(pnl,2),11)+Pad(DoubleToString(pr,2),7)+state,pnl>=0?blue:red);
      shown++;
   }
   if(open>shown) PanelText(line++,"  ... et "+IntegerToString(open-shown)+" autre(s)",grey);

   // Marches
   PanelText(line++,"",grey);
   int n=ArraySize(g_views);
   PanelText(line++,"MARCHES SCANNES ("+IntegerToString(n)+") : Volatility, Forex, crypto - les meilleurs scores d'abord",amber);
   if(n==0) PanelText(line++,"  Aucun symbole compatible dans la Market Watch (ajoutez Volatility 75 Index, EURUSD, BTCUSD...)",red);
   else PanelText(line++,"  "+Pad("Symbole",27)+Pad("Type",11)+Pad("M15",8)+Pad("M5",8)+Pad("Bougie",8)+Pad("Score",7)+"Etat",grey);
   int order[];
   ArrayResize(order,n);
   for(int i=0;i<n;i++) order[i]=i;
   for(int a=0;a<n;a++)
      for(int b=a+1;b<n;b++)
         if(g_views[order[b]].score>g_views[order[a]].score){ int tmp=order[a]; order[a]=order[b]; order[b]=tmp; }
   int room=(int)MathMax(3,MathMin(DashboardMaxMarkets,g_fit_lines-line-9));
   int listed=0;
   for(int k=0;k<n && listed<room;k++)
   {
      ScalpView v=g_views[order[k]];
      string candle=v.c1>0?"hausse":v.c1<0?"baisse":"-";
      color c=v.side!=0?white:(v.valid?cyan:grey);
      PanelText(line,"  "+Pad(v.symbol,27)+Pad(ClassLabel(v.klass),11)+Pad(TrendText(v.t15),8)+Pad(TrendText(v.t5),8)+Pad(candle,8)+
                Pad(IntegerToString(v.score),7)+Pad(v.reason,44),c);
      PanelBar(line,v.score,v.score>=MinimumScore?green:v.score>=MinimumScore-15?blue:amber);
      line++; listed++;
   }
   if(n>listed) PanelText(line++,"  ... et "+IntegerToString(n-listed)+" autre(s) symbole(s)",grey);

   // Journal
   PanelText(line++,"",grey);
   PanelText(line++,"DERNIERES ACTIONS",amber);
   if(ArraySize(g_events)==0) PanelText(line++,"  (aucune action pour le moment)",grey);
   for(int i=ArraySize(g_events)-1;i>=0;i--) PanelText(line++,"  "+g_events[i],StringFind(g_events[i]," ferme ")>=0?cyan:white);

   PanelBackground(line);
   for(int k=line;k<200;k++)
      for(int p=0;p<4;p++)
      {
         string name="SCALP_PANEL_L"+IntegerToString(k);
         if(p>0) name+="_"+IntegerToString(p);
         if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
      }
   for(int k=g_bar_count;k<200;k++)
   {
      string bg="SCALP_PANEL_B"+IntegerToString(k)+"_BG",fg="SCALP_PANEL_B"+IntegerToString(k)+"_FG";
      if(ObjectFind(0,bg)>=0) ObjectDelete(0,bg);
      if(ObjectFind(0,fg)>=0) ObjectDelete(0,fg);
   }
   ChartRedraw(0);
}

// ===================================================================================
//  EVENEMENTS MT5
// ===================================================================================
void Cycle()
{
   bool demo=AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO;
   bool algo=TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED);
   string pause=AccountPause();
   if(!demo && !AllowRealAccount) pause="compte reel non autorise (AllowRealAccount=false)";
   if(pause!=g_pause_reason){ if(pause!="") Note("nouvelles entrees en pause - "+pause); g_pause_reason=pause; }
   bool can_trade=EnableAutomaticTrading && algo && pause=="";
   RefreshAnalysis();          // 1. lire les nouvelles bougies
   ManagePositions();          // 2. proteger / encaisser / couper avec l'analyse a jour
   ScanAndTrade(can_trade);    // 3. chercher de nouvelles entrees
   RenderDashboard(can_trade,pause);
}

int OnInit()
{
   trade.SetAsyncMode(false);
   RefreshSymbols();
   EventSetTimer(MathMax(1,TimerSeconds));
   Print("Sera EA Scalping Intelligent v1.05 : ",ArraySize(g_views)," symboles (Volatility / Forex / crypto), risque ",
         DoubleToString(RiskPercent,2),"% par position, ",MaximumPositionsPerSymbol," position(s) max par symbole");
   if(ArraySize(g_views)==0)
      Print("Sera Scalping: aucun symbole compatible. Ajoutez des symboles a la Market Watch ou renseignez SymbolsList.");
   Cycle();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){ EventKillTimer(); PanelClear(); }

void OnTimer(){ Cycle(); }
