//+------------------------------------------------------------------+
//|                                       GoldCandleConfluence.mq5   |
//|  Candlestick patterns at high-value locations, XAUUSD M5 (MT5)   |
//|                                                                  |
//|  A signal needs ALL of:                                          |
//|    1. Context  - healthy volatility, no news shock, no rollover  |
//|    2. Location - pattern forms at / sweeps a real level          |
//|    3. Trigger  - clean reversal candle pattern on a CLOSED bar   |
//|    4. Score    - confluence score >= MinScore                    |
//|  Then a daily / per-session cap and a cooldown keep only a few.  |
//|                                                                  |
//|  Signals are evaluated on closed bars only (no repainting).      |
//+------------------------------------------------------------------+
#property copyright "GoldCandleConfluence"
#property version   "1.00"
#property description "Quality-filtered candlestick reversal signals for XAUUSD M5"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   6

#property indicator_label1  "Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDodgerBlue
#property indicator_width1  2
#property indicator_label2  "Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrOrangeRed
#property indicator_width2  2
#property indicator_label3  "SL"
#property indicator_type3   DRAW_NONE
#property indicator_label4  "TP1"
#property indicator_type4   DRAW_NONE
#property indicator_label5  "TP2"
#property indicator_type5   DRAW_NONE
#property indicator_label6  "Score (+buy/-sell)"
#property indicator_type6   DRAW_NONE

//--- pattern flags
#define PAT_ENGULF 1
#define PAT_PIN    2
#define PAT_STAR   4
#define PAT_KEYREV 8

#define OBJ_PREFIX "GCC_"

//================================ inputs ============================
input group "Signal quality"
input int      MinScore             = 7;     // Min confluence score (raise = fewer, cleaner signals)
input int      MaxSignalsPerDay     = 5;     // Max signals per trading day
input int      MaxSignalsPerSession = 2;     // Max signals per session (spreads signals across sessions)
input int      CooldownBars         = 6;     // Min bars between signals
input bool     AllowCounterTrend    = true;  // Allow counter-bias trades (only on major-level sweeps, +1 score needed)

input group "Context"
input ENUM_TIMEFRAMES BiasTF        = PERIOD_H1; // Higher-timeframe bias timeframe
input int      BiasEMA              = 50;    // HTF bias EMA period
input int      BiasSlopeBars        = 3;     // HTF EMA slope lookback (bars)
input int      LocalEMA             = 50;    // M5 EMA used as dynamic level (with-bias only)
input int      ATRPeriod            = 14;    // ATR period
input int      ATRAvgPeriod         = 100;   // Bars for ATR baseline
input double   MinVolRatio          = 0.6;   // Min ATR/baseline (skip dead markets)
input double   MaxVolRatio          = 2.5;   // Max ATR/baseline (skip chaos)
input double   ShockRangeATR        = 3.5;   // Skip if any of last 4 bars > this x ATR (news spike)
input int      RSIPeriod            = 14;    // RSI period
input double   RSIBuyBelow          = 35;    // RSI exhaustion level for buys
input double   RSISellAbove         = 65;    // RSI exhaustion level for sells

input group "Levels"
input int      SwingStrength        = 3;     // Bars each side for a swing pivot
input int      SwingLookback        = 144;   // Bars to look back for swings (144 = 12h)
input double   RoundStep            = 10.0;  // Round-number step in price ($10 on gold), 0 = off
input double   LevelTolATR          = 0.35;  // Touch tolerance around a level (x ATR)
input double   MaxSweepATR          = 1.5;   // Max wick beyond a level that still counts as a sweep (x ATR)

input group "Time (GMT based)"
input int      ServerGMTOffset      = 2;     // Broker server time minus GMT (hours)
input int      AsiaStartGMT         = 0;     // Asian range start hour (GMT)
input int      AsiaEndGMT           = 7;     // Asian range end hour (GMT)
input bool     SkipRollover         = true;  // Skip daily rollover (wide spreads)
input int      RolloverStartGMT     = 21;    // Rollover skip start hour (GMT)
input int      RolloverEndGMT       = 23;    // Rollover skip end hour (GMT, exclusive)

input group "Risk model"
input double   SLBufferATR          = 0.2;   // SL buffer beyond pattern extreme (x ATR)
input double   MinRiskATR           = 0.8;   // Min SL distance (x ATR)
input double   MaxRiskATR           = 2.5;   // Max SL distance (x ATR) - wider = rejected
input double   TP1_R                = 1.0;   // TP1 in R
input double   TP2_R                = 2.0;   // TP2 in R
input double   RoomR                = 0.7;   // Penalise if a major level sits within this many R toward target
input double   SpreadCost           = 0.30;  // Assumed round-trip cost in price for stats ($)
input int      MaxHoldBars          = 48;    // Stats: close trade after N bars (48 = 4h)

