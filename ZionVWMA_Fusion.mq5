//+------------------------------------------------------------------+
//|                                             ZionVWMA_Fusion.mq5  |
//|                                                                  |
//| Unified XAUUSD M5 signal indicator built from the strongest      |
//| parts of "Mt.ZionPro Ind" and "VWMA RSI Score".                  |
//|                                                                  |
//| A signal needs, on a CLOSED bar (no repaint):                    |
//|  HARD GATES (all must pass)                                      |
//|   1. Trigger candle (Mt.ZionPro): body / close position and a    |
//|      displacement over the last bars or a rejection wick         |
//|   2. Momentum score >= MinScore (VWMA RSI Score, made symmetric):|
//|      - fast RSI beyond RsiMid (bull > Mid, bear < 100-Mid)       |
//|      - slow RSI beyond RsiMid                                    |
//|      - close beyond the slow VWMA                                |
//|      - fast VWMA beyond the mid VWMA                             |
//|      - slow VWMA sloping in the trade direction                  |
//|   3. Max spread (session window optional, off = all sessions)    |
//|   4. No running idea, cooldown since the last signal             |
//|  QUALITY FILTERS (each failure lowers the grade A -> B -> C)     |
//|   - H1 + H4 EMA 50/200 trend agrees with the trade               |
//|   - D1 close not against the trade (D1 EMA 50)                   |
//|   - signal candle range between min and max x ATR                |
//|   - close not stretched from value (mid VWMA) by > k x ATR       |
//|   - room: no PDH/PDL/PWH/PWL between entry and TP1               |
//|   - no RSI exhaustion (fast RSI beyond OB / OS)                  |
//|   - strict trigger: close through a real swing, or a pin bar     |
//|     that sweeps the last bars                                    |
//| C signals must also pass the "C rules" (defaults): at most 3     |
//| fails (3 only with momentum 5/5), momentum >= 4, not counter-    |
//| trend, room to TP1, no RSI exhaustion, strict candle unless      |
//| momentum is 5/5. Failing C =                                     |
//| grey "C-" (no trade). Each rule can be toggled in the inputs.    |
//| Panel: click its title to hide it, double-click chart to restore.|
//| Arrows: buys Aqua, sells Magenta (all grades).                   |
//| Each signal is tracked (pending -> fill -> TP1 / TP2 / SL) so the|
//| panel shows a running win rate for the loaded history.           |
//+------------------------------------------------------------------+
#property copyright "Mt.ZionPro x VWMA RSI Score"
#property version   "1.00"
#property description "XAUUSD M5: HTF trend + VWMA/RSI momentum score + price-action trigger."
#property description "Graded A/B/C signals on closed bars with entry, SL, TP1, TP2 and live stats."
#property indicator_chart_window
#property indicator_buffers 11
#property indicator_plots   5

#property indicator_label1  "VWMA slow"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrRed
#property indicator_width1  2

#property indicator_label2  "VWMA mid"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange
#property indicator_width2  2

#property indicator_label3  "VWMA fast"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrYellow
#property indicator_width3  1

#property indicator_label4  "Buy"
#property indicator_type4   DRAW_COLOR_ARROW
#property indicator_color4  clrAqua,clrAqua,clrAqua
#property indicator_width4  2

#property indicator_label5  "Sell"
#property indicator_type5   DRAW_COLOR_ARROW
#property indicator_color5  clrMagenta,clrMagenta,clrMagenta
#property indicator_width5  2

enum ENUM_PEND_TYPE
  {
   PEND_LIMIT = 0,   // pullback (buy below / sell above)
   PEND_STOP  = 1    // confirmation break (buy above / sell below)
  };

#define GRADE_A    0
#define GRADE_B    1
#define GRADE_C    2
#define GRADE_NONE 3
#define GRADE_CX   4   // C that failed the C rules: never traded, shown grey as "C-"

// quality filter failure flags
#define F_TREND   1
#define F_COUNTER 2    // H1/H4 trend actively against the trade (also sets F_TREND)
#define F_D1      4
#define F_RANGE   8
#define F_EXT     16
#define F_ROOM    32
#define F_EXH     64
#define F_CANDLE  128

input group "=== Momentum score (VWMA RSI Score) ==="
input int                InpVwmaSlow    = 85;            // VWMA slow (red): close must be beyond it
input int                InpVwmaMid     = 37;            // VWMA mid (orange): also the "value" line
input int                InpVwmaFast    = 18;            // VWMA fast (yellow): must be beyond mid
input ENUM_APPLIED_PRICE InpVwmaPrice   = PRICE_TYPICAL; // VWMA price (typical keeps buys and sells symmetric)
input int                InpSlopeBars   = 5;             // slow VWMA slope look-back (bars)
input int                InpRsiFast     = 7;             // fast RSI period
input int                InpRsiSlow     = 14;            // slow RSI period
input double             InpRsiMid      = 55.0;          // bull RSI above this, bear RSI below 100 - this
input int                InpMinScore    = 4;             // momentum votes needed (1-5)

input group "=== Higher-timeframe trend (Mt.ZionPro) ==="
input bool            InpTrendOn    = true;        // H1 and H4 must both trend with the trade (graded)
input ENUM_TIMEFRAMES InpTrendTF1   = PERIOD_H1;
input ENUM_TIMEFRAMES InpTrendTF2   = PERIOD_H4;
input int             InpTrendFast  = 50;          // TF up = EMA fast > EMA slow and close > EMA slow
input int             InpTrendSlow  = 200;
input bool            InpD1On       = true;        // D1 close must not be against the trade (graded)
input int             InpD1Ema      = 50;

input group "=== Trigger candle (Mt.ZionPro) ==="
input double InpMinBodyRatio = 0.25;               // base trigger: min body / range
input double InpClosePos     = 0.55;               // base trigger: close in the top (buy) / bottom (sell) part
input int    InpSwingLook    = 2;                  // base trigger: displacement over the last N bars
input bool   InpStrictOn     = true;               // strict trigger (graded)
input double InpStrictBody   = 0.50;
input double InpStrictClose  = 0.6625;
input int    InpSwingBars    = 15;                 // swing to break is searched within this many bars
input int    InpFractalSide  = 2;                  // bars on each side that make a swing point
input double InpPinWickMult  = 2.0;                // pin bar: rejection wick >= this x body
input double InpPinWickPct   = 0.55;               // and >= this share of the range
input int    InpPinSweep     = 3;                  // and the wick sweeps the previous N bars

input group "=== Volatility / location filters (graded) ==="
input int    InpATRPeriod   = 14;
input bool   InpATROn       = true;                // signal candle range between min and max x ATR
input double InpMinRangeATR = 0.525;
input double InpMaxRangeATR = 2.5;
input bool   InpLocationOn  = true;                // close within k x ATR of the mid VWMA
input double InpMaxExtATR   = 1.875;
input bool   InpRoomOn      = true;                // no PDH/PDL/PWH/PWL between entry and TP1
input bool   InpExhaustOn   = true;                // fast RSI not beyond OB (buys) / 100-OB (sells)
input double InpRsiOB       = 80.0;

input group "=== Session / spread (hard gates) ==="
input bool   InpSessionOn       = false;           // true = signals only inside the UTC window below (false = all sessions)
input int    InpSessStartUTC    = 7;               // London open
input int    InpSessEndUTC      = 20;              // late New York
input int    InpServerUtcOffset = 99;              // broker server time minus UTC in hours (99 = auto)
input int    InpMaxSpreadPts    = 60;              // max bar spread, in 2-digit gold points (0 = off)
input bool   InpAutoDigits      = true;            // 3-digit gold: point inputs are scaled x10

input group "=== Grades / signals ==="
input bool   InpGradeA       = true;               // A grade (passes every filter) becomes a signal
input bool   InpGradeB       = true;               // B grade (fails one filter) becomes a signal
input bool   InpGradeC       = true;               // C grade (fails 2+ filters AND passes the C rules) becomes a signal
input group "=== Grade C rules (C = fails two or more filters) ==="
input int    InpCMaxFails    = 3;                  // C may fail at most this many filters (more = rejected)
input int    InpCMinScore    = 4;                  // C needs this momentum score (1-5)
input int    InpCMaxFailScore = 5;                 // a C at the max fail count needs this momentum score
input bool   InpCNoCounter   = true;               // reject C when H1+H4 trend is against the trade (no trend is OK)
input bool   InpCNoTrendD1   = false;              // reject C when the trend AND D1 filters both fail
input bool   InpCNeedCandle  = true;               // reject C when the strict candle failed AND momentum is below 5/5
input bool   InpCNeedRoom    = true;               // reject C when PDH/PDL/PWH/PWL blocks the way to TP1
input bool   InpCNoExhaust   = true;               // reject C when the fast RSI is exhausted
input bool   InpCSessionOnly = false;              // C only between InpSessStartUTC and InpSessEndUTC (London/NY)

