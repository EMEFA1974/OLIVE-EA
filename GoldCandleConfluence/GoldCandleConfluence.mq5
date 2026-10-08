//+------------------------------------------------------------------+
//|                                       GoldCandleConfluence.mq5   |
//|  Candlestick patterns at high-value locations, XAUUSD M5 (MT5)   |
//|                                                                  |
//|  A signal needs ALL of:                                          |
//|    1. Context  - healthy volatility, no news shock, no rollover  |
//|    2. Location - pattern forms at / sweeps a real level          |
//|    3. Trigger  - clean reversal candle pattern on a CLOSED bar   |
//|    4. Score    - confluence score graded A / B / C               |
//|  Then a daily / per-session cap and a cooldown keep only a few.  |
//|                                                                  |
//|  Re-entry: if a signal is stopped out before TP1 and the setup   |
//|  is still valid (bias intact, healthy context, price reclaims    |
//|  the zone with a reversal candle), one re-entry is signalled.    |
//|                                                                  |
//|  Signals are evaluated on closed bars only (no repainting).      |
//+------------------------------------------------------------------+
#property copyright "GoldCandleConfluence"
#property version   "1.22"
#property description "Quality-filtered candlestick reversal signals for XAUUSD M5"
#property indicator_chart_window
#property indicator_buffers 9
#property indicator_plots   9

#property indicator_label1  "Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrAqua
#property indicator_width1  2
#property indicator_label2  "Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrMagenta
#property indicator_width2  2
#property indicator_label3  "Re-entry Buy"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrOrange
#property indicator_width3  2
#property indicator_label4  "Re-entry Sell"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrYellow
#property indicator_width4  2
#property indicator_label5  "SL"
#property indicator_type5   DRAW_NONE
#property indicator_label6  "TP1"
#property indicator_type6   DRAW_NONE
#property indicator_label7  "TP2"
#property indicator_type7   DRAW_NONE
#property indicator_label8  "Score (+buy/-sell)"
#property indicator_type8   DRAW_NONE
#property indicator_label9  "Grade (1=A 2=B 3=C)"
#property indicator_type9   DRAW_NONE

//--- pattern flags
#define PAT_ENGULF 1
#define PAT_PIN    2
#define PAT_STAR   4
#define PAT_KEYREV 8

//--- hollow Wingdings arrows
#define ARROW_UP_HOLLOW   241
#define ARROW_DOWN_HOLLOW 242

#define OBJ_PREFIX "GCC_"

//================================ inputs ============================
input group "Signal grades"
input bool     ShowGradeA           = true;  // Show grade A signals (best)
input bool     ShowGradeB           = true;  // Show grade B signals (good)
input bool     ShowGradeC           = false; // Show grade C signals (acceptable, more frequent)
input int      GradeA_MinScore      = 9;     // Min score for grade A
input int      GradeB_MinScore      = 7;     // Min score for grade B
input int      GradeC_MinScore      = 5;     // Min score for grade C
input color    GradeTextColor       = C'105,105,105'; // Grade letter colour (faint grey)
input int      GradeFontSize        = 9;     // Grade letter size
input double   GradeOffsetATR       = 0.9;   // Grade letter distance from candle (x ATR)

input group "Signal quality"
input int      MaxSignalsPerDay     = 0;     // Max signals per trading day, 0 = no limit (re-entries not counted)
input int      MaxSignalsPerSession = 3;     // Max signals per session, 0 = no limit
input int      CooldownBars         = 6;     // Min bars between signals
input bool     AllowCounterTrend    = true;  // Allow counter-bias trades (only on major-level sweeps, graded 1 point lower)

input group "Re-entry"
input bool     EnableReentry        = true;  // Signal a re-entry after SL if the setup is still valid
input int      ReentryWindowBars    = 12;    // Bars after SL hit to wait for re-entry (12 = 1h)
input double   MaxReentrySweepATR   = 1.5;   // Cancel if price runs this far beyond the old SL (x ATR)

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
input int      MaxHoldBars          = 48;    // Close trade after N bars (48 = 4h)

input group "Arrows"
input color    BuyColor             = clrAqua;     // Buy arrow
input color    SellColor            = clrMagenta;  // Sell arrow
input color    ReBuyColor           = clrOrange;   // Re-entry buy arrow
input color    ReSellColor          = clrYellow;   // Re-entry sell arrow
input int      ArrowSize            = 2;           // Arrow size (1-5)