input group "Display / alerts"
input int      MaxBars              = 10000; // Bars of history to evaluate
input int      DrawLastN            = 40;    // Draw SL/TP for the last N signals
input bool     ShowLabels           = true;  // Show score/pattern text
input bool     ShowPanel            = true;  // Show stats panel
input bool     AlertPopup           = true;
input bool     AlertPush            = false;
input bool     AlertEmail           = false;

//================================ buffers ===========================
double BufBuy[], BufSell[], BufSL[], BufTP1[], BufTP2[], BufScore[];

//================================ state =============================
struct Level
{
   double price;
   int    weight;
   bool   major;    // PDH/PDL/Asia
   bool   swing;
   int    dirOnly;  // 0 = any, +1 only buys, -1 only sells
   string name;
};

struct Signal
{
   int      bar;
   datetime time;
   int      dir;
   double   entry, sl, tp1, tp2;
   int      score;
   int      session;
   string   tag;
};

// Price series (index 0 = newest bar)
double   Op[], Hi[], Lo[], Cl[];
datetime Tm[];
int      g_bars = 0;

int      hATR = INVALID_HANDLE, hRSI = INVALID_HANDLE, hEMA = INVALID_HANDLE, hBias = INVALID_HANDLE;
double   g_atr[], g_atrAvg[], g_rsi[], g_ema[], g_biasEma[];
int      g_biasCount = 0;

Level    g_lv[64];
int      g_lvCount = 0;
Signal   g_sig[];
int      g_sigCount = 0;
datetime g_lastBarTime = 0;
datetime g_lastAlert = 0;
int      g_asiaS = 0, g_asiaE = 0;
bool     g_asiaValid = false;
int      g_days = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufBuy,   INDICATOR_DATA);
   SetIndexBuffer(1, BufSell,  INDICATOR_DATA);
   SetIndexBuffer(2, BufSL,    INDICATOR_DATA);
   SetIndexBuffer(3, BufTP1,   INDICATOR_DATA);
   SetIndexBuffer(4, BufTP2,   INDICATOR_DATA);
   SetIndexBuffer(5, BufScore, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   for(int b = 0; b < 6; b++) PlotIndexSetDouble(b, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   hATR  = iATR(_Symbol, _Period, ATRPeriod);
   hRSI  = iRSI(_Symbol, _Period, RSIPeriod, PRICE_CLOSE);
   hEMA  = iMA(_Symbol, _Period, LocalEMA, 0, MODE_EMA, PRICE_CLOSE);
   hBias = iMA(_Symbol, BiasTF, BiasEMA, 0, MODE_EMA, PRICE_CLOSE);
   if(hATR == INVALID_HANDLE || hRSI == INVALID_HANDLE || hEMA == INVALID_HANDLE || hBias == INVALID_HANDLE)
   {
      Print("GoldCandleConfluence: failed to create indicator handles");
      return(INIT_FAILED);
   }

   g_asiaS = (AsiaStartGMT + ServerGMTOffset + 48) % 24;
   g_asiaE = (AsiaEndGMT + ServerGMTOffset + 48) % 24;
   g_asiaValid = (g_asiaS < g_asiaE);   // range must sit inside one server day

   IndicatorSetString(INDICATOR_SHORTNAME, "GoldCandleConfluence");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, OBJ_PREFIX);
   Comment("");
   if(hATR  != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hRSI  != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hEMA  != INVALID_HANDLE) IndicatorRelease(hEMA);
   if(hBias != INVALID_HANDLE) IndicatorRelease(hBias);
}

//============================ candle helpers ========================
double Body(int k)  { return MathAbs(Cl[k] - Op[k]); }
double Rng(int k)   { return Hi[k] - Lo[k]; }
double UpW(int k)   { return Hi[k] - MathMax(Op[k], Cl[k]); }
double LoW(int k)   { return MathMin(Op[k], Cl[k]) - Lo[k]; }

int BitCount(int m) { int c = 0; while(m != 0) { c += (m & 1); m >>= 1; } return c; }

//============================ time helpers ==========================
int GmtHour(datetime t) { return (int)((((long)t - ServerGMTOffset * 3600) % 86400) / 3600); }

// Trading day starts 22:00 GMT (Sydney/Asia open)
int DayKey(datetime t)  { return (int)(((long)t - ServerGMTOffset * 3600 + 2 * 3600) / 86400); }

// 0 Asia 22-07, 1 London 07-12, 2 LDN/NY overlap 12-16, 3 New York 16-22 (GMT)
int Session(datetime t)
{
   int h = GmtHour(t);
   if(h >= 22 || h < 7) return 0;
   if(h < 12) return 1;
   if(h < 16) return 2;
   return 3;
}

string SessionName(int s)
{
   switch(s) { case 0: return "Asia"; case 1: return "London"; case 2: return "Overlap"; }
   return "NewYork";
}