input group "=== Signal display ==="
input bool   InpShowFiltered = true;               // grey grade letter where a toggled-off grade fired (hover = failed filters)
input color  InpFiltColor    = clrSilver;
input bool   InpReplacePending = true;             // a new signal replaces a pending (unfilled) entry
input int    InpCooldown     = 7;                  // bars between signals in the same direction
input int    InpHistoryBars  = 3000;               // closed bars replayed on load (stats cover these)

input group "=== Entry / exits ==="
input bool           InpPendingOn       = true;
input ENUM_PEND_TYPE InpPendingType     = PEND_LIMIT;
input int            InpPendingPts      = 40;      // minimum pending distance (points)
input double         InpPendingRetrace  = 0.40;    // fraction of the signal candle range
input bool           InpPendingUseRange = true;    // distance = max(points, range x retrace)
input int            InpPendingExpire   = 12;      // cancel pending after N closed bars
input int            InpMinSLGapPts     = 15;      // keep pending entry this far from the SL
input int            InpSLBufferPts     = 20;      // SL beyond the signal candle, at least this
input double         InpSLBufATR        = 0.3;     // ... or this x ATR
input double         InpSLBufSpread     = 2.0;     // ... or this x spread
input double         InpSLWidenPct      = 0.0;     // widen SL by % of risk (TPs keep the original R)
input double         InpRR1             = 1.0;     // TP1 R-multiple
input double         InpRR2             = 2.0;     // TP2 R-multiple
input bool           InpMoveBE          = true;    // runner SL to entry after TP1
input bool           InpSpreadAware     = true;    // buy fills / sell exits use the ask

input group "=== Alerts ==="
input bool   InpAlertPopup = true;
input bool   InpAlertSound = true;
input bool   InpAlertPush  = false;
input bool   InpAlertEmail = false;
input string InpSoundFile  = "alert.wav";
input bool   InpAlertFill  = true;                 // alert when a pending entry fills

input group "=== Visuals ==="
input bool   InpShowPanel      = true;
input int    InpPanelX         = 4;
input int    InpPanelY         = 20;
input int    InpPanelWidth     = 260;
input int    InpPanelFont      = 8;
input int    InpPanelRowH      = 15;
input bool   InpShowLevels     = true;             // PDH/PDL and PWH/PWL lines
input bool   InpShowZones      = true;             // entry / SL / TP boxes of the current idea
input bool   InpHideAtTP1      = false;            // remove the zone at TP1 (false = keep until TP2 / BE)
input int    InpZoneRightBars  = 18;
input int    InpLabelBars      = 16;
input int    InpZoneFontSize   = 7;
input int    InpZoneOpacity    = 35;
input int    InpLineOpacity    = 80;
input bool   InpAutoChartShift = true;
input int    InpChartShiftPct  = 25;
input color  InpBuyColorA      = clrAqua;
input color  InpBuyColorB      = clrAqua;
input color  InpBuyColorC      = clrAqua;
input color  InpSellColorA     = clrMagenta;
input color  InpSellColorB     = clrMagenta;
input color  InpSellColorC     = clrMagenta;
input color  InpZoneSL         = C'220,50,50';
input color  InpZoneTP1        = C'30,170,100';
input color  InpZoneTP2        = C'40,100,230';
input color  InpLineSL         = C'255,100,100';
input color  InpLineTP1        = C'60,255,190';
input color  InpLineTP2        = C'120,200,255';

//--- buffers (all as-series)
double VS[], VM[], VF[];
double BuyBuf[], BuyClr[], SellBuf[], SellClr[];
double R7[], R14[], ScoreB[], ScoreS[];

//--- handles
int hRsiF = INVALID_HANDLE, hRsiS = INVALID_HANDLE, hATR = INVALID_HANDLE;
int hT1F = INVALID_HANDLE, hT1S = INVALID_HANDLE, hT2F = INVALID_HANDLE, hT2S = INVALID_HANDLE;
int hD1 = INVALID_HANDLE;

#define MPRE "ZVF_M_"    // filtered marks
#define ZPRE "ZVF_Z_"    // zone
#define LPRE "ZVF_L_"    // levels
#define PPRE "ZVF_P_"    // panel

int      gTotal       = 0;
int      gOffset      = 0;      // server - UTC, hours
datetime gLastBar     = 0;
datetime gLastAlert   = 0;
datetime gLastFill    = 0;
datetime gLastBuy     = 0, gLastSell = 0;
datetime gLastFiltB   = 0, gLastFiltS = 0;
uint     gLastPanelMs = 0;

//--- outcome stats
int gCntBuy = 0, gCntSell = 0, gCntTP1 = 0, gCntTP2 = 0, gCntSL = 0, gCntLoss = 0, gCntBE = 0;
int gWinG[3], gLossG[3];   // TP1 wins / losses per grade A, B, C
#define EV_SIG  0
#define EV_TP1  1
#define EV_TP2  2
#define EV_SL   3
#define EV_LOSS 4
datetime gEvT[];
int      gEvK[];

//--- session highs / lows for the panel
double gAsiaH = 0, gAsiaL = 0, gLonH = 0, gLonL = 0, gNyH = 0, gNyL = 0;
bool   gAsiaOK = false, gLonOK = false, gNyOK = false;

struct Candle
  {
   double   o, h, l, c, spr;
   datetime t;
   bool     valid;
  };

enum IdeaState { IDEA_IDLE = 0, IDEA_PENDING, IDEA_LIVE };

struct Idea
  {
   IdeaState state;
   int       dir, grade, armTrend, pendAge;
   double    entry, sl, tp1, tp2;
   datetime  signalTime, fillTime;
   bool      tp1Done;
  };
Idea idea;

struct ZoneSnap
  {
   bool     valid;
   int      dir, grade;
   double   entry, sl, tp1, tp2;
   datetime t1;
   string   status;
  };
ZoneSnap gz;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpVwmaSlow < 2 || InpVwmaMid < 2 || InpVwmaFast < 2 || InpRsiFast < 2 || InpRsiSlow < 2 || InpSlopeBars < 1)
     {
      Print("ZionVWMA Fusion: periods must be >= 2 (slope >= 1)");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMinScore < 1 || InpMinScore > 5)
     {
      Print("ZionVWMA Fusion: MinScore must be 1-5");
      return INIT_PARAMETERS_INCORRECT;
     }

   SetIndexBuffer(0,  VS,      INDICATOR_DATA);
   SetIndexBuffer(1,  VM,      INDICATOR_DATA);
   SetIndexBuffer(2,  VF,      INDICATOR_DATA);
   SetIndexBuffer(3,  BuyBuf,  INDICATOR_DATA);
   SetIndexBuffer(4,  BuyClr,  INDICATOR_COLOR_INDEX);
   SetIndexBuffer(5,  SellBuf, INDICATOR_DATA);
   SetIndexBuffer(6,  SellClr, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(7,  R7,      INDICATOR_CALCULATIONS);
   SetIndexBuffer(8,  R14,     INDICATOR_CALCULATIONS);
   SetIndexBuffer(9,  ScoreB,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(10, ScoreS,  INDICATOR_CALCULATIONS);
   ArraySetAsSeries(VS, true);      ArraySetAsSeries(VM, true);      ArraySetAsSeries(VF, true);
   ArraySetAsSeries(BuyBuf, true);  ArraySetAsSeries(BuyClr, true);
   ArraySetAsSeries(SellBuf, true); ArraySetAsSeries(SellClr, true);
   ArraySetAsSeries(R7, true);      ArraySetAsSeries(R14, true);
   ArraySetAsSeries(ScoreB, true);  ArraySetAsSeries(ScoreS, true);

   for(int p = 0; p < 5; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(3, PLOT_ARROW, 233);
   PlotIndexSetInteger(4, PLOT_ARROW, 234);
   PlotIndexSetInteger(3, PLOT_ARROW_SHIFT, 14);
   PlotIndexSetInteger(4, PLOT_ARROW_SHIFT, -14);
   PlotIndexSetInteger(3, PLOT_COLOR_INDEXES, 3);
   PlotIndexSetInteger(4, PLOT_COLOR_INDEXES, 3);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, 0, InpBuyColorA);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, 1, InpBuyColorB);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, 2, InpBuyColorC);
   PlotIndexSetInteger(4, PLOT_LINE_COLOR, 0, InpSellColorA);
   PlotIndexSetInteger(4, PLOT_LINE_COLOR, 1, InpSellColorB);
   PlotIndexSetInteger(4, PLOT_LINE_COLOR, 2, InpSellColorC);

   IndicatorSetString(INDICATOR_SHORTNAME, "ZionVWMA Fusion");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   hRsiF = iRSI(_Symbol, _Period, InpRsiFast, PRICE_CLOSE);
   hRsiS = iRSI(_Symbol, _Period, InpRsiSlow, PRICE_CLOSE);
   hATR  = iATR(_Symbol, _Period, InpATRPeriod);
   hT1F  = iMA(_Symbol, InpTrendTF1, InpTrendFast, 0, MODE_EMA, PRICE_CLOSE);
   hT1S  = iMA(_Symbol, InpTrendTF1, InpTrendSlow, 0, MODE_EMA, PRICE_CLOSE);
   hT2F  = iMA(_Symbol, InpTrendTF2, InpTrendFast, 0, MODE_EMA, PRICE_CLOSE);
   hT2S  = iMA(_Symbol, InpTrendTF2, InpTrendSlow, 0, MODE_EMA, PRICE_CLOSE);
   hD1   = iMA(_Symbol, PERIOD_D1, InpD1Ema, 0, MODE_EMA, PRICE_CLOSE);
   if(hRsiF == INVALID_HANDLE || hRsiS == INVALID_HANDLE || hATR == INVALID_HANDLE ||
      hT1F == INVALID_HANDLE || hT1S == INVALID_HANDLE || hT2F == INVALID_HANDLE ||
      hT2S == INVALID_HANDLE || hD1 == INVALID_HANDLE)
     {
      Print("ZionVWMA Fusion: could not create indicator handles");
      return INIT_FAILED;
     }

   gOffset = ServerOffset();
   if(InpAutoChartShift)
     {
      ChartSetInteger(0, CHART_SHIFT, true);
      ChartSetDouble(0, CHART_SHIFT_SIZE, MathMax(10, MathMin(50, InpChartShiftPct)));
     }
   ResetIdea();
   ResetZone();
   ResetCounts();
   gPanelHidden = (GlobalVariableCheck(HideKey()) && GlobalVariableGet(HideKey()) > 0);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void ReleaseHandle(int &h)
  {
   if(h != INVALID_HANDLE) IndicatorRelease(h);
   h = INVALID_HANDLE;
  }

