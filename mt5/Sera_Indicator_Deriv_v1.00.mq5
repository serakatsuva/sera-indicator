//+------------------------------------------------------------------+
//|                                  Sera_Indicator_Deriv_v1.00.mq5 |
//|  Indicateur graphique Sera pour Deriv
//|  v1.00 - base : Sera SMC Vault 6.5 (structure BOS/CHoCH/MSS, OB/FVG   |
//|  notés, zones, kill zones, setup détaillé multi-timeframe, swing,      |
//|  Sniper, alertes push/email). Reconnaissance des marchés Deriv.    |
//|  Se place sur un graphique ; l'EA Deriv reste indépendant.        |
//+------------------------------------------------------------------+
#property copyright   "Sera"
#property version     "1.00"
#property description "Sera Indicator Deriv v1.00 - setup detaille multi-timeframe, profils d'actif, alertes prepare/confirme/annule"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

enum ENUM_SV_MODE { SV_BLUE = 0, SV_RED = 1 };
enum ENUM_SV_PROFILE { PROF_AUTO = 0, PROF_FOREX = 1, PROF_INDICES = 2, PROF_CRYPTO = 3, PROF_SYNTH = 4, PROF_MANUAL = 5 };

input group "=== Général ==="
input ENUM_SV_MODE ColorMode        = SV_BLUE;
input bool         ApplyChartColors = true;
input int          BackLimit        = 1000;
input int          TextSize         = 8;
input string       TextFont         = "Courier New";
input color        TextColor        = clrDarkGray;

input group "=== Dashboard (état initial des boutons, cliquables sur le graphique) ==="
input bool ShowDashboard  = true;
input int  DashX          = 10;
input int  DashY          = 42;
input bool ShowOB         = true;    // OB
input bool ShowFVG        = true;    // FVG
input bool ShowLiquidity  = true;    // DOL (PDH/PDL/PWH/PWL, EQH/EQL, sweeps, HOD/LOD)
input bool ShowStructure  = true;    // MS (BOS / MSS / CHoCH)
input bool inKZShow         = true;    // KZ
input bool ShowPD         = true;    // PDA
input bool ShowSignals    = true;    // SIG (points, étoiles, niveaux)
input bool ShowZones      = true;    // SR (zones fractales)
input bool ShowPanel      = true;    // PNL (panneau d'information à droite)
input bool ShowTrendLine  = true;    // TRD (EMA du régime Flow colorée + flèches jaunes de changement)
input int  TrendBars      = 300;     // Bougies couvertes par la ligne de tendance

input group "=== Scores OB / FVG (qualité heuristique en %, pas une probabilité statistique) ==="
input double DispFullATR    = 3.0;   // Déplacement = 100% quand il atteint x ATR (OB)
input double VolFullRatio   = 2.0;   // Volume tick = 100% quand il atteint x la moyenne
input double GapFullATR     = 0.8;   // Taille de FVG = 100% quand elle atteint x ATR
input int    MinProb        = 0;     // Score mini pour afficher un OB / FVG
input int    ProbThreshold  = 75;    // Seuil "règle des 75%" (mise en évidence)
input bool   PDAFilter      = false; // Masquer OB/FVG non alignés avec le PDA (BUY en discount, SELL en premium)
input double PDABandPct     = 5.0;   // Demi-largeur de la zone Equilibrium (% du range)

input group "=== Signaux : fin de BUY / SELL ==="
input double inSwingATRMult    = 2.5;  // Structure EXTERNE : retournement mini (x ATR)
input int    MinScore        = 0;
input int    StrongPct       = 50;   // Qualité (% du score max) pour "STRONG" **
input int    SniperPct       = 75;   // Qualité (% du score max) pour "SNIPER" ***
input double inStopATR         = 0.5;
input double Target1RR       = 1.0;
input double Target2RR       = 2.0;
input int    DotWidth        = 5;
input int    MaxSignalsShown = 30;
input bool   ShowZigZag      = true;
input bool   ShowStats       = true;
input bool   SignalAlerts    = true;
input bool   ShowHODLOD      = true;

input group "=== Grandes étoiles ==="
input bool   ShowStars       = true;
input int    StarMinScore    = 3;
input int    StarCode        = 171;
input int    StarWidth       = 5;
input double StarOffsetATR   = 0.6;
input color  StarBuyColor    = clrLime;
input color  StarSellColor   = clrRed;
input bool   ShowStarText    = true;

input group "=== Market Structure (MS) ==="
input int    MaxEvents       = 10;   // Externes affichés
input bool   ShowInternal    = true; // Structure interne (mineure)
input double inIntSwingATRMult = 1.0;  // Structure INTERNE : retournement mini (x ATR)
input int    MaxEventsInt    = 8;
input double inMSSBodyATR      = 1.0;  // Cassure contre-tendance avec corps >= x ATR = MSS, sinon CHoCH

input group "=== OB / FVG / DOL / PDA ==="
input int    MaxOB           = 6;
input bool   ShowMitigatedOB = false;
input int    MaxFVG          = 6;
input double inFVGMinATR       = 0.2;
input bool   FVGShowFilled   = false;
input bool   inFVGIgnoreGaps   = true;
input double inEQTolATR        = 0.15;
input int    MaxSweeps       = 6;
input bool   DOLDaily        = true;  // PDH / PDL
input bool   DOLWeekly       = true;  // PWH / PWL

input group "=== Filtres renforcés ==="
input bool             UseFlow        = true;
input int              FlowEMA        = 34;
input double           FlowHyst       = 0.10;
input bool             UseHTF         = true;
input ENUM_TIMEFRAMES  HTFPeriod      = PERIOD_CURRENT;
input int              HTFEMA         = 50;
input bool             inFilterLowVol   = true;
input double           inLowVolRatio    = 0.4;
input bool             UseSpreadCost  = true;

input group "=== Zones Supply / Demand (fractales) ==="
input bool   ShowWeak       = true;
input bool   ShowUntested   = false;
input bool   ShowTurncoat   = false;
input double FuzzFactor     = 0.75;
input int    FractalFast    = 3;
input int    FractalSlow    = 6;
input bool   ZoneExtend     = true;
input bool   ZoneMerge      = true;
input int    ZoneLineWidth  = 2;
input bool   ZoneShowInfo   = true;
input int    ZoneLabelShift = 10;
input string SupName        = "Sup";
input string ResName        = "Res";
input string TestName       = "Retests";

input group "=== Alertes ==="
input bool ZoneAlerts = true;
input bool AlertPopup = true;
input bool AlertSound = true;
input bool AlertPush  = true;    // Notification push sur le téléphone (app MetaTrader 5 + MetaQuotes ID dans Outils > Options > Notifications)
input bool AlertEmail = false;   // Email (SMTP à configurer dans Outils > Options > Email)
input int  AlertWait  = 300;

input group "=== Kill Zones (heure serveur ; à désactiver sur synthétiques / crypto 24h) ==="
input bool  KZFill      = true;
input bool  inKZInScore   = false;
input int   KZDays      = 5;
input bool  LondonOn    = true;
input int   LondonOpen  = 11;
input int   LondonClose = 14;
input bool  NYOn        = true;
input int   NYOpen      = 16;
input int   NYClose     = 19;
input bool  AsiaOn      = true;
input int   AsiaOpen    = 2;
input int   AsiaClose   = 5;

input group "=== Candle Timer / Niveaux ==="
input bool  ShowTimer     = true;
input int   TimerFontSize = 10;
input int   TimerShift    = 7;
input bool  ShowLevels    = true;
input int   LevelPeriod   = 200;

input group "=== Profil d'actif (seuils adaptés à la famille de marché) ==="
input ENUM_SV_PROFILE AssetProfile = PROF_AUTO;   // AUTO détecte Forex / Indices / Crypto / Synthétiques ; MANUAL = tes valeurs

input group "=== Setup détaillé (contexte multi-timeframe, zone d'entrée, alertes) ==="
input bool            SetupEnabled   = true;            // Moteur de setup + alertes
input bool            ShowSetup      = true;            // SET : zones, niveaux et carte (bouton)
input bool            ShowSetupCard  = true;            // Carte détaillée en bas à gauche
input ENUM_TIMEFRAMES SetupCtx1      = PERIOD_CURRENT;  // Contexte 1 (auto : M1-M15 -> H1, H1 -> H4)
input ENUM_TIMEFRAMES SetupCtx2      = PERIOD_CURRENT;  // Contexte 2 (auto : M1-M15 -> H4, H1 -> D1)
input bool            SetupNeedCtx   = true;            // Écarter le setup si la structure du contexte 1 est opposée
input int             SetupMinScore  = 3;               // Score de confluence mini pour garder un setup
input int             SetupMinProb   = 40;              // Score OB / FVG mini (%)
input int             SetupSweepBars = 25;              // Un sweep compte s'il précède la zone de x bougies max
input int             SetupLookback  = 300;             // Bougies analysées
input int             SetupMaxBars   = 40;              // Zone jamais touchée après x bougies : expiré
input int             SetupTapBars   = 8;               // Zone touchée sans déclencheur après x bougies : expiré
input int             SetupHoldBars  = 40;              // Entrée sans TP/SL après x bougies : expiré
input double          SetupMaxRiskATR = 3.0;            // Risque max (x ATR), sinon setup écarté
input int             SetupsShown    = 3;               // Setups dessinés (le plus récent avec niveaux)
input bool            SetupAlerts    = true;            // Alertes : préparé / confirmé / annulé
input bool            SetupSwingOnly = false;           // Alertes seulement pour les setups de type SWING (durée estimée jusqu'à TP2 >= 8 h)

input group "=== AJOUT : Sniper SMC independant ==="
input bool   SXEnabled = true;
input bool   SXAlerts = true;
input int    SXLiquidityBars = 20;
input int    SXBreakBars = 5;
input int    SXExpiryBars = 30;
input double SXBodyATR = 1.0;
input double SXGapATR = 0.15;
input double SXStopATR = 0.30;
input double SXMaxRiskATR = 3.0;
input double SXMaxSpreadATR = 0.15;
input double SXMaxChaseATR = 0.30;
input double SXRR1 = 1.0;
input double SXRR2 = 2.0;


//--- structures
struct SXPlan
  {
   int state, age;
   bool bull;
   datetime sweepTime, gapTime, entryTime;
   double extreme, breakLevel, hi, lo, entry, stop, tp1, tp2;
  };
SXPlan sxPlan[2];
datetime sxLastClosed = 0;


// Valeurs effectives (issues des inputs ou du profil d'actif)
double SwingATRMult, IntSwingATRMult, StopATR, FVGMinATR, EQTolATR, MSSBodyATR, LowVolRatio;
bool   FVGIgnoreGaps, FilterLowVol, KZInScore, KZShow;
string g_profName = "MANUEL";

struct SZone
  {
   bool     isRes;
   double   hi, lo;
   int      bar;
   datetime t1, tEnd;
   bool     slow, broken, visible;
   int      tests;
   string   status;
  };
struct SPivot
  {
   bool     isHigh;
   int      bar, conf;
   double   price;
   datetime tBar, tConf;
  };
struct SSwing
  {
   bool     isHigh;
   int      bar, conf;
   double   price, entry, stop, t1, t2, atrv;
   int      outcome;
   bool     zoneConf, obConf, sweepConf, chochConf, pdConf, kzConf;
   bool     flowConf, htfConf, lowVol;
   double   atrAvg;
   int      score;
   bool     valid, star;
   datetime tBar, tConf;
  };
struct SEvent
  {
   int      bar, lvlBar;
   double   lvl;
   bool     bull, internal;
   int      kind;          // 0 BOS, 1 CHoCH, 2 MSS
   datetime t, tLvl;
  };
struct SOB
  {
   bool     bull;
   double   hi, lo, prob;
   int      bar, evBar;
   datetime t, tEnd;
   bool     mitigated;
  };
struct SFVG
  {
   bool     bull;
   double   hi, lo, prob;
   int      bar;
   datetime t, tEnd;
   bool     filled;
  };
struct SSweep
  {
   int      bar;
   bool     buySide;
   double   price;
   datetime t;
  };

struct SSetup
  {
   bool     bull;
   string   src;                    // "OB", "FVG", "OB+FVG"
   double   zhi, zlo, prob;
   int      fbar;                   // bougie où la zone est née
   int      state;                  // 0 prépa, 1 touchée, 2 confirmé, 3 TP1, 4 SL, 5 annulé, 6 expiré
   int      stateBar, tapBar, trigBar;
   double   entry, stop, t1, t2, dol;
   int      score, c1, c2, ema;     // c1/c2/ema : -1 baissier, 0 inconnu, 1 haussier
   bool     fSweep, fProb, fOver, fC1, fC2, fEma, fFlow, fPda, fKz;
   datetime tForm;
  };

SZone    g_zones[];
SPivot   g_pivE[], g_pivI[];
SSwing   g_sw[];
SEvent   g_ev[], g_evI[];
SOB      g_ob[];
SFVG     g_fvg[];
SSweep   g_sweep[], g_sweepI[];
SSetup   g_set[];
SEvent   g_c1ev[], g_c2ev[];
ENUM_TIMEFRAMES g_ctx1 = PERIOD_CURRENT, g_ctx2 = PERIOD_CURRENT;
int      g_hAtrC1 = INVALID_HANDLE, g_hAtrC2 = INVALID_HANDLE;
datetime g_setKey = 0;
int      g_setState = -1;
int      g_setPick = -1;
int      g_setMax = 3;
double   g_speed = 0;          // vitesse moyenne des jambes de swing (prix par bougie)
string   g_pSetTxt = "-", g_pSetSc = "-";
color    g_pSetCol = clrGray;
int      g_atr = INVALID_HANDLE;
datetime g_lastBar = 0;
datetime g_lastSigAlert = 0;
string   g_akey[];
datetime g_atime[];
int      g_curExtI = 0;
double   g_curExt = 0;
color    g_colSup, g_colRes, g_colBull;
int      g_hMAflow = INVALID_HANDLE;
int      g_hMAhtf  = INVALID_HANDLE;
ENUM_TIMEFRAMES g_htf = PERIOD_CURRENT;
int      g_reg[];
double   g_flowMA[];
int      g_maxScore = 5;
bool     g_hasRange = false;
double   g_rHi = 0, g_rLo = 0;
datetime g_rT0 = 0;

// Dashboard
#define NBTN   11
#define B_OB   0
#define B_FVG  1
#define B_DOL  2
#define B_MS   3
#define B_KZ   4
#define B_PDA  5
#define B_SIG  6
#define B_SR   7
#define B_PNL  8
#define B_TRD  9
#define B_SET  10
string   g_btnName[NBTN] = {"OB", "FVG", "DOL", "MS", "KZ", "PDA", "SIG", "SR", "PNL", "TRD", "SET"};
bool     g_on[NBTN];

#define PFX       "SV_"
#define BTN_PFX   "SVB_"
#define TIMER_OBJ "SVT_Timer"

//+------------------------------------------------------------------+
double A(const double &atr[], const MqlRates &r[], int i)
  {
   if(atr[i] > 0) return atr[i];
   double v = r[i].high - r[i].low;
   return MathMax(v, _Point * 5);
  }
//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
string GKey(int i) { return "SVG_" + IntegerToString((long)ChartID()) + "_" + IntegerToString(i); }

void LoadToggles()
  {
   g_on[B_OB]  = ShowOB;
   g_on[B_FVG] = ShowFVG;
   g_on[B_DOL] = ShowLiquidity;
   g_on[B_MS]  = ShowStructure;
   g_on[B_KZ]  = KZShow;
   g_on[B_PDA] = ShowPD;
   g_on[B_SIG] = ShowSignals;
   g_on[B_SR]  = ShowZones;
   g_on[B_PNL] = ShowPanel;
   g_on[B_TRD] = ShowTrendLine;
   g_on[B_SET] = ShowSetup;
   for(int i = 0; i < NBTN; i++)           // conserve l'état au changement de période
      if(GlobalVariableCheck(GKey(i)))
         g_on[i] = (GlobalVariableGet(GKey(i)) > 0.5);
  }
void UpdateButtons()
  {
   color on = (ColorMode == SV_BLUE) ? C'0,60,160' : C'160,0,0';
   for(int i = 0; i < NBTN; i++)
     {
      string nm = BTN_PFX + g_btnName[i];
      ObjectSetInteger(0, nm, OBJPROP_STATE, g_on[i]);
      ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, g_on[i] ? on : C'45,45,45');
      ObjectSetInteger(0, nm, OBJPROP_COLOR, g_on[i] ? clrWhite : clrGray);
     }
  }