bool InRollover(datetime t)
{
   int h = GmtHour(t);
   if(RolloverStartGMT < RolloverEndGMT) return (h >= RolloverStartGMT && h < RolloverEndGMT);
   return (h >= RolloverStartGMT || h < RolloverEndGMT);
}

//============================ patterns ==============================
// Each detector works on closed bar i (and older bars i+1..).
// atr = ATR of the bar BEFORE the pattern, used as the size yardstick.

bool BullEngulf(int i, double atr, bool &strong)
{
   if(!(Cl[i+1] < Op[i+1] && Body(i+1) >= 0.15 * atr)) return false;
   if(!(Cl[i] > Op[i])) return false;
   double r = Rng(i);
   if(r <= 0) return false;
   if(!(Cl[i] > Op[i+1] && Op[i] <= Cl[i+1] + 0.05 * atr && Body(i) > Body(i+1))) return false;
   if(Body(i) < 0.55 * r || UpW(i) > 0.25 * r) return false;
   if(Cl[i] > Hi[i+1] && Body(i) >= 1.5 * Body(i+1)) strong = true;
   return true;
}

bool BearEngulf(int i, double atr, bool &strong)
{
   if(!(Cl[i+1] > Op[i+1] && Body(i+1) >= 0.15 * atr)) return false;
   if(!(Cl[i] < Op[i])) return false;
   double r = Rng(i);
   if(r <= 0) return false;
   if(!(Cl[i] < Op[i+1] && Op[i] >= Cl[i+1] - 0.05 * atr && Body(i) > Body(i+1))) return false;
   if(Body(i) < 0.55 * r || LoW(i) > 0.25 * r) return false;
   if(Cl[i] < Lo[i+1] && Body(i) >= 1.5 * Body(i+1)) strong = true;
   return true;
}

// Hammer / bullish pin: long lower wick that pokes below the last 3 lows
bool BullPin(int i, double atr, bool &strong)
{
   double r = Rng(i);
   if(r < 0.6 * atr) return false;
   double lw = LoW(i), b = Body(i);
   if(lw < 0.6 * r || lw < 2.0 * b || UpW(i) > 0.25 * r) return false;
   if(Lo[i] >= MathMin(Lo[i+1], MathMin(Lo[i+2], Lo[i+3]))) return false;
   if(lw >= 0.7 * r && Cl[i] >= Op[i]) strong = true;
   return true;
}

// Shooting star / bearish pin
bool BearPin(int i, double atr, bool &strong)
{
   double r = Rng(i);
   if(r < 0.6 * atr) return false;
   double uw = UpW(i), b = Body(i);
   if(uw < 0.6 * r || uw < 2.0 * b || LoW(i) > 0.25 * r) return false;
   if(Hi[i] <= MathMax(Hi[i+1], MathMax(Hi[i+2], Hi[i+3]))) return false;
   if(uw >= 0.7 * r && Cl[i] <= Op[i]) strong = true;
   return true;
}

bool MorningStar(int i, double atr, bool &strong)
{
   if(!(Cl[i+2] < Op[i+2] && Body(i+2) >= 0.5 * atr)) return false;
   if(Body(i+1) > 0.35 * Body(i+2) || Body(i+1) > 0.3 * atr) return false;
   if(Lo[i+1] > Lo[i+2] + 0.15 * atr) return false;
   if(!(Cl[i] > Op[i] && Body(i) >= 0.4 * atr)) return false;
   if(Cl[i] <= (Op[i+2] + Cl[i+2]) / 2.0) return false;
   if(Cl[i] >= Op[i+2]) strong = true;
   return true;
}

bool EveningStar(int i, double atr, bool &strong)
{
   if(!(Cl[i+2] > Op[i+2] && Body(i+2) >= 0.5 * atr)) return false;
   if(Body(i+1) > 0.35 * Body(i+2) || Body(i+1) > 0.3 * atr) return false;
   if(Hi[i+1] < Hi[i+2] - 0.15 * atr) return false;
   if(!(Cl[i] < Op[i] && Body(i) >= 0.4 * atr)) return false;
   if(Cl[i] >= (Op[i+2] + Cl[i+2]) / 2.0) return false;
   if(Cl[i] <= Op[i+2]) strong = true;
   return true;
}

// Key reversal: takes out the last 5 lows then closes above the prior high
bool BullKeyRev(int i, double atr, bool &strong)
{
   double r = Rng(i);
   if(r < 0.7 * atr) return false;
   double ll = Lo[i+1];
   for(int k = 2; k <= 5; k++) ll = MathMin(ll, Lo[i+k]);
   if(Lo[i] >= ll) return false;
   if(!(Cl[i] > Op[i] && Cl[i] > Hi[i+1])) return false;
   if((Cl[i] - Lo[i]) / r < 0.7) return false;
   if(r >= 1.2 * atr) strong = true;
   return true;
}

