//+------------------------------------------------------------------+
//| Sera SMC Zones — indicateur graphique du projet Sera Indicator    |
//| Zones Premium / Equilibre / Discount du dernier swing,            |
//| Strong / Weak High-Low, balayages de liquidite et signaux Sera    |
//| (strategie mesuree « sens de la derive » + balayage SMC).         |
//+------------------------------------------------------------------+
#property copyright "Sera Indicator"
#property link      "https://serakatsuva.github.io/sera-indicator/"
#property version   "1.10"
#property description "Premium / Equilibre / Discount, Strong-Weak High/Low, HH/HL/LH/LL, BOS / CHoCH, zones d'offre et de demande, balayages."
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
input int  SweepBars=120;           // marques "$" de balayage sur les N dernieres bougies seulement (lisibilite)
input bool ShowStructure=true;      // HH / HL / LH / LL, BOS et CHoCH
input int  StructureStrength=3;     // bougies de chaque cote pour un sommet / un creux
input bool ShowOrderBlocks=true;    // zones d'offre (gris) et de demande (bleu) pas encore cassees
input int  OrderBlocksMax=4;        // zones affichees de chaque cote
input bool ShowSignalBox=true;      // cadre en haut a droite : signal, entree, SL, TP

// Etat du signal sur la derniere bougie cloturee (rempli par DrawSignals, affiche par DrawSignalBox)
bool   g_sig_active=false;
int    g_sig_dir=0;
double g_sig_close=0,g_sig_atr=0;
int    g_last_sig_bar=-1,g_last_sig_dir=0;
string g_sig_group="";

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
   g_sig_active=false; g_sig_dir=0; g_last_sig_bar=-1; g_last_sig_dir=0; g_sig_group=group;
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
      if(ShowSweeps && i>last-SweepBars)
      {
         if(SmcSweepAt(i,1,high,low,close)) SmcText(Nm("SWP_B"+IntegerToString(i)),time[i],low[i]-atr*0.4,"$",clrMediumSeaGreen,8);
         if(SmcSweepAt(i,-1,high,low,close)) SmcText(Nm("SWP_S"+IntegerToString(i)),time[i],high[i]+atr*0.6,"$",clrTomato,8);
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
      if(i==last){ g_sig_active=active; g_sig_dir=dir; g_sig_close=close[i]; g_sig_atr=atr; }
      if(active && !wasActive)
      {
         g_last_sig_bar=i; g_last_sig_dir=dir;
         bool buy=dir>0;
         double y=buy?low[i]-atr*0.8:high[i]+atr*0.8;
         SmcArrow(Nm("SIG_A"+IntegerToString(i)),time[i],y,buy,buy?clrLime:clrRed);
         SmcText(Nm("SIG_T"+IntegerToString(i)),time[i],buy?y-atr*0.6:y+atr*0.9,buy?"BUY Sera":"SELL Sera",buy?clrLime:clrRed,8);
      }
      wasActive=active;
   }
}

void SmcLabel(const string name,const int y,const string text,const color clr,const int size)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,12);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,0);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,1);
}

void SmcLine(const string name,const datetime t1,const datetime t2,const double price,const color clr,const int style)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_TREND,0,t1,price,t2,price);
   ObjectSetInteger(0,name,OBJPROP_TIME,0,t1);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,price);
   ObjectSetInteger(0,name,OBJPROP_TIME,1,t2);
   ObjectSetDouble(0,name,OBJPROP_PRICE,1,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,0);
   ObjectSetInteger(0,name,OBJPROP_BACK,1);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,0);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,1);
}

