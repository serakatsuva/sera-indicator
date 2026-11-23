#property version "1.01"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots 0

input int ScanSeconds = 5;
input double SpikeAtrMultiple = 2.0;
input int RetestBars = 6;
input double MinimumRewardRisk = 2.0;
input double StopBufferATR = 0.10;
input bool RequireFreshH1Origin = true;
input bool PopupAlerts = true;
input bool ExportSignals = true;

struct Market
{
   string symbol;
   int direction;
   datetime processed;
   datetime lastSignal;
   string status;
};

struct Signal
{
   double entry;
   double stop;
   double target;
   double ratio;
   double atr;
   double origin;
   double obstacle;
   double spread;
   datetime impulse;
   datetime confirmation;
};

Market markets[];
string prefix;
const int ATR_PERIOD = 14;
const int STRUCTURE_BARS = 5;

void RegisterMarket(const string symbol, const int direction)
{
   for(int i = 0; i < ArraySize(markets); i++)
      if(markets[i].symbol == symbol && markets[i].direction == direction)
         return;
   if(!SymbolSelect(symbol, true))
      return;
   int index = ArraySize(markets);
   if(ArrayResize(markets, index + 1) != index + 1)
      return;
   markets[index].symbol = symbol;
   markets[index].direction = direction;
   markets[index].processed = 0;
   markets[index].lastSignal = 0;
   markets[index].status = "Chargement";
}

void DiscoverMarkets()
{
   for(int i = 0; i < SymbolsTotal(false); i++)
   {
      string symbol = SymbolName(i, false);
      string name = symbol;
      StringToLower(name);
      if(StringFind(name, "boom") >= 0 || StringFind(name, "gain") >= 0)
         RegisterMarket(symbol, 1);
      if(StringFind(name, "crash") >= 0 || StringFind(name, "pain") >= 0)
         RegisterMarket(symbol, -1);
   }
}

double PriorATR(const MqlRates &bars[], int spike)
{
   double sum = 0.0;
   for(int i = spike + 1; i <= spike + ATR_PERIOD; i++)
   {
      double previousClose = bars[i + 1].close;
      sum += MathMax(bars[i].high - bars[i].low,
                     MathMax(MathAbs(bars[i].high - previousClose),
                             MathAbs(bars[i].low - previousClose)));
   }
   return sum / ATR_PERIOD;
}

bool FindSetup(const MqlRates &bars[], int direction, Signal &signal, double &swing)
{
   for(int spike = 2; spike <= RetestBars + 1; spike++)
   {
      double atr = PriorATR(bars, spike);
      double body = direction * (bars[spike].close - bars[spike].open);
      if(atr <= 0 || body < SpikeAtrMultiple * atr)
         continue;

      double pivot = direction > 0 ? bars[spike + 1].high : bars[spike + 1].low;
      for(int j = spike + 2; j <= spike + STRUCTURE_BARS; j++)
         pivot = direction > 0 ? MathMax(pivot, bars[j].high)
                               : MathMin(pivot, bars[j].low);
      if(direction * (bars[spike].close - pivot) <= 0 ||
         direction * (bars[spike + 1].close - pivot) > 0)
         continue;

      swing = direction > 0 ? bars[1].low : bars[1].high;
      bool valid = true;
      for(int j = spike - 1; j >= 2; j--)
      {
         // The latest closed bar must supply the first retest.
         double edge = direction > 0 ? bars[j].low : bars[j].high;
         if(direction * (edge - pivot) <= 0)
         {
            valid = false;
            break;
         }
      }
      if(!valid || direction * (swing - pivot) > 0 ||
         direction * (bars[1].close - pivot) <= 0)
         continue;

      signal.atr = atr;
      signal.impulse = bars[spike].time;
      signal.confirmation = bars[1].time;
      return true;
   }
   return false;
}