bool BearKeyRev(int i, double atr, bool &strong)
{
   double r = Rng(i);
   if(r < 0.7 * atr) return false;
   double hh = Hi[i+1];
   for(int k = 2; k <= 5; k++) hh = MathMax(hh, Hi[i+k]);
   if(Hi[i] <= hh) return false;
   if(!(Cl[i] < Op[i] && Cl[i] < Lo[i+1])) return false;
   if((Hi[i] - Cl[i]) / r < 0.7) return false;
   if(r >= 1.2 * atr) strong = true;
   return true;
}

string PatternNames(int mask)
{
   string s = "";
   if((mask & PAT_ENGULF) != 0) s += "Engulf+";
   if((mask & PAT_PIN)    != 0) s += "Pin+";
   if((mask & PAT_STAR)   != 0) s += "Star+";
   if((mask & PAT_KEYREV) != 0) s += "KeyRev+";
   if(StringLen(s) > 0) s = StringSubstr(s, 0, StringLen(s) - 1);
   return s;
}

//============================ context ===============================
// HTF bias from the last CLOSED HTF bar: +1 bull, -1 bear, 0 neutral
int Bias(int i)
{
   static datetime cacheTime = 0;
   static int cacheBias = 0;
   int s = iBarShift(_Symbol, BiasTF, Tm[i], false);
   if(s < 0) return 0;
   datetime ht = iTime(_Symbol, BiasTF, s);
   if(ht == cacheTime) return cacheBias;

   int a = s + 1, b = s + 1 + BiasSlopeBars;
   int bias = 0;
   if(b < g_biasCount - BiasEMA)
   {
      double c  = iClose(_Symbol, BiasTF, a);
      double e1 = g_biasEma[a];
      double e2 = g_biasEma[b];
      if(c > e1 && e1 > e2) bias = 1;
      else if(c < e1 && e1 < e2) bias = -1;
   }
   cacheTime = ht; cacheBias = bias;
   return bias;
}

void AddLevel(double p, int w, bool major, bool swing, int dirOnly, string name)
{
   if(g_lvCount >= 64 || p <= 0) return;
   g_lv[g_lvCount].price   = p;
   g_lv[g_lvCount].weight  = w;
   g_lv[g_lvCount].major   = major;
   g_lv[g_lvCount].swing   = swing;
   g_lv[g_lvCount].dirOnly = dirOnly;
   g_lv[g_lvCount].name    = name;
   g_lvCount++;
}

bool IsPivotHigh(int j)
{
   for(int k = 1; k <= SwingStrength; k++)
      if(Hi[j] <= Hi[j-k] || Hi[j] < Hi[j+k]) return false;
   return true;
}

bool IsPivotLow(int j)
{
   for(int k = 1; k <= SwingStrength; k++)
      if(Lo[j] >= Lo[j-k] || Lo[j] > Lo[j+k]) return false;
   return true;
}

// Levels known BEFORE bar i closed (nothing from bar i or later)
void BuildLevels(int i, int bias)
{
   g_lvCount = 0;

   // Previous day high / low
   int d = iBarShift(_Symbol, PERIOD_D1, Tm[i], false);
   if(d >= 0 && d + 1 < iBars(_Symbol, PERIOD_D1))
   {
      AddLevel(iHigh(_Symbol, PERIOD_D1, d + 1), 2, true, false, 0, "PDH");
      AddLevel(iLow(_Symbol, PERIOD_D1, d + 1),  2, true, false, 0, "PDL");
   }

   // Asian range of the current server day, once it is complete
   if(g_asiaValid)
   {
      datetime day0 = (datetime)((long)Tm[i] - ((long)Tm[i] % 86400));
      datetime aS = day0 + g_asiaS * 3600, aE = day0 + g_asiaE * 3600;
      if(Tm[i] >= aE)
      {
         double hi = -1, lo = DBL_MAX;
         for(int j = i + 1; j < g_bars && Tm[j] >= aS; j++)
            if(Tm[j] < aE) { hi = MathMax(hi, Hi[j]); lo = MathMin(lo, Lo[j]); }
         if(hi > 0)
         {
            AddLevel(hi, 2, true, false, 0, "AsiaH");
            AddLevel(lo, 2, true, false, 0, "AsiaL");
         }
      }
   }

   // Confirmed swing pivots (right side fully before bar i)
   int found = 0;
   for(int j = i + 1 + SwingStrength; j <= i + SwingLookback && j + SwingStrength < g_bars && found < 16; j++)
   {
      if(IsPivotHigh(j)) { AddLevel(Hi[j], 1, false, true, 0, "Swing"); found++; }
      if(IsPivotLow(j))  { AddLevel(Lo[j], 1, false, true, 0, "Swing"); found++; }
   }

   // Round numbers either side of price
   if(RoundStep > 0)
   {
      double base = MathFloor(Cl[i] / RoundStep) * RoundStep;
      AddLevel(base, 1, false, false, 0, "Round");
      AddLevel(base + RoundStep, 1, false, false, 0, "Round");
   }

   // Dynamic EMA only counts for pullbacks in the bias direction
   if(bias != 0)
      AddLevel(g_ema[i + 1], 1, false, false, bias, "EMA");
}