void CreateDashboard()
  {
   if(!ShowDashboard) return;
   for(int i = 0; i < NBTN; i++)
     {
      string nm = BTN_PFX + g_btnName[i];
      ObjectCreate(0, nm, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, DashX + i * 46);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, DashY);
      ObjectSetInteger(0, nm, OBJPROP_XSIZE, 44);
      ObjectSetInteger(0, nm, OBJPROP_YSIZE, 18);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, nm, OBJPROP_FONT, "Arial");
      ObjectSetString(0, nm, OBJPROP_TEXT, g_btnName[i]);
      ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, clrGray);
      ObjectSetInteger(0, nm, OBJPROP_ZORDER, 10);
     }
   UpdateButtons();
  }
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE) { PanelReposition(); return; }
   if(id != CHARTEVENT_OBJECT_CLICK) return;
   if(StringFind(sparam, BTN_PFX) != 0) return;
   for(int i = 0; i < NBTN; i++)
      if(sparam == BTN_PFX + g_btnName[i])
        {
         g_on[i] = !g_on[i];
         GlobalVariableSet(GKey(i), g_on[i] ? 1.0 : 0.0);
         UpdateButtons();
         Refresh();
         break;
        }
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Niveaux de signal : SIGNAL * / STRONG ** / SNIPER ***            |
//+------------------------------------------------------------------+
string TierName(int score)
  {
   double q = 100.0 * score / MathMax(1, g_maxScore);
   if(q >= SniperPct) return "SNIPER ";
   if(q >= StrongPct) return "STRONG ";
   return "";
  }
string StarStr(int score)
  {
   double q = 100.0 * score / MathMax(1, g_maxScore);
   if(q >= SniperPct) return "***";
   if(q >= StrongPct) return "**";
   return "*";
  }
//+------------------------------------------------------------------+
//| Panneau d'information (droite) : direction, qualité, structure,  |
//| suivi de l'ordre actif, ATR ratio, compteurs OB / FVG            |
//+------------------------------------------------------------------+
#define PNL_PFX "SVP_"
#define PNL_W   232
#define PNL_H   334
string   g_pName[];
int      g_pDx[], g_pDy[];
bool     g_pHas = false, g_pBuy = false;
double   g_pQ = 0, g_pEntry = 0, g_pStop = 0, g_pT1 = 0, g_pAtrRatio = 0;
int      g_pOutcome = 0, g_pOB = 0, g_pFVG = 0, g_pSwingDir = 0, g_pIntDir = 0;
datetime g_pTconf = 0;
int      g_pFlow = -1, g_pHtf = 0;

int PanelX()
  {
   int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   return MathMax(10, w - PNL_W - 10);
  }
int PanelY() { return 66; }
void PReg(string nm, int dx, int dy)
  {
   int k = ArraySize(g_pName);
   ArrayResize(g_pName, k + 1);
   ArrayResize(g_pDx, k + 1);
   ArrayResize(g_pDy, k + 1);
   g_pName[k] = nm;
   g_pDx[k] = dx;
   g_pDy[k] = dy;
  }
void PRect(string key, int dx, int dy, int w, int h, color bg, color border)
  {
   string nm = PNL_PFX + key;
   ObjectCreate(0, nm, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, PanelX() + dx);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, PanelY() + dy);
   ObjectSetInteger(0, nm, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, nm, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, nm, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, border);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   PReg(nm, dx, dy);
  }
void PLabel(string key, int dx, int dy, string txt, int size, color c, string font = "Arial")
  {
   string nm = PNL_PFX + key;
   ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, PanelX() + dx);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, PanelY() + dy);
   ObjectSetString(0, nm, OBJPROP_TEXT, txt);
   ObjectSetString(0, nm, OBJPROP_FONT, font);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   PReg(nm, dx, dy);
  }
void SetT(string key, string txt, color c)
  {
   ObjectSetString(0, PNL_PFX + key, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, PNL_PFX + key, OBJPROP_COLOR, c);
  }
void PanelVisible(bool v)
  {
   for(int i = 0; i < ArraySize(g_pName); i++)
      ObjectSetInteger(0, g_pName[i], OBJPROP_TIMEFRAMES, v ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
  }
void PanelReposition()
  {
   int x = PanelX(), y = PanelY();
   for(int i = 0; i < ArraySize(g_pName); i++)
     {
      ObjectSetInteger(0, g_pName[i], OBJPROP_XDISTANCE, x + g_pDx[i]);
      ObjectSetInteger(0, g_pName[i], OBJPROP_YDISTANCE, y + g_pDy[i]);
     }
  }
void CreatePanel()
  {
   ArrayResize(g_pName, 0);
   color gr = C'130,140,155';
   int W = PNL_W - 24;
   PRect("BG", 0, 0, PNL_W, PNL_H, C'12,16,24', C'60,70,90');
   PLabel("TITLE", 12, 8, "SERA INDICATOR DERIV v1.00", 10, clrDeepSkyBlue, "Arial Bold");
   PLabel("STATUS", 180, 9, g_profName, 8, clrLime);

   PLabel("L_DIR", 12, 32, "SIGNAL DIRECTION", 7, gr);
   PLabel("L_Q", 142, 32, "QUALITY SCORE", 7, gr);
   PLabel("V_DIR", 12, 44, "-", 18, clrGray, "Arial Bold");
   PLabel("V_Q", 150, 46, "-", 14, clrGray, "Arial Bold");
   PRect("BAR_BG", 12, 76, W, 6, C'40,44,52', C'40,44,52');
   PRect("BAR", 12, 76, 2, 6, clrGray, clrGray);

   PLabel("L_MS", 12, 92, "MARKET STRUCTURE", 7, clrDeepSkyBlue);
   PLabel("L_SW", 12, 106, "SWING", 7, gr);
   PLabel("L_IN", 85, 106, "INTERNAL", 7, gr);
   PLabel("L_ZN", 155, 106, "ZONE", 7, gr);
   PLabel("V_SW", 12, 118, "-", 9, clrGray, "Arial Bold");
   PLabel("V_IN", 85, 118, "-", 9, clrGray, "Arial Bold");
   PLabel("V_ZN", 155, 118, "-", 9, clrGray, "Arial Bold");

   PLabel("L_TR", 12, 140, "ACTIVE ORDER TRACKER", 7, clrMediumPurple);
   PLabel("L_EN", 12, 154, "ENTRY", 7, gr);
   PLabel("L_EL", 85, 154, "ELAPSED", 7, gr);
   PLabel("L_PL", 155, 154, "P/L", 7, gr);
   PLabel("V_EN", 12, 166, "-", 9, clrWhite, "Arial Bold");
   PLabel("V_EL", 85, 166, "-", 9, clrWhite, "Arial Bold");
   PLabel("V_PL", 155, 166, "-", 9, clrWhite, "Arial Bold");
   PLabel("V_SL", 12, 186, "SL: -", 8, clrTomato);
   PLabel("V_TP", 128, 186, "TP1: -", 8, clrLime);
   PRect("TBAR_BG", 12, 202, W, 6, C'40,44,52', C'40,44,52');
   PRect("TBAR", 12, 202, 2, 6, clrGray, clrGray);
   PLabel("V_RR", 12, 212, "R -", 7, gr);

   PLabel("L_ATR", 12, 232, "ATR RATIO", 7, gr);
   PLabel("L_OB", 85, 232, "OB COUNT", 7, gr);
   PLabel("L_FVG", 155, 232, "FVG COUNT", 7, gr);
   PLabel("V_ATR", 12, 244, "-", 9, clrDeepSkyBlue, "Arial Bold");
   PLabel("V_OB", 85, 244, "-", 9, clrLime, "Arial Bold");
   PLabel("V_FVG", 155, 244, "-", 9, clrMediumPurple, "Arial Bold");

   string htfName = (g_hMAhtf != INVALID_HANDLE) ? StringSubstr(EnumToString(g_htf), 7) : "";
   PLabel("L_TF", 12, 266, "TREND FLOW", 7, gr);
   PLabel("L_TH", 85, 266, "HTF " + htfName, 7, gr);
   PLabel("L_TA", 155, 266, "ALIGN", 7, gr);
   PLabel("V_TF", 12, 278, "-", 9, clrGray, "Arial Bold");
   PLabel("V_TH", 85, 278, "-", 9, clrGray, "Arial Bold");
   PLabel("V_TA", 155, 278, "-", 9, clrGray, "Arial Bold");

   PLabel("L_SE", 12, 300, "SETUP", 7, gr);
   PLabel("L_SQ", 155, 300, "TIER", 7, gr);
   PLabel("V_SE", 12, 312, "-", 9, clrGray, "Arial Bold");
   PLabel("V_SQ", 155, 312, "-", 9, clrGray, "Arial Bold");
   PanelVisible(g_on[B_PNL]);
  }
// Mise à jour des textes (appelée à chaque nouvelle bougie ET chaque seconde)
void PanelApply()
  {
   if(ArraySize(g_pName) == 0 || !g_on[B_PNL]) return;
   int W = PNL_W - 24;

   if(g_pHas)
     {
      color dc = g_pBuy ? clrLime : clrTomato;
      SetT("V_DIR", g_pBuy ? "BUY" : "SELL", dc);
      SetT("V_Q", DoubleToString(g_pQ, 0) + "%",
           g_pQ >= SniperPct ? clrLime : (g_pQ >= StrongPct ? clrGold : clrGray));
      ObjectSetInteger(0, PNL_PFX + "BAR", OBJPROP_XSIZE, (int)MathMax(2, W * g_pQ / 100.0));
      ObjectSetInteger(0, PNL_PFX + "BAR", OBJPROP_BGCOLOR, dc);
      ObjectSetInteger(0, PNL_PFX + "BAR", OBJPROP_COLOR, dc);

      double px = g_pBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double risk = MathAbs(g_pEntry - g_pStop);
      double pnl = g_pBuy ? (px - g_pEntry) : (g_pEntry - px);
      double rr = (risk > 0) ? pnl / risk : 0;
      string st = "";
      if(g_pOutcome == 1)      { pnl = risk * Target1RR; rr = Target1RR; st = "TP1 HIT  "; }
      else if(g_pOutcome == 2) { pnl = -risk; rr = -1.0; st = "SL HIT  "; }
      int bars = iBarShift(_Symbol, _Period, g_pTconf, false);
      if(bars < 0) bars = 0;

      SetT("V_EN", DoubleToString(g_pEntry, _Digits), clrWhite);
      SetT("V_EL", IntegerToString(bars) + " bars", clrWhite);
      SetT("V_PL", (pnl >= 0 ? "+" : "") + DoubleToString(pnl, _Digits), pnl >= 0 ? clrLime : clrTomato);
      SetT("V_SL", "SL: " + DoubleToString(g_pStop, _Digits), clrTomato);
      SetT("V_TP", "TP1: " + DoubleToString(g_pT1, _Digits), clrLime);
      SetT("V_RR", st + "R:R 1:" + DoubleToString(rr, 2), g_pOutcome == 2 ? clrTomato : clrDarkGray);
      double frac = (rr + 1.0) / (1.0 + MathMax(0.1, Target1RR));
      frac = MathMin(1.0, MathMax(0.02, frac));
      color bc = (rr >= 0) ? clrLime : clrTomato;
      ObjectSetInteger(0, PNL_PFX + "TBAR", OBJPROP_XSIZE, (int)MathMax(2, W * frac));
      ObjectSetInteger(0, PNL_PFX + "TBAR", OBJPROP_BGCOLOR, bc);
      ObjectSetInteger(0, PNL_PFX + "TBAR", OBJPROP_COLOR, bc);
     }
   else
     {
      SetT("V_DIR", "-", clrGray);
      SetT("V_Q", "-", clrGray);
      SetT("V_EN", "-", clrWhite);
      SetT("V_EL", "-", clrWhite);
      SetT("V_PL", "-", clrWhite);
      SetT("V_SL", "SL: -", clrTomato);
      SetT("V_TP", "TP1: -", clrLime);
      SetT("V_RR", "R -", clrDarkGray);
     }

   SetT("V_SW", g_pSwingDir == 0 ? "-" : (g_pSwingDir > 0 ? "BULL" : "BEAR"),
        g_pSwingDir == 0 ? clrGray : (g_pSwingDir > 0 ? clrLime : clrTomato));
   SetT("V_IN", g_pIntDir == 0 ? "-" : (g_pIntDir > 0 ? "BULL" : "BEAR"),
        g_pIntDir == 0 ? clrGray : (g_pIntDir > 0 ? clrLime : clrTomato));
   int loc = PDALoc(SymbolInfoDouble(_Symbol, SYMBOL_BID));
   if(loc == 1)       SetT("V_ZN", "PREMIUM", clrTomato);
   else if(loc == -1) SetT("V_ZN", "DISCOUNT", clrLime);
   else if(loc == 0)  SetT("V_ZN", "EQUILIB.", clrGray);
   else               SetT("V_ZN", "-", clrGray);

   SetT("V_ATR", DoubleToString(g_pAtrRatio, 2) + "x", clrDeepSkyBlue);
   SetT("V_OB", IntegerToString(g_pOB), clrLime);
   SetT("V_FVG", IntegerToString(g_pFVG), clrMediumPurple);

   SetT("V_TF", g_pFlow < 0 ? "-" : (g_pFlow == 1 ? "BULL" : "BEAR"),
        g_pFlow < 0 ? clrGray : (g_pFlow == 1 ? clrLime : clrTomato));
   SetT("V_TH", g_pHtf == 0 ? "-" : (g_pHtf > 0 ? "BULL" : "BEAR"),
        g_pHtf == 0 ? clrGray : (g_pHtf > 0 ? clrLime : clrTomato));
   string al = "-";
   color alc = clrGray;
   if(g_pFlow >= 0 && g_pHtf != 0)
     {
      bool fb = (g_pFlow == 1), hb = (g_pHtf > 0);
      if(fb == hb) { al = fb ? "BULL" : "BEAR"; alc = fb ? clrLime : clrTomato; }
      else         { al = "MIXED"; alc = clrGold; }
     }
   SetT("V_TA", al, alc);
   SetT("V_SE", g_pSetTxt, g_pSetCol);
   SetT("V_SQ", g_pSetSc, g_pSetCol);
  }
// Données du panneau (à chaque nouvelle bougie)
void PanelData(const MqlRates &r[], int n, const double &atr[])
  {
   g_pHas = false;
   for(int k = ArraySize(g_sw) - 1; k >= 0; k--)
      if(g_sw[k].valid)
        {
         g_pHas = true;
         g_pBuy = !g_sw[k].isHigh;
         g_pEntry = g_sw[k].entry;
         g_pStop = g_sw[k].stop;
         g_pT1 = g_sw[k].t1;
         g_pOutcome = g_sw[k].outcome;
         g_pTconf = g_sw[k].tConf;
         g_pQ = 100.0 * g_sw[k].score / MathMax(1, g_maxScore);
         break;
        }
   int e = ArraySize(g_ev);
   g_pSwingDir = (e > 0) ? (g_ev[e - 1].bull ? 1 : -1) : 0;
   int ei = ShowInternal ? ArraySize(g_evI) : 0;
   g_pIntDir = (ei > 0) ? (g_evI[ei - 1].bull ? 1 : -1) : 0;

   double s = 0;
   int c = 0;
   for(int j = 1; j <= 100 && j < n; j++) { s += A(atr, r, j); c++; }
   g_pAtrRatio = (c > 0 && s > 0) ? A(atr, r, 1) / (s / c) : 0;

   g_pOB = 0;
   for(int o = 0; o < ArraySize(g_ob); o++)
      if(!g_ob[o].mitigated) g_pOB++;
   g_pFVG = 0;
   for(int f = 0; f < ArraySize(g_fvg); f++)
      if(!g_fvg[f].filled) g_pFVG++;

   g_pFlow = (ArraySize(g_reg) > 0) ? g_reg[0] : -1;
   g_pHtf = HTFBias(TimeCurrent());
   SetupPanelFill();

   PanelVisible(g_on[B_PNL]);
   PanelApply();
  }
void PanelLive()
  {
   if(!g_on[B_PNL] || ArraySize(g_pName) == 0) return;
   PanelApply();
   if(!ShowTimer) ChartRedraw();
  }
//+------------------------------------------------------------------+
int OnInit()
  {
   ApplyProfile();
   g_colRes = clrDimGray;
   if(ColorMode == SV_BLUE) { g_colSup = C'0,0,128'; g_colBull = C'0,0,128'; }
   else                     { g_colSup = C'128,0,0'; g_colBull = C'128,0,0'; }

   g_atr = iATR(_Symbol, _Period, 14);
   if(g_atr == INVALID_HANDLE) return INIT_FAILED;
   IndicatorSetString(INDICATOR_SHORTNAME, "Sera Indicator Deriv v1.00");

   g_htf = HTFPeriod;
   if(g_htf == PERIOD_CURRENT) g_htf = NextTF(_Period);
   if(UseHTF && PeriodSeconds(g_htf) > PeriodSeconds())
      g_hMAhtf = iMA(_Symbol, g_htf, HTFEMA, 0, MODE_EMA, PRICE_CLOSE);
   if(UseFlow)
      g_hMAflow = iMA(_Symbol, _Period, FlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_ctx1 = (SetupCtx1 == PERIOD_CURRENT) ? CtxTF(1) : SetupCtx1;
   g_ctx2 = (SetupCtx2 == PERIOD_CURRENT) ? CtxTF(2) : SetupCtx2;
   if(SetupEnabled)
     {
      if(PeriodSeconds(g_ctx1) > PeriodSeconds()) g_hAtrC1 = iATR(_Symbol, g_ctx1, 14);
      if(PeriodSeconds(g_ctx2) > PeriodSeconds()) g_hAtrC2 = iATR(_Symbol, g_ctx2, 14);
     }

   if(ApplyChartColors)
     {
      ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrBlack);
      ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrWhite);
      ChartSetInteger(0, CHART_COLOR_GRID, clrBlack);
      ChartSetInteger(0, CHART_SHOW_GRID, false);
      ChartSetInteger(0, CHART_MODE, CHART_CANDLES);
      ChartSetInteger(0, CHART_COLOR_CHART_UP,   ColorMode == SV_BLUE ? clrBlue : clrRed);
      ChartSetInteger(0, CHART_COLOR_CHART_DOWN, clrWhite);
      ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, g_colBull);
      ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, clrDimGray);
      ChartSetInteger(0, CHART_COLOR_CHART_LINE, clrLime);
     }

   LoadToggles();
   CreateDashboard();
   CreatePanel();

   if(ShowTimer)
     {
      ObjectCreate(0, TIMER_OBJ, OBJ_TEXT, 0, 0, 0);
      ObjectSetString(0, TIMER_OBJ, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, TIMER_OBJ, OBJPROP_FONTSIZE, TimerFontSize);
      ObjectSetInteger(0, TIMER_OBJ, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, TIMER_OBJ, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, TIMER_OBJ, OBJPROP_HIDDEN, true);
     }
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   SXReset();   // nettoyage de la couche Sniper SMC+
   EventKillTimer();
   ObjectsDeleteAll(0, PFX);
   ObjectsDeleteAll(0, BTN_PFX);
   ObjectsDeleteAll(0, PNL_PFX);
   ObjectDelete(0, TIMER_OBJ);
   if(g_atr != INVALID_HANDLE) IndicatorRelease(g_atr);
   if(g_hMAflow != INVALID_HANDLE) IndicatorRelease(g_hMAflow);
   if(g_hMAhtf != INVALID_HANDLE) IndicatorRelease(g_hMAhtf);
   if(g_hAtrC1 != INVALID_HANDLE) IndicatorRelease(g_hAtrC1);
   if(g_hAtrC2 != INVALID_HANDLE) IndicatorRelease(g_hAtrC2);
  }
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[], const double &high[],
                const double &low[], const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
  {
   if(rates_total < 2) return 0;
   if(prev_calculated == 0) g_lastBar = 0;
   datetime cur = time[rates_total - 1];
   if(cur != g_lastBar)
      if(Refresh()) g_lastBar = cur;
   SXProcess();   // couche Sniper SMC+ : une fois par bougie clôturée
   CheckAlerts();
   return rates_total;
  }