void OnDeinit(const int reason)
  {
   ReleaseHandle(hRsiF); ReleaseHandle(hRsiS); ReleaseHandle(hATR);
   ReleaseHandle(hT1F);  ReleaseHandle(hT1S);
   ReleaseHandle(hT2F);  ReleaseHandle(hT2S);  ReleaseHandle(hD1);
   ObjectsDeleteAll(0, MPRE);
   ObjectsDeleteAll(0, ZPRE);
   ObjectsDeleteAll(0, LPRE);
   ObjectsDeleteAll(0, PPRE);
  }

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
int ServerOffset()
  {
   if(InpServerUtcOffset != 99) return InpServerUtcOffset;
   long d = (long)TimeTradeServer() - (long)TimeGMT();
   return (int)MathRound(d / 3600.0);
  }

// point unit for point inputs; on 3/5-digit symbols one unit = 10 points
double Pt()
  {
   if(InpAutoDigits && (_Digits == 3 || _Digits == 5)) return _Point * 10.0;
   return _Point;
  }

void ResetIdea()
  {
   idea.state = IDEA_IDLE;
   idea.dir = 0;
   idea.grade = GRADE_NONE;
   idea.armTrend = 0;
   idea.pendAge = 0;
   idea.entry = idea.sl = idea.tp1 = idea.tp2 = 0;
   idea.signalTime = idea.fillTime = 0;
   idea.tp1Done = false;
  }

void ResetZone()
  {
   gz.valid = false;
   gz.dir = 0;
   gz.grade = GRADE_NONE;
   gz.entry = gz.sl = gz.tp1 = gz.tp2 = 0;
   gz.t1 = 0;
   gz.status = "";
  }

void ResetCounts()
  {
   gCntBuy = gCntSell = gCntTP1 = gCntTP2 = gCntSL = gCntLoss = gCntBE = 0;
   ArrayInitialize(gWinG, 0);
   ArrayInitialize(gLossG, 0);
   ArrayResize(gEvT, 0);
   ArrayResize(gEvK, 0);
  }

void AddEv(const int kind, const datetime t)
  {
   int n = ArraySize(gEvT);
   if(n >= 3000) { ArrayRemove(gEvT, 0, 1000); ArrayRemove(gEvK, 0, 1000); n = ArraySize(gEvT); }
   ArrayResize(gEvT, n + 1);
   ArrayResize(gEvK, n + 1);
   gEvT[n] = t;
   gEvK[n] = kind;
  }

double BufAt(const int h, const int sh)
  {
   if(h == INVALID_HANDLE || sh < 0) return 0.0;
   double v[1];
   if(CopyBuffer(h, 0, sh, 1, v) != 1) return 0.0;
   if(v[0] == EMPTY_VALUE) return 0.0;
   return v[0];
  }

// shift of the last bar of tf that was fully closed at time t (no look-ahead)
int ClosedShiftAt(const ENUM_TIMEFRAMES tf, const datetime t)
  {
   int sh = iBarShift(_Symbol, tf, t, false);
   if(sh < 0) return -1;
   datetime ht = iTime(_Symbol, tf, sh);
   if(ht == 0) return -1;
   if(t < ht + (datetime)PeriodSeconds(tf))
      sh++;
   return sh;
  }

double BodyRatio(const Candle &k)
  {
   double rng = k.h - k.l;
   return (rng > 0.0 ? MathAbs(k.c - k.o) / rng : 0.0);
  }

double ClosePos(const Candle &k)
  {
   double rng = k.h - k.l;
   return (rng > 0.0 ? (k.c - k.l) / rng : 0.5);
  }

double ATRAt(const int sh) { return BufAt(hATR, sh); }

double BarHL(const int sh, const int dir) { return (dir > 0 ? iHigh(_Symbol, _Period, sh) : iLow(_Symbol, _Period, sh)); }

//+------------------------------------------------------------------+
//| VWMA                                                             |
//+------------------------------------------------------------------+
double PriceAt(const int sh, const double &o[], const double &h[], const double &l[], const double &c[])
  {
   switch(InpVwmaPrice)
     {
      case PRICE_OPEN:     return o[sh];
      case PRICE_HIGH:     return h[sh];
      case PRICE_LOW:      return l[sh];
      case PRICE_MEDIAN:   return (h[sh] + l[sh]) / 2.0;
      case PRICE_TYPICAL:  return (h[sh] + l[sh] + c[sh]) / 3.0;
      case PRICE_WEIGHTED: return (h[sh] + l[sh] + 2.0 * c[sh]) / 4.0;
      default:             return c[sh];
     }
  }

double Vwma(const int sh, const int period, const double &o[], const double &h[], const double &l[],
            const double &c[], const long &vol[])
  {
   if(sh + period > gTotal) return EMPTY_VALUE;
   double pv = 0.0, v = 0.0, s = 0.0;
   for(int k = sh; k < sh + period; k++)
     {
      double p = PriceAt(k, o, h, l, c);
      pv += p * (double)vol[k];
      v  += (double)vol[k];
      s  += p;
     }
   return (v > 0.0 ? pv / v : s / period);
  }

// momentum votes for one direction (0-5)
int MomScore(const int sh, const int dir, const double close)
  {
   if(sh + InpSlopeBars >= gTotal) return 0;
   if(VS[sh] == EMPTY_VALUE || VM[sh] == EMPTY_VALUE || VF[sh] == EMPTY_VALUE ||
      VS[sh + InpSlopeBars] == EMPTY_VALUE)
      return 0;
   double up = InpRsiMid, dn = 100.0 - InpRsiMid;
   int s = 0;
   if(dir > 0)
     {
      if(R7[sh]  > up) s++;
      if(R14[sh] > up) s++;
      if(close > VS[sh]) s++;
      if(VF[sh] > VM[sh]) s++;
      if(VS[sh] > VS[sh + InpSlopeBars]) s++;
     }
   else
     {
      if(R7[sh]  < dn) s++;
      if(R14[sh] < dn) s++;
      if(close < VS[sh]) s++;
      if(VF[sh] < VM[sh]) s++;
      if(VS[sh] < VS[sh + InpSlopeBars]) s++;
     }
   return s;
  }

//+------------------------------------------------------------------+
//| Trend filters                                                    |
//+------------------------------------------------------------------+
int TFTrendAt(const ENUM_TIMEFRAMES tf, const int hF, const int hS, const datetime t)
  {
   int sh = ClosedShiftAt(tf, t);
   if(sh < 0) return 0;
   double f = BufAt(hF, sh), s = BufAt(hS, sh), c = iClose(_Symbol, tf, sh);
   if(f <= 0 || s <= 0 || c <= 0) return 0;
   if(f > s && c > s) return 1;
   if(f < s && c < s) return -1;
   return 0;
  }

int TrendDirAt(const datetime t)
  {
   int a = TFTrendAt(InpTrendTF1, hT1F, hT1S, t);
   int b = TFTrendAt(InpTrendTF2, hT2F, hT2S, t);
   return ((a != 0 && a == b) ? a : 0);
  }