// Score how well the pattern extreme lines up with levels (capped at 3)
int LocationScore(int dir, double ext, double c, double atr, bool &sweep, bool &majorSweep, string &names)
{
   int sc = 0;
   double tol = LevelTolATR * atr, maxSw = MaxSweepATR * atr;
   for(int k = 0; k < g_lvCount; k++)
   {
      if(g_lv[k].dirOnly != 0 && g_lv[k].dirOnly != dir) continue;
      double L = g_lv[k].price;
      bool hit;
      if(dir > 0) hit = (L < c && ext <= L + tol && ext >= L - maxSw);
      else        hit = (L > c && ext >= L - tol && ext <= L + maxSw);
      if(!hit) continue;

      sc += g_lv[k].weight;
      bool swept = (dir > 0) ? (ext < L - 0.05 * atr) : (ext > L + 0.05 * atr);
      if(swept && (g_lv[k].major || g_lv[k].swing))
      {
         sweep = true;
         if(g_lv[k].major) majorSweep = true;
      }
      if(StringFind(names, g_lv[k].name) < 0)
         names += (names == "" ? "" : "+") + g_lv[k].name;
   }
   return MathMin(sc, 3);
}

//============================ evaluation ============================
bool Evaluate(int i, int dir, int bias, int &score, double &sl, double &tp1, double &tp2, string &tag)
{
   double atr = g_atr[i+1];
   bool strong = false;
   int mask = 0;
   double ext = (dir > 0) ? DBL_MAX : -DBL_MAX;

   if(dir > 0)
   {
      if(BullEngulf(i, atr, strong))  { mask |= PAT_ENGULF; ext = MathMin(ext, MathMin(Lo[i], Lo[i+1])); }
      if(BullPin(i, atr, strong))     { mask |= PAT_PIN;    ext = MathMin(ext, Lo[i]); }
      if(MorningStar(i, atr, strong)) { mask |= PAT_STAR;   ext = MathMin(ext, MathMin(Lo[i], MathMin(Lo[i+1], Lo[i+2]))); }
      if(BullKeyRev(i, atr, strong))  { mask |= PAT_KEYREV; ext = MathMin(ext, Lo[i]); }
   }
   else
   {
      if(BearEngulf(i, atr, strong))  { mask |= PAT_ENGULF; ext = MathMax(ext, MathMax(Hi[i], Hi[i+1])); }
      if(BearPin(i, atr, strong))     { mask |= PAT_PIN;    ext = MathMax(ext, Hi[i]); }
      if(EveningStar(i, atr, strong)) { mask |= PAT_STAR;   ext = MathMax(ext, MathMax(Hi[i], MathMax(Hi[i+1], Hi[i+2]))); }
      if(BearKeyRev(i, atr, strong))  { mask |= PAT_KEYREV; ext = MathMax(ext, Hi[i]); }
   }
   if(mask == 0) return false;

   // 1. Pattern quality (2..4)
   int sc = 2 + (strong ? 1 : 0) + (BitCount(mask) >= 2 ? 1 : 0);

   // 2. Location - mandatory
   bool sweep = false, majorSweep = false;
   string names = "";
   int loc = LocationScore(dir, ext, Cl[i], atr, sweep, majorSweep, names);
   if(loc < 1) return false;
   sc += loc + (sweep ? 1 : 0);

   // 3. Higher-timeframe bias
   int need = MinScore;
   bool counter = false;
   if(bias == dir) sc += 2;
   else if(bias == -dir)
   {
      if(!AllowCounterTrend || !majorSweep) return false;
      need = MinScore + 1;
      counter = true;
   }

   // 4. Exhaustion: RSI stretched during the pattern
   if(dir > 0)
   {
      double m = MathMin(MathMin(g_rsi[i], g_rsi[i+1]), MathMin(g_rsi[i+2], g_rsi[i+3]));
      if(m <= RSIBuyBelow) sc++;
   }
   else
   {
      double m = MathMax(MathMax(g_rsi[i], g_rsi[i+1]), MathMax(g_rsi[i+2], g_rsi[i+3]));
      if(m >= RSISellAbove) sc++;
   }

   // 5. Momentum: close beyond the prior bar's extreme
   if(dir > 0 ? Cl[i] > Hi[i+1] : Cl[i] < Lo[i+1]) sc++;

   // Risk geometry
   double entry = Cl[i];
   double s = (dir > 0) ? ext - SLBufferATR * atr : ext + SLBufferATR * atr;
   double risk = dir * (entry - s);
   if(risk < MinRiskATR * atr) { risk = MinRiskATR * atr; s = entry - dir * risk; }
   if(risk > MaxRiskATR * atr) return false;

   // 6. Room: a major level right in front of entry blocks the move
   bool blocked = false;
   for(int k = 0; k < g_lvCount && !blocked; k++)
   {
      if(!g_lv[k].major) continue;
      double d = dir * (g_lv[k].price - entry);
      if(d > 0 && d < RoomR * risk) blocked = true;
   }
   if(blocked) sc--;

   if(sc < need) return false;

   score = sc;
   sl  = s;
   tp1 = entry + dir * TP1_R * risk;
   tp2 = entry + dir * TP2_R * risk;
   tag = PatternNames(mask) + " @ " + names + (sweep ? " sweep" : "") + (counter ? " CT" : "") + (blocked ? " tight" : "");
   return true;
}