bool FindLevels(const MqlRates &hourly[], const MqlRates &bars[], int direction,
                Signal &signal)
{
   int spike = 2;
   while(bars[spike].time != signal.impulse)
      spike++;

   signal.origin = 0;
   signal.obstacle = 0;
   double newestOriginDistance = DBL_MAX;
   double nearestObstacle = DBL_MAX;
   for(int i = 1; i + 1 < ArraySize(hourly); i++)
   {
      if(hourly[i].time + PeriodSeconds(PERIOD_H1) > signal.impulse)
         continue;
      bool support = hourly[i + 1].close < hourly[i + 1].open &&
                     hourly[i].close > hourly[i].open;
      bool resistance = hourly[i + 1].close > hourly[i + 1].open &&
                        hourly[i].close < hourly[i].open;
      if(!support && !resistance)
         continue;

      double level = hourly[i + 1].close;
      if(MathAbs(hourly[i].open - level) > signal.atr * 0.25)
         continue;

      // Completed H1 bars before the spike, then M5 bars in the spike hour.
      bool fresh = true;
      datetime checkFrom = hourly[i].time + PeriodSeconds(PERIOD_H1);
      for(int j = i - 1; j >= 1; j--)
      {
         if(hourly[j].time + PeriodSeconds(PERIOD_H1) > signal.impulse)
            continue;
         if(hourly[j].low <= level && level <= hourly[j].high)
         {
            fresh = false;
            break;
         }
         checkFrom = hourly[j].time + PeriodSeconds(PERIOD_H1);
      }
      if(!fresh)
         continue;

      int needed = (int)((bars[1].time - checkFrom) / PeriodSeconds(PERIOD_M5)) + 2;
      if(needed > ArraySize(bars))
         continue;
      bool touchedBefore = false;
      bool touchedAfter = false;
      for(int j = needed - 1; j >= 1; j--)
      {
         if(bars[j].time < checkFrom || bars[j].low > level || bars[j].high < level)
            continue;
         if(j > spike)
            touchedBefore = true;
         else
            touchedAfter = true;
      }
      if(touchedBefore)
         continue;

      bool originSide = direction > 0 ? support : resistance;
      if(originSide && bars[spike].low <= level && level <= bars[spike].high)
      {
         double distance = MathAbs(bars[spike].open - level);
         if(distance < newestOriginDistance)
         {
            newestOriginDistance = distance;
            signal.origin = level;
         }
      }
      double distance = direction * (level - signal.entry);
      if(!originSide && !touchedAfter && distance > 0 && distance < nearestObstacle)
      {
         nearestObstacle = distance;
         signal.obstacle = level;
      }
   }
   return signal.obstacle > 0 && (!RequireFreshH1Origin || signal.origin > 0);
}

string SafeName(string value)
{
   string output = "";
   for(int i = 0; i < StringLen(value); i++)
   {
      ushort c = StringGetCharacter(value, i);
      bool allowed = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                     (c >= '0' && c <= '9') || c == '-';
      output += allowed ? StringSubstr(value, i, 1) : "_";
   }
   return output;
}

bool SaveSignal(const Market &market, const Signal &signal)
{
   string id = SafeName(AccountInfoString(ACCOUNT_SERVER)) + "_" +
               SafeName(market.symbol) + (market.direction > 0 ? "_BUY_" : "_SELL_") + IntegerToString((long)signal.confirmation);
   string filename = "SeraBoomCrash\\" + id;
   if(FileIsExist(filename + ".csv", FILE_COMMON))
      return true;
   string temporary = filename + "_" + IntegerToString(ChartID()) + ".tmp";
   int file = FileOpen(temporary, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',', CP_UTF8);
   if(file == INVALID_HANDLE)
      return false;
   int digits = (int)SymbolInfoInteger(market.symbol, SYMBOL_DIGITS);
   uint written = FileWrite(file, id, market.symbol, market.direction > 0 ? "BUY" : "SELL",
                            TimeToString(signal.impulse, TIME_DATE | TIME_MINUTES),
                            TimeToString(signal.confirmation, TIME_DATE | TIME_MINUTES),
                            DoubleToString(signal.entry, digits), DoubleToString(signal.stop, digits),
                            DoubleToString(signal.target, digits), DoubleToString(signal.ratio, 3),
                            DoubleToString(signal.atr, digits), DoubleToString(signal.origin, digits),
                            DoubleToString(signal.obstacle, digits), DoubleToString(signal.spread, digits));
   FileClose(file);
   bool saved = written > 0 && FileMove(temporary, FILE_COMMON, filename + ".csv", FILE_COMMON);
   if(!saved)
      FileDelete(temporary, FILE_COMMON);
   return saved || FileIsExist(filename + ".csv", FILE_COMMON);
}

void DrawLevel(string suffix, double price, color lineColor)
{
   string name = prefix + suffix;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, lineColor);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, suffix);
}