bool D1Against(const int dir, const datetime t)
  {
   int sh = ClosedShiftAt(PERIOD_D1, t);
   if(sh < 0) return false;
   double e = BufAt(hD1, sh), c = iClose(_Symbol, PERIOD_D1, sh);
   if(e <= 0 || c <= 0) return false;
   return (dir > 0 ? c < e : c > e);
  }

//+------------------------------------------------------------------+
//| Session / spread gates                                           |
//+------------------------------------------------------------------+
int UtcHour(const datetime t)
  {
   long u = (long)t - (long)gOffset * 3600;
   return (int)(((u % 86400) + 86400) % 86400 / 3600);
  }

bool InWindow(const datetime t)
  {
   int h = UtcHour(t);
   if(InpSessStartUTC <= InpSessEndUTC) return (h >= InpSessStartUTC && h < InpSessEndUTC);
   return (h >= InpSessStartUTC || h < InpSessEndUTC);
  }

bool InSession(const datetime t)
  {
   if(!InpSessionOn) return true;
   int h = UtcHour(t);
   if(InpSessStartUTC <= InpSessEndUTC) return (h >= InpSessStartUTC && h < InpSessEndUTC);
   return (h >= InpSessStartUTC || h < InpSessEndUTC);
  }

//+------------------------------------------------------------------+
//| Triggers                                                         |
//+------------------------------------------------------------------+
double RecentExt(const int sh, const int dir, const double &high[], const double &low[])
  {
   int from = sh + 1;
   int to   = (int)MathMin(gTotal - 1, sh + InpSwingLook);
   if(from > gTotal - 1) return (dir > 0 ? high[sh] : low[sh]);
   double e = (dir > 0 ? high[from] : low[from]);
   for(int k = from; k <= to; k++)
      e = (dir > 0 ? MathMax(e, high[k]) : MathMin(e, low[k]));
   return e;
  }

bool BaseTrigger(const int dir, const Candle &k, const double prevExt)
  {
   if(!k.valid) return false;
   if(dir > 0 ? k.c <= k.o : k.c >= k.o) return false;
   if(BodyRatio(k) < InpMinBodyRatio) return false;
   double cp = ClosePos(k);
   if(dir > 0 ? cp < InpClosePos : cp > 1.0 - InpClosePos) return false;
   bool displace = (dir > 0 ? k.c > prevExt : k.c < prevExt);
   bool reject   = (dir > 0 ? (k.o - k.l) >= (k.c - k.o) * 0.55 : (k.h - k.o) >= (k.o - k.c) * 0.55);
   return (displace || reject);
  }

// most recent confirmed swing high (dir > 0) / low (dir < 0) before bar sh
double SwingLevel(const int sh, const int dir)
  {
   int side = (int)MathMax(1, InpFractalSide);
   int last = (int)MathMin(gTotal - 1 - side, sh + InpSwingBars);
   for(int j = sh + 1 + side; j <= last; j++)
     {
      double p = BarHL(j, dir);
      bool ok = true;
      for(int k = 1; k <= side && ok; k++)
        {
         double a = BarHL(j - k, dir), b = BarHL(j + k, dir);
         if(dir > 0 ? (a >= p || b > p) : (a <= p || b < p)) ok = false;
        }
      if(ok) return p;
     }
   double ext = BarHL(sh + 1, dir);
   for(int m = sh + 2; m <= sh + InpSwingBars && m < gTotal; m++)
     {
      double p = BarHL(m, dir);
      if(dir > 0 ? p > ext : p < ext) ext = p;
     }
   return ext;
  }

// strong close through a real swing, or a pin bar that sweeps the previous bars
bool StrictTrigger(const int dir, const Candle &k, const int sh)
  {
   double rng = k.h - k.l;
   if(!k.valid || rng <= 0) return false;
   double body = MathAbs(k.c - k.o);
   double cp   = ClosePos(k);
   if(dir < 0) cp = 1.0 - cp;
   bool strongClose = (cp >= InpStrictClose);

   double lvl  = SwingLevel(sh, dir);
   double prev = iClose(_Symbol, _Period, sh + 1);
   bool breaks = (dir > 0 ? (k.c > lvl && prev <= lvl) : (k.c < lvl && prev >= lvl));
   if(BodyRatio(k) >= InpStrictBody && strongClose && breaks) return true;

   double wick = (dir > 0 ? MathMin(k.o, k.c) - k.l : k.h - MathMax(k.o, k.c));
   if(wick < body * InpPinWickMult || wick < rng * InpPinWickPct || !strongClose) return false;
   double ext = BarHL(sh + 1, -dir);
   for(int j = sh + 2; j <= sh + InpPinSweep; j++)
     {
      double p = BarHL(j, -dir);
      if(dir > 0 ? p < ext : p > ext) ext = p;
     }
   return (dir > 0 ? k.l < ext : k.h > ext);
  }

//+------------------------------------------------------------------+
//| Levels                                                           |
//+------------------------------------------------------------------+
double StopBuffer(const int sh, const double spr)
  {
   double b = (double)InpSLBufferPts * Pt();
   double atr = ATRAt(sh);
   if(atr > 0) b = MathMax(b, atr * InpSLBufATR);
   return MathMax(b, spr * InpSLBufSpread);
  }

double PendingDist(const Candle &bar)
  {
   double d = (double)InpPendingPts * Pt();
   if(InpPendingUseRange && bar.h > bar.l)
      d = MathMax(d, (bar.h - bar.l) * InpPendingRetrace);
   return (d > 0.0 ? d : 10.0 * Pt());
  }

// entry / SL / TP1 / TP2 for a signal candle; false if the geometry is invalid
bool CalcLevels(const int dir, const Candle &bar, const double buf,
                double &entry, double &sl, double &tp1, double &tp2)
  {
   double gap  = MathMax((double)InpMinSLGapPts * Pt(), 5.0 * Pt());
   double dist = PendingDist(bar);
   if(dir > 0)
     {
      sl = bar.l - buf;
      if(InpPendingOn)
        {
         entry = (InpPendingType == PEND_LIMIT ? bar.c - dist : bar.h + dist);
         if(entry <= sl + gap) entry = sl + gap;
        }
      else
         entry = bar.c;
      if(entry <= sl) return false;
     }
   else
     {
      sl = bar.h + buf;
      if(InpPendingOn)
        {
         entry = (InpPendingType == PEND_LIMIT ? bar.c + dist : bar.l - dist);
         if(entry >= sl - gap) entry = sl - gap;
        }
      else
         entry = bar.c;
      if(entry >= sl) return false;
     }
   double risk = MathAbs(entry - sl);
   double w = 1.0 + MathMax(0.0, InpSLWidenPct) / 100.0;
   sl  = entry - dir * risk * w;
   tp1 = entry + dir * risk * InpRR1;
   tp2 = entry + dir * risk * InpRR2;
   return true;
  }