//============================ stats =================================
// Outcome in R: 50% off at TP1 + SL to breakeven, rest at TP2.
// Same-bar SL/TP ambiguity resolved as a loss. done=false if still running.
double Simulate(const Signal &sg, bool &tp1hit, bool &done)
{
   tp1hit = false; done = false;
   double risk = sg.dir * (sg.entry - sg.sl);
   if(risk <= 0) return 0;
   int phase = 0;
   int last = MathMax(1, sg.bar - MaxHoldBars);
   double r = 0;

   for(int k = sg.bar - 1; k >= last && !done; k--)
   {
      bool slHit = (sg.dir > 0) ? Lo[k] <= sg.sl    : Hi[k] >= sg.sl;
      bool t1    = (sg.dir > 0) ? Hi[k] >= sg.tp1   : Lo[k] <= sg.tp1;
      bool t2    = (sg.dir > 0) ? Hi[k] >= sg.tp2   : Lo[k] <= sg.tp2;
      bool be    = (sg.dir > 0) ? Lo[k] <= sg.entry : Hi[k] >= sg.entry;
      if(phase == 0)
      {
         if(slHit) { r = -1.0; done = true; }
         else if(t1)
         {
            tp1hit = true;
            if(t2) { r = 0.5 * TP1_R + 0.5 * TP2_R; done = true; }
            else phase = 1;
         }
      }
      else
      {
         if(be)      { r = 0.5 * TP1_R; done = true; }
         else if(t2) { r = 0.5 * TP1_R + 0.5 * TP2_R; done = true; }
      }
   }

   if(!done && sg.bar - MaxHoldBars >= 1)   // time stop
   {
      double mtm = sg.dir * (Cl[last] - sg.entry) / risk;
      r = (phase == 0) ? mtm : 0.5 * TP1_R + 0.5 * mtm;
      done = true;
   }
   if(done) r -= SpreadCost / risk;
   return r;
}

