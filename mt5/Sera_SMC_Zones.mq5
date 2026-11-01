//+------------------------------------------------------------------+
//| Sera SMC Zones — indicateur graphique du projet Sera Indicator    |
//| Zones Premium / Equilibre / Discount du dernier swing,            |
//| Strong / Weak High-Low, balayages de liquidite et signaux Sera    |
//| (strategie mesuree « sens de la derive » + balayage SMC).         |
//+------------------------------------------------------------------+
#property copyright "Sera Indicator"
#property link      "https://serakatsuva.github.io/sera-indicator/"
#property version   "1.00"
#property description "Premium / Equilibre / Discount, Strong-Weak High/Low, balayages de liquidite."
#property description "Fleches BUY/SELL : signaux Sera mesures (sens de la derive + balayage) sur Boom, Crash, Bull/Bear Market, PainX, GainX, SwitchX, BreakX, TrendX."
#property description "Les autres marches (Volatility, Forex...) n'ont pas d'avantage mesure : seuls les zones et les balayages y sont affiches."
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   1
#property indicator_label1  "Tendance Sera"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrDodgerBlue,clrDarkOrange
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

input int  TrendPeriod=34;        // ligne de tendance (bleue = monte, orange = baisse)
input int  RangeBars=60;          // bougies du swing pour Premium / Equilibre / Discount
input int  SweepLookback=20;      // balayage : plus bas / plus haut des N bougies precedentes
input int  HistoryBars=500;       // fleches et balayages dessines sur les N dernieres bougies
input bool ShowZones=true;
input bool ShowSignals=true;
input bool ShowSweeps=true;

double TrendBuf[];
double TrendColor[];
datetime g_last_draw=0;
// Nom d'objet de l'indicateur (prefixe commun, supprime au retrait de l'indicateur).
string Nm(const string suffix){ return "SERASMC_"+suffix; }
color SmcRgb(const int r,const int g,const int b){ return (color)(r+256*g+65536*b); }

int OnInit()
{
   SetIndexBuffer(0,TrendBuf,INDICATOR_DATA);
   SetIndexBuffer(1,TrendColor,INDICATOR_COLOR_INDEX);
   IndicatorSetString(INDICATOR_SHORTNAME,"Sera SMC Zones");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0,Nm(""));
}

// Meme regle que DriftGroup() des EA Sera et driftProfile() du moteur en ligne.
string SmcDriftGroup(const string name,string &side)
{
   string n=name;
   StringToUpper(n);
   StringReplace(n," ","");
   StringReplace(n,"_","");
   side="";
   if(StringFind(n,"BULLMARKET")>=0){ side="BUY"; return "bullbear"; }
   if(StringFind(n,"BEARMARKET")>=0){ side="SELL"; return "bullbear"; }
   if(StringFind(n,"BOOM")>=0 || (StringFind(n,"GAINX")>=0 && StringFind(n,"SWITCHX")<0)){ side="SELL"; return "spike"; }
   if(StringFind(n,"CRASH")>=0 || StringFind(n,"PAINX")>=0){ side="BUY"; return "spike"; }
   if(StringFind(n,"SWITCHX")>=0 || StringFind(n,"BREAKX")>=0 || StringFind(n,"TRENDX")>=0){ side="TREND"; return "regime"; }
   return "";
}

void SmcRect(const string name,const datetime t1,const double p1,const datetime t2,const double p2,const color clr)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,p1,t2,p2);
   ObjectSetInteger(0,name,OBJPROP_TIME,0,t1);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,p1);
   ObjectSetInteger(0,name,OBJPROP_TIME,1,t2);
   ObjectSetDouble(0,name,OBJPROP_PRICE,1,p2);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FILL,1);
   ObjectSetInteger(0,name,OBJPROP_BACK,1);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,0);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,1);
}

void SmcText(const string name,const datetime t,const double price,const string text,const color clr,const int size)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_TEXT,0,t,price);
   ObjectSetInteger(0,name,OBJPROP_TIME,0,t);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,price);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,0);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,1);
}

void SmcArrow(const string name,const datetime t,const double price,const bool buy,const color clr)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,buy?OBJ_ARROW_BUY:OBJ_ARROW_SELL,0,t,price);
   ObjectSetInteger(0,name,OBJPROP_TIME,0,t);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,3);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,0);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,1);
}

// Balayage de liquidite a la bougie k (dir +1 : plus bas pris puis cloture au-dessus ; -1 : l'inverse).
bool SmcSweepAt(const int k,const int dir,const double &high[],const double &low[],const double &close[])
{
   if(k-SweepLookback<0) return false;
   double lo=low[k-SweepLookback],hi=high[k-SweepLookback];
   for(int j=k-SweepLookback;j<k;j++){ if(low[j]<lo) lo=low[j]; if(high[j]>hi) hi=high[j]; }
   if(dir>0) return low[k]<lo && close[k]>lo;
   return high[k]>hi && close[k]<hi;
}