// previous day / week high-low between entry and TP1 blocks the move
bool RoomBlocked(const int dir, const datetime t, const double entry, const double tp1)
  {
   double lv[4];
   int n = 0;
   int d = ClosedShiftAt(PERIOD_D1, t);
   if(d >= 0) { lv[n++] = iHigh(_Symbol, PERIOD_D1, d); lv[n++] = iLow(_Symbol, PERIOD_D1, d); }
   int w = ClosedShiftAt(PERIOD_W1, t);
   if(w >= 0) { lv[n++] = iHigh(_Symbol, PERIOD_W1, w); lv[n++] = iLow(_Symbol, PERIOD_W1, w); }
   for(int k = 0; k < n; k++)
     {
      if(lv[k] <= 0) continue;
      if(dir > 0 ? (lv[k] > entry && lv[k] < tp1) : (lv[k] < entry && lv[k] > tp1)) return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Grade: A = passes every enabled filter, B = fails one, C = more. |
//| A C must also pass the C rules, otherwise it becomes C- (grey).  |
//+------------------------------------------------------------------+
int SignalGrade(const int dir, const Candle &k, const int sh, const int trendDir,
                const double entry, const double tp1, const int score, string &why)
  {
   int fails = 0, mask = 0;
   why = "";
   if(InpTrendOn && trendDir != dir)
     {
      fails++; mask |= F_TREND;
      if(trendDir == -dir) { mask |= F_COUNTER; why += " trend(against)"; }
      else why += " trend(none)";
     }
   if(InpD1On && D1Against(dir, k.t)) { fails++; mask |= F_D1; why += " D1"; }
   double atr = ATRAt(sh);
   if(InpATROn)
     {
      double rng = k.h - k.l;
      if(atr <= 0 || rng < atr * InpMinRangeATR || rng > atr * InpMaxRangeATR) { fails++; mask |= F_RANGE; why += " range"; }
     }
   if(InpLocationOn)
     {
      if(atr <= 0 || VM[sh] == EMPTY_VALUE || MathAbs(k.c - VM[sh]) > atr * InpMaxExtATR) { fails++; mask |= F_EXT; why += " extended"; }
     }
   if(InpRoomOn && RoomBlocked(dir, k.t, entry, tp1)) { fails++; mask |= F_ROOM; why += " room"; }
   if(InpExhaustOn && (dir > 0 ? R7[sh] > InpRsiOB : R7[sh] < 100.0 - InpRsiOB)) { fails++; mask |= F_EXH; why += " exhausted"; }
   if(InpStrictOn && !StrictTrigger(dir, k, sh)) { fails++; mask |= F_CANDLE; why += " candle"; }
   if(fails < 2) return fails;

   //--- C rules: only "context" misses are tolerated, never the execution ones
   string rule = "";
   if(fails > InpCMaxFails)                                   rule += " too-many-fails";
   if(score < InpCMinScore)                                   rule += " score<" + IntegerToString(InpCMinScore);
   else if(fails == InpCMaxFails && fails > 2 && score < InpCMaxFailScore)
                                                              rule += " " + IntegerToString(fails) + "-fails-score<" + IntegerToString(InpCMaxFailScore);
   if(InpCNoCounter  && (mask & F_COUNTER) != 0)              rule += " counter-trend";
   if(InpCNoTrendD1  && (mask & F_TREND) != 0 && (mask & F_D1) != 0) rule += " trend+D1";
   if(InpCNeedCandle && (mask & F_CANDLE) != 0 && score < 5)  rule += " weak-candle";
   if(InpCNeedRoom   && (mask & F_ROOM) != 0)                 rule += " no-room";
   if(InpCNoExhaust  && (mask & F_EXH) != 0)                  rule += " exhausted";
   if(InpCSessionOnly && !InWindow(k.t))                      rule += " off-session";
   if(rule == "") return GRADE_C;
   why += " | C rules:" + rule;
   return GRADE_CX;
  }

string GradeName(const int g)
  {
   if(g == GRADE_A) return "A";
   if(g == GRADE_B) return "B";
   if(g == GRADE_C) return "C";
   if(g == GRADE_CX) return "C-";
   return "-";
  }

bool GradeOn(const int g)
  {
   if(g == GRADE_A) return InpGradeA;
   if(g == GRADE_B) return InpGradeB;
   if(g == GRADE_C) return InpGradeC;
   return false;
  }

bool Cooled(const datetime now, const datetime last, const int bars)
  {
   return (last == 0 || (now - last) >= (datetime)bars * PeriodSeconds(_Period));
  }

//+------------------------------------------------------------------+
//| Trade idea engine                                                |
//+------------------------------------------------------------------+
void EndIdea(const string status)
  {
   if(idea.state != IDEA_IDLE && idea.signalTime != 0)
     {
      gz.valid  = true;
      gz.dir    = idea.dir;
      gz.grade  = idea.grade;
      gz.entry  = idea.entry;
      gz.sl     = idea.sl;
      gz.tp1    = idea.tp1;
      gz.tp2    = idea.tp2;
      gz.t1     = idea.signalTime;
      gz.status = status;
     }
   ResetIdea();
  }

void ArmIdea(const int dir, const Candle &bar, const int grade, const int trendDir,
             const double entry, const double sl, const double tp1, const double tp2)
  {
   idea.dir        = dir;
   idea.grade      = grade;
   idea.armTrend   = trendDir;
   idea.entry      = entry;
   idea.sl         = sl;
   idea.tp1        = tp1;
   idea.tp2        = tp2;
   idea.signalTime = bar.t;
   idea.pendAge    = 0;
   idea.tp1Done    = false;
   idea.state      = (InpPendingOn ? IDEA_PENDING : IDEA_LIVE);
   idea.fillTime   = (InpPendingOn ? 0 : bar.t);
  }

void StopOut(const Candle &bar)
  {
   if(idea.tp1Done && InpMoveBE) { gCntBE++; EndIdea(" [BE]"); return; }
   gCntSL++; AddEv(EV_SL, bar.t);
   if(!idea.tp1Done) { gCntLoss++; AddEv(EV_LOSS, bar.t); if(idea.grade <= GRADE_C) gLossG[idea.grade]++; }
   EndIdea(" [SL HIT]");
  }

void ManageIdea(const Candle &bar, const int trendDir)
  {
   if(idea.state == IDEA_IDLE) return;
   double sp = (InpSpreadAware ? bar.spr : 0.0);
   double xs = (idea.dir < 0 ? sp : 0.0);   // sells exit on the ask
   bool fillBar = false;

   if(idea.state == IDEA_PENDING)
     {
      idea.pendAge++;
      if(idea.pendAge > InpPendingExpire) { EndIdea(" [EXPIRED]"); return; }
      if(InpTrendOn && trendDir == -idea.dir && idea.armTrend != -idea.dir) { EndIdea(" [CANCELLED]"); return; }
      double shift = (idea.dir > 0 ? sp : 0.0);   // buys fill on the ask
      if(!(bar.l + shift <= idea.entry && bar.h + shift >= idea.entry)) return;
      idea.state = IDEA_LIVE;
      idea.fillTime = bar.t;
      fillBar = true;
     }

   bool hitTP2 = (idea.dir > 0 ? bar.h >= idea.tp2 : bar.l + xs <= idea.tp2);
   bool hitTP1 = (idea.dir > 0 ? bar.h >= idea.tp1 : bar.l + xs <= idea.tp1);
   bool hitSL  = (idea.dir > 0 ? bar.l <= idea.sl  : bar.h + xs >= idea.sl);

   if(fillBar)
     {
      // order of prices inside the fill bar is unknown: be conservative
      if(!InpPendingOn || InpPendingType == PEND_LIMIT)
        {
         hitTP1 = (idea.dir > 0 ? bar.c >= idea.tp1 : bar.c + xs <= idea.tp1);
         hitTP2 = (idea.dir > 0 ? bar.c >= idea.tp2 : bar.c + xs <= idea.tp2);
        }
      else
         hitSL = (idea.dir > 0 ? bar.c <= idea.sl : bar.c + xs >= idea.sl);
      if(hitSL) hitTP1 = hitTP2 = false;
     }

   if(hitSL && hitTP1)
     {
      bool closeFav = (idea.dir > 0 ? bar.c > idea.entry : bar.c + xs < idea.entry);
      if(!closeFav) { StopOut(bar); return; }
     }

   if(hitTP2)
     {
      if(!idea.tp1Done) { gCntTP1++; AddEv(EV_TP1, bar.t); if(idea.grade <= GRADE_C) gWinG[idea.grade]++; }
      gCntTP2++; AddEv(EV_TP2, bar.t);
      EndIdea(" [TP2 HIT]");
      return;
     }

   bool tp1Now = false;
   if(hitTP1 && !idea.tp1Done)
     {
      gCntTP1++; AddEv(EV_TP1, bar.t);
      if(idea.grade <= GRADE_C) gWinG[idea.grade]++;
      idea.tp1Done = true;
      tp1Now = true;
     }

   if(hitSL) { StopOut(bar); return; }
   if(tp1Now && InpMoveBE) idea.sl = idea.entry;
  }

//+------------------------------------------------------------------+
//| Drawing                                                          |
//+------------------------------------------------------------------+
color Faint(const color c, const int opacityPct)
  {
   double a = MathMax(0, MathMin(100, opacityPct)) / 100.0;
   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   int r = (int)MathRound(( bg        & 0xFF) + (( c        & 0xFF) - ( bg        & 0xFF)) * a);
   int g = (int)MathRound(((bg >> 8)  & 0xFF) + (((c >> 8)  & 0xFF) - ((bg >> 8)  & 0xFF)) * a);
   int b = (int)MathRound(((bg >> 16) & 0xFF) + (((c >> 16) & 0xFF) - ((bg >> 16) & 0xFF)) * a);
   return (color)(r | (g << 8) | (b << 16));
  }

color SignalColor(const int dir, const int grade)
  {
   if(dir > 0) return (grade == GRADE_A ? InpBuyColorA : (grade == GRADE_B ? InpBuyColorB : InpBuyColorC));
   return (grade == GRADE_A ? InpSellColorA : (grade == GRADE_B ? InpSellColorB : InpSellColorC));
  }

void FilteredMark(const datetime t, const double price, const int dir, const int grade, const string why)
  {
   string name = MPRE + TimeToString(t, TIME_DATE|TIME_MINUTES) + (dir > 0 ? "_U" : "_D");
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetString(0, name, OBJPROP_TEXT, GradeName(grade));
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpFiltColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpZoneFontSize + 1);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, dir > 0 ? ANCHOR_UPPER : ANCHOR_LOWER);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, (dir > 0 ? "BUY " : "SELL ") + GradeName(grade) + " not taken, failed:" + why);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