//============================ drawing ===============================
void DrawLine(string name, datetime t1, datetime t2, double p, color c, ENUM_LINE_STYLE style)
{
   ObjectCreate(0, name, OBJ_TREND, 0, t1, p, t2, p);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

void DrawSignal(const Signal &sg, int idx)
{
   string p = OBJ_PREFIX + IntegerToString(idx) + "_";
   datetime t2 = sg.time + 12 * PeriodSeconds();
   DrawLine(p + "E",  sg.time, t2, sg.entry, clrSilver,    STYLE_DOT);
   DrawLine(p + "SL", sg.time, t2, sg.sl,    clrRed,       STYLE_SOLID);
   DrawLine(p + "T1", sg.time, t2, sg.tp1,   clrLimeGreen, STYLE_DASH);
   DrawLine(p + "T2", sg.time, t2, sg.tp2,   clrLimeGreen, STYLE_SOLID);

   if(ShowLabels)
   {
      double atr = g_atr[sg.bar + 1];
      double y = (sg.dir > 0) ? Lo[sg.bar] - 1.2 * atr : Hi[sg.bar] + 1.2 * atr;
      string n = p + "T";
      ObjectCreate(0, n, OBJ_TEXT, 0, sg.time, y);
      ObjectSetString(0, n, OBJPROP_TEXT, IntegerToString(sg.score) + " " + sg.tag);
      ObjectSetInteger(0, n, OBJPROP_COLOR, sg.dir > 0 ? clrDodgerBlue : clrOrangeRed);
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, n, OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   }
}

//============================ data loading ==========================
// Copies prices and indicator values into series arrays (index 0 = newest).
bool LoadData(int rates_total, int n)
{
   ArraySetAsSeries(Op, true); ArraySetAsSeries(Hi, true); ArraySetAsSeries(Lo, true);
   ArraySetAsSeries(Cl, true); ArraySetAsSeries(Tm, true);
   if(CopyOpen(_Symbol, _Period, 0, rates_total, Op)  != rates_total) return false;
   if(CopyHigh(_Symbol, _Period, 0, rates_total, Hi)  != rates_total) return false;
   if(CopyLow(_Symbol, _Period, 0, rates_total, Lo)   != rates_total) return false;
   if(CopyClose(_Symbol, _Period, 0, rates_total, Cl) != rates_total) return false;
   if(CopyTime(_Symbol, _Period, 0, rates_total, Tm)  != rates_total) return false;
   g_bars = rates_total;

   ArraySetAsSeries(g_atr, true); ArraySetAsSeries(g_rsi, true); ArraySetAsSeries(g_ema, true);
   if(BarsCalculated(hATR) < n || BarsCalculated(hRSI) < n || BarsCalculated(hEMA) < n) return false;
   if(CopyBuffer(hATR, 0, 0, n, g_atr) != n) return false;
   if(CopyBuffer(hRSI, 0, 0, n, g_rsi) != n) return false;
   if(CopyBuffer(hEMA, 0, 0, n, g_ema) != n) return false;

   // Baseline ATR: rolling mean of ATRAvgPeriod bars (series indexing)
   ArraySetAsSeries(g_atrAvg, false);
   ArrayResize(g_atrAvg, n);
   double sum = 0;
   for(int k = n - 1; k >= 0; k--)
   {
      sum += g_atr[k];
      if(k + ATRAvgPeriod < n) sum -= g_atr[k + ATRAvgPeriod];
      g_atrAvg[k] = (k + ATRAvgPeriod <= n) ? sum / ATRAvgPeriod : 0;
   }

   // Full higher-timeframe EMA history
   int hb = BarsCalculated(hBias);
   if(hb < BiasEMA + BiasSlopeBars + 10) return false;
   ArraySetAsSeries(g_biasEma, true);
   g_biasCount = CopyBuffer(hBias, 0, 0, hb, g_biasEma);
   if(g_biasCount <= 0) return false;

   return (iBars(_Symbol, PERIOD_D1) >= 3);
}

//============================ main ==================================
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   ArraySetAsSeries(time, true);

   // Only work once per new bar - signals use closed bars only
   if(prev_calculated > 0 && time[0] == g_lastBarTime) return(rates_total);

   int need  = SwingLookback + SwingStrength + ATRAvgPeriod + 20;
   int limit = MathMin(MaxBars, rates_total - need);
   if(limit < 10) return(0);
   int n = MathMin(rates_total, limit + ATRAvgPeriod + 10);

   // Data (incl. H1/D1) may still be loading - retry on the next tick
   if(!LoadData(rates_total, n)) return(0);
   g_lastBarTime = time[0];

   ArraySetAsSeries(BufBuy, true);  ArraySetAsSeries(BufSell, true);
   ArraySetAsSeries(BufSL, true);   ArraySetAsSeries(BufTP1, true);
   ArraySetAsSeries(BufTP2, true);  ArraySetAsSeries(BufScore, true);
   ArrayInitialize(BufBuy, EMPTY_VALUE);  ArrayInitialize(BufSell, EMPTY_VALUE);
   ArrayInitialize(BufSL, EMPTY_VALUE);   ArrayInitialize(BufTP1, EMPTY_VALUE);
   ArrayInitialize(BufTP2, EMPTY_VALUE);  ArrayInitialize(BufScore, EMPTY_VALUE);
   ObjectsDeleteAll(0, OBJ_PREFIX);

   g_sigCount = 0;
   ArrayResize(g_sig, 0, 512);
   g_days = 0;
   int lastSigBar = -1, curDay = -1, dayCnt = 0, sessKey = -1, sessCnt = 0;

   // Chronological pass: oldest -> newest closed bar
   for(int i = limit; i >= 1; i--)
   {
      int dk = DayKey(Tm[i]);
      if(dk != curDay) { curDay = dk; dayCnt = 0; g_days++; }
      int sk = dk * 4 + Session(Tm[i]);
      if(sk != sessKey) { sessKey = sk; sessCnt = 0; }

      if(dayCnt >= MaxSignalsPerDay || sessCnt >= MaxSignalsPerSession) continue;
      if(lastSigBar != -1 && lastSigBar - i < CooldownBars) continue;
      if(SkipRollover && InRollover(Tm[i])) continue;

      // Volatility regime gate
      double atr = g_atr[i+1];
      if(atr <= 0 || g_atrAvg[i+1] <= 0) continue;
      double vr = atr / g_atrAvg[i+1];
      if(vr < MinVolRatio || vr > MaxVolRatio) continue;
      if(Rng(i) < 0.5 * atr) continue;
      bool shock = false;
      for(int k = i; k <= i + 3; k++) if(Rng(k) > ShockRangeATR * atr) shock = true;
      if(shock) continue;

      int bias = Bias(i);
      BuildLevels(i, bias);

      int    bS = 0, sS = 0;
      double bSL = 0, bT1 = 0, bT2 = 0, sSL = 0, sT1 = 0, sT2 = 0;
      string bTag = "", sTag = "";
      bool isBuy  = Evaluate(i,  1, bias, bS, bSL, bT1, bT2, bTag);
      bool isSell = Evaluate(i, -1, bias, sS, sSL, sT1, sT2, sTag);
      if(isBuy && isSell)
      {
         if(bS == sS) continue;          // conflicting evidence - stand aside
         if(bS > sS) isSell = false; else isBuy = false;
      }
      if(!isBuy && !isSell) continue;

      Signal sg;
      sg.bar = i; sg.time = Tm[i]; sg.entry = Cl[i]; sg.session = Session(Tm[i]);
      if(isBuy) { sg.dir = 1;  sg.sl = bSL; sg.tp1 = bT1; sg.tp2 = bT2; sg.score = bS; sg.tag = bTag; }
      else      { sg.dir = -1; sg.sl = sSL; sg.tp1 = sT1; sg.tp2 = sT2; sg.score = sS; sg.tag = sTag; }

      ArrayResize(g_sig, g_sigCount + 1, 512);
      g_sig[g_sigCount++] = sg;
      lastSigBar = i; dayCnt++; sessCnt++;

      if(sg.dir > 0) BufBuy[i]  = Lo[i] - 0.3 * atr;
      else           BufSell[i] = Hi[i] + 0.3 * atr;
      BufSL[i] = sg.sl; BufTP1[i] = sg.tp1; BufTP2[i] = sg.tp2;
      BufScore[i] = sg.dir * sg.score;
   }

   // Stats + drawing
   int closed = 0, wins = 0, tp1Hits = 0;
   double netR = 0;
   int sessN[4] = {0, 0, 0, 0};
   double sessR[4] = {0, 0, 0, 0};
   for(int s = 0; s < g_sigCount; s++)
   {
      bool t1 = false, done = false;
      double r = Simulate(g_sig[s], t1, done);
      if(done)
      {
         closed++; netR += r;
         if(r > 0) wins++;
         if(t1) tp1Hits++;
         sessN[g_sig[s].session]++; sessR[g_sig[s].session] += r;
      }
      if(s >= g_sigCount - DrawLastN) DrawSignal(g_sig[s], s);
   }

   // Alert on a fresh signal on the just-closed bar
   if(g_sigCount > 0)
   {
      Signal last = g_sig[g_sigCount - 1];
      if(last.bar == 1 && last.time != g_lastAlert)
      {
         g_lastAlert = last.time;
         string msg = StringFormat("%s M5 %s @ %s | SL %s | TP1 %s | TP2 %s | score %d | %s",
                                   _Symbol, last.dir > 0 ? "BUY" : "SELL",
                                   DoubleToString(last.entry, _Digits), DoubleToString(last.sl, _Digits),
                                   DoubleToString(last.tp1, _Digits), DoubleToString(last.tp2, _Digits),
                                   last.score, last.tag);
         if(AlertPopup) Alert(msg);
         if(AlertPush)  SendNotification(msg);
         if(AlertEmail) SendMail("GoldCandleConfluence signal", msg);
      }
   }

   if(ShowPanel)
   {
      int today = 0, dkNow = DayKey(Tm[1]);
      for(int s = 0; s < g_sigCount; s++) if(DayKey(g_sig[s].time) == dkNow) today++;
      int b = Bias(1);
      double vrNow = (g_atrAvg[1] > 0) ? g_atr[1] / g_atrAvg[1] : 0;

      string txt = "GoldCandleConfluence" + (_Period != PERIOD_M5 ? "   (designed for M5!)" : "") + "\n";
      txt += StringFormat("Bias %s: %s   |   Vol regime: %.2f %s\n", EnumToString(BiasTF),
                          b > 0 ? "BULL" : (b < 0 ? "BEAR" : "NEUTRAL"), vrNow,
                          (vrNow >= MinVolRatio && vrNow <= MaxVolRatio) ? "(ok)" : "(filtered)");
      txt += StringFormat("Today: %d / %d signals\n", today, MaxSignalsPerDay);
      txt += StringFormat("History: %d signals over %d days = %.1f / day\n", g_sigCount, g_days,
                          g_days > 0 ? (double)g_sigCount / g_days : 0.0);
      if(closed > 0)
         txt += StringFormat("Closed %d | TP1 hit %.0f%% | Win %.0f%% | Net %+.1fR | Avg %+.2fR (after cost)\n",
                             closed, 100.0 * tp1Hits / closed, 100.0 * wins / closed, netR, netR / closed);
      txt += "By session (n / R):";
      for(int s = 0; s < 4; s++) txt += StringFormat("  %s %d/%+.1f", SessionName(s), sessN[s], sessR[s]);
      txt += "\n";
      if(g_sigCount > 0)
      {
         Signal ls = g_sig[g_sigCount - 1];
         txt += StringFormat("Last: %s %s  score %d  [%s]", ls.dir > 0 ? "BUY" : "SELL",
                             TimeToString(ls.time, TIME_DATE | TIME_MINUTES), ls.score, ls.tag);
      }
      Comment(txt);
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