input group "Trade zones"
input bool     ShowZones            = true;            // Draw SL / TP zone boxes
input bool     ZoneFill             = true;            // Filled boxes (false = outline)
input color    ZoneSLColor          = C'110,35,35';    // Risk zone (Entry -> SL)
input color    ZoneTP1Color         = C'25,95,55';     // Reward zone (Entry -> TP1)
input color    ZoneTP2Color         = C'25,75,105';    // Extension zone (TP1 -> TP2)
input color    EntryLineColor       = clrSilver;       // Entry line / label
input color    SLLineColor          = clrRed;          // SL line / label
input color    TPLineColor          = clrLime;         // TP lines / labels
input int      ZoneMinBars          = 12;              // Min box width in bars
input bool     ShowLevelPrices      = true;            // Print Entry/SL/TP prices at box edge

input group "Display / alerts"
input int      MaxBars              = 10000; // Bars of history to evaluate
input int      DrawLastN            = 40;    // Draw zones for the last N signals
input bool     ShowLabels           = false; // Show score/pattern text (beyond the grade letter)
input bool     ShowPanel            = true;  // Show stats panel
input bool     AlertPopup           = true;
input bool     AlertPush            = false;
input bool     AlertEmail           = false;

//================================ buffers ===========================
double BufBuy[], BufSell[], BufReBuy[], BufReSell[], BufSL[], BufTP1[], BufTP2[], BufScore[], BufGrade[];

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
   double   ext;       // pattern extreme the SL was built from
   int      score;
   int      grade;     // 1 = A, 2 = B, 3 = C
   int      session;
   bool     counter;   // against HTF bias
   bool     reentry;
   string   tag;
};