// Structure du marche : sommets / creux (HH, HL, LH, LL), cassures BOS (dans le sens de la tendance) et CHoCH
// (changement de tendance), zones de demande (derniere bougie baissiere avant une cassure haussiere) et d'offre
// (derniere bougie haussiere avant une cassure baissiere) tant qu'aucune cloture ne les traverse.
void DrawStructure(const int rates_total,const datetime &time[],const double &open[],const double &high[],const double &low[],const double &close[])
{
   ObjectsDeleteAll(0,Nm("STR_"));
   ObjectsDeleteAll(0,Nm("OB_"));
   int K=MathMax(1,StructureStrength);
   int last=rates_total-2;
   int start=MathMax(2*K,last-HistoryBars);
   double shPrice=0,slPrice=0,prevSh=0,prevSl=0;
   int shIdx=-1,slIdx=-1,trend=0;
   bool shBroken=true,slBroken=true,havePrevSh=false,havePrevSl=false;
   datetime zT[];
   double zTop[],zBot[];
   int zDir[],zAlive[];
   int nz=0;
   for(int i=start;i<=last;i++)
   {
      int p=i-K;                                   // un sommet / creux en p est confirme a la bougie i
      bool isH=true,isL=true;
      for(int j=1;j<=K;j++)
      {
         if(high[p]<=high[p-j] || high[p]<high[p+j]) isH=false;
         if(low[p]>=low[p-j] || low[p]>low[p+j]) isL=false;
      }
      double pad=(high[p]-low[p])*0.6;
      if(isH)
      {
         string lab="H";
         if(havePrevSh) lab=high[p]>prevSh?"HH":"LH";
         if(ShowStructure) SmcText(Nm("STR_H"+IntegerToString(p)),time[p],high[p]+pad,lab,clrSilver,7);
         prevSh=high[p]; havePrevSh=true; shPrice=high[p]; shIdx=p; shBroken=false;
      }
      if(isL)
      {
         string lab="L";
         if(havePrevSl) lab=low[p]>prevSl?"HL":"LL";
         if(ShowStructure) SmcText(Nm("STR_L"+IntegerToString(p)),time[p],low[p]-pad,lab,clrSilver,7);
         prevSl=low[p]; havePrevSl=true; slPrice=low[p]; slIdx=p; slBroken=false;
      }
      // cassure haussiere du dernier sommet
      if(!shBroken && shIdx>=0 && close[i]>shPrice)
      {
         string kind="BOS";
         if(trend==-1) kind="CHoCH";
         if(ShowStructure)
         {
            SmcLine(Nm("STR_BL"+IntegerToString(i)),time[shIdx],time[i],shPrice,kind=="CHoCH"?clrWhite:clrSilver,STYLE_DOT);
            SmcText(Nm("STR_BT"+IntegerToString(i)),time[(shIdx+i)/2],shPrice+(high[i]-low[i])*0.5,kind,kind=="CHoCH"?clrWhite:clrSilver,7);
         }
         trend=1; shBroken=true;
         for(int k=i-1;k>=MathMax(shIdx-K,1);k--)
            if(close[k]<open[k])
            {
               nz++; ArrayResize(zT,nz); ArrayResize(zTop,nz); ArrayResize(zBot,nz); ArrayResize(zDir,nz); ArrayResize(zAlive,nz);
               zT[nz-1]=time[k]; zTop[nz-1]=high[k]; zBot[nz-1]=low[k]; zDir[nz-1]=1; zAlive[nz-1]=1;
               break;
            }
      }
      // cassure baissiere du dernier creux
      if(!slBroken && slIdx>=0 && close[i]<slPrice)
      {
         string kind="BOS";
         if(trend==1) kind="CHoCH";
         if(ShowStructure)
         {
            SmcLine(Nm("STR_SL"+IntegerToString(i)),time[slIdx],time[i],slPrice,kind=="CHoCH"?clrWhite:clrSilver,STYLE_DOT);
            SmcText(Nm("STR_ST"+IntegerToString(i)),time[(slIdx+i)/2],slPrice-(high[i]-low[i])*0.3,kind,kind=="CHoCH"?clrWhite:clrSilver,7);
         }
         trend=-1; slBroken=true;
         for(int k=i-1;k>=MathMax(slIdx-K,1);k--)
            if(close[k]>open[k])
            {
               nz++; ArrayResize(zT,nz); ArrayResize(zTop,nz); ArrayResize(zBot,nz); ArrayResize(zDir,nz); ArrayResize(zAlive,nz);
               zT[nz-1]=time[k]; zTop[nz-1]=high[k]; zBot[nz-1]=low[k]; zDir[nz-1]=-1; zAlive[nz-1]=1;
               break;
            }
      }
      // une zone est cassee quand une cloture la traverse
      for(int z=0;z<nz;z++)
      {
         if(zAlive[z]==0 || zT[z]>=time[i]) continue;
         if(zDir[z]>0 && close[i]<zBot[z]) zAlive[z]=0;
         if(zDir[z]<0 && close[i]>zTop[z]) zAlive[z]=0;
      }
   }
   if(!ShowOrderBlocks) return;
   datetime right=time[last]+(datetime)(PeriodSeconds()*15);
   int shownD=0,shownS=0;
   for(int z=nz-1;z>=0;z--)
   {
      if(zAlive[z]==0) continue;
      if(zDir[z]>0 && shownD<OrderBlocksMax){ shownD++; SmcRect(Nm("OB_D"+IntegerToString(z)),zT[z],zTop[z],right,zBot[z],SmcRgb(0,20,120)); }
      if(zDir[z]<0 && shownS<OrderBlocksMax){ shownS++; SmcRect(Nm("OB_S"+IntegerToString(z)),zT[z],zTop[z],right,zBot[z],SmcRgb(85,85,85)); }
   }
}