//+------------------------------------------------------------------+
void OnTimer()
  {
   PanelLive();
   if(!ShowTimer) return;
   datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 == 0) return;
   long rem = (long)(t0 + PeriodSeconds() - TimeCurrent());
   if(rem < 0) rem = 0;
   string s = (rem >= 3600)
              ? StringFormat("%02d:%02d:%02d", (int)(rem / 3600), (int)((rem % 3600) / 60), (int)(rem % 60))
              : StringFormat("%02d:%02d", (int)(rem / 60), (int)(rem % 60));
   bool up = iClose(_Symbol, _Period, 0) >= iOpen(_Symbol, _Period, 0);
   ObjectSetString(0, TIMER_OBJ, OBJPROP_TEXT, s);
   ObjectSetInteger(0, TIMER_OBJ, OBJPROP_COLOR, up ? clrLime : clrRed);
   ObjectSetInteger(0, TIMER_OBJ, OBJPROP_TIME, t0 + (long)PeriodSeconds() * TimerShift);
   ObjectSetDouble(0, TIMER_OBJ, OBJPROP_PRICE, SymbolInfoDouble(_Symbol, SYMBOL_BID));
   ChartRedraw();
  }
//+------------------------------------------------------------------+
bool Refresh()
  {
   int total = MathMin(BackLimit, Bars(_Symbol, _Period));
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int n = CopyRates(_Symbol, _Period, 0, total, r);
   if(n < FractalSlow * 2 + 20) return false;
   double atr[];
   ArraySetAsSeries(atr, true);
   int got = CopyBuffer(g_atr, 0, 0, n, atr);
   if(got < FractalSlow * 2 + 20) return false;
   n = MathMin(n, got);

   ObjectsDeleteAll(0, PFX);

   BuildZones(r, n, atr);

   // structure externe (majeure) -> signaux
   double dummyExt; int dummyI;
   BuildPivots(r, n, atr, SwingATRMult, g_pivE, g_curExt, g_curExtI);
   ArrayResize(g_sw, 0);
   for(int p = 0; p < ArraySize(g_pivE); p++)
      AddSwing(g_pivE[p].isHigh, g_pivE[p].bar, g_pivE[p].price, g_pivE[p].conf, r, atr);
   BuildStructure(r, n, atr, g_pivE, g_ev, g_sweep, false);

   // structure interne (mineure)
   if(ShowInternal)
     {
      BuildPivots(r, n, atr, IntSwingATRMult, g_pivI, dummyExt, dummyI);
      BuildStructure(r, n, atr, g_pivI, g_evI, g_sweepI, true);
     }
   else
     {
      ArrayResize(g_evI, 0);
     }

   FindRange();
   BuildOB(r, n, atr);
   BuildFVG(r, n, atr);
   BuildRegime(r, n, atr);
   g_maxScore = 5 + (KZInScore ? 1 : 0) + (UseFlow ? 1 : 0) + (g_hMAhtf != INVALID_HANDLE ? 1 : 0);
   ScoreSwings();
   BuildSetups(r, n, atr);
   SetupAlert();
   PanelData(r, n, atr);

   if(g_on[B_PDA])  DrawPD(r);
   if(g_on[B_TRD])  DrawTrendLine(r, n);
   if(g_on[B_SR])   DrawZones(r);
   if(g_on[B_MS])
     {
      DrawStructure(g_ev, MaxEvents, false);
      if(ShowInternal) DrawStructure(g_evI, MaxEventsInt, true);
     }
   if(g_on[B_OB])   DrawOB(r);
   if(g_on[B_FVG])  DrawFVG(r);
   if(g_on[B_DOL])
     {
      DrawSweeps();
      DrawDOL(r, n);
      if(ShowHODLOD) DrawHODLOD(r, n);
     }
   if(g_on[B_SIG])
     {
      DrawSwings(r);
      SignalAlert();
     }
   if(g_on[B_SET])
     {
      DrawSetups(r);
      if(ShowSetupCard) DrawSetupCard();
     }
   if(g_on[B_KZ])
     {
      if(LondonOn) DrawKillZone("London", LondonOpen, LondonClose, r, n);
      if(NYOn)     DrawKillZone("NewYork", NYOpen, NYClose, r, n);
      if(AsiaOn)   DrawKillZone("Asia", AsiaOpen, AsiaClose, r, n);
     }
   if(ShowLevels) DrawLevels(r, n);
   SXRender();   // conserve la couche Sniper SMC+ après un redessin
   ChartRedraw();
   return true;
  }
//+------------------------------------------------------------------+
//| Helpers de dessin                                                |
//+------------------------------------------------------------------+
void MakeTrend(string nm, datetime t1, double p1, datetime t2, double p2,
               color c, int w, ENUM_LINE_STYLE st, bool rayRight)
  {
   ObjectCreate(0, nm, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, st);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, rayRight);
   ObjectSetInteger(0, nm, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
  }
void MakeText(string nm, datetime t, double p, string txt, color c, ENUM_ANCHOR_POINT anc)
  {
   ObjectCreate(0, nm, OBJ_TEXT, 0, t, p);
   ObjectSetString(0, nm, OBJPROP_TEXT, txt);
   ObjectSetString(0, nm, OBJPROP_FONT, TextFont);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, TextSize);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, anc);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
  }
void MakeDot(string nm, datetime t, double p, color c, int w, int code, ENUM_ARROW_ANCHOR anc)
  {
   ObjectCreate(0, nm, OBJ_ARROW, 0, t, p);
   ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, code);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, anc);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
  }
void MakeRect(string nm, datetime t1, double p1, datetime t2, double p2,
              color c, int w, ENUM_LINE_STYLE st, bool fill = false)
  {
   ObjectCreate(0, nm, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, st);
   ObjectSetInteger(0, nm, OBJPROP_FILL, fill);
   ObjectSetInteger(0, nm, OBJPROP_BACK, true);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
  }
//+------------------------------------------------------------------+
//| Zones S/R par fractales                                          |
//+------------------------------------------------------------------+
bool IsFractalHigh(const MqlRates &r[], int i, int k)
  {
   for(int j = 1; j <= k; j++)
      if(!(r[i].high > r[i + j].high && r[i].high >= r[i - j].high)) return false;
   return true;
  }
bool IsFractalLow(const MqlRates &r[], int i, int k)
  {
   for(int j = 1; j <= k; j++)
      if(!(r[i].low < r[i + j].low && r[i].low <= r[i - j].low)) return false;
   return true;
  }
void AddZone(bool isRes, double hi, double lo, int bar, datetime t, bool slow)
  {
   int sz = ArraySize(g_zones);
   if(ZoneMerge)
      for(int i = 0; i < sz; i++)
         if(g_zones[i].isRes == isRes && hi >= g_zones[i].lo && lo <= g_zones[i].hi)
           {
            g_zones[i].hi = MathMax(g_zones[i].hi, hi);
            g_zones[i].lo = MathMin(g_zones[i].lo, lo);
            g_zones[i].slow = g_zones[i].slow || slow;
            return;
           }
   ArrayResize(g_zones, sz + 1);
   g_zones[sz].isRes = isRes;
   g_zones[sz].hi = hi;
   g_zones[sz].lo = lo;
   g_zones[sz].bar = bar;
   g_zones[sz].t1 = t;
   g_zones[sz].tEnd = 0;
   g_zones[sz].slow = slow;
   g_zones[sz].tests = 0;
   g_zones[sz].broken = false;
   g_zones[sz].visible = false;
   g_zones[sz].status = "";
  }
void BuildZones(const MqlRates &r[], int n, const double &atr[])
  {
   ArrayResize(g_zones, 0);
   int kf = MathMax(1, FractalFast), ks = MathMax(kf, FractalSlow);
   for(int i = n - 1 - kf; i >= kf; i--)
     {
      double a = A(atr, r, i);
      bool slowOk = (i >= ks && i + ks <= n - 1);
      if(IsFractalHigh(r, i, kf))
        {
         bool slow = slowOk && IsFractalHigh(r, i, ks);
         double hi = r[i].high;
         double w = hi - MathMax(r[i].open, r[i].close);
         w = MathMin(MathMax(w, 0.3 * a), FuzzFactor * a * 2.0);
         AddZone(true, hi, hi - w, i, r[i].time, slow);
        }
      if(IsFractalLow(r, i, kf))
        {
         bool slow = slowOk && IsFractalLow(r, i, ks);
         double lo = r[i].low;
         double w = MathMin(r[i].open, r[i].close) - lo;
         w = MathMin(MathMax(w, 0.3 * a), FuzzFactor * a * 2.0);
         AddZone(false, lo + w, lo, i, r[i].time, slow);
        }
     }
   for(int z = 0; z < ArraySize(g_zones); z++)
     {
      int lastTouch = 1000000;
      for(int j = g_zones[z].bar - kf - 1; j >= 0; j--)
        {
         if(g_zones[z].isRes)
           {
            if(r[j].close > g_zones[z].hi) { g_zones[z].broken = true; g_zones[z].tEnd = r[j].time; break; }
            if(r[j].high >= g_zones[z].lo && lastTouch - j >= ks) { g_zones[z].tests++; lastTouch = j; }
           }
         else
           {
            if(r[j].close < g_zones[z].lo) { g_zones[z].broken = true; g_zones[z].tEnd = r[j].time; break; }
            if(r[j].low <= g_zones[z].hi && lastTouch - j >= ks) { g_zones[z].tests++; lastTouch = j; }
           }
        }
      string st;
      if(g_zones[z].broken)          st = "Turncoat";
      else if(g_zones[z].tests == 0) st = g_zones[z].slow ? "Untested" : "Weak";
      else if(g_zones[z].tests >= 3) st = "Proven";
      else                           st = "Verified";
      g_zones[z].status = st;
      bool vis = true;
      if(st == "Weak")     vis = ShowWeak;
      if(st == "Untested") vis = ShowUntested;
      if(st == "Turncoat") vis = ShowTurncoat;
      g_zones[z].visible = vis;
     }
  }
void DrawZones(const MqlRates &r[])
  {
   datetime t0 = r[0].time;
   int ps = PeriodSeconds();
   for(int z = 0; z < ArraySize(g_zones); z++)
     {
      if(!g_zones[z].visible) continue;
      string nm = PFX + "Z" + IntegerToString(z);
      datetime te;
      if(g_zones[z].broken) te = g_zones[z].tEnd;
      else                  te = ZoneExtend ? t0 + (datetime)((long)ps * 30) : t0;
      MakeRect(nm, g_zones[z].t1, g_zones[z].hi, te, g_zones[z].lo,
               g_zones[z].isRes ? g_colRes : g_colSup, ZoneLineWidth, STYLE_SOLID);
      if(ZoneShowInfo)
        {
         string txt = (g_zones[z].isRes ? ResName : SupName) + " " + g_zones[z].status;
         if(g_zones[z].tests > 0) txt += ", " + TestName + "=" + IntegerToString(g_zones[z].tests);
         MakeText(PFX + "L" + IntegerToString(z), t0 + (datetime)((long)ps * ZoneLabelShift),
                  (g_zones[z].hi + g_zones[z].lo) / 2.0, txt, TextColor, ANCHOR_LEFT);
        }
     }
  }
//+------------------------------------------------------------------+
//| Pivots (ZigZag ATR, sans repaint) - générique externe / interne  |
//+------------------------------------------------------------------+
void AddPivot(SPivot &out[], bool isHigh, int pbar, double price, int conf, const MqlRates &r[])
  {
   int k = ArraySize(out);
   ArrayResize(out, k + 1);
   out[k].isHigh = isHigh;
   out[k].bar = pbar;
   out[k].conf = conf;
   out[k].price = price;
   out[k].tBar = r[pbar].time;
   out[k].tConf = r[conf].time;
  }
void BuildPivots(const MqlRates &r[], int n, const double &atr[], double mult,
                 SPivot &out[], double &extOut, int &extIOut)
  {
   ArrayResize(out, 0);
   int dir = 1;
   double ext = r[n - 1].high;
   int extI = n - 1;
   bool first = true;
   for(int i = n - 2; i >= 1; i--)
     {
      double thr = A(atr, r, i) * mult;
      if(dir == 1)
        {
         if(r[i].high > ext) { ext = r[i].high; extI = i; }
         else if(ext - r[i].low >= thr)
           {
            if(first) first = false; else AddPivot(out, true, extI, ext, i, r);
            dir = -1; ext = r[i].low; extI = i;
           }
        }
      else
        {
         if(r[i].low < ext) { ext = r[i].low; extI = i; }
         else if(r[i].high - ext >= thr)
           {
            if(first) first = false; else AddPivot(out, false, extI, ext, i, r);
            dir = 1; ext = r[i].high; extI = i;
           }
        }
     }
   if(dir == 1 && r[0].high > ext) { ext = r[0].high; extI = 0; }
   if(dir == -1 && r[0].low < ext) { ext = r[0].low; extI = 0; }
   extOut = ext;
   extIOut = extI;
  }