void PutRect(const string name, const datetime t1, const double p1, const datetime t2, const double p2, const color fill)
  {
   if(t1 <= 0 || t2 <= t1) return;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, fill);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, fill);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

void PutLine(const string name, const datetime t1, const datetime t2, const double price, const color clr)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

void PutLabel(const string name, const datetime t, const double price, const string text, const color clr)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpZoneFontSize);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

// only the running idea's zone is drawn
void DrawLiveZone()
  {
   bool show = InpShowZones && idea.state != IDEA_IDLE && idea.signalTime != 0
               && !(InpHideAtTP1 && idea.tp1Done);
   if(!show)
     {
      ObjectsDeleteAll(0, ZPRE);
      return;
     }
   int ps = PeriodSeconds(_Period);
   datetime now = iTime(_Symbol, _Period, 0);
   if(now == 0) now = TimeCurrent();
   datetime t1 = idea.signalTime;
   datetime t2 = now + (datetime)MathMax(2, InpZoneRightBars) * ps;
   datetime tl = t2 + ps;
   datetime t3 = t2 + (datetime)MathMax(4, InpLabelBars) * ps;

   string status = (idea.state == IDEA_PENDING ? (InpPendingType == PEND_LIMIT ? " [LIMIT]" : " [STOP]")
                    : (idea.tp1Done ? " [TP1 HIT]" : " [FILLED]"));
   color  sig  = SignalColor(idea.dir, idea.grade);
   string side = (idea.dir > 0 ? "BUY " : "SELL ") + GradeName(idea.grade);

   PutRect(ZPRE + "SL",  t1, idea.entry, t2, idea.sl,  Faint(InpZoneSL,  InpZoneOpacity));
   PutRect(ZPRE + "T1",  t1, idea.entry, t2, idea.tp1, Faint(InpZoneTP1, InpZoneOpacity));
   PutRect(ZPRE + "T2",  t1, idea.tp1,   t2, idea.tp2, Faint(InpZoneTP2, InpZoneOpacity));
   PutLine(ZPRE + "LEN", t1, t3, idea.entry, Faint(sig,        InpLineOpacity));
   PutLine(ZPRE + "LSL", t1, t3, idea.sl,    Faint(InpLineSL,  InpLineOpacity));
   PutLine(ZPRE + "LT1", t1, t3, idea.tp1,   Faint(InpLineTP1, InpLineOpacity));
   PutLine(ZPRE + "LT2", t1, t3, idea.tp2,   Faint(InpLineTP2, InpLineOpacity));
   PutLabel(ZPRE + "NEN", tl, idea.entry, "Entry  " + DoubleToString(idea.entry, _Digits) + "  " + side + status, sig);
   PutLabel(ZPRE + "NSL", tl, idea.sl,    "SL  "  + DoubleToString(idea.sl,  _Digits), InpLineSL);
   PutLabel(ZPRE + "NT1", tl, idea.tp1,   "TP1  " + DoubleToString(idea.tp1, _Digits), InpLineTP1);
   PutLabel(ZPRE + "NT2", tl, idea.tp2,   "TP2  " + DoubleToString(idea.tp2, _Digits), InpLineTP2);
  }

void HLine(const string name, const double price, const color clr, const ENUM_LINE_STYLE style)
  {
   string n = LPRE + name;
   if(price <= 0) { ObjectDelete(0, n); return; }
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, n, OBJPROP_BACK, true);
     }
   ObjectSetDouble(0, n, OBJPROP_PRICE, price);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, n, OBJPROP_STYLE, style);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, name + " " + DoubleToString(price, _Digits));
  }

void DrawLevels()
  {
   HLine("PDH", iHigh(_Symbol, PERIOD_D1, 1), clrAqua,    STYLE_DOT);
   HLine("PDL", iLow(_Symbol,  PERIOD_D1, 1), clrAqua,    STYLE_DOT);
   HLine("PWH", iHigh(_Symbol, PERIOD_W1, 1), clrMagenta, STYLE_DASH);
   HLine("PWL", iLow(_Symbol,  PERIOD_W1, 1), clrMagenta, STYLE_DASH);
  }

// high / low of the most recent session (current or last completed); hours are UTC
bool SessionHL(const datetime &time[], const double &high[], const double &low[],
               const int sH, const int eH, double &hi, double &lo)
  {
   long off    = (long)gOffset * 3600;
   long nowUtc = (long)time[0] - off;
   long st     = nowUtc - nowUtc % 86400 + (long)sH * 3600;
   if(st > nowUtc) st -= 86400;
   int len = ((eH - sH) % 24 + 24) % 24;
   if(len == 0) len = 24;
   long en = st + (long)len * 3600;
   hi = -DBL_MAX;
   lo = DBL_MAX;
   for(int i = 0; i < gTotal; i++)
     {
      long u = (long)time[i] - off;
      if(u < st) break;
      if(u >= en) continue;
      hi = MathMax(hi, high[i]);
      lo = MathMin(lo, low[i]);
     }
   return (hi > -DBL_MAX);
  }

//+------------------------------------------------------------------+
//| Panel                                                            |
//+------------------------------------------------------------------+
#define C_HEAD C'130,215,255'
#define C_LBL  C'235,240,248'
#define C_TXT  C'255,255,255'
#define C_UP   C'60,255,150'
#define C_DN   C'255,95,95'
#define C_WARN C'255,225,60'
#define C_INFO C'110,245,255'
#define C_MUTE C'190,196,208'

int gRow = 0, gMaxRow = 0;

void PText(const string name, const int x, const int y, const string text, const color clr,
           const int size, const ENUM_ANCHOR_POINT anchor, const string font)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

int RowY() { return InpPanelY + 44 + gRow * InpPanelRowH; }

void PSection(const string title)
  {
   if(gRow > 0) gRow++;
   PText(PPRE + "L" + IntegerToString(gRow), InpPanelX + 10, RowY(), title, C_HEAD, InpPanelFont, ANCHOR_LEFT_UPPER, "Arial Bold");
   ObjectDelete(0, PPRE + "V" + IntegerToString(gRow));
   gRow++;
  }

void PRow(const string label, const string value, const color vc)
  {
   PText(PPRE + "L" + IntegerToString(gRow), InpPanelX + 12, RowY(), label, C_LBL, InpPanelFont, ANCHOR_LEFT_UPPER, "Arial");
   PText(PPRE + "V" + IntegerToString(gRow), InpPanelX + InpPanelWidth - 12, RowY(), value, vc, InpPanelFont, ANCHOR_RIGHT_UPPER, "Arial");
   gRow++;
  }

string Px(const double p) { return DoubleToString(p, _Digits); }

int CountEv(const int kind, const datetime from)
  {
   int c = 0;
   for(int i = ArraySize(gEvT) - 1; i >= 0; i--)
      if(gEvK[i] == kind && gEvT[i] >= from) c++;
   return c;
  }

string WinRate(const int wins, const int losses, color &c)
  {
   int n = wins + losses;
   if(n == 0) { c = C_MUTE; return "-"; }
   double wr = 100.0 * wins / n;
   c = (wr >= 50 ? C_UP : C_DN);
   return StringFormat("%.0f%%  (%d/%d)", wr, wins, n);
  }

string SessionNow(color &c)
  {
   MqlDateTime g;
   TimeToStruct(TimeGMT(), g);
   if(g.day_of_week == 6 || (g.day_of_week == 0 && g.hour < 21) || (g.day_of_week == 5 && g.hour >= 21))
     { c = C_MUTE; return "CLOSED"; }
   int h = g.hour;
   string name;
   if(h >= 12 && h < 16)      name = "LONDON + NY";
   else if(h >= 7 && h < 12)  name = "LONDON";
   else if(h >= 16 && h < 21) name = "NEW YORK";
   else                       name = (h >= 21 ? "SYDNEY" : "ASIA");
   bool on = InSession(TimeTradeServer());
   c = (on ? C_UP : C_MUTE);
   return name + (on ? "  (trading)" : "  (off)");
  }

string TrendText(const int t, color &c)
  {
   if(t > 0) { c = C_UP; return "UP"; }
   if(t < 0) { c = C_DN; return "DOWN"; }
   c = C_WARN;
   return "NONE";
  }

bool gPanelHidden = false;
uint gLastClickMs = 0;
int  gLastClickX = 0, gLastClickY = 0;

string HideKey() { return "ZVF_panel_hidden_" + IntegerToString(ChartID()); }