void Scan(Market &market)
{
   datetime current = iTime(market.symbol, PERIOD_M5, 0);
   if(current == 0 || current == market.processed)
      return;
   MqlRates bars[], hourly[];
   ArraySetAsSeries(bars, true);
   ArraySetAsSeries(hourly, true);
   if(CopyRates(market.symbol, PERIOD_M5, 0, 110, bars) < 110 ||
      CopyRates(market.symbol, PERIOD_H1, 0, 72, hourly) < 72 ||
      bars[0].time != current)
      return;

   Signal signal;
   double swing;
   if(!FindSetup(bars, market.direction, signal, swing))
   {
      market.processed = current;
      market.status = "Attente spike + retest";
      return;
   }
   MqlTick tick;
   double point = SymbolInfoDouble(market.symbol, SYMBOL_POINT);
   double step = SymbolInfoDouble(market.symbol, SYMBOL_TRADE_TICK_SIZE);
   if(!SymbolInfoTick(market.symbol, tick) || tick.time < current ||
      tick.ask <= 0 || tick.bid <= 0 || point <= 0 || step <= 0)
      return;
   signal.entry = market.direction > 0 ? tick.ask : tick.bid;
   signal.spread = tick.ask - tick.bid;
   if(!FindLevels(hourly, bars, market.direction, signal))
   {
      market.processed = current;
      market.status = "Filtre H1";
      return;
   }

   double margin = MathMax(step, StopBufferATR * signal.atr);
   signal.stop = market.direction > 0 ? MathFloor((swing - margin) / step) * step
                                     : MathCeil((swing + margin) / step) * step;
   signal.target = market.direction > 0 ? MathFloor((signal.obstacle - step) / step) * step
                                       : MathCeil((signal.obstacle + step) / step) * step;
   double risk = market.direction * (signal.entry - signal.stop);
   double reward = market.direction * (signal.target - signal.entry);
   if(risk <= 0 || reward / risk < MinimumRewardRisk)
   {
      market.status = "Ratio insuffisant";
      market.processed = current;
      return;
   }
   signal.ratio = reward / risk;
   if(ExportSignals && !SaveSignal(market, signal))
   {
      market.status = "Export a reessayer";
      return;
   }

   market.processed = current;
   market.lastSignal = signal.confirmation;
   market.status = market.direction > 0 ? "ACHAT" : "VENTE";
   if(market.symbol == _Symbol)
   {
      DrawLevel("Entree", signal.entry, clrDodgerBlue);
      DrawLevel("Stop", signal.stop, clrTomato);
      DrawLevel("Objectif", signal.target, clrMediumSeaGreen);
      if(signal.origin > 0)
         DrawLevel("Niveau H1 origine", signal.origin, clrGold);
      else
         ObjectDelete(0, prefix + "Niveau H1 origine");
   }
   if(PopupAlerts)
      Alert(StringFormat("Sera %s %s | %.*f SL %.*f TP %.*f | %.2fR",
                         market.symbol, market.status,
                         (int)SymbolInfoInteger(market.symbol, SYMBOL_DIGITS), signal.entry,
                         (int)SymbolInfoInteger(market.symbol, SYMBOL_DIGITS), signal.stop,
                         (int)SymbolInfoInteger(market.symbol, SYMBOL_DIGITS), signal.target,
                         signal.ratio));
}

int OnInit()
{
   if(ScanSeconds < 1 || RetestBars < 1 || RetestBars > 24 ||
      SpikeAtrMultiple <= 0 || StopBufferATR < 0 || MinimumRewardRisk <= 0)
      return INIT_PARAMETERS_INCORRECT;
   prefix = "SeraBC_" + IntegerToString(ChartID()) + "_";
   DiscoverMarkets();
   return EventSetTimer(ScanSeconds) ? INIT_SUCCEEDED : INIT_FAILED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, prefix);
   Comment("");
}

void OnTimer()
{
   static datetime nextDiscovery = 0;
   datetime now = TimeLocal();
   if(now >= nextDiscovery)
   {
      DiscoverMarkets();
      nextDiscovery = now + 60;
   }
   string panel = "SERA BOOM & CRASH | " + IntegerToString(ArraySize(markets)) +
                  " configurations | H1 / M5\n";
   for(int i = 0; i < ArraySize(markets); i++)
   {
      Scan(markets[i]);
      panel += markets[i].symbol + (markets[i].direction > 0 ? " [BUY]  " : " [SELL]  ") + markets[i].status;
      if(markets[i].lastSignal != 0)
         panel += "  | dernier signal " + TimeToString(markets[i].lastSignal, TIME_DATE | TIME_MINUTES);
      panel += "\n";
   }
   Comment(panel);
   ChartRedraw();
}

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[], const double &high[],
                const double &low[], const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
{
   return rates_total;
}