void DrawZones(const int last,const datetime &time[],const double &high[],const double &low[])
{
   int from=MathMax(0,last-RangeBars+1);
   int hiIdx=from,loIdx=from;
   for(int i=from;i<=last;i++){ if(high[i]>high[hiIdx]) hiIdx=i; if(low[i]<low[loIdx]) loIdx=i; }
   double hi=high[hiIdx],lo=low[loIdx],range=hi-lo;
   if(range<=0) return;
   double eq=(hi+lo)/2.0;
   datetime t1=time[MathMin(hiIdx,loIdx)];
   datetime t2=time[last]+(datetime)(PeriodSeconds()*15);
   SmcRect(Nm("PREMIUM"),t1,hi,t2,hi-range*0.25,SmcRgb(90,20,30));
   SmcRect(Nm("EQUILIBRE"),t1,eq+range*0.015,t2,eq-range*0.015,SmcRgb(70,70,80));
   SmcRect(Nm("DISCOUNT"),t1,lo+range*0.25,t2,lo,SmcRgb(15,70,35));
   SmcText(Nm("PREMIUM_T"),time[last],hi-range*0.03,"Premium",clrTomato,8);
   SmcText(Nm("EQUILIBRE_T"),time[last],eq+range*0.04,"Equilibre",clrSilver,8);
   SmcText(Nm("DISCOUNT_T"),time[last],lo+range*0.05,"Discount",clrMediumSeaGreen,8);
   // Le dernier extreme forme est « faible » (liquidite a prendre), l'autre est « fort » (protege).
   bool upLeg=hiIdx>loIdx;
   SmcText(Nm("HIGH_T"),time[hiIdx],hi+range*0.02,upLeg?"Weak High":"Strong High",upLeg?clrOrange:clrTomato,8);
   SmcText(Nm("LOW_T"),time[loIdx],lo-range*0.02,upLeg?"Strong Low":"Weak Low",upLeg?clrMediumSeaGreen:clrOrange,8);
}

void DrawSignals(const int rates_total,const datetime &time[],const double &high[],const double &low[],const double &close[])
{
   ObjectsDeleteAll(0,Nm("SIG_"));
   ObjectsDeleteAll(0,Nm("SWP_"));
   int last=rates_total-2;                      // derniere bougie cloturee
   int start=MathMax(SweepLookback+3,last-HistoryBars);
   string fixedSide="";
   string group=SmcDriftGroup(_Symbol,fixedSide);
   double rsiTh=group=="bullbear"?40.0:45.0;
   bool needTrend=group!="bullbear";
   // indicateurs recursifs depuis la premiere bougie (memes formules que DriftCompute des EA)
   double k20=2.0/21.0,k50=2.0/51.0,e20=close[0],e50=close[0],atr=high[0]-low[0],up=1e-9,dn=1e-9;
   bool wasActive=false;
   for(int i=1;i<=last;i++)
   {
      e20=k20*close[i]+(1.0-k20)*e20;
      e50=k50*close[i]+(1.0-k50)*e50;
      double tr=MathMax(high[i]-low[i],MathMax(MathAbs(high[i]-close[i-1]),MathAbs(low[i]-close[i-1])));
      atr=(atr*13.0+tr)/14.0;
      double d=close[i]-close[i-1];
      up=(up*13.0+(d>0?d:0.0))/14.0;
      dn=(dn*13.0+(d<0?-d:0.0))/14.0;
      if(i<start) continue;
      double rsi=100.0-100.0/(1.0+up/MathMax(dn,1e-12));
      if(ShowSweeps)
      {
         if(SmcSweepAt(i,1,high,low,close)) SmcText(Nm("SWP_B"+IntegerToString(i)),time[i],low[i]-atr*0.4,"$ balayage",clrMediumSeaGreen,7);
         if(SmcSweepAt(i,-1,high,low,close)) SmcText(Nm("SWP_S"+IntegerToString(i)),time[i],high[i]+atr*0.6,"$ balayage",clrTomato,7);
      }
      if(!ShowSignals || group=="" || i<210) continue;
      string trendSide=e20>e50?"BUY":(e20<e50?"SELL":"NEUTRE");
      string side=fixedSide=="TREND"?trendSide:fixedSide;
      int dir=side=="BUY"?1:(side=="SELL"?-1:0);
      bool pullback=dir>0?rsi<rsiTh:(dir<0?rsi>100.0-rsiTh:false);
      bool trendOk=!needTrend || trendSide==side;
      bool sweep=false;
      for(int b=0;b<3 && dir!=0 && !sweep;b++) sweep=SmcSweepAt(i-b,dir,high,low,close);
      bool active=dir!=0 && pullback && trendOk && sweep;
      if(active && !wasActive)
      {
         bool buy=dir>0;
         double y=buy?low[i]-atr*0.8:high[i]+atr*0.8;
         SmcArrow(Nm("SIG_A"+IntegerToString(i)),time[i],y,buy,buy?clrLime:clrRed);
         SmcText(Nm("SIG_T"+IntegerToString(i)),time[i],buy?y-atr*0.6:y+atr*0.9,buy?"BUY Sera":"SELL Sera",buy?clrLime:clrRed,8);
      }
      wasActive=active;
   }
}

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],const double &open[],const double &high[],
                const double &low[],const double &close[],const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<TrendPeriod+5) return 0;
   ArraySetAsSeries(TrendBuf,false);
   ArraySetAsSeries(TrendColor,false);
   ArraySetAsSeries(time,false);
   ArraySetAsSeries(high,false);
   ArraySetAsSeries(low,false);
   ArraySetAsSeries(close,false);
   double k=2.0/(TrendPeriod+1.0);
   int start=prev_calculated>1?prev_calculated-1:1;
   if(start==1){ TrendBuf[0]=close[0]; TrendColor[0]=0; }
   for(int i=start;i<rates_total;i++)
   {
      TrendBuf[i]=k*close[i]+(1.0-k)*TrendBuf[i-1];
      TrendColor[i]=TrendBuf[i]>=TrendBuf[i-1]?0:1;
   }
   // les objets ne sont redessines qu'a chaque nouvelle bougie
   if(time[rates_total-1]!=g_last_draw)
   {
      g_last_draw=time[rates_total-1];
      if(ShowZones) DrawZones(rates_total-2,time,high,low);
      DrawSignals(rates_total,time,high,low,close);
      ChartRedraw(0);
   }
   return rates_total;
}