void DrawPanel(const bool force = false)
  {
   if(!InpShowPanel) return;
   if(gPanelHidden)
     {
      if(ObjectFind(0, PPRE + "HINT") >= 0) return;
      ObjectsDeleteAll(0, PPRE);
      gMaxRow = 0;
      PText(PPRE + "HINT", InpPanelX + 2, InpPanelY, "ZION  (double-click chart to show panel)", C'120,130,150',
            InpPanelFont - 1, ANCHOR_LEFT_UPPER, "Arial");
      return;
     }
   uint ms = GetTickCount();
   if(!force && gLastPanelMs != 0 && ms - gLastPanelMs < 500) return;
   gLastPanelMs = ms;

   string bg = PPRE + "BG";
   if(ObjectFind(0, bg) < 0)
     {
      ObjectsDeleteAll(0, PPRE);
      gMaxRow = 0;
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
     }

   color c;
   string v;
   gRow = 0;

   string st; color sc;
   if(idea.state == IDEA_PENDING)   { st = (idea.dir > 0 ? "PENDING BUY" : "PENDING SELL"); sc = C_WARN; }
   else if(idea.state == IDEA_LIVE) { st = (idea.dir > 0 ? "LIVE BUY" : "LIVE SELL"); sc = SignalColor(idea.dir, idea.grade); }
   else                             { st = "WAIT"; sc = C_MUTE; }
   PText(PPRE + "T1", InpPanelX + 10, InpPanelY + 6, "ZION VWMA FUSION", C_TXT, InpPanelFont + 3, ANCHOR_LEFT_UPPER, "Arial Bold");
   PText(PPRE + "T3", InpPanelX + 10, InpPanelY + 26, _Symbol + "  " + StringSubstr(EnumToString(_Period), 7), C_LBL, InpPanelFont, ANCHOR_LEFT_UPPER, "Arial");
   PText(PPRE + "T4", InpPanelX + InpPanelWidth - 10, InpPanelY + 26, st, sc, InpPanelFont, ANCHOR_RIGHT_UPPER, "Arial Bold");

   datetime tNow = iTime(_Symbol, _Period, 0);
   PSection("MARKET");
   v = SessionNow(c); PRow("Session", v, c);
   int tr = TrendDirAt(tNow);
   v = TrendText(tr, c);
   PRow("Trend " + StringSubstr(EnumToString(InpTrendTF1), 7) + "+" + StringSubstr(EnumToString(InpTrendTF2), 7), v, c);
   bool d1b = D1Against(1, tNow), d1s = D1Against(-1, tNow);
   PRow("D1 vs EMA" + IntegerToString(InpD1Ema), (d1s ? "ABOVE" : (d1b ? "BELOW" : "-")), (d1s ? C_UP : (d1b ? C_DN : C_MUTE)));
   if(gTotal > 2)
     {
      int sb = (int)ScoreB[1], ss = (int)ScoreS[1];
      PRow("Momentum B / S", StringFormat("%d / %d  (need %d)", sb, ss, InpMinScore),
           (sb >= InpMinScore ? C_UP : (ss >= InpMinScore ? C_DN : C_MUTE)));
      double up = InpRsiMid, dn = 100.0 - InpRsiMid;
      PRow("RSI " + IntegerToString(InpRsiFast) + " / " + IntegerToString(InpRsiSlow),
           DoubleToString(R7[1], 1) + " / " + DoubleToString(R14[1], 1),
           (R7[1] > up && R14[1] > up ? C_UP : (R7[1] < dn && R14[1] < dn ? C_DN : C_MUTE)));
     }
   PRow("ATR " + IntegerToString(InpATRPeriod), DoubleToString(ATRAt(1), _Digits), C_TXT);
   double spr = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / Pt();
   PRow("Spread", StringFormat("%.0f pts", spr), (InpMaxSpreadPts > 0 && spr > InpMaxSpreadPts ? C_DN : C_TXT));

   PSection("LEVELS");
   PRow("PDH / PDL", Px(iHigh(_Symbol, PERIOD_D1, 1)) + " / " + Px(iLow(_Symbol, PERIOD_D1, 1)), C_INFO);
   PRow("PWH / PWL", Px(iHigh(_Symbol, PERIOD_W1, 1)) + " / " + Px(iLow(_Symbol, PERIOD_W1, 1)), C'255,120,255');
   PRow("Asia H / L",   gAsiaOK ? Px(gAsiaH) + " / " + Px(gAsiaL) : "-", C_TXT);
   PRow("London H / L", gLonOK  ? Px(gLonH)  + " / " + Px(gLonL)  : "-", C_TXT);
   PRow("NY H / L",     gNyOK   ? Px(gNyH)   + " / " + Px(gNyL)   : "-", C_TXT);

   datetime ds = TimeCurrent() - TimeCurrent() % 86400;
   int t1 = CountEv(EV_TP1, ds), t2 = CountEv(EV_TP2, ds), tsl = CountEv(EV_SL, ds), tl = CountEv(EV_LOSS, ds);
   PSection("TODAY");
   PRow("Signals", IntegerToString(CountEv(EV_SIG, ds)), C_INFO);
   PRow("TP1 / TP2 / SL", StringFormat("%d / %d / %d", t1, t2, tsl), C_TXT);
   v = WinRate(t1, tl, c); PRow("Win rate (TP1)", v, c);

   PSection("HISTORY (" + IntegerToString(InpHistoryBars) + " BARS)");
   PRow("Signals B / S", StringFormat("%d  (%d / %d)", gCntBuy + gCntSell, gCntBuy, gCntSell), C_INFO);
   PRow("TP1 / TP2 / SL / BE", StringFormat("%d / %d / %d / %d", gCntTP1, gCntTP2, gCntSL, gCntBE), C_TXT);
   v = WinRate(gCntTP1, gCntLoss, c); PRow("Win rate (TP1)", v, c);
   v = WinRate(gWinG[GRADE_A], gLossG[GRADE_A], c); PRow("  grade A", v, c);
   v = WinRate(gWinG[GRADE_B], gLossG[GRADE_B], c); PRow("  grade B", v, c);
   v = WinRate(gWinG[GRADE_C], gLossG[GRADE_C], c); PRow("  grade C", v, c);

   PSection("CURRENT SIGNAL");
   if(idea.state == IDEA_IDLE)
      PRow("Status", "no active signal", C_MUTE);
   else
     {
      PRow("Status", (idea.dir > 0 ? "BUY " : "SELL ") + GradeName(idea.grade) + "  " + st, SignalColor(idea.dir, idea.grade));
      PRow("Entry", Px(idea.entry), C_TXT);
      PRow("SL", Px(idea.sl), InpLineSL);
      PRow("TP1 / TP2", Px(idea.tp1) + " / " + Px(idea.tp2), InpLineTP1);
     }

   for(int i = gRow; i < gMaxRow; i++)
     {
      ObjectDelete(0, PPRE + "L" + IntegerToString(i));
      ObjectDelete(0, PPRE + "V" + IntegerToString(i));
     }
   gMaxRow = gRow;

   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, InpPanelX);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, InpPanelY);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, InpPanelWidth);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, 44 + gRow * InpPanelRowH + 10);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'24,30,46');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, C'80,110,160');
   ObjectSetInteger(0, bg, OBJPROP_BACK, false);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
  }

//+------------------------------------------------------------------+
//| Click the panel title to hide it; double-click the chart to       |
//| bring it back. The state is remembered per chart.                 |
//+------------------------------------------------------------------+
void SetPanelHidden(const bool hidden)
  {
   gPanelHidden = hidden;
   GlobalVariableSet(HideKey(), hidden ? 1 : 0);
   ObjectsDeleteAll(0, PPRE);
   gMaxRow = 0;
   gLastPanelMs = 0;
   DrawPanel(true);
   ChartRedraw(0);
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_CLICK || !InpShowPanel) return;
   int  x = (int)lparam, y = (int)dparam;
   uint now = GetTickCount();
   if(!gPanelHidden)
     {
      if(x >= InpPanelX && x <= InpPanelX + InpPanelWidth && y >= InpPanelY && y <= InpPanelY + 40)
        {
         SetPanelHidden(true);
         gLastClickMs = 0;   // the hiding click does not count towards a double-click
         return;
        }
     }
   else if(gLastClickMs != 0 && now - gLastClickMs <= 450 &&
           MathAbs(x - gLastClickX) <= 12 && MathAbs(y - gLastClickY) <= 12)
     {
      SetPanelHidden(false);
      gLastClickMs = 0;
      return;
     }
   gLastClickMs = now;
   gLastClickX = x;
   gLastClickY = y;
  }

//+------------------------------------------------------------------+
//| Alerts                                                           |
//+------------------------------------------------------------------+
void FireAlert(const string what, const datetime barTime)
  {
   string tf = StringSubstr(EnumToString(_Period), 7);
   string lv = "";
   if(idea.state != IDEA_IDLE)
      lv = StringFormat(" | EN %s SL %s TP1 %s TP2 %s", Px(idea.entry), Px(idea.sl), Px(idea.tp1), Px(idea.tp2));
   string msg = StringFormat("ZionVWMA %s %s %s | %s%s", what, _Symbol, tf,
                             TimeToString(barTime, TIME_DATE|TIME_MINUTES), lv);
   if(InpAlertPopup) Alert(msg);
   if(InpAlertSound) PlaySound(InpSoundFile);
   if(InpAlertPush)  SendNotification(msg);
   if(InpAlertEmail) SendMail("ZionVWMA " + what + " " + _Symbol, msg);
  }