//+------------------------------------------------------------------+
//| Signal de fin de BUY / SELL (pivot externe) + niveaux + résultat |
//+------------------------------------------------------------------+
void AddSwing(bool isHigh, int pbar, double price, int conf,
              const MqlRates &r[], const double &atr[])
  {
   int k = ArraySize(g_sw);
   ArrayResize(g_sw, k + 1);
   double a = A(atr, r, conf);

   double entry = r[conf].close;
   double risk = isHigh ? (price + StopATR * a - entry) : (entry - (price - StopATR * a));
   risk = MathMax(risk, 0.2 * a);
   double stop = isHigh ? entry + risk : entry - risk;
   double t1 = isHigh ? entry - risk * Target1RR : entry + risk * Target1RR;
   double t2 = isHigh ? entry - risk * Target2RR : entry + risk * Target2RR;

   double sumA = 0;
   int cntA = 0;
   for(int j = conf; j < ArraySize(r) && j < conf + 100; j++) { sumA += A(atr, r, j); cntA++; }
   double avg = (cntA > 0) ? sumA / cntA : a;

   double spr = UseSpreadCost ? (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point : 0.0;
   int outc = 0;
   for(int j = conf - 1; j >= 0; j--)
     {
      if(isHigh)
        {
         if(r[j].high + spr >= stop) { outc = 2; break; }
         if(r[j].low + spr <= t1)    { outc = 1; break; }
        }
      else
        {
         if(r[j].low <= stop)        { outc = 2; break; }
         if(r[j].high >= t1 + spr)   { outc = 1; break; }
        }
     }

   g_sw[k].isHigh = isHigh;
   g_sw[k].bar = pbar;
   g_sw[k].conf = conf;
   g_sw[k].price = price;
   g_sw[k].entry = entry;
   g_sw[k].stop = stop;
   g_sw[k].t1 = t1;
   g_sw[k].t2 = t2;
   g_sw[k].atrv = a;
   g_sw[k].outcome = outc;
   g_sw[k].zoneConf = false;
   g_sw[k].obConf = false;
   g_sw[k].sweepConf = false;
   g_sw[k].chochConf = false;
   g_sw[k].pdConf = false;
   g_sw[k].kzConf = false;
   g_sw[k].flowConf = false;
   g_sw[k].htfConf = false;
   g_sw[k].lowVol = false;
   g_sw[k].atrAvg = avg;
   g_sw[k].score = 0;
   g_sw[k].valid = true;
   g_sw[k].star = false;
   g_sw[k].tBar = r[pbar].time;
   g_sw[k].tConf = r[conf].time;
  }
//+------------------------------------------------------------------+
//| Market Structure : BOS / CHoCH / MSS + sweeps (générique)        |
//+------------------------------------------------------------------+
void AddEvent(SEvent &ev[], int i, int lvlBar, double lvl, bool bull, bool counter,
              bool internal, const MqlRates &r[], const double &atr[])
  {
   int k = ArraySize(ev);
   ArrayResize(ev, k + 1);
   int kind = 0;
   if(counter)
     {
      double body = MathAbs(r[i].close - r[i].open);
      kind = (body >= MSSBodyATR * A(atr, r, i)) ? 2 : 1;   // MSS = cassure avec déplacement
     }
   ev[k].bar = i;
   ev[k].lvlBar = lvlBar;
   ev[k].lvl = lvl;
   ev[k].bull = bull;
   ev[k].internal = internal;
   ev[k].kind = kind;
   ev[k].t = r[i].time;
   ev[k].tLvl = r[lvlBar].time;
  }
void AddSweep(SSweep &swp[], int i, bool buySide, const MqlRates &r[])
  {
   int k = ArraySize(swp);
   ArrayResize(swp, k + 1);
   swp[k].bar = i;
   swp[k].buySide = buySide;
   swp[k].price = buySide ? r[i].high : r[i].low;
   swp[k].t = r[i].time;
  }
void BuildStructure(const MqlRates &r[], int n, const double &atr[], SPivot &pv[],
                    SEvent &ev[], SSweep &swp[], bool internal)
  {
   ArrayResize(ev, 0);
   ArrayResize(swp, 0);
   int sz = ArraySize(pv);
   int p = 0, trend = 0;
   bool hv = false, lv = false, hBroken = false, lBroken = false;
   double hp = 0, lp = 0;
   int hb = 0, lb = 0;

   for(int i = n - 1; i >= 1; i--)
     {
      if(hv && !hBroken)
        {
         if(r[i].close > hp)
           { AddEvent(ev, i, hb, hp, true, trend == -1, internal, r, atr); trend = 1; hBroken = true; }
         else if(r[i].high > hp)
            AddSweep(swp, i, true, r);
        }
      if(lv && !lBroken)
        {
         if(r[i].close < lp)
           { AddEvent(ev, i, lb, lp, false, trend == 1, internal, r, atr); trend = -1; lBroken = true; }
         else if(r[i].low < lp)
            AddSweep(swp, i, false, r);
        }
      while(p < sz && pv[p].conf >= i)
        {
         if(pv[p].isHigh) { hv = true; hp = pv[p].price; hb = pv[p].bar; hBroken = false; }
         else             { lv = true; lp = pv[p].price; lb = pv[p].bar; lBroken = false; }
         p++;
        }
     }
  }
//+------------------------------------------------------------------+
//| PDA : range de référence = dernier sommet / dernier creux externe|
//+------------------------------------------------------------------+
void FindRange()
  {
   g_hasRange = false;
   int h = -1, l = -1;
   for(int k = ArraySize(g_sw) - 1; k >= 0 && (h < 0 || l < 0); k--)
     {
      if(g_sw[k].isHigh && h < 0) h = k;
      if(!g_sw[k].isHigh && l < 0) l = k;
     }
   if(h < 0 || l < 0) return;
   g_rHi = MathMax(g_sw[h].price, g_sw[l].price);
   g_rLo = MathMin(g_sw[h].price, g_sw[l].price);
   g_rT0 = (g_sw[h].tBar < g_sw[l].tBar) ? g_sw[h].tBar : g_sw[l].tBar;
   g_hasRange = (g_rHi > g_rLo);
  }
// 1 premium, 0 equilibrium, -1 discount, 2 inconnu
int PDALoc(double price)
  {
   if(!g_hasRange) return 2;
   double pos = (price - g_rLo) / (g_rHi - g_rLo);
   double band = PDABandPct / 100.0;
   if(pos > 0.5 + band) return 1;
   if(pos < 0.5 - band) return -1;
   return 0;
  }
string PDATag(int loc)
  {
   if(loc == 1)  return " P";
   if(loc == -1) return " D";
   if(loc == 0)  return " EQ";
   return "";
  }
//+------------------------------------------------------------------+
//| Order Blocks notés (déplacement + volume tick)                   |
//+------------------------------------------------------------------+
double AvgTickVol(const MqlRates &r[], int from, int to, int n)
  {
   double s = 0;
   int c = 0;
   for(int j = MathMax(0, from); j <= MathMin(n - 1, to); j++) { s += (double)r[j].tick_volume; c++; }
   return (c > 0) ? s / c : 0;
  }
void BuildOB(const MqlRates &r[], int n, const double &atr[])
  {
   ArrayResize(g_ob, 0);
   for(int e = 0; e < ArraySize(g_ev); e++)
     {
      int eb = g_ev[e].bar, lb = g_ev[e].lvlBar;
      if(lb <= eb) continue;
      bool bull = g_ev[e].bull;

      int m = eb;
      for(int j = eb; j <= lb && j < n; j++)
        {
         if(bull) { if(r[j].low < r[m].low) m = j; }
         else     { if(r[j].high > r[m].high) m = j; }
        }
      int c = m;
      for(int j = m; j <= MathMin(n - 1, m + 5); j++)
        {
         bool opp = bull ? (r[j].close < r[j].open) : (r[j].close > r[j].open);
         if(opp) { c = j; break; }
        }

      bool dup = false;
      for(int o = 0; o < ArraySize(g_ob); o++)
         if(g_ob[o].bar == c && g_ob[o].bull == bull) { dup = true; break; }
      if(dup) continue;

      double hi = r[c].high, lo = r[c].low;
      bool mit = false;
      datetime te = 0;
      for(int j = eb - 1; j >= 0; j--)
        {
         if(bull && r[j].close < lo) { mit = true; te = r[j].time; break; }
         if(!bull && r[j].close > hi) { mit = true; te = r[j].time; break; }
        }

      // --- score : déplacement (45%) + volume tick (40%) + type de cassure (15%)
      double a = A(atr, r, c);
      double extreme = bull ? r[eb].high : r[eb].low;
      for(int j = eb; j <= c; j++)
        {
         if(bull) extreme = MathMax(extreme, r[j].high);
         else     extreme = MathMin(extreme, r[j].low);
        }
      double disp = bull ? (extreme - lo) : (hi - extreme);
      double dScore = MathMin(1.0, MathMax(0.0, (disp / a) / DispFullATR));

      double impVol = AvgTickVol(r, eb, c, n);
      double baseVol = AvgTickVol(r, c + 1, c + 50, n);
      double vScore = 0.5;                                       // neutre si pas de volume
      if(baseVol > 0 && impVol > 0) vScore = MathMin(1.0, (impVol / baseVol) / VolFullRatio);
      double sScore = (g_ev[e].kind >= 1) ? 1.0 : 0.6;
      double prob = 100.0 * (0.45 * dScore + 0.40 * vScore + 0.15 * sScore);

      int k = ArraySize(g_ob);
      ArrayResize(g_ob, k + 1);
      g_ob[k].bull = bull;
      g_ob[k].hi = hi;
      g_ob[k].lo = lo;
      g_ob[k].prob = prob;
      g_ob[k].bar = c;
      g_ob[k].evBar = eb;
      g_ob[k].t = r[c].time;
      g_ob[k].tEnd = te;
      g_ob[k].mitigated = mit;
     }
  }
//+------------------------------------------------------------------+
//| Fair Value Gaps notés (taille + volume de la bougie centrale)    |
//+------------------------------------------------------------------+
void BuildFVG(const MqlRates &r[], int n, const double &atr[])
  {
   ArrayResize(g_fvg, 0);
   for(int i = n - 3; i >= 1; i--)
     {
      if(FVGIgnoreGaps && (long)(r[i].time - r[i + 2].time) > (long)PeriodSeconds() * 3) continue;
      double a = A(atr, r, i + 1);
      double minSz = FVGMinATR * a;
      bool bull = (r[i].low > r[i + 2].high) && ((r[i].low - r[i + 2].high) >= minSz);
      bool bear = (r[i].high < r[i + 2].low) && ((r[i + 2].low - r[i].high) >= minSz);
      if(!bull && !bear) continue;

      double hi, lo;
      if(bull) { lo = r[i + 2].high; hi = r[i].low; }
      else     { hi = r[i + 2].low;  lo = r[i].high; }
      double gap = hi - lo;

      double gScore = MathMin(1.0, (gap / a) / GapFullATR);
      double cVol = (double)r[i + 1].tick_volume;
      double bVol = AvgTickVol(r, i + 2, i + 21, n);
      double vScore = 0.5;
      if(bVol > 0 && cVol > 0) vScore = MathMin(1.0, (cVol / bVol) / VolFullRatio);
      double prob = 100.0 * (0.5 * gScore + 0.5 * vScore);

      bool filled = false;
      datetime te = 0;
      for(int j = i - 1; j >= 0; j--)
        {
         if(bull)
           {
            if(r[j].low <= lo) { filled = true; te = r[j].time; break; }
            if(r[j].low < hi) hi = r[j].low;
           }
         else
           {
            if(r[j].high >= hi) { filled = true; te = r[j].time; break; }
            if(r[j].high > lo) lo = r[j].high;
           }
        }
      if(filled && !FVGShowFilled) continue;

      int k = ArraySize(g_fvg);
      ArrayResize(g_fvg, k + 1);
      g_fvg[k].bull = bull;
      g_fvg[k].hi = hi;
      g_fvg[k].lo = lo;
      g_fvg[k].prob = prob;
      g_fvg[k].bar = i + 2;
      g_fvg[k].t = r[i + 2].time;
      g_fvg[k].tEnd = te;
      g_fvg[k].filled = filled;
     }
  }
//+------------------------------------------------------------------+
//| Filtres : régime Flow, biais HTF, kill zone                      |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES NextTF(ENUM_TIMEFRAMES tf)
  {
   int s = PeriodSeconds(tf);
   if(s <= 60)    return PERIOD_M15;
   if(s <= 900)   return PERIOD_H1;
   if(s <= 3600)  return PERIOD_H4;
   if(s <= 14400) return PERIOD_D1;
   if(s <= 86400) return PERIOD_W1;
   return PERIOD_MN1;
  }
void BuildRegime(const MqlRates &r[], int n, const double &atr[])
  {
   ArrayResize(g_reg, n);
   ArrayResize(g_flowMA, 0);
   for(int i = 0; i < n; i++) g_reg[i] = -1;
   if(!UseFlow || g_hMAflow == INVALID_HANDLE) return;
   ArraySetAsSeries(g_flowMA, true);
   if(CopyBuffer(g_hMAflow, 0, 0, n, g_flowMA) < n) { ArrayResize(g_flowMA, 0); return; }
   int reg = -1;
   for(int i = n - 1; i >= 0; i--)
     {
      double a = A(atr, r, i);
      double d = r[i].close - g_flowMA[i];
      if(reg < 0) reg = (d >= 0) ? 1 : 0;
      else if(d > FlowHyst * a)  reg = 1;
      else if(d < -FlowHyst * a) reg = 0;
      g_reg[i] = reg;
     }
  }
int HTFBias(datetime t)
  {
   if(g_hMAhtf == INVALID_HANDLE) return 0;
   int sh = iBarShift(_Symbol, g_htf, t, false);
   if(sh < 0) return 0;
   sh++;
   double ma[1], cl[1];
   if(CopyBuffer(g_hMAhtf, 0, sh, 1, ma) != 1) return 0;
   if(CopyClose(_Symbol, g_htf, sh, 1, cl) != 1) return 0;
   return (cl[0] > ma[0]) ? 1 : -1;
  }
bool InKillZone(datetime t)
  {
   MqlDateTime s;
   TimeToStruct(t, s);
   int h = s.hour;
   if(LondonOn && h >= LondonOpen && h < LondonClose) return true;
   if(NYOn && h >= NYOpen && h < NYClose) return true;
   if(AsiaOn && h >= AsiaOpen && h < AsiaClose) return true;
   return false;
  }
//+------------------------------------------------------------------+
//| Score de confluence de chaque signal (connu à la confirmation)   |
//+------------------------------------------------------------------+
void ScoreSwings()
  {
   int sz = ArraySize(g_sw);
   for(int k = 0; k < sz; k++)
     {
      bool hi = g_sw[k].isHigh;
      double pr = g_sw[k].price;
      int pb = g_sw[k].bar;
      double tol = 0.25 * g_sw[k].atrv;

      for(int z = 0; z < ArraySize(g_zones); z++)
         if(g_zones[z].isRes == hi && g_zones[z].bar > pb &&
            pr >= g_zones[z].lo - tol && pr <= g_zones[z].hi + tol)
           { g_sw[k].zoneConf = true; break; }

      for(int o = 0; o < ArraySize(g_ob); o++)
        {
         if(g_ob[o].bull == hi) continue;
         if(g_ob[o].evBar <= pb) continue;
         if(g_ob[o].tEnd != 0 && g_ob[o].tEnd <= g_sw[k].tBar) continue;
         if(pr >= g_ob[o].lo - tol && pr <= g_ob[o].hi + tol)
           { g_sw[k].obConf = true; break; }
        }

      for(int s = 0; s < ArraySize(g_sweep); s++)
         if(g_sweep[s].buySide == hi && MathAbs(g_sweep[s].bar - pb) <= 2)
           { g_sw[k].sweepConf = true; break; }

      // contre-tendance (CHoCH ou MSS) dans le bon sens avant la confirmation
      for(int e = 0; e < ArraySize(g_ev); e++)
         if(g_ev[e].kind >= 1 && g_ev[e].bull == !hi && g_ev[e].bar < pb && g_ev[e].bar >= g_sw[k].conf)
           { g_sw[k].chochConf = true; break; }

      if(k > 0)
        {
         double eq = (pr + g_sw[k - 1].price) / 2.0;
         g_sw[k].pdConf = hi ? (g_sw[k].entry > eq) : (g_sw[k].entry < eq);
        }

      if(KZInScore) g_sw[k].kzConf = InKillZone(g_sw[k].tConf);

      int sc = 0;
      if(g_sw[k].zoneConf)  sc++;
      if(g_sw[k].obConf)    sc++;
      if(g_sw[k].sweepConf) sc++;
      if(g_sw[k].chochConf) sc++;
      if(g_sw[k].pdConf)    sc++;
      if(g_sw[k].kzConf)    sc++;

      if(UseFlow && g_sw[k].conf < ArraySize(g_reg))
        {
         g_sw[k].flowConf = hi ? (g_reg[g_sw[k].conf] == 0) : (g_reg[g_sw[k].conf] == 1);
         if(g_sw[k].flowConf) sc++;
        }
      if(g_hMAhtf != INVALID_HANDLE)
        {
         int b = HTFBias(g_sw[k].tConf);
         g_sw[k].htfConf = hi ? (b == -1) : (b == 1);
         if(g_sw[k].htfConf) sc++;
        }
      g_sw[k].lowVol = (g_sw[k].atrAvg > 0 && g_sw[k].atrv < LowVolRatio * g_sw[k].atrAvg);
      g_sw[k].score = sc;
      g_sw[k].valid = (sc >= MinScore) && !(FilterLowVol && g_sw[k].lowVol);
      g_sw[k].star = (sc >= StarMinScore);
     }
  }
//+------------------------------------------------------------------+
//| Dessins SMC                                                      |
//+------------------------------------------------------------------+
void DrawStructure(SEvent &ev[], int maxN, bool internal)
  {
   int sz = ArraySize(ev);
   int start = MathMax(0, sz - maxN);
   string pre = internal ? "i" : "";
   for(int e = start; e < sz; e++)
     {
      color c;
      if(ev[e].kind == 2)      c = clrGold;
      else if(internal)        c = ev[e].bull ? C'0,120,70' : C'150,50,50';
      else                     c = ev[e].bull ? clrLime : clrRed;
      string id = (internal ? "I" : "E") + IntegerToString(e);
      ENUM_LINE_STYLE st = internal ? STYLE_DOT : (ev[e].kind >= 1 ? STYLE_SOLID : STYLE_DASH);
      MakeTrend(PFX + "EV" + id, ev[e].tLvl, ev[e].lvl, ev[e].t, ev[e].lvl, c,
                (!internal && ev[e].kind == 2) ? 2 : 1, st, false);
      string lab = ev[e].kind == 2 ? "MSS" : (ev[e].kind == 1 ? "CHoCH" : "BOS");
      datetime tm = ev[e].tLvl + (datetime)(((long)ev[e].t - (long)ev[e].tLvl) / 2);
      MakeText(PFX + "EVT" + id, tm, ev[e].lvl, pre + lab, c,
               ev[e].bull ? ANCHOR_LOWER : ANCHOR_UPPER);
     }
  }
bool OBShown(int o)
  {
   if(g_ob[o].mitigated && !ShowMitigatedOB) return false;
   if(g_ob[o].prob < MinProb) return false;
   if(PDAFilter && g_hasRange)
     {
      int loc = PDALoc((g_ob[o].hi + g_ob[o].lo) / 2.0);
      if(g_ob[o].bull && loc != -1) return false;
      if(!g_ob[o].bull && loc != 1) return false;
     }
   return true;
  }
void DrawOB(const MqlRates &r[])
  {
   int ps = PeriodSeconds();
   int cnt = 0;
   for(int o = ArraySize(g_ob) - 1; o >= 0 && cnt < MaxOB; o--)
     {
      if(!OBShown(o)) continue;
      cnt++;
      bool strong = (g_ob[o].prob >= ProbThreshold);
      color c = g_ob[o].bull ? C'0,170,150' : C'210,70,70';
      datetime te = g_ob[o].mitigated ? g_ob[o].tEnd
                    : (ZoneExtend ? r[0].time + (datetime)((long)ps * 30) : r[0].time);
      string id = IntegerToString(o);
      MakeRect(PFX + "OB" + id, g_ob[o].t, g_ob[o].hi, te, g_ob[o].lo, c, strong ? 2 : 1, STYLE_SOLID);
      string txt = (g_ob[o].bull ? "OB+ " : "OB- ") + IntegerToString((int)MathRound(g_ob[o].prob)) + "%" +
                   PDATag(PDALoc((g_ob[o].hi + g_ob[o].lo) / 2.0)) + (strong ? " *" : "");
      MakeText(PFX + "OBT" + id, g_ob[o].t, (g_ob[o].hi + g_ob[o].lo) / 2.0, txt,
               strong ? clrWhite : c, ANCHOR_RIGHT);
     }
  }
void DrawFVG(const MqlRates &r[])
  {
   int ps = PeriodSeconds();
   int cnt = 0;
   for(int f = ArraySize(g_fvg) - 1; f >= 0 && cnt < MaxFVG; f--)
     {
      if(g_fvg[f].prob < MinProb) continue;
      double mid = (g_fvg[f].hi + g_fvg[f].lo) / 2.0;
      int loc = PDALoc(mid);
      if(PDAFilter && g_hasRange)
        {
         if(g_fvg[f].bull && loc != -1) continue;
         if(!g_fvg[f].bull && loc != 1) continue;
        }
      cnt++;
      bool strong = (g_fvg[f].prob >= ProbThreshold);
      color c = g_fvg[f].bull ? C'0,130,70' : C'150,50,50';
      datetime te = g_fvg[f].filled ? g_fvg[f].tEnd
                    : (ZoneExtend ? r[0].time + (datetime)((long)ps * 30) : r[0].time);
      string id = IntegerToString(f);
      MakeRect(PFX + "FVG" + id, g_fvg[f].t, g_fvg[f].hi, te, g_fvg[f].lo, c, strong ? 2 : 1, STYLE_DOT);
      string txt = (g_fvg[f].bull ? "FVG+ " : "FVG- ") + IntegerToString((int)MathRound(g_fvg[f].prob)) + "%" +
                   PDATag(loc) + (strong ? " *" : "");
      MakeText(PFX + "FVGT" + id, g_fvg[f].t, mid, txt, strong ? clrWhite : c, ANCHOR_RIGHT);
     }
  }
// Ligne de tendance : EMA du régime Flow, colorée selon le régime (couleur du mode = haussier,
// blanc = baissier), avec une petite flèche jaune à chaque changement de régime (bougies clôturées)
void DrawTrendLine(const MqlRates &r[], int n)
  {
   if(ArraySize(g_flowMA) < n || ArraySize(g_reg) < n) return;
   color cBull = (ColorMode == SV_BLUE) ? clrDodgerBlue : clrTomato;
   int from = MathMin(n - 2, MathMax(5, TrendBars));
   for(int i = from; i >= 1; i--)
     {
      if(g_reg[i] < 0) continue;
      string id = IntegerToString(i);
      MakeTrend(PFX + "TR" + id, r[i + 1].time, g_flowMA[i + 1], r[i].time, g_flowMA[i],
                (g_reg[i] == 1) ? cBull : clrWhite, 2, STYLE_SOLID, false);
      if(g_reg[i + 1] >= 0 && g_reg[i] != g_reg[i + 1])
        {
         if(g_reg[i] == 1) MakeDot(PFX + "TRF" + id, r[i].time, r[i].low, clrYellow, 1, 233, ANCHOR_TOP);
         else              MakeDot(PFX + "TRF" + id, r[i].time, r[i].high, clrYellow, 1, 234, ANCHOR_BOTTOM);
        }
     }
  }
//+------------------------------------------------------------------+
//| PROFILS D'ACTIF : points de départ par famille de marché         |
//| (valeurs raisonnables, pas optimisées : à ajuster sur tes données)|
//+------------------------------------------------------------------+
bool NameHas(string nm, string key) { return StringFind(nm, key) >= 0; }
ENUM_SV_PROFILE DetectProfile()
  {
   string nm = _Symbol;
   string pa = SymbolInfoString(_Symbol, SYMBOL_PATH);
   StringToUpper(nm);
   StringToUpper(pa);
   if(NameHas(pa, "SYNTH") || NameHas(pa, "DERIVED") || NameHas(nm, "VOLATILITY") || NameHas(nm, "BOOM") ||
      NameHas(nm, "CRASH") || NameHas(nm, "STEP") || NameHas(nm, "JUMP") || NameHas(nm, "RANGE BREAK") ||
      NameHas(nm, "DRIFT") || NameHas(nm, "DEX") || NameHas(nm, "BULL MARKET") || NameHas(nm, "BEAR MARKET") ||
      NameHas(nm, "BASKET") || NameHas(nm, "VOLSWITCH") || NameHas(nm, "SWITCH"))
      return PROF_SYNTH;
   string cr[] = {"BTC", "ETH", "LTC", "XRP", "SOL", "DOGE", "BNB", "ADA", "DOT", "LINK", "AVAX", "MATIC", "TRX"};
   if(NameHas(pa, "CRYPTO"))
      return PROF_CRYPTO;
   for(int i = 0; i < ArraySize(cr); i++)
      if(StringFind(nm, cr[i]) == 0) return PROF_CRYPTO;
   string ix[] = {"US30", "US500", "US100", "NAS", "USTEC", "SPX", "GER", "DE40", "DE30", "DAX", "UK100", "FRA40",
                  "JP225", "NIKKEI", "HK50", "DJ30", "WS30", "AUS200", "EU50", "ES35", "NDX", "DJI", "US2000"};
   if(NameHas(pa, "INDIC") || NameHas(pa, "INDEX"))
      return PROF_INDICES;
   for(int i = 0; i < ArraySize(ix); i++)
      if(NameHas(nm, ix[i])) return PROF_INDICES;
   return PROF_FOREX;
  }
void ApplyProfile()
  {
   SwingATRMult = inSwingATRMult;  IntSwingATRMult = inIntSwingATRMult;  StopATR = inStopATR;
   FVGMinATR = inFVGMinATR;        EQTolATR = inEQTolATR;                 MSSBodyATR = inMSSBodyATR;
   LowVolRatio = inLowVolRatio;    FVGIgnoreGaps = inFVGIgnoreGaps;       FilterLowVol = inFilterLowVol;
   KZInScore = inKZInScore;        KZShow = inKZShow;
   g_profName = "MANUEL";
   if(AssetProfile == PROF_MANUAL) return;

   ENUM_SV_PROFILE p = (AssetProfile == PROF_AUTO) ? DetectProfile() : AssetProfile;
   string nm = _Symbol;
   StringToUpper(nm);
   switch(p)
     {
      case PROF_INDICES:
         g_profName = "INDICES";
         SwingATRMult = 2.2; IntSwingATRMult = 0.9; StopATR = 0.6; FVGMinATR = 0.25; EQTolATR = 0.12;
         MSSBodyATR = 1.1; LowVolRatio = 0.4; FilterLowVol = true; FVGIgnoreGaps = true;
         KZInScore = true; KZShow = true;
         break;
      case PROF_CRYPTO:
         g_profName = "CRYPTO";
         SwingATRMult = 2.8; IntSwingATRMult = 1.1; StopATR = 0.7; FVGMinATR = 0.2; EQTolATR = 0.2;
         MSSBodyATR = 1.2; LowVolRatio = 0.35; FilterLowVol = true; FVGIgnoreGaps = false;
         KZInScore = false; KZShow = false;
         break;
      case PROF_SYNTH:
         g_profName = "SYNTH";
         SwingATRMult = 2.2; IntSwingATRMult = 0.9; StopATR = 0.8; FVGMinATR = 0.3; EQTolATR = 0.1;
         MSSBodyATR = 1.2; LowVolRatio = 0.0; FilterLowVol = false; FVGIgnoreGaps = false;
         KZInScore = false; KZShow = false;
         if(NameHas(nm, "BOOM") || NameHas(nm, "CRASH"))     // spikes : ATR déformé, stop plus large
           { SwingATRMult = 3.2; StopATR = 1.0; }
         break;
      default:
         g_profName = "FOREX";
         SwingATRMult = 2.5; IntSwingATRMult = 1.0; StopATR = 0.5; FVGMinATR = 0.2; EQTolATR = 0.15;
         MSSBodyATR = 1.0; LowVolRatio = 0.4; FilterLowVol = true; FVGIgnoreGaps = true;
         KZInScore = true; KZShow = true;
         break;
     }
  }
//+------------------------------------------------------------------+
//| CONTEXTE MULTI-TIMEFRAME : structure (BOS/CHoCH/MSS) du H1 / H4   |
//+------------------------------------------------------------------+
string TFName(ENUM_TIMEFRAMES tf) { return StringSubstr(EnumToString(tf), 7); }
ENUM_TIMEFRAMES CtxTF(int which)
  {
   int s = PeriodSeconds();
   if(which == 1)
     {
      if(s <= 900)   return PERIOD_H1;
      if(s <= 3600)  return PERIOD_H4;
      if(s <= 14400) return PERIOD_D1;
      return PERIOD_W1;
     }
   if(s <= 900)   return PERIOD_H4;
   if(s <= 3600)  return PERIOD_D1;
   if(s <= 14400) return PERIOD_W1;
   return PERIOD_MN1;
  }
void BuildCtx(ENUM_TIMEFRAMES tf, int hAtr, SEvent &ev[])
  {
   ArrayResize(ev, 0);
   if(hAtr == INVALID_HANDLE) return;
   int want = MathMin(1500, Bars(_Symbol, tf));
   if(want < 60) return;
   MqlRates cr[];
   ArraySetAsSeries(cr, true);
   int cn = CopyRates(_Symbol, tf, 0, want, cr);
   if(cn < 60) return;
   double ca[];
   ArraySetAsSeries(ca, true);
   int got = CopyBuffer(hAtr, 0, 0, cn, ca);
   if(got < 60) return;
   cn = MathMin(cn, got);
   SPivot pv[];
   SSweep dummy[];
   double ext;
   int extI;
   BuildPivots(cr, cn, ca, SwingATRMult, pv, ext, extI);
   BuildStructure(cr, cn, ca, pv, ev, dummy, false);
  }
// biais de structure du contexte à l'instant t (événement clôturé avant t)
int CtxBiasAt(SEvent &ev[], ENUM_TIMEFRAMES tf, datetime t)
  {
   int b = 0;
   long ps = (long)PeriodSeconds(tf);
   for(int k = 0; k < ArraySize(ev); k++)
     {
      if((long)ev[k].t + ps > (long)t) break;
      b = ev[k].bull ? 1 : -1;
     }
   return b;
  }
string BiasTxt(int b) { return (b > 0) ? "BULL" : ((b < 0) ? "BEAR" : "-"); }
//+------------------------------------------------------------------+
//| SETUP DETAILLE                                                   |
//+------------------------------------------------------------------+
string SetupStateName(int s)
  {
   switch(s)
     {
      case 0: return "PREPARATION";
      case 1: return "ZONE TOUCHEE";
      case 2: return "ENTREE CONFIRMEE";
      case 3: return "TP1 ATTEINT";
      case 4: return "STOP TOUCHE";
      case 5: return "ANNULE";
     }
   return "EXPIRE";
  }
string SetupStateShort(int s)
  {
   switch(s)
     {
      case 0: return "PREP";
      case 1: return "TOUCHE";
      case 2: return "ENTREE";
      case 3: return "TP1";
      case 4: return "SL";
      case 5: return "ANNULE";
     }
   return "EXPIRE";
  }
color SetupStateColor(int s, bool bull)
  {
   switch(s)
     {
      case 0: return clrGold;
      case 1: return clrOrange;
      case 2: return bull ? clrLime : clrRed;
      case 3: return clrAqua;
     }
   return clrGray;
  }
bool IsSwing(int k)
  {
   double h2 = HoursTo(MathAbs(g_set[k].t2 - g_set[k].entry));
   return (h2 >= 8.0);
  }
string SetupStars(int score)
  {
   double q = 100.0 * score / MathMax(1, g_setMax);
   if(q >= SniperPct) return "***";
   if(q >= StrongPct) return "**";
   return "*";
  }
string SetupTier(int score)
  {
   double q = 100.0 * score / MathMax(1, g_setMax);
   if(q >= SniperPct) return "SNIPER";
   if(q >= StrongPct) return "STRONG";
   return "SETUP";
  }
string Px(double v) { return DoubleToString(v, _Digits); }
// Vitesse empirique : moyenne des 10 dernières jambes externes (|variation| / nombre de bougies)
void CalcSpeed()
  {
   g_speed = 0;
   double sd = 0;
   int sb = 0, c = 0;
   for(int p = ArraySize(g_pivE) - 1; p >= 1 && c < 10; p--, c++)
     {
      sd += MathAbs(g_pivE[p].price - g_pivE[p - 1].price);
      sb += MathAbs(g_pivE[p - 1].bar - g_pivE[p].bar);
     }
   if(sb > 0 && sd > 0) g_speed = sd / sb;
  }
double HoursTo(double dist)
  {
   if(g_speed <= 0 || dist <= 0) return -1;
   return (dist / g_speed) * (double)PeriodSeconds() / 3600.0;
  }
string DurTxt(double dist)
  {
   double h = HoursTo(dist);
   if(h < 0) return "n/d";
   if(h < 1.0) return "~" + IntegerToString((int)MathMax(5, MathRound(h * 60.0))) + "min";
   if(h < 48.0) return "~" + DoubleToString(h, h < 10 ? 1 : 0) + "h";
   return "~" + DoubleToString(h / 24.0, 1) + "j";
  }
string SetupKind(int k)
  {
   int dir = g_set[k].bull ? 1 : -1;
   string tr = (g_set[k].c1 == dir && g_set[k].c2 == dir) ? "AVEC TENDANCE"
               : (g_set[k].c2 == -dir ? "CONTRE TENDANCE" : "PULLBACK / MIXTE");
   double h2 = HoursTo(MathAbs(g_set[k].t2 - g_set[k].entry));
   string hz = (h2 < 0) ? "HORIZON n/d" : (h2 < 8.0 ? "INTRADAY" : (h2 < 48.0 ? "SWING COURT" : "SWING"));
   return hz + " - " + tr;
  }
bool SweepNear(bool bull, int fbar)
  {
   for(int s = 0; s < ArraySize(g_sweep); s++)
      if(g_sweep[s].buySide == !bull && g_sweep[s].bar >= fbar && g_sweep[s].bar <= fbar + SetupSweepBars)
         return true;
   for(int s = 0; s < ArraySize(g_sweepI); s++)
      if(g_sweepI[s].buySide == !bull && g_sweepI[s].bar >= fbar && g_sweepI[s].bar <= fbar + SetupSweepBars)
         return true;
   return false;
  }
bool StructNear(bool bull, int fbar)
  {
   for(int e = 0; e < ArraySize(g_ev); e++)
      if(g_ev[e].bull == bull && g_ev[e].bar >= fbar - 1 && g_ev[e].bar <= fbar + 5) return true;
   for(int e = 0; e < ArraySize(g_evI); e++)
      if(g_evI[e].bull == bull && g_evI[e].bar >= fbar - 1 && g_evI[e].bar <= fbar + 5) return true;
   return false;
  }
// Rejoue la vie d'une zone sur les bougies clôturées : préparation -> touchée -> entrée -> TP1 / SL
void EvalSetup(bool bull, string src, double zhi, double zlo, double prob, int fbar,
               const MqlRates &r[], int n, const double &atr[])
  {
   double a0 = A(atr, r, fbar);
   double spr = UseSpreadCost ? (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point : 0.0;

   // niveaux prévus avant confirmation : entrée au bord proche de la zone
   double entry = bull ? zhi : zlo;
   double stop  = bull ? (zlo - StopATR * a0) : (zhi + StopATR * a0);
   double risk  = MathMax(MathAbs(entry - stop), 0.2 * a0);
   stop = bull ? entry - risk : entry + risk;
   double t1 = bull ? entry + risk * Target1RR : entry - risk * Target1RR;
   double t2 = bull ? entry + risk * Target2RR : entry - risk * Target2RR;
   int state = 0, stateBar = fbar, tapBar = -1, trigBar = -1;

   for(int j = fbar - 1; j >= 1; j--)
     {
      if(state <= 1)
        {
         if(bull ? (r[j].close < zlo) : (r[j].close > zhi)) { state = 5; stateBar = j; break; }
         if(tapBar < 0 && (bull ? (r[j].low <= zhi) : (r[j].high >= zlo)))
           { tapBar = j; state = 1; stateBar = j; }
         if(tapBar < 0)
           {
            if(fbar - j >= SetupMaxBars) { state = 6; stateBar = j; break; }
            continue;
           }
         bool trig = bull ? (r[j].close > zhi && r[j].close > r[j].open)
                          : (r[j].close < zlo && r[j].close < r[j].open);
         if(trig)
           {
            double a = A(atr, r, j);
            entry = r[j].close;
            risk = MathMax(MathAbs(entry - (bull ? (zlo - StopATR * a) : (zhi + StopATR * a))), 0.2 * a);
            stop = bull ? entry - risk : entry + risk;
            t1 = bull ? entry + risk * Target1RR : entry - risk * Target1RR;
            t2 = bull ? entry + risk * Target2RR : entry - risk * Target2RR;
            if(risk > SetupMaxRiskATR * a) { state = 5; stateBar = j; break; }
            trigBar = j; state = 2; stateBar = j;
           }
         else if(tapBar - j >= SetupTapBars) { state = 6; stateBar = j; break; }
        }
      else if(state == 2)
        {
         if(trigBar - j >= SetupHoldBars) { state = 6; stateBar = j; break; }
         if(bull)
           {
            if(r[j].low <= stop)      { state = 4; stateBar = j; break; }
            if(r[j].high >= t1 + spr) { state = 3; stateBar = j; break; }
           }
         else
           {
            if(r[j].high + spr >= stop) { state = 4; stateBar = j; break; }
            if(r[j].low <= t1)          { state = 3; stateBar = j; break; }
           }
        }
     }

   // DOL : plus proche liquidité externe non encore prise, au-delà de TP1
   double dol = 0;
   int refBar = (trigBar >= 0) ? trigBar : 1;
   double minDist = risk * Target1RR;
   for(int p = 0; p < ArraySize(g_pivE); p++)
     {
      if(g_pivE[p].conf < refBar) continue;
      double pr = g_pivE[p].price;
      if(bull != g_pivE[p].isHigh) continue;
      if(bull ? (pr <= entry + minDist) : (pr >= entry - minDist)) continue;
      bool taken = false;
      for(int j = g_pivE[p].bar - 1; j >= refBar; j--)
         if(bull ? (r[j].high > pr) : (r[j].low < pr)) { taken = true; break; }
      if(taken) continue;
      if(dol == 0 || (bull ? (pr < dol) : (pr > dol))) dol = pr;
     }

   // confluences connues à la naissance de la zone
   int dir = bull ? 1 : -1;
   datetime tf0 = r[fbar].time;
   bool fSweep = SweepNear(bull, fbar);
   bool fProb = (prob >= ProbThreshold);
   bool fOver = (src == "OB+FVG");
   int c1 = CtxBiasAt(g_c1ev, g_ctx1, tf0);
   int c2 = CtxBiasAt(g_c2ev, g_ctx2, tf0);
   bool fC1 = (c1 == dir), fC2 = (c2 == dir);
   int em = (g_hMAhtf != INVALID_HANDLE) ? HTFBias(tf0) : 0;
   bool fEma = (em == dir);
   bool fFlow = (UseFlow && fbar < ArraySize(g_reg) && g_reg[fbar] == (bull ? 1 : 0));
   bool fPda = false;
   if(g_hasRange)
     {
      int loc = PDALoc((zhi + zlo) / 2.0);
      fPda = bull ? (loc == -1) : (loc == 1);
     }
   bool fKz = (KZInScore && InKillZone(tf0));
   int sc = (fSweep ? 1 : 0) + (fProb ? 1 : 0) + (fOver ? 1 : 0) + (fC1 ? 1 : 0) + (fC2 ? 1 : 0) +
            (fEma ? 1 : 0) + (fFlow ? 1 : 0) + (fPda ? 1 : 0) + (fKz ? 1 : 0);
   if(sc < SetupMinScore) return;
   if(SetupNeedCtx && c1 != 0 && c1 != dir) return;

   int k = ArraySize(g_set);
   ArrayResize(g_set, k + 1);
   g_set[k].bull = bull;      g_set[k].src = src;
   g_set[k].zhi = zhi;        g_set[k].zlo = zlo;       g_set[k].prob = prob;
   g_set[k].fbar = fbar;      g_set[k].state = state;   g_set[k].stateBar = stateBar;
   g_set[k].tapBar = tapBar;  g_set[k].trigBar = trigBar;
   g_set[k].entry = entry;    g_set[k].stop = stop;     g_set[k].t1 = t1;
   g_set[k].t2 = t2;          g_set[k].dol = dol;
   g_set[k].score = sc;       g_set[k].c1 = c1;         g_set[k].c2 = c2;   g_set[k].ema = em;
   g_set[k].fSweep = fSweep;  g_set[k].fProb = fProb;   g_set[k].fOver = fOver;
   g_set[k].fC1 = fC1;        g_set[k].fC2 = fC2;       g_set[k].fEma = fEma;
   g_set[k].fFlow = fFlow;    g_set[k].fPda = fPda;     g_set[k].fKz = fKz;
   g_set[k].tForm = tf0;
  }
void BuildSetups(const MqlRates &r[], int n, const double &atr[])
  {
   ArrayResize(g_set, 0);
   g_setPick = -1;
   if(!SetupEnabled) return;
   BuildCtx(g_ctx1, g_hAtrC1, g_c1ev);
   BuildCtx(g_ctx2, g_hAtrC2, g_c2ev);
   CalcSpeed();
   g_setMax = 3 + (g_hAtrC1 != INVALID_HANDLE ? 1 : 0) + (g_hAtrC2 != INVALID_HANDLE ? 1 : 0) +
              (g_hMAhtf != INVALID_HANDLE ? 1 : 0) + (UseFlow ? 1 : 0) + (g_hasRange ? 1 : 0) + (KZInScore ? 1 : 0);

   int maxBar = MathMin(n - 8, SetupLookback);
   bool used[];
   ArrayResize(used, ArraySize(g_fvg));
   ArrayInitialize(used, false);

   for(int o = 0; o < ArraySize(g_ob); o++)
     {
      if(g_ob[o].prob < SetupMinProb) continue;
      int fb = g_ob[o].evBar;
      if(fb < 1 || fb > maxBar) continue;
      bool bull = g_ob[o].bull;
      double prob = g_ob[o].prob;
      string src = "OB";
      for(int f = 0; f < ArraySize(g_fvg); f++)
         if(g_fvg[f].bull == bull && !g_fvg[f].filled && MathAbs((g_fvg[f].bar - 2) - fb) <= 6 &&
            g_fvg[f].hi >= g_ob[o].lo && g_fvg[f].lo <= g_ob[o].hi)
           { used[f] = true; src = "OB+FVG"; prob = MathMax(prob, g_fvg[f].prob); break; }
      EvalSetup(bull, src, g_ob[o].hi, g_ob[o].lo, prob, fb, r, n, atr);
     }
   for(int f = 0; f < ArraySize(g_fvg); f++)
     {
      if(used[f] || g_fvg[f].filled || g_fvg[f].prob < SetupMinProb) continue;
      int fb = g_fvg[f].bar - 2;
      if(fb < 1 || fb > maxBar) continue;
      if(!StructNear(g_fvg[f].bull, fb)) continue;
      EvalSetup(g_fvg[f].bull, "FVG", g_fvg[f].hi, g_fvg[f].lo, g_fvg[f].prob, fb, r, n, atr);
     }

   // choix : setup actif le plus récent, sinon le dernier qui a changé d'état
   int best = -1, any = -1;
   for(int k = 0; k < ArraySize(g_set); k++)
     {
      if(g_set[k].state <= 2 && (best < 0 || g_set[k].fbar < g_set[best].fbar)) best = k;
      if(any < 0 || g_set[k].stateBar < g_set[any].stateBar) any = k;
     }
   g_setPick = (best >= 0) ? best : any;
  }
//+------------------------------------------------------------------+
//| Alertes : setup préparé / entrée confirmée / setup annulé         |
//+------------------------------------------------------------------+
void SetupAlert()
  {
   if(!SetupAlerts || g_setPick < 0) return;
   int k = g_setPick;
   datetime key = g_set[k].tForm;
   int st = g_set[k].state;
   if(key == g_setKey && st == g_setState) return;
   bool fresh = (g_set[k].stateBar <= 1);
   g_setKey = key;
   g_setState = st;
   if(!fresh) return;
   if(SetupSwingOnly && !IsSwing(k)) return;

   bool bull = g_set[k].bull;
   string head = _Symbol + " " + TFName(_Period) + " : " + (IsSwing(k) ? "[SWING] " : "") + SetupTier(g_set[k].score) + " " +
                 (bull ? "BUY " : "SELL ") + g_set[k].src + " " + SetupStars(g_set[k].score) +
                 " (" + IntegerToString(g_set[k].score) + "/" + IntegerToString(g_setMax) + ") - ";
   string msg = "";
   if(st == 0 || st == 1)
      msg = head + (st == 0 ? "SETUP EN PREPARATION" : "ZONE TOUCHEE") +
            " | zone " + Px(g_set[k].zlo) + " - " + Px(g_set[k].zhi) +
            " | declencheur : cloture " + (bull ? "> " + Px(g_set[k].zhi) : "< " + Px(g_set[k].zlo)) +
            " | invalidation : cloture " + (bull ? "< " + Px(g_set[k].zlo) : "> " + Px(g_set[k].zhi)) +
            " | " + SetupKind(k) + " | duree TP2 " + DurTxt(MathAbs(g_set[k].t2 - g_set[k].entry));
   else if(st == 2)
      msg = head + "ENTREE CONFIRMEE @ " + Px(g_set[k].entry) + " | SL " + Px(g_set[k].stop) +
            " | TP1 " + Px(g_set[k].t1) + " | TP2 " + Px(g_set[k].t2) +
            (g_set[k].dol > 0 ? " | DOL " + Px(g_set[k].dol) : "") +
            " | " + SetupKind(k) + " | duree TP1 " + DurTxt(MathAbs(g_set[k].t1 - g_set[k].entry)) +
            " TP2 " + DurTxt(MathAbs(g_set[k].t2 - g_set[k].entry));
   else if(st == 4)
      msg = head + "SETUP INVALIDE : stop touche " + Px(g_set[k].stop);
   else if(st == 5)
      msg = head + "SETUP ANNULE : cloture au-dela de la zone (ou risque trop large)";
   else
      return;
   if(AlertPopup) Alert(msg);
   if(AlertSound) PlaySound("alert.wav");
   if(AlertPush)  SendNotification(StringSubstr(msg, 0, 255));
   if(AlertEmail) SendMail("Sera SMC Vault " + _Symbol, msg);
  }
//+------------------------------------------------------------------+
//| Dessin des setups + carte détaillée                              |
//+------------------------------------------------------------------+
void DrawOneSetup(int b, const MqlRates &r[], bool primary)
  {
   int ps = PeriodSeconds();
   string id = IntegerToString(b);
   bool bull = g_set[b].bull;
   int st = g_set[b].state;
   color c = SetupStateColor(st, bull);
   color cTgt = (ColorMode == SV_BLUE) ? clrDodgerBlue : clrTomato;
   datetime te = (st <= 2) ? r[0].time + (datetime)((long)ps * 12) : r[g_set[b].stateBar].time;

   MakeRect(PFX + "SU" + id, g_set[b].tForm, g_set[b].zhi, te, g_set[b].zlo, c, primary ? 2 : 1, STYLE_DASH);
   MakeText(PFX + "SUT" + id, g_set[b].tForm, bull ? g_set[b].zlo : g_set[b].zhi,
            "SETUP " + (bull ? "BUY " : "SELL ") + SetupStars(g_set[b].score) + " " + SetupStateShort(st) + (IsSwing(b) ? " [SWING]" : ""),
            c, bull ? ANCHOR_RIGHT_UPPER : ANCHOR_RIGHT_LOWER);

   if(g_set[b].tapBar >= 1)
      MakeDot(PFX + "SUP" + id, r[g_set[b].tapBar].time, bull ? r[g_set[b].tapBar].low : r[g_set[b].tapBar].high,
              clrOrange, 2, 159, bull ? ANCHOR_TOP : ANCHOR_BOTTOM);
   if(g_set[b].trigBar >= 1)
     {
      int tb = g_set[b].trigBar;
      MakeDot(PFX + "SUE" + id, r[tb].time, bull ? r[tb].low : r[tb].high, bull ? clrLime : clrRed, 3,
              bull ? 233 : 234, bull ? ANCHOR_TOP : ANCHOR_BOTTOM);
      MakeText(PFX + "SUET" + id, r[tb].time, bull ? r[tb].low : r[tb].high, "ENTRY",
               bull ? clrLime : clrRed, bull ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
     }
   if(st >= 3 && st <= 5)
     {
      int sb = g_set[b].stateBar;
      string lbl = (st == 3) ? "TP1" : ((st == 4) ? "SL" : "ANNULE");
      MakeText(PFX + "SUR" + id, r[sb].time, bull ? r[sb].low : r[sb].high, lbl, c,
               bull ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
     }

   if(!primary) return;
   datetime tl = (g_set[b].trigBar >= 1) ? r[g_set[b].trigBar].time : r[0].time;
   datetime tx = r[0].time + (datetime)((long)ps * ZoneLabelShift);
   double inval = bull ? g_set[b].zlo : g_set[b].zhi;
   MakeTrend(PFX + "SL_ENT", tl, g_set[b].entry, tl + 1, g_set[b].entry, clrWhite, 1, STYLE_DASH, true);
   MakeTrend(PFX + "SL_STP", tl, g_set[b].stop,  tl + 1, g_set[b].stop,  clrRed,   1, STYLE_DASH, true);
   MakeTrend(PFX + "SL_T1",  tl, g_set[b].t1,    tl + 1, g_set[b].t1,    cTgt,     1, STYLE_DASH, true);
   MakeTrend(PFX + "SL_T2",  tl, g_set[b].t2,    tl + 1, g_set[b].t2,    cTgt,     1, STYLE_DASH, true);
   MakeText(PFX + "SL_ENT_T", tx, g_set[b].entry, (st == 2 ? "S-ENTRY " : "S-ENTRY? ") + Px(g_set[b].entry),
            clrWhite, ANCHOR_LEFT_UPPER);
   MakeText(PFX + "SL_STP_T", tx, g_set[b].stop, "S-SL " + Px(g_set[b].stop), clrRed, ANCHOR_LEFT_UPPER);
   MakeText(PFX + "SL_T1_T", tx, g_set[b].t1, "S-TP1 " + Px(g_set[b].t1), cTgt, ANCHOR_LEFT_UPPER);
   MakeText(PFX + "SL_T2_T", tx, g_set[b].t2, "S-TP2 " + Px(g_set[b].t2), cTgt, ANCHOR_LEFT_UPPER);
   if(g_set[b].dol > 0)
     {
      MakeTrend(PFX + "SL_DOL", tl, g_set[b].dol, tl + 1, g_set[b].dol, clrGold, 1, STYLE_DOT, true);
      MakeText(PFX + "SL_DOL_T", tx, g_set[b].dol, "S-DOL " + Px(g_set[b].dol), clrGold, ANCHOR_LEFT_UPPER);
     }
   if(st <= 1)
     {
      MakeTrend(PFX + "SL_INV", tl, inval, tl + 1, inval, clrGray, 1, STYLE_DOT, true);
      MakeText(PFX + "SL_INV_T", tx, inval, "S-INVAL " + Px(inval), clrGray, ANCHOR_LEFT_UPPER);
     }
  }
void DrawSetups(const MqlRates &r[])
  {
   int cnt = ArraySize(g_set);
   if(cnt == 0) return;
   bool done[];
   ArrayResize(done, cnt);
   ArrayInitialize(done, false);
   for(int rank = 0; rank < SetupsShown; rank++)
     {
      int b = -1;
      for(int k = 0; k < cnt; k++)
         if(!done[k] && (b < 0 || g_set[k].fbar < g_set[b].fbar)) b = k;
      if(b < 0) break;
      done[b] = true;
      DrawOneSetup(b, r, b == g_setPick);
     }
   if(g_setPick >= 0 && !done[g_setPick]) DrawOneSetup(g_setPick, r, true);
  }
void CardLine(int idx, string txt, color c)
  {
   string nm = PFX + "CARD" + IntegerToString(idx);
   ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, 8 + idx * (TextSize + 6));
   ObjectSetString(0, nm, OBJPROP_TEXT, txt);
   ObjectSetString(0, nm, OBJPROP_FONT, TextFont);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, TextSize);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
  }
void DrawSetupCard()
  {
   string tf = TFName(_Period);
   string ctx = TFName(g_ctx1) + "/" + TFName(g_ctx2);
   string lines[10];
   color  cols[10];
   int m = 0;
   if(g_setPick < 0)
     {
      lines[m] = "SETUP : aucun setup actif | profil " + g_profName + " | contexte " + ctx;
      cols[m] = clrGray;
      m++;
     }
   else
     {
      int k = g_setPick;
      bool bull = g_set[k].bull;
      int st = g_set[k].state;
      color sc = SetupStateColor(st, bull);
      string conf = "";
      if(g_set[k].fSweep) conf += "sweep ";
      if(g_set[k].fOver)  conf += "OB+FVG ";
      if(g_set[k].fProb)  conf += "prob>=" + IntegerToString(ProbThreshold) + " ";
      if(g_set[k].fPda)   conf += (bull ? "discount " : "premium ");
      if(g_set[k].fFlow)  conf += "flow ";
      if(g_set[k].fKz)    conf += "KZ ";
      if(conf == "") conf = "-";
      lines[m] = SetupTier(g_set[k].score) + " " + (bull ? "BUY " : "SELL ") + SetupStars(g_set[k].score) +
                 " " + IntegerToString(g_set[k].score) + "/" + IntegerToString(g_setMax) +
                 " | " + _Symbol + " " + tf + " | profil " + g_profName;
      cols[m++] = bull ? clrLime : clrTomato;
      lines[m] = "ETAT  : " + SetupStateName(st) + ((st == 2) ? " @ " + Px(g_set[k].entry) : "");
      cols[m++] = sc;
      lines[m] = "CTX   : " + TFName(g_ctx1) + " " + BiasTxt(g_set[k].c1) + "  " + TFName(g_ctx2) + " " +
                 BiasTxt(g_set[k].c2) + "  EMA-" + TFName(g_htf) + " " + BiasTxt(g_set[k].ema);
      cols[m++] = clrSilver;
      lines[m] = "ZONE  : " + g_set[k].src + " " + Px(g_set[k].zlo) + " - " + Px(g_set[k].zhi) + " (" +
                 IntegerToString((int)MathRound(g_set[k].prob)) + "%)  conf: " + conf;
      cols[m++] = clrSilver;
      lines[m] = "TRIG  : cloture " + tf + (bull ? " > " + Px(g_set[k].zhi) + " (bougie haussiere)"
                                                 : " < " + Px(g_set[k].zlo) + " (bougie baissiere)") + " apres retest";
      cols[m++] = clrSilver;
      lines[m] = "SL    : " + Px(g_set[k].stop) + "   TP1 " + Px(g_set[k].t1) + "   TP2 " + Px(g_set[k].t2) +
                 (g_set[k].dol > 0 ? "   DOL " + Px(g_set[k].dol) : "");
      cols[m++] = clrWhite;
      lines[m] = "TYPE  : " + SetupKind(k);
      cols[m++] = clrGold;
      lines[m] = "DUREE : TP1 " + DurTxt(MathAbs(g_set[k].t1 - g_set[k].entry)) +
                 "   TP2 " + DurTxt(MathAbs(g_set[k].t2 - g_set[k].entry)) +
                 (g_set[k].dol > 0 ? "   DOL " + DurTxt(MathAbs(g_set[k].dol - g_set[k].entry)) : "") +
                 "  (vitesse des swings recents)";
      cols[m++] = clrGold;
      lines[m] = "INVAL : " + (st == 2 ? "stop " + Px(g_set[k].stop)
                                       : "cloture " + (bull ? "sous " + Px(g_set[k].zlo) : "au-dessus de " + Px(g_set[k].zhi)));
      cols[m++] = clrGray;
     }
   for(int i = 0; i < m; i++)
      CardLine(m - 1 - i, lines[i], cols[i]);
  }
void SetupPanelFill()
  {
   if(g_setPick < 0) { g_pSetTxt = "-"; g_pSetSc = "-"; g_pSetCol = clrGray; return; }
   int k = g_setPick;
   g_pSetTxt = (g_set[k].bull ? "BUY " : "SELL ") + SetupStateShort(g_set[k].state) + (IsSwing(k) ? " SW" : "");
   g_pSetSc = SetupStars(g_set[k].score) + " " + IntegerToString(g_set[k].score) + "/" + IntegerToString(g_setMax);
   g_pSetCol = SetupStateColor(g_set[k].state, g_set[k].bull);
  }
void DrawSweeps()
  {
   int sz = ArraySize(g_sweep);
   int start = MathMax(0, sz - MaxSweeps);
   for(int s = start; s < sz; s++)
      MakeText(PFX + "SW" + IntegerToString(s), g_sweep[s].t, g_sweep[s].price, "SWEEP", clrGray,
               g_sweep[s].buySide ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
  }
// PDA : zones Premium / Equilibrium / Discount du range courant
void DrawPD(const MqlRates &r[])
  {
   if(!g_hasRange) return;
   datetime tR = r[0].time + (datetime)((long)PeriodSeconds() * 30);
   double rng = g_rHi - g_rLo;
   double band = PDABandPct / 100.0;
   double eqHi = g_rLo + rng * (0.5 + band);
   double eqLo = g_rLo + rng * (0.5 - band);
   MakeRect(PFX + "PDA_P", g_rT0, g_rHi, tR, eqHi, C'60,20,20', 1, STYLE_DOT, true);
   MakeRect(PFX + "PDA_E", g_rT0, eqHi, tR, eqLo, C'45,45,45', 1, STYLE_DOT, true);
   MakeRect(PFX + "PDA_D", g_rT0, eqLo, tR, g_rLo, C'15,55,35', 1, STYLE_DOT, true);
   MakeTrend(PFX + "PDA_EQL", g_rT0, g_rLo + rng * 0.5, g_rT0 + 1, g_rLo + rng * 0.5, clrGray, 1, STYLE_DOT, true);
   datetime tx = r[0].time + (datetime)((long)PeriodSeconds() * ZoneLabelShift);
   MakeText(PFX + "PDA_PT", tx, (g_rHi + eqHi) / 2.0, "PREMIUM", clrGray, ANCHOR_LEFT);
   MakeText(PFX + "PDA_ET", tx, g_rLo + rng * 0.5,
            "EQ (" + DoubleToString(g_rLo + rng * 0.5, _Digits) + ")", clrGray, ANCHOR_LEFT);
   MakeText(PFX + "PDA_DT", tx, (g_rLo + eqLo) / 2.0, "DISCOUNT", clrGray, ANCHOR_LEFT);
  }
// DOL : liquidité externe = PDH/PDL, PWH/PWL
void DolLine(string tag, double lvl, datetime tStart, bool isHigh, const MqlRates &r[], int n)
  {
   if(lvl <= 0 || tStart == 0) return;
   bool swept = false;
   for(int i = 0; i < n; i++)
     {
      if(r[i].time < tStart) break;
      if(isHigh && r[i].high >= lvl) { swept = true; break; }
      if(!isHigh && r[i].low <= lvl) { swept = true; break; }
     }
   color c = swept ? clrDimGray : clrGold;
   MakeTrend(PFX + "DOL_" + tag, tStart, lvl, tStart + 1, lvl, c, 1, swept ? STYLE_DOT : STYLE_DASH, true);
   datetime tx = r[0].time + (datetime)((long)PeriodSeconds() * ZoneLabelShift);
   MakeText(PFX + "DOLT_" + tag, tx, lvl,
            tag + " (" + DoubleToString(lvl, _Digits) + ")" + (swept ? " SWEPT" : ""), c, ANCHOR_LEFT);
  }
void DrawDOL(const MqlRates &r[], int n)
  {
   if(DOLDaily)
     {
      datetime t0 = iTime(_Symbol, PERIOD_D1, 0);
      DolLine("PDH", iHigh(_Symbol, PERIOD_D1, 1), t0, true, r, n);
      DolLine("PDL", iLow(_Symbol, PERIOD_D1, 1), t0, false, r, n);
     }
   if(DOLWeekly)
     {
      datetime t0 = iTime(_Symbol, PERIOD_W1, 0);
      DolLine("PWH", iHigh(_Symbol, PERIOD_W1, 1), t0, true, r, n);
      DolLine("PWL", iLow(_Symbol, PERIOD_W1, 1), t0, false, r, n);
     }
  }
//+------------------------------------------------------------------+
//| Points, étoiles, signaux, niveaux, stats                         |
//+------------------------------------------------------------------+
void DrawSwings(const MqlRates &r[])
  {
   int sz = ArraySize(g_sw);
   if(sz == 0) return;
   int ps = PeriodSeconds();
   int start = MathMax(0, sz - MaxSignalsShown);
   color cTgt = (ColorMode == SV_BLUE) ? clrDodgerBlue : clrTomato;

   if(ShowZigZag)
     {
      for(int k = start; k < sz - 1; k++)
         MakeTrend(PFX + "ZZ" + IntegerToString(k), g_sw[k].tBar, g_sw[k].price,
                   g_sw[k + 1].tBar, g_sw[k + 1].price, clrWhite, 2, STYLE_SOLID, false);
      MakeTrend(PFX + "ZZc", g_sw[sz - 1].tBar, g_sw[sz - 1].price,
                r[g_curExtI].time, g_curExt, clrWhite, 1, STYLE_DOT, false);
     }

   if(g_on[B_DOL])
      for(int k = MathMax(start, 2); k < sz; k++)
         if(MathAbs(g_sw[k].price - g_sw[k - 2].price) <= EQTolATR * g_sw[k].atrv)
           {
            string id = IntegerToString(k);
            MakeTrend(PFX + "EQ" + id, g_sw[k - 2].tBar, g_sw[k - 2].price,
                      g_sw[k].tBar, g_sw[k].price, clrWhite, 1, STYLE_DOT, false);
            MakeText(PFX + "EQT" + id, g_sw[k].tBar, g_sw[k].price, g_sw[k].isHigh ? "EQH" : "EQL",
                     clrWhite, g_sw[k].isHigh ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
           }

   for(int k = start; k < sz; k++)
     {
      if(!g_sw[k].valid) continue;
      string id = IntegerToString(k);
      bool hi = g_sw[k].isHigh;

      MakeDot(PFX + "DOT" + id, g_sw[k].tBar, g_sw[k].price,
              g_sw[k].star ? clrWhite : clrGray, DotWidth, 159, hi ? ANCHOR_BOTTOM : ANCHOR_TOP);

      if(ShowStars && g_sw[k].star)
        {
         double sp = g_sw[k].price + (hi ? 1.0 : -1.0) * StarOffsetATR * g_sw[k].atrv;
         color sc = hi ? StarSellColor : StarBuyColor;
         MakeDot(PFX + "STAR" + id, g_sw[k].tBar, sp, sc, StarWidth, StarCode, hi ? ANCHOR_BOTTOM : ANCHOR_TOP);
         if(ShowStarText)
            MakeText(PFX + "STX" + id, g_sw[k].tBar, sp,
                     hi ? " FIN BUY > SELL" : " FIN SELL > BUY", sc,
                     hi ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
        }

      string an = PFX + "SIG" + id;
      double ap = hi ? r[g_sw[k].conf].high : r[g_sw[k].conf].low;
      ObjectCreate(0, an, hi ? OBJ_ARROW_DOWN : OBJ_ARROW_UP, 0, g_sw[k].tConf, ap);
      ObjectSetInteger(0, an, OBJPROP_COLOR, hi ? clrRed : clrLime);
      ObjectSetInteger(0, an, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, an, OBJPROP_ANCHOR, hi ? ANCHOR_BOTTOM : ANCHOR_TOP);
      ObjectSetInteger(0, an, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, an, OBJPROP_HIDDEN, true);

      string tag = TierName(g_sw[k].score) + (hi ? "SELL " : "BUY ") + StarStr(g_sw[k].score) +
                   " (" + IntegerToString(g_sw[k].score) + "/" + IntegerToString(g_maxScore) + ")";
      if(g_sw[k].outcome == 1) tag += " >TP1";
      if(g_sw[k].outcome == 2) tag += " >SL";
      MakeText(PFX + "TXT" + id, g_sw[k].tConf, ap, tag,
               g_sw[k].outcome == 2 ? clrGray : (hi ? clrTomato : clrMediumSeaGreen),
               hi ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
     }

   int L = -1;
   for(int k = sz - 1; k >= 0; k--)
      if(g_sw[k].valid) { L = k; break; }
   if(L >= 0)
     {
      datetime tl = g_sw[L].tConf;
      datetime tx = r[0].time + (datetime)((long)ps * ZoneLabelShift);
      int pts = (int)MathRound(MathAbs(g_sw[L].stop - g_sw[L].entry) / _Point);
      MakeTrend(PFX + "LV_ENT", tl, g_sw[L].entry, tl + 1, g_sw[L].entry, clrWhite, 1, STYLE_DOT, true);
      MakeTrend(PFX + "LV_STP", tl, g_sw[L].stop,  tl + 1, g_sw[L].stop,  clrRed,   1, STYLE_DOT, true);
      MakeTrend(PFX + "LV_T1",  tl, g_sw[L].t1,    tl + 1, g_sw[L].t1,    cTgt,    1, STYLE_DOT, true);
      MakeTrend(PFX + "LV_T2",  tl, g_sw[L].t2,    tl + 1, g_sw[L].t2,    cTgt,    1, STYLE_DOT, true);
      MakeText(PFX + "LV_ENT_T", tx, g_sw[L].entry,
               (g_sw[L].isHigh ? "SELL" : "BUY") + " ENTRY (" + DoubleToString(g_sw[L].entry, _Digits) + ")",
               clrWhite, ANCHOR_LEFT);
      MakeText(PFX + "LV_STP_T", tx, g_sw[L].stop,
               "STOP LEVEL -" + IntegerToString(pts) + " (" + DoubleToString(g_sw[L].stop, _Digits) + ")",
               clrRed, ANCHOR_LEFT);
      MakeText(PFX + "LV_T1_T", tx, g_sw[L].t1,
               "TP1 " + DoubleToString(Target1RR, 1) + "R (" + DoubleToString(g_sw[L].t1, _Digits) + ")", cTgt, ANCHOR_LEFT);
      MakeText(PFX + "LV_T2_T", tx, g_sw[L].t2,
               "TP2 " + DoubleToString(Target2RR, 1) + "R (" + DoubleToString(g_sw[L].t2, _Digits) + ")", cTgt, ANCHOR_LEFT);
     }

   if(ShowStats)
     {
      int tot = 0, w = 0, l = 0, o = 0, sTot = 0, sW = 0, sL = 0;
      for(int k = 0; k < sz; k++)
        {
         if(!g_sw[k].valid) continue;
         tot++;
         if(g_sw[k].outcome == 1) w++; else if(g_sw[k].outcome == 2) l++; else o++;
         if(g_sw[k].star)
           {
            sTot++;
            if(g_sw[k].outcome == 1) sW++; else if(g_sw[k].outcome == 2) sL++;
           }
        }
      string r1 = (w + l > 0) ? DoubleToString(100.0 * w / (w + l), 0) + "%" : "-";
      string r2 = (sW + sL > 0) ? DoubleToString(100.0 * sW / (sW + sL), 0) + "%" : "-";
      string st = StringFormat("Sera Indicator Deriv v1.00 | signaux:%d TP1:%d SL:%d ouverts:%d taux:%s  ||  etoiles:%d TP1:%d SL:%d taux:%s",
                               tot, w, l, o, r1, sTot, sW, sL, r2);
      string nm = PFX + "STATS";
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, 20);
      ObjectSetString(0, nm, OBJPROP_TEXT, st);
      ObjectSetString(0, nm, OBJPROP_FONT, TextFont);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, TextSize + 1);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
     }
  }
//+------------------------------------------------------------------+
void SignalAlert()
  {
   if(!SignalAlerts) return;
   int sz = ArraySize(g_sw);
   int L = -1;
   for(int k = sz - 1; k >= 0; k--)
      if(g_sw[k].valid) { L = k; break; }
   if(L < 0) return;
   if(g_sw[L].conf != 1) return;
   if(g_sw[L].tConf == g_lastSigAlert) return;
   g_lastSigAlert = g_sw[L].tConf;

   string msg = _Symbol + " " + EnumToString(_Period) + " : " +
                (g_sw[L].isHigh ? "FIN DE BUY -> SELL" : "FIN DE SELL -> BUY") +
                " score " + IntegerToString(g_sw[L].score) + "/" + IntegerToString(g_maxScore) +
                (g_sw[L].star ? " *" : "") +
                " | Entree " + DoubleToString(g_sw[L].entry, _Digits) +
                " SL " + DoubleToString(g_sw[L].stop, _Digits) +
                " TP1 " + DoubleToString(g_sw[L].t1, _Digits) +
                " TP2 " + DoubleToString(g_sw[L].t2, _Digits);
   if(AlertPopup) Alert(msg);
   if(AlertSound) PlaySound("alert.wav");
   if(AlertPush)  SendNotification(StringSubstr(msg, 0, 255));
   if(AlertEmail) SendMail("Sera SMC Vault " + _Symbol, msg);
  }
//+------------------------------------------------------------------+
void DrawHODLOD(const MqlRates &r[], int n)
  {
   datetime ds = TimeCurrent() - (TimeCurrent() % 86400);
   double hi = -DBL_MAX, lo = DBL_MAX;
   datetime th = 0, tlw = 0;
   for(int i = 0; i < n; i++)
     {
      if(r[i].time < ds) break;
      if(r[i].high > hi) { hi = r[i].high; th = r[i].time; }
      if(r[i].low < lo)  { lo = r[i].low;  tlw = r[i].time; }
     }
   if(th == 0) return;
   MakeDot(PFX + "HOD_D", th, hi, clrWhite, 3, 159, ANCHOR_BOTTOM);
   MakeText(PFX + "HOD_T", th, hi, "HOD", clrWhite, ANCHOR_LEFT_LOWER);
   MakeDot(PFX + "LOD_D", tlw, lo, clrWhite, 3, 159, ANCHOR_TOP);
   MakeText(PFX + "LOD_T", tlw, lo, "LOD", clrWhite, ANCHOR_LEFT_UPPER);
  }
//+------------------------------------------------------------------+
void DrawKillZone(string tag, int hs, int he, const MqlRates &r[], int n)
  {
   if(PeriodSeconds() > 3600) return;
   color col = (ColorMode == SV_BLUE) ? C'0,0,128' : C'128,0,0';
   color txtcol = (ColorMode == SV_BLUE) ? clrBlue : clrRed;
   datetime today = TimeCurrent() - (TimeCurrent() % 86400);
   for(int d = 0; d < KZDays; d++)
     {
      datetime t1 = today - (datetime)((long)d * 86400) + (datetime)(hs * 3600);
      datetime t2 = today - (datetime)((long)d * 86400) + (datetime)(he * 3600);
      double hi = -DBL_MAX, lo = DBL_MAX;
      bool found = false;
      for(int i = 0; i < n; i++)
        {
         if(r[i].time < t1) break;
         if(r[i].time >= t2) continue;
         hi = MathMax(hi, r[i].high);
         lo = MathMin(lo, r[i].low);
         found = true;
        }
      if(!found) continue;
      string nm = PFX + "KZ_" + tag + "_" + IntegerToString(d);
      MakeRect(nm, t1, hi, t2, lo, col, 1, STYLE_SOLID, KZFill);
      MakeText(nm + "_T", t1, hi, tag, txtcol, ANCHOR_LEFT_LOWER);
     }
  }
//+------------------------------------------------------------------+
void DrawLevels(const MqlRates &r[], int n)
  {
   int L = MathMax(10, LevelPeriod);
   color cSup = (ColorMode == SV_BLUE) ? clrRoyalBlue : clrIndianRed;
   for(int b = 0; b < 2; b++)
     {
      int from = b * L, to = MathMin(n - 1, from + L - 1);
      if(from >= n - 5) break;
      double hi = -DBL_MAX, lo = DBL_MAX;
      for(int i = from; i <= to; i++)
        {
         hi = MathMax(hi, r[i].high);
         lo = MathMin(lo, r[i].low);
        }
      string nh = PFX + "LV_H" + IntegerToString(b);
      string nl = PFX + "LV_L" + IntegerToString(b);
      ObjectCreate(0, nh, OBJ_HLINE, 0, 0, hi);
      ObjectCreate(0, nl, OBJ_HLINE, 0, 0, lo);
      string names[2];
      names[0] = nh;
      names[1] = nl;
      color cols[2];
      cols[0] = clrGray;
      cols[1] = cSup;
      for(int k = 0; k < 2; k++)
        {
         ObjectSetInteger(0, names[k], OBJPROP_COLOR, cols[k]);
         ObjectSetInteger(0, names[k], OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, names[k], OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, names[k], OBJPROP_BACK, true);
         ObjectSetInteger(0, names[k], OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, names[k], OBJPROP_HIDDEN, true);
        }
     }
  }
//+------------------------------------------------------------------+
void CheckAlerts()
  {
   if(!ZoneAlerts) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   for(int i = 0; i < ArraySize(g_zones); i++)
     {
      if(!g_zones[i].visible || g_zones[i].broken) continue;
      if(bid < g_zones[i].lo || bid > g_zones[i].hi) continue;
      string key = (g_zones[i].isRes ? "R" : "S") + DoubleToString(g_zones[i].hi, _Digits);
      int k = -1;
      for(int j = 0; j < ArraySize(g_akey); j++)
         if(g_akey[j] == key) { k = j; break; }
      if(k < 0)
        {
         k = ArraySize(g_akey);
         ArrayResize(g_akey, k + 1);
         ArrayResize(g_atime, k + 1);
         g_akey[k] = key;
         g_atime[k] = 0;
        }
      if(TimeCurrent() - g_atime[k] < AlertWait) continue;
      g_atime[k] = TimeCurrent();
      string msg = _Symbol + " : prix dans zone " + (g_zones[i].isRes ? ResName : SupName) + " " +
                   g_zones[i].status + " [" + DoubleToString(g_zones[i].lo, _Digits) + " - " +
                   DoubleToString(g_zones[i].hi, _Digits) + "]";
      if(AlertPopup) Alert(msg);
      if(AlertSound) PlaySound("alert.wav");
      if(AlertPush)  SendNotification(StringSubstr(msg, 0, 255));
   if(AlertEmail) SendMail("Sera SMC Vault " + _Symbol, msg);
     }
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| AJOUT INDEPENDANT SMC SNIPER - aucune logique v1.00 remplacee       |
//| Etats : 0 attente, 1 sweep, 2 FVG, 3 confirmation, 4 TP1,         |
//| 5 TP2, 6 SL, 7 annule/expire. Pas d'ordre automatique.           |
//| Demarre au chargement : aucun signal historique reconstruit.     |
//| Seuils heuristiques, a valider separement sur chaque instrument.  |
//+------------------------------------------------------------------+

string SXState(int s)
  {
   switch(s)
     {
      case 1: return "SWEEP : attendre cassure + FVG";
      case 2: return "FVG : attendre retour + rejet";
      case 3: return "CONFIRME (reference indicative)";
      case 4: return "TP1 atteint - suivi TP2";
      case 5: return "TP2 atteint";
      case 6: return "SL atteint";
      case 7: return "ANNULE / EXPIRE";
     }
   return "ATTENTE NOUVEAU SWEEP";
  }
void SXNotify(int k)
  {
   string msg = "SMC+ " + _Symbol + " " + TFName(_Period) + " " +
                (sxPlan[k].bull ? "BUY " : "SELL ") + SXState(sxPlan[k].state);
   if(sxPlan[k].state == 3)
      msg += " E " + Px(sxPlan[k].entry) + " SL " + Px(sxPlan[k].stop) +
             " TP1 " + Px(sxPlan[k].tp1) + " TP2 " + Px(sxPlan[k].tp2);
   Print(msg);
   if(!SXAlerts) return;
   if(AlertPopup) Alert(msg);
   if(AlertSound) PlaySound("alert.wav");
   if(AlertPush) SendNotification(StringSubstr(msg, 0, 255));
   if(AlertEmail) SendMail("Sera SMC Vault " + _Symbol, msg);
  }
double SXRound(double price, bool up)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(step <= 0) step = _Point;
   return NormalizeDouble((up ? MathCeil(price / step) : MathFloor(price / step)) * step, _Digits);
  }
void SXReset()
  {
   ObjectsDeleteAll(0, "SX_");
  }
void SXRender()
  {
   SXReset();
   if(!SXEnabled) return;
   datetime now = iTime(_Symbol, _Period, 0);
   for(int k = 0; k < 2; k++)
     {
      SXPlan s = sxPlan[k];
      string nm = "SX_" + IntegerToString(k);
      color c = s.bull ? clrLime : clrOrangeRed;
      ObjectCreate(0, nm + "STATUS", OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm + "STATUS", OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm + "STATUS", OBJPROP_XDISTANCE, DashX);
      ObjectSetInteger(0, nm + "STATUS", OBJPROP_YDISTANCE, DashY + 24 + k * 18);
      ObjectSetInteger(0, nm + "STATUS", OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, nm + "STATUS", OBJPROP_COLOR, c);
      ObjectSetString(0, nm + "STATUS", OBJPROP_TEXT, "SMC+ " + (k == 0 ? "BUY : " : "SELL : ") + SXState(s.state));
      if(s.state >= 2 && s.hi > s.lo)
         MakeRect(nm + "FVG", s.gapTime, s.hi, now + PeriodSeconds() * 3, s.lo, c, 1, STYLE_DOT);
      if(s.entryTime > 0)
        {
         MakeDot(nm + "ENTRY", s.entryTime, s.entry, c, 3, s.bull ? 233 : 234, s.bull ? ANCHOR_TOP : ANCHOR_BOTTOM);
         MakeTrend(nm + "E", s.entryTime, s.entry, now + PeriodSeconds() * 3, s.entry, c, 1, STYLE_SOLID, false);
         MakeTrend(nm + "SL", s.entryTime, s.stop, now + PeriodSeconds() * 3, s.stop, clrRed, 1, STYLE_DASH, false);
         MakeTrend(nm + "T1", s.entryTime, s.tp1, now + PeriodSeconds() * 3, s.tp1, clrGold, 1, STYLE_DASH, false);
         MakeTrend(nm + "T2", s.entryTime, s.tp2, now + PeriodSeconds() * 3, s.tp2, clrAqua, 1, STYLE_DASH, false);
         MakeText(nm + "DETAIL", now, s.entry, "SMC+ E " + Px(s.entry) + " SL " + Px(s.stop) + " T1 " + Px(s.tp1) + " T2 " + Px(s.tp2), c, ANCHOR_LEFT);
        }
     }
  }
void SXProcess()
  {
   if(!SXEnabled) return;
   if(SXLiquidityBars < 3 || SXBreakBars < 2 || SXExpiryBars < 3 ||
      SXRR1 <= 0 || SXRR2 <= SXRR1 || SXBodyATR <= 0 || SXGapATR <= 0 ||
      SXStopATR < 0 || SXMaxRiskATR <= 0 || SXMaxSpreadATR < 0 || SXMaxChaseATR < 0) return;
   int need = MathMax(SXLiquidityBars, SXBreakBars) + 5;
   MqlRates r[]; double av[];
   ArraySetAsSeries(r, true); ArraySetAsSeries(av, true);
   if(CopyRates(_Symbol, _Period, 0, need, r) < need || CopyBuffer(g_atr, 0, 0, 3, av) < 3) return;
   if(av[1] <= 0 || r[1].time == sxLastClosed) return;
   // Ne pas envoyer de vieux signaux lors de l'installation ou d'une coupure.
   if(sxLastClosed == 0)
     { sxPlan[0].bull = true; sxPlan[1].bull = false; sxLastClosed = r[1].time; SXRender(); return; }
   bool missed = (r[2].time != sxLastClosed);
   sxLastClosed = r[1].time;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.ask <= 0 || tick.bid <= 0) { sxLastClosed = r[2].time; return; }
   double spread = MathMax(0.0, tick.ask - tick.bid), a = av[1];
   for(int k = 0; k < 2; k++)
     {
      bool bull = (k == 0);
      sxPlan[k].bull = bull;
      int old = sxPlan[k].state;
      if(missed && old > 0 && old <= 4)
        { sxPlan[k].state = 7; SXNotify(k); continue; }
      if(old == 3 || old == 4)
        {
         // Bougies Bid : approximation Ask historique via spread de la bougie.
         double hs = MathMax(0, r[1].spread) * _Point;
         bool sl = bull ? r[1].low <= sxPlan[k].stop : r[1].high + hs >= sxPlan[k].stop;
         bool t2 = bull ? r[1].high >= sxPlan[k].tp2 : r[1].low + hs <= sxPlan[k].tp2;
         bool t1 = bull ? r[1].high >= sxPlan[k].tp1 : r[1].low + hs <= sxPlan[k].tp1;
         // Si SL et TP sur la meme bougie : SL prioritaire, ordre intrabar inconnu.
         if(sl) sxPlan[k].state = 6;
         else if(t2) sxPlan[k].state = 5;
         else if(t1) sxPlan[k].state = 4;
         if(sxPlan[k].state != old) SXNotify(k);
         continue;
        }
      if(old == 1 || old == 2)
        {
         sxPlan[k].age++;
         bool invalid = bull ? r[1].low < sxPlan[k].extreme : r[1].high > sxPlan[k].extreme;
         if(invalid || sxPlan[k].age > SXExpiryBars)
           { sxPlan[k].state = 7; SXNotify(k); continue; }
         if(old == 1)
           {
            bool displacement = MathAbs(r[1].close - r[1].open) >= SXBodyATR * a;
            bool broken = bull ? (r[1].close > sxPlan[k].breakLevel && r[1].close > r[1].open)
                               : (r[1].close < sxPlan[k].breakLevel && r[1].close < r[1].open);
            double hi = bull ? r[1].low : r[3].low;
            double lo = bull ? r[3].high : r[1].high;
            if(displacement && broken && hi - lo >= SXGapATR * a && r[3].time >= sxPlan[k].sweepTime)
              {
               sxPlan[k].hi = hi; sxPlan[k].lo = lo; sxPlan[k].gapTime = r[1].time;
               sxPlan[k].state = 2; SXNotify(k);
              }
           }
         else
           {
            bool touch = r[1].low <= sxPlan[k].hi && r[1].high >= sxPlan[k].lo;
            bool reject = bull ? (r[1].close > sxPlan[k].hi && r[1].close > r[1].open)
                               : (r[1].close < sxPlan[k].lo && r[1].close < r[1].open);
            double entry = SXRound(bull ? tick.ask : tick.bid, bull);
            double stop = SXRound(bull ? sxPlan[k].extreme - SXStopATR * a
                                      : sxPlan[k].extreme + SXStopATR * a + spread, !bull);
            double risk = bull ? entry - stop : stop - entry;
            double stopMin = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
            bool distanceOK = bull ? tick.bid - stop >= stopMin : stop - tick.ask >= stopMin;
            double chase = MathAbs((bull ? tick.bid : tick.ask) - (r[1].close + (bull ? 0 : spread)));
            if(touch && reject && spread <= SXMaxSpreadATR * a && chase <= SXMaxChaseATR * a &&
               risk > 0 && risk <= SXMaxRiskATR * a && distanceOK && risk * SXRR1 >= stopMin)
              {
               sxPlan[k].entry = entry; sxPlan[k].stop = stop;
               sxPlan[k].tp1 = SXRound(entry + (bull ? 1 : -1) * risk * SXRR1, bull);
               sxPlan[k].tp2 = SXRound(entry + (bull ? 1 : -1) * risk * SXRR2, bull);
               sxPlan[k].entryTime = r[0].time; sxPlan[k].state = 3; SXNotify(k);
              }
           }
         continue;
        }
      double liq = bull ? r[2].low : r[2].high;
      double level = bull ? r[2].high : r[2].low;
      for(int j = 3; j <= SXLiquidityBars + 1; j++)
         liq = bull ? MathMin(liq, r[j].low) : MathMax(liq, r[j].high);
      for(int j = 3; j <= SXBreakBars + 1; j++)
         level = bull ? MathMax(level, r[j].high) : MathMin(level, r[j].low);
      bool sweep = bull ? (r[1].low < liq && r[1].close > liq) : (r[1].high > liq && r[1].close < liq);
      if(sweep)
        {
         ZeroMemory(sxPlan[k]); sxPlan[k].bull = bull; sxPlan[k].state = 1;
         sxPlan[k].sweepTime = r[1].time; sxPlan[k].extreme = bull ? r[1].low : r[1].high;
         sxPlan[k].breakLevel = level; SXNotify(k);
        }
     }
   SXRender();
  }