// Tracks a primary signal so a re-entry can follow its stop-out
struct Watch
{
   int    dir;
   double entry, sl, tp1, ext;
   int    score;
   int    grade;
   bool   counter;
   int    startBar;
   int    state;      // 0 live, 1 stopped out (waiting for re-entry), 2 finished
   int    armedBar;
   double sweepExt;   // furthest price beyond the old SL since the stop-out
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
Watch    g_watch[];
int      g_watchCount = 0;
datetime g_lastBarTime = 0;
datetime g_lastAlert = 0;
int      g_asiaS = 0, g_asiaE = 0;
bool     g_asiaValid = false;
int      g_days = 0;

//+------------------------------------------------------------------+
void SetupArrowPlot(int plot, int code, color c)
{
   PlotIndexSetInteger(plot, PLOT_ARROW, code);
   PlotIndexSetInteger(plot, PLOT_LINE_COLOR, c);
   PlotIndexSetInteger(plot, PLOT_LINE_WIDTH, ArrowSize);
}

int OnInit()
{
   SetIndexBuffer(0, BufBuy,    INDICATOR_DATA);
   SetIndexBuffer(1, BufSell,   INDICATOR_DATA);
   SetIndexBuffer(2, BufReBuy,  INDICATOR_DATA);
   SetIndexBuffer(3, BufReSell, INDICATOR_DATA);
   SetIndexBuffer(4, BufSL,     INDICATOR_DATA);
   SetIndexBuffer(5, BufTP1,    INDICATOR_DATA);
   SetIndexBuffer(6, BufTP2,    INDICATOR_DATA);
   SetIndexBuffer(7, BufScore,  INDICATOR_DATA);
   SetIndexBuffer(8, BufGrade,  INDICATOR_DATA);
   SetupArrowPlot(0, ARROW_UP_HOLLOW,   BuyColor);
   SetupArrowPlot(1, ARROW_DOWN_HOLLOW, SellColor);
   SetupArrowPlot(2, ARROW_UP_HOLLOW,   ReBuyColor);
   SetupArrowPlot(3, ARROW_DOWN_HOLLOW, ReSellColor);
   for(int b = 0; b < 9; b++) PlotIndexSetDouble(b, PLOT_EMPTY_VALUE, EMPTY_VALUE);

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

// All patterns on bar i for a direction; returns flag mask and the pattern extreme
int DetectPatterns(int i, int dir, double atr, bool &strong, double &ext)
{
   int mask = 0;
   ext = (dir > 0) ? DBL_MAX : -DBL_MAX;
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
   return mask;
}

// Strong directional candle that closes beyond the prior bar (used to confirm a reclaim)
bool ReclaimBar(int k, int dir)
{
   double r = Rng(k);
   if(r <= 0 || Body(k) < 0.55 * r) return false;
   if(dir > 0) return (Cl[k] > Op[k] && Cl[k] > Hi[k+1]);
   return (Cl[k] < Op[k] && Cl[k] < Lo[k+1]);
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

//============================ grades ================================
// 1 = A, 2 = B, 3 = C, 0 = below every grade
int GradeOf(int score)
{
   if(score >= GradeA_MinScore) return 1;
   if(score >= GradeB_MinScore) return 2;
   if(score >= GradeC_MinScore) return 3;
   return 0;
}

bool GradeEnabled(int g)
{
   if(g == 1) return ShowGradeA;
   if(g == 2) return ShowGradeB;
   if(g == 3) return ShowGradeC;
   return false;
}

string GradeLetter(int g)
{
   if(g == 1) return "A";
   if(g == 2) return "B";
   if(g == 3) return "C";
   return "?";
}

//============================ evaluation ============================
// Primary signal: pattern + location + confluence score
bool Evaluate(int i, int dir, int bias, Signal &out)
{
   double atr = g_atr[i+1];
   bool strong = false;
   double ext;
   int mask = DetectPatterns(i, dir, atr, strong, ext);
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
   bool counter = false;
   if(bias == dir) sc += 2;
   else if(bias == -dir)
   {
      if(!AllowCounterTrend || !majorSweep) return false;
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

   // Grade: counter-trend setups are graded one point lower
   int grade = GradeOf(sc - (counter ? 1 : 0));
   if(!GradeEnabled(grade)) return false;

   out.bar     = i;
   out.time    = Tm[i];
   out.dir     = dir;
   out.entry   = entry;
   out.sl      = s;
   out.tp1     = entry + dir * TP1_R * risk;
   out.tp2     = entry + dir * TP2_R * risk;
   out.ext     = ext;
   out.score   = sc;
   out.grade   = grade;
   out.session = Session(Tm[i]);
   out.counter = counter;
   out.reentry = false;
   out.tag     = PatternNames(mask) + " @ " + names + (sweep ? " sweep" : "") + (counter ? " CT" : "") + (blocked ? " tight" : "");
   return true;
}

//============================ signals ===============================
void AddSignal(const Signal &sg)
{
   ArrayResize(g_sig, g_sigCount + 1, 512);
   g_sig[g_sigCount++] = sg;

   int i = sg.bar;
   double off = 0.3 * g_atr[i+1];
   if(sg.dir > 0)
   {
      if(sg.reentry) BufReBuy[i] = Lo[i] - off; else BufBuy[i] = Lo[i] - off;
   }
   else
   {
      if(sg.reentry) BufReSell[i] = Hi[i] + off; else BufSell[i] = Hi[i] + off;
   }
   BufSL[i] = sg.sl; BufTP1[i] = sg.tp1; BufTP2[i] = sg.tp2;
   BufScore[i] = sg.dir * sg.score;
   BufGrade[i] = sg.grade;
}

void AddWatch(const Signal &sg)
{
   ArrayResize(g_watch, g_watchCount + 1, 256);
   g_watch[g_watchCount].dir      = sg.dir;
   g_watch[g_watchCount].entry    = sg.entry;
   g_watch[g_watchCount].sl       = sg.sl;
   g_watch[g_watchCount].tp1      = sg.tp1;
   g_watch[g_watchCount].ext      = sg.ext;
   g_watch[g_watchCount].score    = sg.score;
   g_watch[g_watchCount].grade    = sg.grade;
   g_watch[g_watchCount].counter  = sg.counter;
   g_watch[g_watchCount].startBar = sg.bar;
   g_watch[g_watchCount].state    = 0;
   g_watch[g_watchCount].armedBar = -1;
   g_watch[g_watchCount].sweepExt = 0;
   g_watchCount++;
}

// Advance every tracked trade by closed bar k. Returns true if a re-entry fired on k.
//  - Stop hit before TP1 -> arm a re-entry window
//  - Re-entry fires when, inside the window, a closed bar:
//      * closes back beyond the ORIGINAL pattern extreme (zone reclaimed)
//      * is a reversal pattern or a strong reclaim candle
//      * the HTF bias has not turned against the trade (unless it was a CT trade)
//      * context is healthy (volatility, no shock, no rollover)
//      * the new stop fits the risk limits
//  - Cancelled if price runs too far beyond the old stop, TP1 is hit first, or the window expires
bool ProcessWatches(int k, bool ctxOK)
{
   bool fired = false;
   double atr = g_atr[k+1];

   for(int w = 0; w < g_watchCount; w++)
   {
      if(g_watch[w].state == 2 || g_watch[w].startBar <= k) continue;
      int dir = g_watch[w].dir;

      if(g_watch[w].state == 0)
      {
         if(g_watch[w].startBar - k > MaxHoldBars) { g_watch[w].state = 2; continue; }
         bool slHit = (dir > 0) ? Lo[k] <= g_watch[w].sl  : Hi[k] >= g_watch[w].sl;
         bool t1Hit = (dir > 0) ? Hi[k] >= g_watch[w].tp1 : Lo[k] <= g_watch[w].tp1;
         if(!slHit)
         {
            if(t1Hit) g_watch[w].state = 2;   // worked - no re-entry needed
            continue;
         }
         g_watch[w].state    = 1;
         g_watch[w].armedBar = k;
         g_watch[w].sweepExt = (dir > 0) ? Lo[k] : Hi[k];
      }
      else
      {
         g_watch[w].sweepExt = (dir > 0) ? MathMin(g_watch[w].sweepExt, Lo[k]) : MathMax(g_watch[w].sweepExt, Hi[k]);
      }

      // Armed: check expiry and invalidation
      if(g_watch[w].armedBar - k > ReentryWindowBars) { g_watch[w].state = 2; continue; }
      if(atr <= 0) continue;
      if(dir * (g_watch[w].sl - g_watch[w].sweepExt) > MaxReentrySweepATR * atr) { g_watch[w].state = 2; continue; }

      if(fired || !ctxOK) continue;
      if(!g_watch[w].counter && Bias(k) == -dir) continue;

      // Zone reclaimed: close back beyond the original pattern extreme
      if(dir * (Cl[k] - g_watch[w].ext) <= 0) continue;

      bool strong = false;
      double pext;
      int mask = DetectPatterns(k, dir, atr, strong, pext);
      if(mask == 0 && !ReclaimBar(k, dir)) continue;

      // New stop beyond the sweep low/high
      double entry = Cl[k];
      double ext   = g_watch[w].sweepExt;
      double s     = ext - dir * SLBufferATR * atr;
      double risk  = dir * (entry - s);
      if(risk < MinRiskATR * atr) { risk = MinRiskATR * atr; s = entry - dir * risk; }
      if(risk > MaxRiskATR * atr) continue;

      Signal sg;
      sg.bar     = k;
      sg.time    = Tm[k];
      sg.dir     = dir;
      sg.entry   = entry;
      sg.sl      = s;
      sg.tp1     = entry + dir * TP1_R * risk;
      sg.tp2     = entry + dir * TP2_R * risk;
      sg.ext     = ext;
      sg.score   = g_watch[w].score;
      sg.grade   = g_watch[w].grade;
      sg.session = Session(Tm[k]);
      sg.counter = g_watch[w].counter;
      sg.reentry = true;
      sg.tag     = "RE " + (mask != 0 ? PatternNames(mask) : "Reclaim") + " after SL";
      AddSignal(sg);

      g_watch[w].state = 2;   // one re-entry per original signal
      fired = true;
   }
   return fired;
}

//============================ stats =================================
// Outcome in R: 50% off at TP1 + SL to breakeven, rest at TP2.
// Same-bar SL/TP ambiguity resolved as a loss. done=false if still running.
double Simulate(const Signal &sg, bool &tp1hit, bool &done, int &exitBar)
{
   tp1hit = false; done = false; exitBar = 0;
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
      if(done) exitBar = k;
   }

   if(!done && sg.bar - MaxHoldBars >= 1)   // time stop
   {
      double mtm = sg.dir * (Cl[last] - sg.entry) / risk;
      r = (phase == 0) ? mtm : 0.5 * TP1_R + 0.5 * mtm;
      done = true;
      exitBar = last;
   }
   if(done) r -= SpreadCost / risk;
   return r;
}

//============================ drawing ===============================
void DrawRect(string name, datetime t1, double p1, datetime t2, double p2, color c)
{
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_FILL, ZoneFill);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawLine(string name, datetime t1, datetime t2, double p, color c, ENUM_LINE_STYLE style)
{
   ObjectCreate(0, name, OBJ_TREND, 0, t1, p, t2, p);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawText(string name, datetime t, double p, string text, color c, ENUM_ANCHOR_POINT anchor)
{
   ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 7);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

// Zone boxes run from the signal bar to the trade's exit (or to now if still live)
void DrawSignal(const Signal &sg, int idx, bool done, int exitBar)
{
   string p = OBJ_PREFIX + IntegerToString(idx) + "_";
   int ps = PeriodSeconds();
   datetime t1 = sg.time;
   datetime t2 = done ? Tm[exitBar] : Tm[0] + 3 * ps;
   if(t2 < t1 + ZoneMinBars * ps) t2 = t1 + ZoneMinBars * ps;

   if(ShowZones)
   {
      DrawRect(p + "ZSL", t1, sg.entry, t2, sg.sl,  ZoneSLColor);
      DrawRect(p + "ZT1", t1, sg.entry, t2, sg.tp1, ZoneTP1Color);
      DrawRect(p + "ZT2", t1, sg.tp1,   t2, sg.tp2, ZoneTP2Color);

      DrawLine(p + "LE",  t1, t2, sg.entry, EntryLineColor, STYLE_DOT);
      DrawLine(p + "LSL", t1, t2, sg.sl,    SLLineColor,    STYLE_SOLID);
      DrawLine(p + "LT1", t1, t2, sg.tp1,   TPLineColor,    STYLE_DASH);
      DrawLine(p + "LT2", t1, t2, sg.tp2,   TPLineColor,    STYLE_SOLID);

      if(ShowLevelPrices)
      {
         DrawText(p + "PE",  t2, sg.entry, " Entry " + DoubleToString(sg.entry, _Digits), EntryLineColor, ANCHOR_LEFT);
         DrawText(p + "PSL", t2, sg.sl,    " SL "    + DoubleToString(sg.sl,    _Digits), SLLineColor,    ANCHOR_LEFT);
         DrawText(p + "PT1", t2, sg.tp1,   " TP1 "   + DoubleToString(sg.tp1,   _Digits), TPLineColor,    ANCHOR_LEFT);
         DrawText(p + "PT2", t2, sg.tp2,   " TP2 "   + DoubleToString(sg.tp2,   _Digits), TPLineColor,    ANCHOR_LEFT);
      }
   }

   if(ShowLabels)
   {
      double atr = g_atr[sg.bar + 1];
      double y = (sg.dir > 0) ? Lo[sg.bar] - 1.9 * atr : Hi[sg.bar] + 1.9 * atr;
      color c = sg.dir > 0 ? (sg.reentry ? ReBuyColor : BuyColor) : (sg.reentry ? ReSellColor : SellColor);
      DrawText(p + "T", sg.time, y, IntegerToString(sg.score) + " " + sg.tag, c, sg.dir > 0 ? ANCHOR_UPPER : ANCHOR_LOWER);
   }
}

// Faint grade letter: under the arrow for buys, above the arrow for sells
void DrawGrade(const Signal &sg, int idx)
{
   string n = OBJ_PREFIX + "G" + IntegerToString(idx);
   double atr = g_atr[sg.bar + 1];
   double y = (sg.dir > 0) ? Lo[sg.bar] - GradeOffsetATR * atr : Hi[sg.bar] + GradeOffsetATR * atr;
   ObjectCreate(0, n, OBJ_TEXT, 0, sg.time, y);
   ObjectSetString(0, n, OBJPROP_TEXT, GradeLetter(sg.grade));
   ObjectSetString(0, n, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, n, OBJPROP_COLOR, GradeTextColor);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, GradeFontSize);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, sg.dir > 0 ? ANCHOR_UPPER : ANCHOR_LOWER);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
}

string SignalName(const Signal &sg)
{
   return (sg.reentry ? "RE-ENTRY " : "") + (sg.dir > 0 ? "BUY" : "SELL") + " [" + GradeLetter(sg.grade) + "]";
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

   // Baseline ATR: rolling mean of ATRAvgPeriod bars (index = bar shift)
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

   ArraySetAsSeries(BufBuy, true);   ArraySetAsSeries(BufSell, true);
   ArraySetAsSeries(BufReBuy, true); ArraySetAsSeries(BufReSell, true);
   ArraySetAsSeries(BufSL, true);    ArraySetAsSeries(BufTP1, true);
   ArraySetAsSeries(BufTP2, true);   ArraySetAsSeries(BufScore, true);
   ArraySetAsSeries(BufGrade, true);
   ArrayInitialize(BufBuy, EMPTY_VALUE);   ArrayInitialize(BufSell, EMPTY_VALUE);
   ArrayInitialize(BufReBuy, EMPTY_VALUE); ArrayInitialize(BufReSell, EMPTY_VALUE);
   ArrayInitialize(BufSL, EMPTY_VALUE);    ArrayInitialize(BufTP1, EMPTY_VALUE);
   ArrayInitialize(BufTP2, EMPTY_VALUE);   ArrayInitialize(BufScore, EMPTY_VALUE);
   ArrayInitialize(BufGrade, EMPTY_VALUE);
   ObjectsDeleteAll(0, OBJ_PREFIX);

   g_sigCount = 0;   ArrayResize(g_sig, 0, 512);
   g_watchCount = 0; ArrayResize(g_watch, 0, 256);
   g_days = 0;
   int lastSigBar = -1, curDay = -1, dayCnt = 0, sessKey = -1, sessCnt = 0;

   // Chronological pass: oldest -> newest closed bar
   for(int i = limit; i >= 1; i--)
   {
      int dk = DayKey(Tm[i]);
      if(dk != curDay) { curDay = dk; dayCnt = 0; g_days++; }
      int sk = dk * 4 + Session(Tm[i]);
      if(sk != sessKey) { sessKey = sk; sessCnt = 0; }

      // Context gate (shared by primary signals and re-entries)
      double atr = g_atr[i+1];
      bool ctxOK = (atr > 0 && g_atrAvg[i+1] > 0);
      if(ctxOK)
      {
         double vr = atr / g_atrAvg[i+1];
         if(vr < MinVolRatio || vr > MaxVolRatio) ctxOK = false;
      }
      if(ctxOK)
         for(int k = i; k <= i + 3; k++) if(Rng(k) > ShockRangeATR * atr) ctxOK = false;
      if(SkipRollover && InRollover(Tm[i])) ctxOK = false;

      // Track open trades; a re-entry takes this bar
      if(EnableReentry && ProcessWatches(i, ctxOK)) { lastSigBar = i; continue; }

      if(!ctxOK) continue;
      if(MaxSignalsPerDay > 0 && dayCnt >= MaxSignalsPerDay) continue;
      if(MaxSignalsPerSession > 0 && sessCnt >= MaxSignalsPerSession) continue;
      if(lastSigBar != -1 && lastSigBar - i < CooldownBars) continue;
      if(Rng(i) < 0.5 * atr) continue;

      int bias = Bias(i);
      BuildLevels(i, bias);

      Signal buy, sell;
      bool isBuy  = Evaluate(i,  1, bias, buy);
      bool isSell = Evaluate(i, -1, bias, sell);
      if(isBuy && isSell)
      {
         if(buy.score == sell.score) continue;   // conflicting evidence - stand aside
         if(buy.score > sell.score) isSell = false; else isBuy = false;
      }
      if(!isBuy && !isSell) continue;

      if(isBuy) { AddSignal(buy);  AddWatch(buy); }
      else      { AddSignal(sell); AddWatch(sell); }
      lastSigBar = i; dayCnt++; sessCnt++;
   }

   // Stats + drawing. Index 0 = primary signals, 1 = re-entries
   int closed[2]  = {0, 0};
   int wins[2]    = {0, 0};
   int tp1Hits[2] = {0, 0};
   int count[2]   = {0, 0};
   double netR[2] = {0, 0};
   int sessN[4] = {0, 0, 0, 0};
   double sessR[4] = {0, 0, 0, 0};
   int gN[4]      = {0, 0, 0, 0};   // index 1..3 = A..C
   int gClosed[4] = {0, 0, 0, 0};
   int gWins[4]   = {0, 0, 0, 0};
   double gR[4]   = {0, 0, 0, 0};
   for(int s = 0; s < g_sigCount; s++)
   {
      bool t1 = false, done = false;
      int exitBar = 0;
      double r = Simulate(g_sig[s], t1, done, exitBar);
      int t = g_sig[s].reentry ? 1 : 0;
      count[t]++;
      if(done)
      {
         closed[t]++; netR[t] += r;
         if(r > 0) wins[t]++;
         if(t1) tp1Hits[t]++;
         sessN[g_sig[s].session]++; sessR[g_sig[s].session] += r;
         gClosed[g_sig[s].grade]++; gR[g_sig[s].grade] += r;
         if(r > 0) gWins[g_sig[s].grade]++;
      }
      gN[g_sig[s].grade]++;
      DrawGrade(g_sig[s], s);
      if(s >= g_sigCount - DrawLastN) DrawSignal(g_sig[s], s, done, exitBar);
   }

   // Alert on a fresh signal on the just-closed bar
   if(g_sigCount > 0)
   {
      Signal last = g_sig[g_sigCount - 1];
      if(last.bar == 1 && last.time != g_lastAlert)
      {
         g_lastAlert = last.time;
         string msg = StringFormat("%s M5 %s @ %s | SL %s | TP1 %s | TP2 %s | score %d | %s",
                                   _Symbol, SignalName(last),
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
      int today = 0, todayRe = 0, dkNow = DayKey(Tm[1]);
      for(int s = 0; s < g_sigCount; s++)
         if(DayKey(g_sig[s].time) == dkNow) { if(g_sig[s].reentry) todayRe++; else today++; }
      int b = Bias(1);
      double vrNow = (g_atrAvg[1] > 0) ? g_atr[1] / g_atrAvg[1] : 0;

      string txt = "GoldCandleConfluence" + (_Period != PERIOD_M5 ? "   (designed for M5!)" : "") + "\n";
      txt += StringFormat("Bias %s: %s   |   Vol regime: %.2f %s\n", EnumToString(BiasTF),
                          b > 0 ? "BULL" : (b < 0 ? "BEAR" : "NEUTRAL"), vrNow,
                          (vrNow >= MinVolRatio && vrNow <= MaxVolRatio) ? "(ok)" : "(filtered)");
      txt += StringFormat("Today: %d%s signals  +%d re-entries\n", today,
                          MaxSignalsPerDay > 0 ? StringFormat(" / %d", MaxSignalsPerDay) : " (no daily limit)", todayRe);
      txt += StringFormat("History: %d signals + %d re-entries over %d days = %.1f signals / day\n",
                          count[0], count[1], g_days, g_days > 0 ? (double)count[0] / g_days : 0.0);
      string kind[2] = {"Signals  ", "Re-entry "};
      for(int t = 0; t < 2; t++)
         if(closed[t] > 0)
            txt += StringFormat("%s closed %d | TP1 hit %.0f%% | Win %.0f%% | Net %+.1fR | Avg %+.2fR\n",
                                kind[t], closed[t], 100.0 * tp1Hits[t] / closed[t], 100.0 * wins[t] / closed[t],
                                netR[t], netR[t] / closed[t]);
      txt += "By grade (n / win% / avg R):";
      for(int g = 1; g <= 3; g++)
      {
         if(!GradeEnabled(g)) { txt += StringFormat("  %s off", GradeLetter(g)); continue; }
         txt += StringFormat("  %s %d / %.0f%% / %+.2f", GradeLetter(g), gN[g],
                             gClosed[g] > 0 ? 100.0 * gWins[g] / gClosed[g] : 0.0,
                             gClosed[g] > 0 ? gR[g] / gClosed[g] : 0.0);
      }
      txt += "\n";
      txt += "By session (n / R):";
      for(int s = 0; s < 4; s++) txt += StringFormat("  %s %d/%+.1f", SessionName(s), sessN[s], sessR[s]);
      txt += "\n";
      if(g_sigCount > 0)
      {
         Signal ls = g_sig[g_sigCount - 1];
         txt += StringFormat("Last: %s %s  score %d  [%s]", SignalName(ls),
                             TimeToString(ls.time, TIME_DATE | TIME_MINUTES), ls.score, ls.tag);
      }
      Comment(txt);
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