void CheckAlerts(const datetime barTime)
  {
   if(barTime == 0) return;
   if(InpAlertFill && idea.state == IDEA_LIVE && InpPendingOn && idea.fillTime == barTime && gLastFill != barTime)
     {
      gLastFill = barTime;
      FireAlert(idea.dir > 0 ? "FILLED BUY" : "FILLED SELL", barTime);
     }
   if(barTime == gLastAlert) return;
   bool buy = (BuyBuf[1] != EMPTY_VALUE), sell = (SellBuf[1] != EMPTY_VALUE);
   if(!buy && !sell) return;
   gLastAlert = barTime;
   string side = (buy ? "BUY " : "SELL ") + GradeName(idea.grade) + (InpPendingOn ? " PEND" : "");
   FireAlert(side, barTime);
  }

//+------------------------------------------------------------------+
//| Main                                                             |
//+------------------------------------------------------------------+
bool Ready(const int h, const int need) { return (h != INVALID_HANDLE && BarsCalculated(h) >= need); }

void CopySeries(const int h, const int count, double &dst[])
  {
   double tmp[];
   ArraySetAsSeries(tmp, true);
   int n = CopyBuffer(h, 0, 0, count, tmp);
   for(int k = 0; k < n; k++)
      dst[k] = tmp[k];
  }

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
   int warm = InpVwmaSlow + InpSlopeBars + InpSwingBars + 20;
   if(rates_total < warm + 10) return 0;
   if(!Ready(hRsiF, rates_total) || !Ready(hRsiS, rates_total) || !Ready(hATR, rates_total) ||
      !Ready(hT1F, 1) || !Ready(hT1S, 1) || !Ready(hT2F, 1) || !Ready(hT2S, 1) || !Ready(hD1, 1))
      return (prev_calculated > 0 ? prev_calculated : 0);

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(tick_volume, true);
   ArraySetAsSeries(spread, true);
   gTotal = rates_total;

   bool full = (prev_calculated <= 0 || prev_calculated > rates_total);
   int  maxSh = (int)MathMin(rates_total - 1, InpHistoryBars + warm);
   int  limit;
   if(full)
     {
      gOffset = ServerOffset();
      ArrayInitialize(VS, EMPTY_VALUE);     ArrayInitialize(VM, EMPTY_VALUE);    ArrayInitialize(VF, EMPTY_VALUE);
      ArrayInitialize(BuyBuf, EMPTY_VALUE); ArrayInitialize(SellBuf, EMPTY_VALUE);
      ArrayInitialize(BuyClr, 0);           ArrayInitialize(SellClr, 0);
      ArrayInitialize(R7, EMPTY_VALUE);     ArrayInitialize(R14, EMPTY_VALUE);
      ArrayInitialize(ScoreB, 0);           ArrayInitialize(ScoreS, 0);
      ObjectsDeleteAll(0, MPRE);
      ObjectsDeleteAll(0, ZPRE);
      ResetIdea();
      ResetZone();
      ResetCounts();
      gLastBar = 0;
      gLastBuy = gLastSell = gLastFiltB = gLastFiltS = 0;
      limit = maxSh;
     }
   else
      limit = (int)MathMin(maxSh, rates_total - prev_calculated + 1);

   //--- RSI, VWMA and momentum score
   CopySeries(hRsiF, limit + 1, R7);
   CopySeries(hRsiS, limit + 1, R14);
   for(int sh = limit; sh >= 0; sh--)
     {
      VS[sh] = Vwma(sh, InpVwmaSlow, open, high, low, close, tick_volume);
      VM[sh] = Vwma(sh, InpVwmaMid,  open, high, low, close, tick_volume);
      VF[sh] = Vwma(sh, InpVwmaFast, open, high, low, close, tick_volume);
     }
   for(int sh = limit; sh >= 0; sh--)
     {
      ScoreB[sh] = MomScore(sh, 1, close[sh]);
      ScoreS[sh] = MomScore(sh, -1, close[sh]);
     }
   BuyBuf[0] = SellBuf[0] = EMPTY_VALUE;

   //--- signal engine: every closed bar exactly once, oldest first
   int start = (full ? (int)MathMin(InpHistoryBars, maxSh - warm) : limit);
   if(start < 1) start = 1;
   for(int i = start; i >= 1; i--)
     {
      if(time[i] <= gLastBar) continue;
      gLastBar = time[i];
      BuyBuf[i] = SellBuf[i] = EMPTY_VALUE;

      Candle bar;
      bar.o = open[i]; bar.h = high[i]; bar.l = low[i]; bar.c = close[i];
      bar.t = time[i];
      bar.valid = (bar.h > bar.l);
      bar.spr = (spread[i] > 0 ? spread[i] * _Point : SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point);

      int trendDir = TrendDirAt(bar.t);
      ManageIdea(bar, trendDir);
      if(!bar.valid) continue;

      //--- hard gates
      bool gate = InSession(bar.t);
      if(InpMaxSpreadPts > 0 && spread[i] > 0 && spread[i] * _Point > InpMaxSpreadPts * Pt()) gate = false;
      if(!gate) continue;

      bool trigB = (ScoreB[i] >= InpMinScore) && BaseTrigger(1,  bar, RecentExt(i,  1, high, low));
      bool trigS = (ScoreS[i] >= InpMinScore) && BaseTrigger(-1, bar, RecentExt(i, -1, high, low));
      if(!trigB && !trigS) continue;

      double buf = StopBuffer(i, bar.spr);
      double eB = 0, sB = 0, t1B = 0, t2B = 0, eS = 0, sS = 0, t1S = 0, t2S = 0;
      if(trigB && !CalcLevels(1,  bar, buf, eB, sB, t1B, t2B)) trigB = false;
      if(trigS && !CalcLevels(-1, bar, buf, eS, sS, t1S, t2S)) trigS = false;

      string whyB = "", whyS = "";
      int gB = (trigB ? SignalGrade(1,  bar, i, trendDir, eB, t1B, (int)ScoreB[i], whyB) : GRADE_NONE);
      int gS = (trigS ? SignalGrade(-1, bar, i, trendDir, eS, t1S, (int)ScoreS[i], whyS) : GRADE_NONE);

      bool free  = (idea.state == IDEA_IDLE || (InpReplacePending && idea.state == IDEA_PENDING));
      bool coolB = Cooled(bar.t, gLastBuy,  InpCooldown) && Cooled(bar.t, gLastSell, 3);
      bool coolS = Cooled(bar.t, gLastSell, InpCooldown) && Cooled(bar.t, gLastBuy,  3);

      if(free && GradeOn(gB) && coolB)
        {
         if(idea.state == IDEA_PENDING) EndIdea(" [REPLACED]");
         BuyBuf[i] = low[i];
         BuyClr[i] = gB;
         gLastBuy  = bar.t;
         ArmIdea(1, bar, gB, trendDir, eB, sB, t1B, t2B);
         gCntBuy++; AddEv(EV_SIG, bar.t);
        }
      else if(free && GradeOn(gS) && coolS)
        {
         if(idea.state == IDEA_PENDING) EndIdea(" [REPLACED]");
         SellBuf[i] = high[i];
         SellClr[i] = gS;
         gLastSell  = bar.t;
         ArmIdea(-1, bar, gS, trendDir, eS, sS, t1S, t2S);
         gCntSell++; AddEv(EV_SIG, bar.t);
        }
      else if(InpShowFiltered)
        {
         if(gB != GRADE_NONE && !GradeOn(gB) && Cooled(bar.t, gLastFiltB, InpCooldown))
           { gLastFiltB = bar.t; FilteredMark(bar.t, low[i], 1, gB, whyB); }
         else if(gS != GRADE_NONE && !GradeOn(gS) && Cooled(bar.t, gLastFiltS, InpCooldown))
           { gLastFiltS = bar.t; FilteredMark(bar.t, high[i], -1, gS, whyS); }
        }
     }

   //--- session ranges for the panel
   gAsiaOK = SessionHL(time, high, low, 0,  7,  gAsiaH, gAsiaL);
   gLonOK  = SessionHL(time, high, low, 7,  16, gLonH,  gLonL);
   gNyOK   = SessionHL(time, high, low, 12, 21, gNyH,   gNyL);

   if(InpShowLevels) DrawLevels();
   DrawLiveZone();
   DrawPanel();

   if(full)
     {
      gLastAlert = time[1];   // no alerts for history on load
      gLastFill  = time[1];
     }
   else
      CheckAlerts(time[1]);

   return rates_total;
  }
//+------------------------------------------------------------------+