// Cadre en haut a droite : signal Sera de la derniere bougie cloturee, avec entree / SL / TP dessines.
void DrawSignalBox(const int rates_total,const datetime &time[])
{
   ObjectsDeleteAll(0,Nm("BOX_"));
   if(!ShowSignalBox) return;
   int last=rates_total-2;
   SmcLabel(Nm("BOX_0"),18,"Sera SMC Zones",clrWhite,10);
   if(g_sig_group=="")
   {
      SmcLabel(Nm("BOX_1"),36,"Pas d'avantage mesure sur ce marche",clrSilver,9);
      SmcLabel(Nm("BOX_2"),52,"zones et structure seulement, sans signal",clrSilver,9);
      return;
   }
   if(g_sig_active && g_sig_dir!=0 && g_sig_atr>0)
   {
      double slAtr=g_sig_group=="bullbear"?2.5:1.0, t3=g_sig_group=="bullbear"?1.5:1.0;
      double risk=slAtr*g_sig_atr,e=g_sig_close;
      double sl=e-g_sig_dir*risk,tp1=e+g_sig_dir*0.3*risk,tp3=e+g_sig_dir*t3*risk;
      bool buy=g_sig_dir>0;
      color c=buy?clrLime:clrRed;
      SmcLabel(Nm("BOX_1"),36,buy?"SIGNAL BUY Sera (derive + balayage)":"SIGNAL SELL Sera (derive + balayage)",c,9);
      SmcLabel(Nm("BOX_2"),52,"Entree : "+DoubleToString(e,_Digits),clrWhite,9);
      SmcLabel(Nm("BOX_3"),68,"Stop Loss : "+DoubleToString(sl,_Digits),clrTomato,9);
      SmcLabel(Nm("BOX_4"),84,"TP1 : "+DoubleToString(tp1,_Digits)+"   TP3 : "+DoubleToString(tp3,_Digits),clrMediumSeaGreen,9);
      datetime t1=time[MathMax(0,last-8)],t2=time[last]+(datetime)(PeriodSeconds()*15);
      SmcLine(Nm("BOX_LE"),t1,t2,e,clrSilver,STYLE_DOT);
      SmcLine(Nm("BOX_LS"),t1,t2,sl,clrTomato,STYLE_DOT);
      SmcLine(Nm("BOX_LT1"),t1,t2,tp1,clrMediumSeaGreen,STYLE_DOT);
      SmcLine(Nm("BOX_LT3"),t1,t2,tp3,clrMediumSeaGreen,STYLE_SOLID);
      return;
   }
   SmcLabel(Nm("BOX_1"),36,"Pas de signal maintenant",clrSilver,9);
   string ago="attendre un repli + un balayage de liquidite";
   if(g_last_sig_bar>=0)
   {
      string side="SELL";
      if(g_last_sig_dir>0) side="BUY";
      ago="dernier : "+side+" il y a "+IntegerToString(last-g_last_sig_bar)+" bougies";
   }
   SmcLabel(Nm("BOX_2"),52,ago,clrSilver,9);
}

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],const double &open[],const double &high[],
                const double &low[],const double &close[],const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<TrendPeriod+5) return 0;
   ArraySetAsSeries(TrendBuf,false);
   ArraySetAsSeries(TrendColor,false);
   ArraySetAsSeries(time,false);
   ArraySetAsSeries(open,false);
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
      DrawStructure(rates_total,time,open,high,low,close);
      DrawSignalBox(rates_total,time);
      ChartRedraw(0);
   }
   return rates_total;
}
