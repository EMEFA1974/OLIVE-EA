//+------------------------------------------------------------------+
//|                                           Mt.ZionPro_Fusion.mq5  |
//|                                                                  |
//| Mt.ZionPro signal engine (MTF bias, EMA trend, ATR / location,   |
//| strict trigger, pending entry, re-entry, zones, stats panel)     |
//| fused with the VWMA RSI Score (four VWMAs on High weighted by    |
//| tick volume + three RSIs -> 5-point score, OB/OS exhaustion,     |
//| session / day / week levels).                                    |
//|                                                                  |
//| Grades: A = passes every enabled filter, B = fails one,          |
//|         C = fails two or more. Each grade has its own toggle.    |
//| C signals must also pass the Grade C filter (score, no counter-  |
//| trend, no RSI exhaustion, momentum, real trigger candle); a C    |
//| that fails it is shown as a grey "Cx" mark and never armed.      |
//|                                                                  |
//| Buffers 0-3 (Buy / Sell / ReBuy / ReSell) keep the Mt.ZionPro    |
//| layout; buffers 4-7 hold the VWMAs (calculated, not drawn).      |
//+------------------------------------------------------------------+
#property copyright "Mt.ZionPro Fusion"
#property link      ""
#property version   "2.00"
#property description "Mt.ZionPro engine + VWMA/RSI score. Grade A/B/C toggles, filtered Grade C, hollow arrows."
#property indicator_chart_window
#property indicator_buffers 10
#property indicator_plots   8

#property indicator_label1  "Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrAqua
#property indicator_width1  4

#property indicator_label2  "Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrMagenta
#property indicator_width2  4

#property indicator_label3  "ReBuy"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrAqua
#property indicator_width3  3

#property indicator_label4  "ReSell"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrMagenta
#property indicator_width4  3

#property indicator_label5  "VWMA High 1"
#property indicator_type5   DRAW_NONE
#property indicator_color5  clrRed
#property indicator_width5  2

#property indicator_label6  "VWMA High 2"
#property indicator_type6   DRAW_NONE
#property indicator_color6  clrOrange
#property indicator_width6  2

#property indicator_label7  "VWMA High 3"
#property indicator_type7   DRAW_NONE
#property indicator_color7  clrYellow
#property indicator_width7  1

#property indicator_label8  "VWMA High 4"
#property indicator_type8   DRAW_NONE
#property indicator_color8  clrLime
#property indicator_width8  1

enum ENUM_PEND_TYPE
  {
   PEND_LIMIT = 0,   // pullback (buy below / sell above)
   PEND_STOP  = 1    // confirmation break (buy above / sell below)
  };

enum ENUM_CHECK4_PRICE
  {
   CHECK4_CLOSE = 0, // Close
   CHECK4_HIGH  = 1  // High
  };

enum ENUM_GRADE
  {
   GRADE_A = 0,   // passes every enabled quality filter
   GRADE_B = 1,   // fails one filter
   GRADE_C = 2    // fails two or more filters
  };
#define GRADE_NONE 3
#define GRADE_CX   4   // grade C rejected by the Grade C filter

// hollow (outline) Wingdings arrows
#define ARROW_UP_HOLLOW 241
#define ARROW_DN_HOLLOW 242

input group "=== Timeframes ==="
input ENUM_TIMEFRAMES InpTF_D  = PERIOD_D1;
input ENUM_TIMEFRAMES InpTF_H4 = PERIOD_H4;
input ENUM_TIMEFRAMES InpTF_H1 = PERIOD_H1;
input ENUM_TIMEFRAMES InpTF_M5 = PERIOD_M5;

input group "=== Signal Quality ==="
input int    InpMinAlign     = 2;
input double InpMinBodyRatio = 0.25;
input double InpClosePos     = 0.55;
input int    InpSwingLook    = 2;
input int    InpCooldown     = 8;
input bool   InpRequireD     = false;
input bool   InpRequireH4    = true;
input bool   InpUseM5Trigger = false;
input bool   InpAutoDigits   = true;   // 3/5-digit brokers: point inputs are scaled x10 (same $ distances on 2- and 3-digit XAUUSD)

input group "=== Pending Entry ==="
input bool           InpPendingOn       = true;
input ENUM_PEND_TYPE InpPendingType     = PEND_LIMIT;
input int            InpPendingPts      = 40;    // minimum distance in points
input double         InpPendingRetrace  = 0.40;  // fraction of signal candle range
input bool           InpPendingUseRange = true;  // use max(points, range*retrace)
input int            InpPendingExpire   = 12;    // cancel pending after N closed bars
input int            InpMinSLGapPts     = 15;    // keep pending entry this far from SL

input group "=== Re-entry after SL ==="
input bool   InpReentryOn      = true;
input int    InpSLBufferPts    = 20;
input double InpSLWidenPct     = 100.0;  // widen the SL by this % of the entry-SL distance (0 = off). TP1/TP2 keep the original R. Set the same in Ind and EA
input double InpRR1            = 1.0;   // TP1 R-multiple
input double InpRR2            = 2.0;   // TP2 R-multiple
input int    InpMaxReentry     = 1;     // one re-entry at most
input int    InpReentryWindow  = 24;
input int    InpReentryCool    = 3;
input bool   InpSpreadAware    = true;  // fills / SL / TP use the ask where the broker does (buy entries, sell exits)

input group "=== Trend Filter (EMA, replaces the one-candle bias vote) ==="
input bool            InpFiltOn     = true;        // on = EMA trend on TF1 AND TF2 must agree with the trade (legacy candle vote is skipped)
input ENUM_TIMEFRAMES InpFiltTF1    = PERIOD_H1;
input ENUM_TIMEFRAMES InpFiltTF2    = PERIOD_H4;
input int             InpFiltFast   = 50;          // TF trend up = EMA fast > EMA slow and close > EMA slow
input int             InpFiltSlow   = 200;
input bool            InpD1FilterOn = true;        // D1 must not be against the trade
input int             InpD1EmaP     = 50;          // D1 against a buy = last D1 close below this D1 EMA

input group "=== ATR / Location Filter ==="
input int    InpATRPeriod   = 14;                  // ATR on the chart timeframe
input bool   InpATROn       = true;                // signal candle range must be between min and max x ATR
input double InpMinRangeATR = 0.6;                 // smaller = noise
input double InpMaxRangeATR = 2.5;                 // larger = exhaustion
input bool   InpLocationOn  = true;                // skip signals that chase price far from value
input int    InpLocEmaP     = 21;                  // chart-TF EMA used as value
input double InpMaxExtATR   = 1.5;                 // max distance close <-> EMA in ATR
input bool   InpATRStopOn   = true;                // SL buffer = max(InpSLBufferPts, ATR x k, spread x m)
input double InpSLBufATR    = 0.3;
input double InpSLBufSpread = 2.0;

input group "=== Strict Trigger ==="
input bool   InpStrictOn    = true;                // strong displacement through a real swing, or a real pin bar
input double InpStrictBody  = 0.50;                // min body / range
input double InpStrictClose = 0.70;                // close in the top (buy) / bottom (sell) 30% of the candle
input int    InpSwingBars   = 15;                  // swing to break is searched within this many bars
input int    InpFractalSide = 2;                   // bars on each side that make a swing point
input double InpPinWickMult = 2.0;                 // pin bar: rejection wick >= this x body
input double InpPinWickPct  = 0.55;                // and >= this share of the candle range
input int    InpPinSweep    = 3;                   // and the wick takes out the low/high of the previous N bars

input group "=== VWMA / RSI Score ==="
input bool              InpScoreOn     = true;          // score below InpMinScore counts as a failed grade filter
input int               InpMinScore    = 4;             // score needed in the trade direction (0-5)
input bool              InpObOsOn      = true;          // RSI beyond OB (buy) / OS (sell) counts as a failed grade filter
input bool              InpObOsAllRsi  = false;         // false = only the slow RSI1 is checked (fast RSIs spike on every strong trigger candle)
input int               InpVWMA1       = 85;            // VWMA1 period (red, scored vs price)
input int               InpVWMA2       = 37;            // VWMA2 period (orange)
input int               InpVWMA3       = 18;            // VWMA3 period (yellow, scored vs VWMA2)
input int               InpVWMA4       = 6;             // VWMA4 period (green, used by the C momentum check)
input ENUM_CHECK4_PRICE InpCheck4Price = CHECK4_CLOSE;  // price compared with VWMA1
input int               InpRSI1        = 14;            // RSI1 period
input int               InpRSI2        = 9;             // RSI2 period
input int               InpRSI3        = 7;             // RSI3 period (fast, used by the C momentum check)
input double            InpRsiMid      = 55.0;          // bull vote RSI > this, bear vote RSI < 100 - this
input double            InpRsiOB       = 80.0;          // RSI overbought
input double            InpRsiOS       = 20.0;          // RSI oversold

input group "=== Signal Flow ==="
input bool       InpOppOverride = true;            // a fresh opposite signal cancels a pending order or an SL re-entry wait (live trades still block)
input bool       InpSoftChase   = true;            // range / extended / exhausted together count as at most ONE failed filter
input bool       InpShowDiag    = true;            // buy / sell diagnostics on the panel

input group "=== Signal Grade ==="
input bool       InpGradeA   = true;               // A-grade signals (pass every filter) become signals (zone / alert / EA trade)
input bool       InpGradeB   = true;               // B-grade signals (fail one filter) become signals
input bool       InpGradeC   = false;              // allow Grade C trades (fail two or more filters); they must also pass the Grade C filter
input bool       InpReNeedA  = false;              // true = re-entries only on a fresh A-grade trigger (false = same grades as the toggles)
input bool       InpShowFiltered = true;          // grey grade letter on signals whose grade is toggled off / rejected (no zone, no alert)
input color      InpFiltColor    = clrSilver;
input bool       InpGradeTag     = true;          // grade letter under / over each signal arrow
input double     InpTagOffATR    = 0.8;           // grade letter distance from the candle, in ATR

input group "=== Grade C Filter (removes weak C signals) ==="
input bool   InpCFilterOn   = true;                // C signals must pass every enabled check below
input int    InpCMaxFails   = 3;                   // reject C if it fails more than this many grade filters
input int    InpCMinScore   = 4;                   // reject C if the VWMA/RSI score in its direction is below this (0-5)
input bool   InpCNoCounter  = true;                // reject C if the EMA trend (TF1 + TF2) points against it (neutral is allowed)
input bool   InpCNoD1       = true;                // reject C if the D1 close is on the wrong side of the D1 EMA
input bool   InpCNoExhaust  = true;                // reject C if any RSI is beyond OB (buy) / OS (sell)
input bool   InpCMomentum   = true;                // C needs fast RSI turning its way and close beyond VWMA4
input bool   InpCNeedCandle = true;                // C needs a strict trigger candle (displacement through a swing, or a pin bar)

input group "=== Trade Management (set the same as the EA) ==="
input bool   InpManageOn     = true;    // EA closes part at TP1 and lets the rest run to TP2
input bool   InpMoveBE       = true;    // EA moves the SL to entry after TP1 (zone and stats follow it)

input group "=== Alerts ==="
input bool   InpAlertPopup   = true;
input bool   InpAlertSound   = true;
input bool   InpAlertPush    = true;
input bool   InpAlertEmail   = false;
input string InpSoundFile    = "alert.wav";
input bool   InpAlertOnLoad  = false;
input bool   InpAlertReentry = true;
input bool   InpAlertFill    = true;    // alert when pending is filled

input group "=== Visuals ==="
input bool   InpShowPanel    = true;
input color  InpBuyColor     = clrAqua;      // buy arrows (hollow)
input color  InpSellColor    = clrMagenta;   // sell arrows (hollow)
input color  InpReBuyColor   = clrAqua;      // re-entry buy arrows (hollow, thinner, further out)
input color  InpReSellColor  = clrMagenta;   // re-entry sell arrows (hollow, thinner, further out)
input int    InpArrowWidth   = 4;            // arrow size 1-5 (re-entry arrows are one size smaller)
input int    InpArrowShift   = 12;
input int    InpPanelX       = 4;        // left edge
input int    InpPanelY       = 20;       // top-left (EA panel goes bottom-left). Drag to move.
input int    InpPanelWidth   = 270;
input string InpPanelFontName = "Segoe UI Semilight"; // thin font for labels and values (thinner: "Segoe UI Light")
input string InpPanelFontHead = "Segoe UI";           // headings / title (e.g. "Segoe UI", "Calibri Light", "Arial")
input int    InpPanelFont    = 8;
input int    InpPanelTitleFont = 8;      // size of the panel name
input int    InpPanelRowH    = 15;
input ENUM_TIMEFRAMES InpTrendTF = PERIOD_H1;   // timeframe for the EMA trend line on the panel
input int    InpTrendFast    = 50;
input int    InpTrendSlow    = 200;

input group "=== Zones ==="
input bool   InpShowZones     = true;
input bool   InpKeepLastZone  = false;   // true = keep a finished zone on the chart until the next signal
input bool   InpHideAtTP1     = true;    // zone is mitigated (removed) when TP1 is hit; false = keep until TP2
input int    InpZoneRightBars = 18;       // box extends this many bars past the current bar
input int    InpLabelBars     = 16;       // extra line length to the right of the box for the labels
input int    InpZoneFontSize  = 7;
input string InpZoneFont      = "Segoe UI Semilight"; // thin font for zone labels (e.g. "Segoe UI Light", "Calibri Light", "Arial")
input bool   InpAutoChartShift = true;    // turn on chart shift so the box and labels have room
input int    InpChartShiftPct = 30;       // chart shift size in % of chart width (10-50)
input color  InpZoneSL        = C'220,50,50';
input color  InpZoneTP1       = C'30,170,100';
input color  InpZoneTP2       = C'40,100,230';
input int    InpZoneOpacity   = 35;       // box opacity % (0-100): lower = fainter / more see-through
input int    InpLineOpacity   = 80;       // level line opacity % (0-100); labels stay full colour
input color  InpLineEntry     = C'235,235,235';
input color  InpLineSL        = C'255,100,100';
input color  InpLineTP1       = C'60,255,190';
input color  InpLineTP2       = C'120,200,255';

input group "=== Levels / Sessions ==="
input bool   InpShowLevels    = true;     // draw PDH/PDL and PWH/PWL lines
input color  InpPDColor       = clrSteelBlue;
input color  InpPWColor       = clrOrchid;
input bool   InpShowSessions  = true;     // session / day / week levels on the panel
input int    InpServerUtcOffset = 99;     // broker server time minus UTC in hours (99 = auto)
input int    InpSydS = 21;                // Sydney start hour (UTC)
input int    InpSydE = 6;                 // Sydney end hour (UTC)
input int    InpAsiS = 0;                 // Asian start hour (UTC)
input int    InpAsiE = 9;                 // Asian end hour (UTC)
input int    InpLonS = 7;                 // London start hour (UTC)
input int    InpLonE = 16;                // London end hour (UTC)
input int    InpNyS  = 12;                // New York start hour (UTC)
input int    InpNyE  = 21;                // New York end hour (UTC)

double BuyBuf[];
double SellBuf[];
double ReBuyBuf[];
double ReSellBuf[];
double V1[], V2[], V3[], V4[];   // VWMA lines on High (series indexing, like the arrow buffers)
double VL1[], VL4[];             // VWMA1 / VWMA4 on Low: sells are measured against these (mirror of buys vs High)

int gHR1 = INVALID_HANDLE, gHR2 = INVALID_HANDLE, gHR3 = INVALID_HANDLE;   // RSI handles

datetime lastBuyTime   = 0;
datetime lastSellTime  = 0;
datetime lastAlertBar  = 0;
datetime lastFillAlert = 0;
bool     allowAlerts   = false;
datetime gLastBar      = 0;      // last closed bar fed to the signal engine
datetime lastFiltB     = 0;      // last grey (grade toggled off) markers, for their own cooldown
datetime lastFiltS     = 0;

int gCntBuy = 0, gCntSell = 0, gCntTP1 = 0, gCntTP2 = 0, gCntSL = 0, gCntLoss = 0;

// signal outcome events, kept so the panel can count "today"
#define EV_SIG  0
#define EV_TP1  1
#define EV_TP2  2
#define EV_SL   3
#define EV_LOSS 4   // SL hit before TP1
datetime gEvT[];
int      gEvK[];

void AddEv(const int kind, const datetime t)
  {
   int n = ArraySize(gEvT);
   if(n >= 3000) { ArrayRemove(gEvT, 0, 1000); ArrayRemove(gEvK, 0, 1000); n = ArraySize(gEvT); }
   ArrayResize(gEvT, n + 1);
   ArrayResize(gEvK, n + 1);
   gEvT[n] = t;
   gEvK[n] = kind;
  }

#define PREFIX "MZF_"
#define ARPRE  "MZFAR_"
#define ZPRE   "MZFZN_"
#define LPRE   "MZFLV_"

enum IdeaState { IDEA_IDLE = 0, IDEA_PENDING, IDEA_LIVE, IDEA_SL_WAIT };

struct Idea
  {
   IdeaState state;
   int       dir;
   double    entry, sl, tp1, tp2;
   double    slR;        // original (not widened) SL: TP1/TP2 are measured from it
   datetime  signalTime, slTime, fillTime;
   int       reCount, slBarAge, pendAge;
   bool      tp1Done;
   bool      re;
   int       grade;      // GRADE_A / B / C
   int       armTrend;   // EMA trend when the idea was armed
  };
Idea idea;

// snapshot of the current (most recent) zone; only one is ever drawn
struct ZoneSnap
  {
   bool     valid;
   int      dir;
   bool     re;
   int      grade;
   double   entry, sl, tp1, tp2;
   datetime t1, tEnd;   // tEnd = 0 while the idea is still running
   string   status;
  };
ZoneSnap gz;

void ResetZone()
  {
   gz.valid = false;
   gz.dir = 0;
   gz.re = false;
   gz.grade = GRADE_NONE;
   gz.entry = gz.sl = gz.tp1 = gz.tp2 = 0;
   gz.t1 = gz.tEnd = 0;
   gz.status = "";
  }

struct Candle
  {
   double o,h,l,c;
   double spr;      // bar spread as a price (ask = bid + spr)
   datetime t;
   bool valid;
  };

struct Bias
  {
   int  dir;
   bool strong;
  };

Bias gD, gH4, gH1, gM5;
int  gScoreB = 0, gScoreS = 0;

int OnInit()
  {
   if(InpVWMA1 < 1 || InpVWMA2 < 1 || InpVWMA3 < 1 || InpVWMA4 < 1 || InpRSI1 < 1 || InpRSI2 < 1 || InpRSI3 < 1)
     {
      Print("Mt.ZionPro Fusion: all VWMA / RSI periods must be >= 1");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpMinScore < 0 || InpMinScore > 5 || InpCMinScore < 0 || InpCMinScore > 5)
     {
      Print("Mt.ZionPro Fusion: InpMinScore and InpCMinScore must be between 0 and 5");
      return(INIT_PARAMETERS_INCORRECT);
     }

   SetIndexBuffer(0, BuyBuf,    INDICATOR_DATA);
   SetIndexBuffer(1, SellBuf,   INDICATOR_DATA);
   SetIndexBuffer(2, ReBuyBuf,  INDICATOR_DATA);
   SetIndexBuffer(3, ReSellBuf, INDICATOR_DATA);
   SetIndexBuffer(4, V1,        INDICATOR_DATA);
   SetIndexBuffer(5, V2,        INDICATOR_DATA);
   SetIndexBuffer(6, V3,        INDICATOR_DATA);
   SetIndexBuffer(7, V4,        INDICATOR_DATA);
   SetIndexBuffer(8, VL1,       INDICATOR_CALCULATIONS);
   SetIndexBuffer(9, VL4,       INDICATOR_CALCULATIONS);
   ArraySetAsSeries(BuyBuf, true);
   ArraySetAsSeries(SellBuf, true);
   ArraySetAsSeries(ReBuyBuf, true);
   ArraySetAsSeries(ReSellBuf, true);
   ArraySetAsSeries(V1, true);
   ArraySetAsSeries(V2, true);
   ArraySetAsSeries(V3, true);
   ArraySetAsSeries(V4, true);
   ArraySetAsSeries(VL1, true);
   ArraySetAsSeries(VL4, true);

   // hollow outline arrows: aqua buys, magenta sells
   PlotIndexSetInteger(0, PLOT_ARROW, ARROW_UP_HOLLOW);
   PlotIndexSetInteger(1, PLOT_ARROW, ARROW_DN_HOLLOW);
   PlotIndexSetInteger(2, PLOT_ARROW, ARROW_UP_HOLLOW);
   PlotIndexSetInteger(3, PLOT_ARROW, ARROW_DN_HOLLOW);
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT,  InpArrowShift);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, -InpArrowShift);
   PlotIndexSetInteger(2, PLOT_ARROW_SHIFT,  InpArrowShift + 10);
   PlotIndexSetInteger(3, PLOT_ARROW_SHIFT, -(InpArrowShift + 10));
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpBuyColor);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpSellColor);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, InpReBuyColor);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, InpReSellColor);
   int aw = (int)MathMax(1, MathMin(5, InpArrowWidth));
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, aw);
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, aw);
   PlotIndexSetInteger(2, PLOT_LINE_WIDTH, MathMax(1, aw - 1));
   PlotIndexSetInteger(3, PLOT_LINE_WIDTH, MathMax(1, aw - 1));
   for(int p = 0; p < 8; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   for(int p = 4; p < 8; p++)                   // VWMAs are used by the score only, not drawn
      PlotIndexSetInteger(p, PLOT_DRAW_TYPE, DRAW_NONE);

   IndicatorSetString(INDICATOR_SHORTNAME, "Mt.ZionPro Fusion");
   gEmaFast = iMA(_Symbol, InpTrendTF, InpTrendFast, 0, MODE_EMA, PRICE_CLOSE);
   gEmaSlow = iMA(_Symbol, InpTrendTF, InpTrendSlow, 0, MODE_EMA, PRICE_CLOSE);
   if(!FiltersInit())
     {
      Print("Mt.ZionPro Fusion: could not create the filter indicators (EMA / ATR / RSI)");
      return(INIT_FAILED);
     }
   PanelInit();
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   lastAlertBar = 0;
   lastFillAlert = 0;
   allowAlerts  = InpAlertOnLoad;
   ResetIdea();
   ResetZone();
   ResetCounts();
   if(InpAutoChartShift)
     {
      ChartSetInteger(0, CHART_SHIFT, true);
      ChartSetDouble(0, CHART_SHIFT_SIZE, MathMax(10, MathMin(50, InpChartShiftPct)));
     }
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(gDrag) ChartSetInteger(0, CHART_MOUSE_SCROLL, gScrollWas);
   if(gEmaFast != INVALID_HANDLE) IndicatorRelease(gEmaFast);
   if(gEmaSlow != INVALID_HANDLE) IndicatorRelease(gEmaSlow);
   FiltersRelease();
   ObjectsDeleteAll(0, PREFIX);
   ObjectsDeleteAll(0, ARPRE);
   ObjectsDeleteAll(0, ZPRE);
   ObjectsDeleteAll(0, LPRE);
  }

void ClearZones()
  {
   ObjectsDeleteAll(0, ZPRE);
  }

// buy / sell diagnostics: index 0 = buy, 1 = sell
#define DIAG_NF 7
string gFailName[DIAG_NF] = {"trend", "D1", "range", "extended", "candle", "score", "exhausted"};
int    gDTrig[2], gDBusy[2], gDGrade[10], gDFail[14];   // gDGrade[d*5 + grade], gDFail[d*DIAG_NF + f]

void DiagRecord(const int d, const int grade, const string why)
  {
   if(grade == GRADE_NONE) return;
   gDTrig[d]++;
   gDGrade[d * 5 + grade]++;
   int cut = StringFind(why, "  |");
   string w = (cut >= 0 ? StringSubstr(why, 0, cut) : why) + " ";
   for(int f = 0; f < DIAG_NF; f++)
      if(StringFind(w, " " + gFailName[f] + " ") >= 0) gDFail[d * DIAG_NF + f]++;
  }

string DiagTop(const int d)
  {
   int a = -1, b = -1;
   for(int f = 0; f < DIAG_NF; f++)
     {
      int n = gDFail[d * DIAG_NF + f];
      if(n <= 0) continue;
      if(a < 0 || n > gDFail[d * DIAG_NF + a]) { b = a; a = f; }
      else if(b < 0 || n > gDFail[d * DIAG_NF + b]) b = f;
     }
   if(a < 0) return "-";
   string s = gFailName[a] + " " + IntegerToString(gDFail[d * DIAG_NF + a]);
   if(b >= 0) s += ", " + gFailName[b] + " " + IntegerToString(gDFail[d * DIAG_NF + b]);
   return s;
  }

void ResetCounts()
  {
   ArrayInitialize(gDTrig, 0); ArrayInitialize(gDBusy, 0);
   ArrayInitialize(gDGrade, 0); ArrayInitialize(gDFail, 0);
   gCntBuy = gCntSell = gCntTP1 = gCntTP2 = gCntSL = gCntLoss = 0;
   ArrayResize(gEvT, 0);
   ArrayResize(gEvK, 0);
  }

void ResetIdea()
  {
   idea.state = IDEA_IDLE;
   idea.dir = 0;
   idea.entry = idea.sl = idea.tp1 = idea.tp2 = idea.slR = 0;
   idea.signalTime = idea.slTime = idea.fillTime = 0;
   idea.reCount = idea.slBarAge = idea.pendAge = 0;
   idea.tp1Done = false;
   idea.re = false;
   idea.grade = GRADE_NONE;
   idea.armTrend = 0;
  }

// finish the running idea but keep its levels as the current zone
void EndIdea(const string status, const datetime t)
  {
   if(idea.state != IDEA_IDLE && idea.signalTime != 0)
     {
      gz.valid  = true;
      gz.dir    = idea.dir;
      gz.re     = idea.re;
      gz.grade  = idea.grade;
      gz.entry  = idea.entry;
      gz.sl     = idea.sl;
      gz.tp1    = idea.tp1;
      gz.tp2    = idea.tp2;
      gz.t1     = idea.signalTime;
      gz.tEnd   = t;
      gz.status = status;
     }
   ResetIdea();
  }

// point unit for the point-based inputs; on 3/5-digit brokers one unit = 10 points
double Pt()
  {
   if(InpAutoDigits && (_Digits == 3 || _Digits == 5)) return _Point * 10.0;
   return _Point;
  }

double PointBuf() { return (double)InpSLBufferPts * Pt(); }

double PendingDist(const Candle &bar)
  {
   double byPts = (double)InpPendingPts * Pt();
   double byRng = 0.0;
   if(InpPendingUseRange && bar.h > bar.l)
      byRng = (bar.h - bar.l) * InpPendingRetrace;
   double d = MathMax(byPts, byRng);
   if(d <= 0.0) d = 10.0 * Pt();
   return d;
  }

void ApplyLevels(const int dir, const double entry, const double sl)
  {
   idea.dir   = dir;
   idea.entry = entry;
   idea.sl    = sl;
   idea.slR   = sl;
   double risk = (dir > 0 ? (entry - sl) : (sl - entry));
   if(risk <= 0.0) risk = Pt() * 10;
   // wider SL, same TPs: the SL moves InpSLWidenPct % further away, TP1/TP2 keep the original R
   double w = 1.0 + MathMax(0.0, InpSLWidenPct) / 100.0;
   idea.sl = (dir > 0 ? entry - risk * w : entry + risk * w);
   if(dir > 0)
     {
      idea.tp1 = entry + risk * InpRR1;
      idea.tp2 = entry + risk * InpRR2;
     }
   else
     {
      idea.tp1 = entry - risk * InpRR1;
      idea.tp2 = entry - risk * InpRR2;
     }
  }

bool BuildPendingPrices(const int dir, const Candle &bar, const double buf, double &entry, double &sl)
  {
   double gap = (double)InpMinSLGapPts * Pt();
   if(gap <= 0.0) gap = 5.0 * Pt();
   double dist = PendingDist(bar);

   if(dir > 0)
     {
      sl = bar.l - buf;
      if(InpPendingOn)
        {
         if(InpPendingType == PEND_LIMIT)
            entry = bar.c - dist;
         else
            entry = bar.h + dist;
         if(entry <= sl + gap)
            entry = sl + gap;
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
         if(InpPendingType == PEND_LIMIT)
            entry = bar.c + dist;
         else
            entry = bar.l - dist;
         if(entry >= sl - gap)
            entry = sl - gap;
        }
      else
         entry = bar.c;
      if(entry >= sl) return false;
     }
   return true;
  }

void ArmIdea(const int dir, const Candle &bar, const bool re, const double buf,
             const int grade, const int trendDir)
  {
   double entry = 0, sl = 0;
   if(!BuildPendingPrices(dir, bar, buf, entry, sl))
     {
      EndIdea(idea.state == IDEA_SL_WAIT ? " [SL HIT]" : " [CANCELLED]", bar.t);
      return;
     }
   idea.signalTime = bar.t;
   idea.slTime = 0;
   idea.fillTime = 0;
   idea.slBarAge = 0;
   idea.pendAge = 0;
   idea.tp1Done = false;
   idea.re = re;
   idea.grade = grade;
   idea.armTrend = trendDir;
   ApplyLevels(dir, entry, sl);
   idea.state = (InpPendingOn ? IDEA_PENDING : IDEA_LIVE);
   if(idea.state == IDEA_LIVE)
      idea.fillTime = bar.t;
  }

// shift = spread for prices the broker checks on the ask (chart bars are bid)
bool TouchedLevel(const Candle &bar, const double price, const double shift = 0.0)
  {
   return (bar.valid && bar.l + shift <= price && bar.h + shift >= price);
  }

// break-even after TP1 is simulated only when the EA manages trades that way
bool EngineBE() { return (InpManageOn && InpMoveBE); }

// idea must be dropped because the higher timeframe turned against it
bool TrendAgainst(const int dir, const Bias &d, const Bias &h4, const int trendDir)
  {
   if(InpFiltOn) return (trendDir == -dir && idea.armTrend != -dir);
   return (dir > 0 ? (d.dir < 0 || h4.dir < 0) : (d.dir > 0 || h4.dir > 0));
  }

void StopOut(const Candle &bar)
  {
   if(idea.tp1Done && EngineBE()) { EndIdea(" [BE]", bar.t); return; }   // runner stopped at entry
   gCntSL++; AddEv(EV_SL, bar.t);
   if(!idea.tp1Done) { gCntLoss++; AddEv(EV_LOSS, bar.t); }
   idea.state = IDEA_SL_WAIT;
   idea.slTime = bar.t;
   idea.slBarAge = 0;
  }

void ManageIdea(const Candle &bar, const Bias &d, const Bias &h4, const int trendDir)
  {
   if(idea.state == IDEA_IDLE) return;
   bool fillBar = false;
   // buys are filled at the ask, sells are closed (SL / TP) at the ask
   double sp = (InpSpreadAware ? bar.spr : 0.0);
   double xs = (idea.dir < 0 ? sp : 0.0);

   if(idea.state == IDEA_PENDING)
     {
      idea.pendAge++;
      if(idea.pendAge > InpPendingExpire) { EndIdea(" [EXPIRED]", bar.t); return; }
      if(TrendAgainst(idea.dir, d, h4, trendDir)) { EndIdea(" [CANCELLED]", bar.t); return; }
      if(!TouchedLevel(bar, idea.entry, (idea.dir > 0 ? sp : 0.0))) return;
      idea.state = IDEA_LIVE;
      idea.fillTime = bar.t;
      idea.slBarAge = 0;
      fillBar = true;   // SL / TP are checked on the fill bar too
     }

   if(!InpReentryOn && idea.state == IDEA_SL_WAIT)
     {
      EndIdea(" [SL HIT]", idea.slTime);
      return;
     }

   idea.slBarAge++;

   bool hitTP2 = (idea.dir > 0 ? (bar.h >= idea.tp2) : (bar.l + xs <= idea.tp2));
   bool hitTP1 = (idea.dir > 0 ? (bar.h >= idea.tp1) : (bar.l + xs <= idea.tp1));
   bool hitSL  = (idea.dir > 0 ? (bar.l <= idea.sl)  : (bar.h + xs >= idea.sl));

   if(fillBar)
     {
      // the order of prices inside the fill bar is unknown. A limit is filled coming from
      // the TP side, so only a close beyond a TP proves it came after the fill; a stop is
      // filled coming from the SL side, so only a close beyond the SL proves that.
      if(!InpPendingOn || InpPendingType == PEND_LIMIT)
        {
         hitTP1 = (idea.dir > 0 ? bar.c >= idea.tp1 : bar.c + xs <= idea.tp1);
         hitTP2 = (idea.dir > 0 ? bar.c >= idea.tp2 : bar.c + xs <= idea.tp2);
        }
      else
         hitSL = (idea.dir > 0 ? bar.c <= idea.sl : bar.c + xs >= idea.sl);
      if(hitSL) hitTP1 = hitTP2 = false;   // both possible: assume the loss
     }

   if(idea.state == IDEA_LIVE && hitSL && hitTP1)
     {
      bool closeFav = (idea.dir > 0 ? (bar.c > idea.entry) : (bar.c + xs < idea.entry));
      if(!closeFav)
        {
         StopOut(bar);
         return;
        }
     }

   if(idea.state == IDEA_LIVE && hitTP2)
     {
      if(!idea.tp1Done) { gCntTP1++; AddEv(EV_TP1, bar.t); idea.tp1Done = true; }
      gCntTP2++; AddEv(EV_TP2, bar.t);
      EndIdea(" [TP2 HIT]", bar.t);
      return;
     }

   bool tp1Now = false;
   if(idea.state == IDEA_LIVE && hitTP1 && !idea.tp1Done)
     {
      gCntTP1++; AddEv(EV_TP1, bar.t);
      idea.tp1Done = true;
      tp1Now = true;
     }

   if(idea.state == IDEA_LIVE && hitSL)
     {
      StopOut(bar);
      return;
     }

   if(tp1Now && EngineBE()) idea.sl = idea.entry;   // from the next bar the runner is at break-even

   if(idea.state == IDEA_SL_WAIT)
     {
      if(idea.slBarAge > InpReentryWindow || TrendAgainst(idea.dir, d, h4, trendDir))
         EndIdea(" [SL HIT]", idea.slTime);
     }
  }

bool StructureAllows(const int dir, const Bias &d, const Bias &h4, const Bias &h1,
                     const int scoreB, const int scoreS)
  {
   if(dir > 0)
     {
      if(scoreB < InpMinAlign) return false;
      if(InpRequireD  && d.dir  !=  1) return false;
      if(InpRequireH4 && h4.dir !=  1) return false;
      if(h1.dir == -1) return false;
      return true;
     }
   if(scoreS < InpMinAlign) return false;
   if(InpRequireD  && d.dir  != -1) return false;
   if(InpRequireH4 && h4.dir != -1) return false;
   if(h1.dir == 1) return false;
   return true;
  }

bool Cooled(const datetime now, const datetime lastSig, const int bars)
  {
   if(lastSig == 0) return true;
   return ((now - lastSig) >= (datetime)bars * PeriodSeconds(_Period));
  }

Candle CandleAtShift(ENUM_TIMEFRAMES tf, int sh)
  {
   Candle k;
   k.valid = false; k.o = k.h = k.l = k.c = 0; k.spr = 0; k.t = 0;
   if(sh < 0) return k;
   MqlRates r[];
   if(CopyRates(_Symbol, tf, sh, 1, r) != 1) return k;
   k.o = r[0].open; k.h = r[0].high; k.l = r[0].low; k.c = r[0].close;
   k.t = r[0].time;
   k.valid = (k.h > k.l);
   return k;
  }

int ClosedShiftAt(ENUM_TIMEFRAMES tf, const datetime t)
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
   if(rng <= 0.0) return 0.0;
   return MathAbs(k.c - k.o) / rng;
  }

double ClosePos(const Candle &k)
  {
   double rng = k.h - k.l;
   if(rng <= 0.0) return 0.5;
   return (k.c - k.l) / rng;
  }

bool BullCandle(const Candle &k) { return (k.valid && k.c > k.o); }
bool BearCandle(const Candle &k) { return (k.valid && k.c < k.o); }

Bias BiasFromTwo(const Candle &c1, const Candle &c2)
  {
   Bias b; b.dir = 0; b.strong = false;
   if(!c1.valid || !c2.valid) return b;

   bool bull = (c1.c > c1.o);
   bool bear = (c1.c < c1.o);
   bool hhhl = (c1.h >= c2.h && c1.l >= c2.l && c1.c > c2.c);
   bool lhll = (c1.l <= c2.l && c1.h <= c2.h && c1.c < c2.c);
   if(hhhl) bull = true;
   if(lhll) bear = true;

   if(bull && !bear) { b.dir = 1;  b.strong = hhhl || BodyRatio(c1) >= InpMinBodyRatio; }
   else if(bear && !bull) { b.dir = -1; b.strong = lhll || BodyRatio(c1) >= InpMinBodyRatio; }
   else if(c1.c > c2.c && c1.c > c1.o) b.dir = 1;
   else if(c1.c < c2.c && c1.c < c1.o) b.dir = -1;
   return b;
  }

Bias TFBiasNow(ENUM_TIMEFRAMES tf)
  {
   return BiasFromTwo(CandleAtShift(tf, 1), CandleAtShift(tf, 2));
  }

Bias TFBiasAt(ENUM_TIMEFRAMES tf, const datetime t)
  {
   int sh = ClosedShiftAt(tf, t);
   if(sh < 0) return TFBiasNow(tf);
   return BiasFromTwo(CandleAtShift(tf, sh), CandleAtShift(tf, sh + 1));
  }

bool QualityBullTrigger(const Candle &k, const double prevHigh)
  {
   if(!k.valid || k.c <= k.o) return false;
   if(BodyRatio(k) < InpMinBodyRatio) return false;
   if(ClosePos(k) < InpClosePos) return false;
   bool displace = (k.c > prevHigh);
   bool reject   = ((k.o - k.l) >= (k.c - k.o) * 0.55);
   return (displace || reject);
  }

bool QualityBearTrigger(const Candle &k, const double prevLow)
  {
   if(!k.valid || k.c >= k.o) return false;
   if(BodyRatio(k) < InpMinBodyRatio) return false;
   if(ClosePos(k) > 1.0 - InpClosePos) return false;
   bool displace = (k.c < prevLow);
   bool reject   = ((k.h - k.o) >= (k.o - k.c) * 0.55);
   return (displace || reject);
  }

//+------------------------------------------------------------------+
//| Quality filters: EMA trend, D1, ATR range, location, strict      |
//| trigger and the A/B/C grade. Keep in sync between Ind and EA.     |
//+------------------------------------------------------------------+
int gHTf1F = INVALID_HANDLE, gHTf1S = INVALID_HANDLE;
int gHTf2F = INVALID_HANDLE, gHTf2S = INVALID_HANDLE;
int gHD1   = INVALID_HANDLE, gHLoc  = INVALID_HANDLE, gHATR = INVALID_HANDLE;

bool FiltersInit()
  {
   gHTf1F = iMA(_Symbol, InpFiltTF1, InpFiltFast, 0, MODE_EMA, PRICE_CLOSE);
   gHTf1S = iMA(_Symbol, InpFiltTF1, InpFiltSlow, 0, MODE_EMA, PRICE_CLOSE);
   gHTf2F = iMA(_Symbol, InpFiltTF2, InpFiltFast, 0, MODE_EMA, PRICE_CLOSE);
   gHTf2S = iMA(_Symbol, InpFiltTF2, InpFiltSlow, 0, MODE_EMA, PRICE_CLOSE);
   gHD1   = iMA(_Symbol, PERIOD_D1, InpD1EmaP, 0, MODE_EMA, PRICE_CLOSE);
   gHLoc  = iMA(_Symbol, _Period, InpLocEmaP, 0, MODE_EMA, PRICE_CLOSE);
   gHATR  = iATR(_Symbol, _Period, InpATRPeriod);
   gHR1   = iRSI(_Symbol, _Period, InpRSI1, PRICE_CLOSE);
   gHR2   = iRSI(_Symbol, _Period, InpRSI2, PRICE_CLOSE);
   gHR3   = iRSI(_Symbol, _Period, InpRSI3, PRICE_CLOSE);
   return (gHTf1F != INVALID_HANDLE && gHTf1S != INVALID_HANDLE && gHTf2F != INVALID_HANDLE
           && gHTf2S != INVALID_HANDLE && gHD1 != INVALID_HANDLE && gHLoc != INVALID_HANDLE
           && gHATR != INVALID_HANDLE && gHR1 != INVALID_HANDLE && gHR2 != INVALID_HANDLE
           && gHR3 != INVALID_HANDLE);
  }

void ReleaseHandle(int &h)
  {
   if(h != INVALID_HANDLE) IndicatorRelease(h);
   h = INVALID_HANDLE;
  }

void FiltersRelease()
  {
   ReleaseHandle(gHTf1F); ReleaseHandle(gHTf1S);
   ReleaseHandle(gHTf2F); ReleaseHandle(gHTf2S);
   ReleaseHandle(gHD1);   ReleaseHandle(gHLoc);  ReleaseHandle(gHATR);
   ReleaseHandle(gHR1);   ReleaseHandle(gHR2);   ReleaseHandle(gHR3);
  }

bool HReady(const int h) { return (h != INVALID_HANDLE && BarsCalculated(h) > 0); }

// all filter data is calculated (history replay must wait for it)
bool FiltersReady()
  {
   return (HReady(gHTf1F) && HReady(gHTf1S) && HReady(gHTf2F) && HReady(gHTf2S)
           && HReady(gHD1) && HReady(gHLoc) && HReady(gHATR)
           && HReady(gHR1) && HReady(gHR2) && HReady(gHR3));
  }

double BufAt(const int h, const int sh)
  {
   if(h == INVALID_HANDLE || sh < 0) return 0.0;
   double v[1];
   if(CopyBuffer(h, 0, sh, 1, v) != 1) return 0.0;
   if(v[0] == EMPTY_VALUE) return 0.0;
   return v[0];
  }

// trend of one timeframe on its last bar closed at time t: 1 up, -1 down, 0 none
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

// both filter timeframes must agree
int TrendDirAt(const datetime t)
  {
   int a = TFTrendAt(InpFiltTF1, gHTf1F, gHTf1S, t);
   int b = TFTrendAt(InpFiltTF2, gHTf2F, gHTf2S, t);
   return ((a != 0 && a == b) ? a : 0);
  }

bool D1Against(const int dir, const datetime t)
  {
   int sh = ClosedShiftAt(PERIOD_D1, t);
   if(sh < 0) return false;
   double e = BufAt(gHD1, sh), c = iClose(_Symbol, PERIOD_D1, sh);
   if(e <= 0 || c <= 0) return false;
   return (dir > 0 ? c < e : c > e);
  }

double ATRAt(const int sh) { return BufAt(gHATR, sh); }

double SpreadPriceAt(const int sh)
  {
   int s[];
   if(CopySpread(_Symbol, _Period, sh, 1, s) == 1 && s[0] > 0) return s[0] * _Point;
   return (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
  }

// SL distance beyond the signal candle
double StopBuffer(const int sh)
  {
   double b = PointBuf();
   if(!InpATRStopOn) return b;
   double atr = ATRAt(sh);
   if(atr > 0) b = MathMax(b, atr * InpSLBufATR);
   b = MathMax(b, SpreadPriceAt(sh) * InpSLBufSpread);
   return b;
  }

double BarHL(const int sh, const int dir) { return (dir > 0 ? iHigh(_Symbol, _Period, sh) : iLow(_Symbol, _Period, sh)); }

// most recent confirmed swing high (dir > 0) / swing low (dir < 0) before bar sh;
// falls back to the extreme of the look-back window when there is no swing point
double SwingLevel(const int sh, const int dir)
  {
   int total = Bars(_Symbol, _Period);
   int side  = (int)MathMax(1, InpFractalSide);
   int last  = (int)MathMin(total - 1 - side, sh + InpSwingBars);
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
   for(int m = sh + 2; m <= sh + InpSwingBars && m < total; m++)
     {
      double p = BarHL(m, dir);
      if(dir > 0 ? p > ext : p < ext) ext = p;
     }
   return ext;
  }

// strong displacement candle that is the first close through a real swing, or a real pin bar
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
//| VWMA / RSI score (from VWMA RSI Score), evaluated at chart bar sh |
//|   1-3. RSI1/2/3 > RsiMid (buy)  /  < 100 - RsiMid (sell)          |
//|   4.   Close (or High) above VWMA1 of highs (buy) /               |
//|        Close (or Low) below VWMA1 of lows (sell)                  |
//|   5.   VWMA3 above (buy) / below (sell) VWMA2                     |
//+------------------------------------------------------------------+
double VwmaAt(const int i, const int period, const int total, const double &high[], const long &vol[])
  {
   if(i + period > total) return EMPTY_VALUE;
   double pv = 0.0, v = 0.0, h = 0.0;
   for(int k = i; k < i + period; k++)
     {
      pv += high[k] * (double)vol[k];
      v  += (double)vol[k];
      h  += high[k];
     }
   return (v > 0.0) ? pv / v : h / period;
  }

bool VOk(const int sh)
  {
   return (sh >= 0 && sh < ArraySize(V1) && V1[sh] != EMPTY_VALUE && V2[sh] != EMPTY_VALUE
           && V3[sh] != EMPTY_VALUE && V4[sh] != EMPTY_VALUE
           && VL1[sh] != EMPTY_VALUE && VL4[sh] != EMPTY_VALUE);
  }

bool RsiAt(const int sh, double &r1, double &r2, double &r3)
  {
   r1 = BufAt(gHR1, sh); r2 = BufAt(gHR2, sh); r3 = BufAt(gHR3, sh);
   return (r1 > 0.0 && r2 > 0.0 && r3 > 0.0);
  }

int ScoreAt(const int sh, const int dir)
  {
   double r1, r2, r3;
   if(!VOk(sh) || !RsiAt(sh, r1, r2, r3)) return 0;
   bool useHL = (InpCheck4Price == CHECK4_HIGH);
   int s = 0;
   if(dir > 0)
     {
      double m = InpRsiMid;
      if(r1 > m) s++;
      if(r2 > m) s++;
      if(r3 > m) s++;
      double price = (useHL ? iHigh(_Symbol, _Period, sh) : iClose(_Symbol, _Period, sh));
      if(price > V1[sh]) s++;      // above the VWMA of highs
      if(V3[sh] > V2[sh]) s++;
     }
   else
     {
      double m = 100.0 - InpRsiMid;
      if(r1 < m) s++;
      if(r2 < m) s++;
      if(r3 < m) s++;
      double price = (useHL ? iLow(_Symbol, _Period, sh) : iClose(_Symbol, _Period, sh));
      if(price < VL1[sh]) s++;     // below the VWMA of lows (mirror of the buy check)
      if(V3[sh] < V2[sh]) s++;
     }
   return s;
  }

// buy into overbought / sell into oversold (slow RSI1 only unless InpObOsAllRsi)
bool RsiExhausted(const int sh, const int dir)
  {
   double r1, r2, r3;
   if(!RsiAt(sh, r1, r2, r3)) return false;
   if(!InpObOsAllRsi) return (dir > 0 ? r1 > InpRsiOB : r1 < InpRsiOS);
   if(dir > 0) return (r1 > InpRsiOB || r2 > InpRsiOB || r3 > InpRsiOB);
   return (r1 < InpRsiOS || r2 < InpRsiOS || r3 < InpRsiOS);
  }

// fast RSI turning the trade's way and close beyond the fast VWMA (highs for buys, lows for sells)
bool Momentum(const int sh, const int dir)
  {
   double now = BufAt(gHR3, sh), prev = BufAt(gHR3, sh + 1);
   if(now <= 0.0 || prev <= 0.0 || !VOk(sh)) return false;
   double c = iClose(_Symbol, _Period, sh);
   return (dir > 0 ? (now > prev && c > V4[sh]) : (now < prev && c < VL4[sh]));
  }

// A = passes every enabled filter, B = fails one, C = fails two or more
int SignalGrade(const int dir, const Candle &k, const int sh, const int trendDir, string &why, int &fails)
  {
   fails = 0;
   why = "";
   if(InpFiltOn && trendDir != dir)          { fails++; why += " trend"; }
   if(InpD1FilterOn && D1Against(dir, k.t))  { fails++; why += " D1"; }
   // "chasing" filters: a strong trend candle often trips several of them at once
   int chase = 0;
   double atr = ATRAt(sh);
   if(InpATROn)
     {
      double rng = k.h - k.l;
      if(atr <= 0 || rng < atr * InpMinRangeATR || rng > atr * InpMaxRangeATR) { chase++; why += " range"; }
     }
   if(InpLocationOn)
     {
      double e = BufAt(gHLoc, sh);
      if(atr <= 0 || e <= 0 || MathAbs(k.c - e) > atr * InpMaxExtATR) { chase++; why += " extended"; }
     }
   if(InpStrictOn && !StrictTrigger(dir, k, sh)) { fails++; why += " candle"; }
   if(InpScoreOn && ScoreAt(sh, dir) < InpMinScore) { fails++; why += " score"; }
   if(InpObOsOn && RsiExhausted(sh, dir))           { chase++; why += " exhausted"; }
   fails += (InpSoftChase ? (int)MathMin(chase, 1) : chase);
   if(fails >= 2) return GRADE_C;
   return fails;
  }

// extra gate for C signals: they already failed two or more filters, so the
// ones that most often turn into losers (counter-trend, against D1, chasing
// an exhausted RSI, no momentum, weak candle, low score) are thrown out
bool CFilterPass(const int dir, const Candle &k, const int sh, const int fails, const int trendDir, string &rej)
  {
   rej = "";
   if(!InpCFilterOn) return true;
   if(fails > InpCMaxFails)                        rej += " fails>" + IntegerToString(InpCMaxFails);
   if(ScoreAt(sh, dir) < InpCMinScore)             rej += " score<" + IntegerToString(InpCMinScore);
   if(InpCNoCounter && trendDir == -dir)           rej += " counter-trend";
   if(InpCNoD1 && D1Against(dir, k.t))             rej += " D1";
   if(InpCNoExhaust && RsiExhausted(sh, dir))      rej += " exhausted";
   if(InpCMomentum && !Momentum(sh, dir))          rej += " momentum";
   if(InpCNeedCandle && !StrictTrigger(dir, k, sh)) rej += " candle";
   return (rej == "");
  }

string GradeName(const int g)
  {
   if(g == GRADE_A)  return "A";
   if(g == GRADE_B)  return "B";
   if(g == GRADE_C)  return "C";
   if(g == GRADE_CX) return "Cx";
   return "-";
  }

// grade toggles; a C rejected by the C filter (GRADE_CX) never arms
bool GradeOn(const int g)
  {
   if(g == GRADE_A) return InpGradeA;
   if(g == GRADE_B) return InpGradeB;
   if(g == GRADE_C) return InpGradeC;
   return false;
  }
bool FreshOK(const int g) { return GradeOn(g); }
bool ReOK(const int g)    { return (InpReNeedA ? g == GRADE_A : GradeOn(g)); }
string GradesText(const bool re)
  {
   if(re && InpReNeedA) return "A";
   string s = (InpGradeA ? "A" : "") + (InpGradeB ? "B" : "") + (InpGradeC ? (InpCFilterOn ? "C+" : "C") : "");
   return (s == "" ? "none" : s);
  }

double RecentSwingHigh(const int rates_total, const int i, const double &high[])
  {
   int from = i + 1;
   int to   = (int)MathMin(rates_total - 1, i + InpSwingLook);
   if(from > rates_total - 1) return high[i];
   double mx = high[from];
   for(int k = from; k <= to; k++) if(high[k] > mx) mx = high[k];
   return mx;
  }

double RecentSwingLow(const int rates_total, const int i, const double &low[])
  {
   int from = i + 1;
   int to   = (int)MathMin(rates_total - 1, i + InpSwingLook);
   if(from > rates_total - 1) return low[i];
   double mn = low[from];
   for(int k = from; k <= to; k++) if(low[k] < mn) mn = low[k];
   return mn;
  }

// grade letter beyond the (hollow) signal arrow, in the arrow colour
void GradeTag(const int sh, const datetime t, const double price, const int dir, const int grade,
              const bool re, const string why)
  {
   if(!InpGradeTag || t == 0) return;
   double atr = ATRAt(sh);
   if(atr <= 0) atr = (iHigh(_Symbol, _Period, sh) - iLow(_Symbol, _Period, sh));
   double p = (dir > 0 ? price - atr * InpTagOffATR : price + atr * InpTagOffATR);
   string name = ARPRE + "G" + TimeToString(t, TIME_DATE|TIME_MINUTES) + (dir > 0 ? "_U" : "_D") + (re ? "R" : "");
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
   ObjectSetInteger(0, name, OBJPROP_TIME, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, p);
   ObjectSetString(0, name, OBJPROP_TEXT, (re ? "R" : "") + GradeName(grade));
   ObjectSetInteger(0, name, OBJPROP_COLOR, SignalColor(dir, re));
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpZoneFontSize + 1);
   ObjectSetString(0, name, OBJPROP_FONT, InpZoneFont);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, dir > 0 ? ANCHOR_UPPER : ANCHOR_LOWER);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, (dir > 0 ? (re ? "RE-BUY " : "BUY ") : (re ? "RE-SELL " : "SELL ")) + GradeName(grade)
                   + "  score " + IntegerToString(ScoreAt(sh, dir)) + "/5" + (why == "" ? "" : "  failed:" + why));
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

// signal whose grade is toggled off: grey grade letter, hover shows the failed filters
void FilteredMark(const datetime t, const double price, const int dir, const int grade, const string why)
  {
   if(t == 0) return;
   string name = ARPRE + "F" + TimeToString(t, TIME_DATE|TIME_MINUTES) + (dir > 0 ? "_U" : "_D");
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetString(0, name, OBJPROP_TEXT, GradeName(grade));
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpFiltColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpZoneFontSize + 1);
   ObjectSetString(0, name, OBJPROP_FONT, InpZoneFont);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, dir > 0 ? ANCHOR_UPPER : ANCHOR_LOWER);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, (dir > 0 ? "BUY " : "SELL ") + GradeName(grade) + " not taken, failed:" + why);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

void PutRect(const string name, datetime t1, double p1, datetime t2, double p2, color fill)
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
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

void PutLine(const string name, datetime t1, datetime t2, double price, color clr)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

void PutLabel(const string name, datetime t, double price, const string text, color clr)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpZoneFontSize);
   ObjectSetString(0, name, OBJPROP_FONT, InpZoneFont);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);   // text sits on top of the line
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

// MT5 chart objects have no alpha channel, so fake transparency by
// blending the colour into the chart background colour.
color Faint(const color c, const int opacityPct)
  {
   double a = MathMax(0, MathMin(100, opacityPct)) / 100.0;
   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   int r = (int)MathRound(( bg        & 0xFF) + (( c        & 0xFF) - ( bg        & 0xFF)) * a);
   int g = (int)MathRound(((bg >> 8)  & 0xFF) + (((c >> 8)  & 0xFF) - ((bg >> 8)  & 0xFF)) * a);
   int b = (int)MathRound(((bg >> 16) & 0xFF) + (((c >> 16) & 0xFF) - ((bg >> 16) & 0xFF)) * a);
   return (color)(r | (g << 8) | (b << 16));
  }

color SignalColor(const int dir, const bool re)
  {
   if(dir > 0) return (re ? InpReBuyColor  : InpBuyColor);
   return (re ? InpReSellColor : InpSellColor);
  }

// Draws only the current zone: the running idea, or (optionally) the last
// finished one until a new signal replaces it. Objects are updated in place.
void DrawLiveZone()
  {
   if(idea.state != IDEA_IDLE && idea.signalTime != 0)
     {
      gz.valid = true;
      gz.dir   = idea.dir;
      gz.re    = idea.re;
      gz.grade = idea.grade;
      gz.entry = idea.entry;
      gz.sl    = idea.sl;
      gz.tp1   = idea.tp1;
      gz.tp2   = idea.tp2;
      gz.t1    = idea.signalTime;
      gz.tEnd  = 0;
      gz.status = "";
      if(idea.state == IDEA_PENDING) gz.status = (InpPendingType == PEND_LIMIT ? " [LIMIT]" : " [STOP]");
      if(idea.state == IDEA_LIVE)    gz.status = (idea.tp1Done ? " [TP1 HIT]" : " [FILLED]");
      if(idea.state == IDEA_SL_WAIT) gz.status = " [SL HIT]";
     }

   // mitigated = SL hit, TP1 hit (or TP2 when InpHideAtTP1 is off), cancelled or expired
   bool mitigated = (idea.state == IDEA_SL_WAIT)
                    || (idea.state == IDEA_LIVE && idea.tp1Done && InpHideAtTP1)
                    || (idea.state == IDEA_IDLE);
   bool show = InpShowZones && gz.valid && gz.t1 != 0
               && (!mitigated || InpKeepLastZone);
   if(!show)
     {
      ClearZones();
      return;
     }

   // box: signal bar -> a few bars past the current bar
   // lines: continue past the box so the labels can sit on top of them
   int ps = PeriodSeconds(_Period);
   datetime now = iTime(_Symbol, _Period, 0);
   if(now == 0) now = TimeCurrent();
   datetime t1 = gz.t1;
   datetime t2 = now + (datetime)MathMax(2, InpZoneRightBars) * ps;
   if(t2 <= t1)
      t2 = t1 + ps * 8;
   datetime tl = t2 + ps;                                          // label start
   datetime t3 = t2 + (datetime)MathMax(4, InpLabelBars) * ps;    // line end

   color sig = SignalColor(gz.dir, gz.re);
   string side = (gz.dir > 0 ? (gz.re ? "RE-BUY" : "BUY") : (gz.re ? "RE-SELL" : "SELL")) + " " + GradeName(gz.grade);

   PutRect(ZPRE+"ZSL0",  t1, gz.entry, t2, gz.sl,  Faint(InpZoneSL,  InpZoneOpacity));
   PutRect(ZPRE+"ZT10",  t1, gz.entry, t2, gz.tp1, Faint(InpZoneTP1, InpZoneOpacity));
   PutRect(ZPRE+"ZT20",  t1, gz.tp1,   t2, gz.tp2, Faint(InpZoneTP2, InpZoneOpacity));

   PutLine(ZPRE+"LEN0", t1, t3, gz.entry, Faint(sig,        InpLineOpacity));
   PutLine(ZPRE+"LSL0", t1, t3, gz.sl,    Faint(InpLineSL,  InpLineOpacity));
   PutLine(ZPRE+"LT10", t1, t3, gz.tp1,   Faint(InpLineTP1, InpLineOpacity));
   PutLine(ZPRE+"LT20", t1, t3, gz.tp2,   Faint(InpLineTP2, InpLineOpacity));

   PutLabel(ZPRE+"NEN0", tl, gz.entry, "Entry  " + DoubleToString(gz.entry, _Digits) + "  " + side + gz.status, sig);
   PutLabel(ZPRE+"NSL0", tl, gz.sl,    "SL  "    + DoubleToString(gz.sl,    _Digits), InpLineSL);
   PutLabel(ZPRE+"NT10", tl, gz.tp1,   "TP1  "   + DoubleToString(gz.tp1,   _Digits), InpLineTP1);
   PutLabel(ZPRE+"NT20", tl, gz.tp2,   "TP2  "   + DoubleToString(gz.tp2,   _Digits), InpLineTP2);
   ChartRedraw(0);
  }

string StateText()
  {
   if(idea.state == IDEA_PENDING)
      return (idea.dir > 0 ? "PEND LONG" : "PEND SHORT");
   if(idea.state == IDEA_LIVE)
      return (idea.dir > 0 ? "LIVE LONG" : "LIVE SHORT");
   if(idea.state == IDEA_SL_WAIT)
      return StringFormat("SL HIT  re %d/%d", idea.reCount, InpMaxReentry);
   return "IDLE";
  }

//+------------------------------------------------------------------+
//| Dashboard panel (same style as Lukes MTF EA)                     |
//+------------------------------------------------------------------+
#define PPRE    "MZF_P_"
int  gPX = 0, gPY = 0, gPanelH = 0;
int  gOtherObjs = -1;

// objects on the chart that are not part of either Lukes panel
int OtherObjCount()
  {
   int n = 0, total = ObjectsTotal(0);
   for(int i = 0; i < total; i++)
     {
      string nm = ObjectName(0, i);
      if(StringFind(nm, PPRE) == 0 || StringFind(nm, "LEA_P_") == 0) continue;
      n++;
     }
   return n;
  }
bool gCollapsed = false, gAutoBottom = false;   // gCollapsed = panel hidden, only the small tab shows
#define TAB_W 74
#define TAB_H 20
bool gDrag = false, gPrevDown = false, gScrollWas = true;
int  gDragDX = 0, gDragDY = 0, gDownX = 0, gDownY = 0;
#define C_HEAD  C'130,215,255'
#define C_LBL   C'235,240,248'
#define C_TXT   C'255,255,255'
#define C_UP    C'60,255,150'
#define C_DN    C'255,95,95'
#define C_WARN  C'255,225,60'
#define C_INFO  C'110,245,255'
#define C_MUTE  C'190,196,208'

int    gRow = 0, gMaxRow = 0;
int    gEmaFast = INVALID_HANDLE, gEmaSlow = INVALID_HANDLE;
uint   gLastPanelMs = 0;

string Px(const double p) { return DoubleToString(p, _Digits); }

datetime DayStart() { datetime t = TimeCurrent(); return t - (t % 86400); }

int CountEv(const int kind, const datetime from)
  {
   int c = 0;
   for(int i = ArraySize(gEvT) - 1; i >= 0; i--)
      if(gEvK[i] == kind && gEvT[i] >= from) c++;
   return c;
  }

string SessionName(color &c)
  {
   MqlDateTime g; TimeToStruct(TimeGMT(), g);
   if(g.day_of_week == 6 || (g.day_of_week == 0 && g.hour < 21) || (g.day_of_week == 5 && g.hour >= 21))
     { c = C_MUTE; return "CLOSED"; }
   int h = g.hour;
   if(h >= 12 && h < 16) { c = C_UP;   return "LONDON + NY"; }
   if(h >= 7  && h < 12) { c = C_INFO; return "LONDON"; }
   if(h >= 16 && h < 21) { c = C_WARN; return "NEW YORK"; }
   c = C'190,120,255';
   return (h >= 21 ? "SYDNEY" : "ASIA");
  }

string TrendText(color &c)
  {
   double f[1], s[1];
   if(gEmaFast == INVALID_HANDLE || gEmaSlow == INVALID_HANDLE ||
      CopyBuffer(gEmaFast, 0, 1, 1, f) != 1 || CopyBuffer(gEmaSlow, 0, 1, 1, s) != 1)
     { c = C_MUTE; return "-"; }
   double px = iClose(_Symbol, InpTrendTF, 1);
   if(f[0] > s[0] && px > f[0]) { c = C_UP; return "EMA UP"; }
   if(f[0] < s[0] && px < f[0]) { c = C_DN; return "EMA DOWN"; }
   c = C_WARN;
   return (f[0] > s[0] ? "UP / PULLBACK" : "DOWN / PULLBACK");
  }

string FilterTrendText(color &c)
  {
   if(!InpFiltOn) { c = C_MUTE; return "OFF"; }
   string tfs = StringSubstr(EnumToString(InpFiltTF1), 7) + "+" + StringSubstr(EnumToString(InpFiltTF2), 7);
   int t = TrendDirAt(iTime(_Symbol, _Period, 0));
   if(t > 0) { c = C_UP; return "UP " + tfs; }
   if(t < 0) { c = C_DN; return "DOWN " + tfs; }
   c = C_WARN;
   return "NONE (no A signals)";
  }

string BiasText(const ENUM_TIMEFRAMES tf, color &c)
  {
   Bias b = TFBiasNow(tf);
   if(b.dir > 0) { c = C_UP; return (b.strong ? "BULL Q" : "BULL"); }
   if(b.dir < 0) { c = C_DN; return (b.strong ? "BEAR Q" : "BEAR"); }
   c = C_MUTE;
   return "MIXED";
  }

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

int RowY() { return gPY + 46 + gRow * InpPanelRowH; }

void PSection(const string title)
  {
   if(gRow > 0) gRow++;   // small gap before a section
   PText(PPRE + "L" + IntegerToString(gRow), gPX + 10, RowY(), title, C_HEAD, InpPanelFont, ANCHOR_LEFT_UPPER, InpPanelFontHead);
   ObjectDelete(0, PPRE + "V" + IntegerToString(gRow));
   gRow++;
  }

void PRow(const string label, const string value, const color vc)
  {
   PText(PPRE + "L" + IntegerToString(gRow), gPX + 12, RowY(), label, C_LBL, InpPanelFont, ANCHOR_LEFT_UPPER, InpPanelFontName);
   PText(PPRE + "V" + IntegerToString(gRow), gPX + InpPanelWidth - 12, RowY(), value, vc, InpPanelFont, ANCHOR_RIGHT_UPPER, InpPanelFontName);
   gRow++;
  }

string WinRate(const int wins, const int losses, color &c)
  {
   int n = wins + losses;
   if(n == 0) { c = C_MUTE; return "-"; }
   double wr = 100.0 * wins / n;
   c = (wr >= 50 ? C_UP : C_DN);
   return StringFormat("%.0f%%  (%d/%d)", wr, wins, n);
  }

void DrawPanel(const bool force = false)
  {
   if(!InpShowPanel) return;
   uint now = GetTickCount();
   if(!force && gLastPanelMs != 0 && now - gLastPanelMs < 500) return;   // redraw at most twice a second
   gLastPanelMs = now;

   color c;
   string v;
   gRow = 0;

   // background is created BEFORE any text, otherwise it is drawn on top and hides it
   string bg = PPRE + "BG";
   int others = OtherObjCount();
   if(others != gOtherObjs)
     {
      // objects created after the panel are drawn over it: rebuild the panel on top
      ObjectDelete(0, bg);
      gOtherObjs = others;
     }
   if(ObjectFind(0, bg) < 0)
     {
      ObjectsDeleteAll(0, PPRE);
      gMaxRow = 0;
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
     }

   // hidden: only a small tab at the top; one click on it brings the panel back
   if(gCollapsed)
     {
      for(int i = 0; i < gMaxRow; i++)
        {
         ObjectDelete(0, PPRE + "L" + IntegerToString(i));
         ObjectDelete(0, PPRE + "V" + IntegerToString(i));
        }
      gMaxRow = 0;
      ObjectDelete(0, PPRE + "T1"); ObjectDelete(0, PPRE + "T2");
      ObjectDelete(0, PPRE + "T3"); ObjectDelete(0, PPRE + "T4");
      PText(PPRE + "T0", gPX + TAB_W / 2, gPY + TAB_H / 2, "MZF  " + ShortToString((ushort)0x25BC),
            C_TXT, InpPanelTitleFont, ANCHOR_CENTER, InpPanelFontHead);
      ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, gPX);
      ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, gPY);
      ObjectSetInteger(0, bg, OBJPROP_XSIZE, TAB_W);
      ObjectSetInteger(0, bg, OBJPROP_YSIZE, TAB_H);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'24,30,46');
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_COLOR, C'80,110,160');
      ObjectSetInteger(0, bg, OBJPROP_BACK, false);
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
      gPanelH = TAB_H;
      return;
     }
   ObjectDelete(0, PPRE + "T0");

   // header
   string st; color sc;
   if(idea.state == IDEA_PENDING)      { st = (idea.dir > 0 ? "PENDING BUY" : "PENDING SELL"); sc = C_WARN; }
   else if(idea.state == IDEA_LIVE)    { st = (idea.dir > 0 ? "LIVE BUY" : "LIVE SELL"); sc = (idea.dir > 0 ? InpBuyColor : InpSellColor); }
   else if(idea.state == IDEA_SL_WAIT) { st = "SL HIT"; sc = C_DN; }
   else                                { st = "WAIT"; sc = C_WARN; }
   PText(PPRE + "T1", gPX + 10, gPY + 6, "MT.ZIONPRO FUSION", C_TXT, InpPanelTitleFont, ANCHOR_LEFT_UPPER, InpPanelFontHead);
   PText(PPRE + "T2", gPX + InpPanelWidth - 10, gPY + 6, "v2.03  " + ShortToString((ushort)0x25B2), C_MUTE, InpPanelFont - 1, ANCHOR_RIGHT_UPPER, InpPanelFontName);
   PText(PPRE + "T3", gPX + 10, gPY + 27, _Symbol + "  " + StringSubstr(EnumToString(_Period), 7), C_LBL, InpPanelFont, ANCHOR_LEFT_UPPER, InpPanelFontName);
   PText(PPRE + "T4", gPX + InpPanelWidth - 10, gPY + 27, ShortToString((ushort)0x25CF) + " " + st, sc, InpPanelFont, ANCHOR_RIGHT_UPPER, InpPanelFontHead);

   {

   PSection("MARKET");
   v = SessionName(c);         PRow("Session", v, c);
   v = TrendText(c);           PRow("Trend (" + StringSubstr(EnumToString(InpTrendTF), 7) + ")", v, c);
   v = BiasText(InpTF_D, c);   PRow("D1", v, c);
   v = BiasText(InpTF_H4, c);  PRow("H4", v, c);
   v = BiasText(InpTF_H1, c);  PRow("H1", v, c);
   v = BiasText(InpTF_M5, c);  PRow("M5", v, c);
   PRow("Align B / S", StringFormat("%d / %d", gScoreB, gScoreS),
        (gScoreB >= InpMinAlign ? C_UP : (gScoreS >= InpMinAlign ? C_DN : C_MUTE)));
   v = FilterTrendText(c);     PRow("Trend filter", v, c);
   PRow("Grades / re-entry", GradesText(false) + " / " + GradesText(true), C_INFO);
   PRow("C filter", (InpCFilterOn ? "ON" : "OFF"), (InpCFilterOn ? C_UP : C_MUTE));
   double spr = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / Pt();
   PRow("Spread", StringFormat("%.0f pts", spr), (spr > 50 ? C_WARN : C_TXT));

   PSection("VWMA / RSI SCORE");
   int scB = ScoreAt(1, 1), scS = ScoreAt(1, -1);
   PRow("Bull / Bear score", StringFormat("%d / %d   (min %d)", scB, scS, InpMinScore),
        (scB >= InpMinScore ? C_UP : (scS >= InpMinScore ? C_DN : C_MUTE)));
   double r1, r2, r3;
   if(RsiAt(1, r1, r2, r3))
     {
      double lo = 100.0 - InpRsiMid;
      color rc = ((r1 > InpRsiMid && r2 > InpRsiMid && r3 > InpRsiMid) ? C_UP
                  : ((r1 < lo && r2 < lo && r3 < lo) ? C_DN : C_MUTE));
      if(RsiExhausted(1, 1) || RsiExhausted(1, -1)) rc = C_WARN;
      PRow(StringFormat("RSI %d / %d / %d", InpRSI1, InpRSI2, InpRSI3), StringFormat("%.1f / %.1f / %.1f", r1, r2, r3), rc);
     }
   if(VOk(1))
     {
      double px = iClose(_Symbol, _Period, 1);
      bool above = (px > V1[1]), below = (px < VL1[1]), stackUp = (V3[1] > V2[1]);
      PRow("Price vs VWMA" + IntegerToString(InpVWMA1), (above ? "ABOVE" : (below ? "BELOW" : "INSIDE")),
           (above ? C_UP : (below ? C_DN : C_MUTE)));
      PRow("VWMA" + IntegerToString(InpVWMA3) + " vs VWMA" + IntegerToString(InpVWMA2), (stackUp ? "UP" : "DOWN"), (stackUp ? C_UP : C_DN));
     }

   if(InpShowSessions)
     {
      PSection("LEVELS");
      double hi, lo2;
      PRow("Sydney H / L", SessionHL(InpSydS, InpSydE, hi, lo2) ? Px(hi) + " / " + Px(lo2) : "-", C_TXT);
      PRow("Asia H / L",   SessionHL(InpAsiS, InpAsiE, hi, lo2) ? Px(hi) + " / " + Px(lo2) : "-", C_TXT);
      PRow("London H / L", SessionHL(InpLonS, InpLonE, hi, lo2) ? Px(hi) + " / " + Px(lo2) : "-", C_TXT);
      PRow("NY H / L",     SessionHL(InpNyS,  InpNyE,  hi, lo2) ? Px(hi) + " / " + Px(lo2) : "-", C_TXT);
      PRow("PDH / PDL", Px(iHigh(_Symbol, PERIOD_D1, 1)) + " / " + Px(iLow(_Symbol, PERIOD_D1, 1)), InpPDColor);
      PRow("PWH / PWL", Px(iHigh(_Symbol, PERIOD_W1, 1)) + " / " + Px(iLow(_Symbol, PERIOD_W1, 1)), InpPWColor);
     }

   if(InpShowDiag)
     {
      PSection("DIAGNOSTICS  (BUY / SELL)");
      PRow("Triggers graded", StringFormat("%d / %d", gDTrig[0], gDTrig[1]), C_INFO);
      PRow("Buy  A / B / C / Cx", StringFormat("%d / %d / %d / %d", gDGrade[0], gDGrade[1], gDGrade[2], gDGrade[4]), InpBuyColor);
      PRow("Sell A / B / C / Cx", StringFormat("%d / %d / %d / %d", gDGrade[5], gDGrade[6], gDGrade[7], gDGrade[9]), InpSellColor);
      PRow("Busy / cooldown", StringFormat("%d / %d", gDBusy[0], gDBusy[1]), C_MUTE);
      PRow("Buy blockers", DiagTop(0), InpBuyColor);
      PRow("Sell blockers", DiagTop(1), InpSellColor);
     }

   datetime d = DayStart();
   int tS = CountEv(EV_SIG, d), t1 = CountEv(EV_TP1, d), t2 = CountEv(EV_TP2, d), tSL = CountEv(EV_SL, d), tL = CountEv(EV_LOSS, d);
   PSection("TODAY");
   PRow("Signals", IntegerToString(tS), C_INFO);
   PRow("TP1 hits", IntegerToString(t1), C_UP);
   PRow("TP2 hits", IntegerToString(t2), C_UP);
   PRow("SL hits", IntegerToString(tSL), C_DN);
   PRow("Running", IntegerToString(idea.state == IDEA_LIVE ? 1 : 0), C_WARN);
   v = WinRate(t1, tL, c);     PRow("Win rate", v, c);

   PSection("TOTAL (CHART HISTORY)");
   PRow("Signals (B/S)", StringFormat("%d  (%d/%d)", gCntBuy + gCntSell, gCntBuy, gCntSell), C_INFO);
   PRow("TP1 / TP2 / SL", StringFormat("%d / %d / %d", gCntTP1, gCntTP2, gCntSL), C_TXT);
   v = WinRate(gCntTP1, gCntLoss, c); PRow("Win rate", v, c);

   PSection("CURRENT SIGNAL");
   if(idea.state == IDEA_IDLE)
      PRow("Status", "no active signal", C_MUTE);
   else
     {
      string side = (idea.dir > 0 ? (idea.re ? "RE-BUY" : "BUY") : (idea.re ? "RE-SELL" : "SELL"));
      PRow("Status", side + " " + GradeName(idea.grade) + "  " + StateText(), SignalColor(idea.dir, idea.re));
      PRow("Entry", Px(idea.entry), C_TXT);
      PRow("SL", Px(idea.sl), InpLineSL);
      PRow("TP1 / TP2", Px(idea.tp1) + " / " + Px(idea.tp2), InpLineTP1);
     }
   PRow("Re-entry", (InpReentryOn ? StringFormat("ON  %d / %d", idea.reCount, InpMaxReentry) : "OFF"), (InpReentryOn ? C_UP : C_MUTE));

   }

   for(int i = gRow; i < gMaxRow; i++)
     {
      ObjectDelete(0, PPRE + "L" + IntegerToString(i));
      ObjectDelete(0, PPRE + "V" + IntegerToString(i));
     }
   gMaxRow = gRow;

   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, gPX);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, gPY);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, InpPanelWidth);
   gPanelH = 46 + gRow * InpPanelRowH + 10;
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, gPanelH);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'24,30,46');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, C'80,110,160');
   ObjectSetInteger(0, bg, OBJPROP_BACK, false);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
   if(gAutoBottom)
     {
      gAutoBottom = false;
      int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      gPY = (int)MathMax(20, ch - gPanelH - 10);
      DrawPanel(true);
     }
  }


//+------------------------------------------------------------------+
//| Session / day / week levels (from VWMA RSI Score)                |
//+------------------------------------------------------------------+
long ServerOffsetSec()
  {
   if(InpServerUtcOffset != 99) return (long)InpServerUtcOffset * 3600;
   long d = (long)(TimeTradeServer() - TimeGMT());
   return (long)MathRound(d / 1800.0) * 1800;
  }

// high / low of the most recent session (current or last completed); hours are UTC
bool SessionHL(const int sH, const int eH, double &hi, double &lo)
  {
   datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 == 0) return false;
   long off    = ServerOffsetSec();
   long nowUtc = (long)t0 - off;
   long st     = nowUtc - nowUtc % 86400 + (long)sH * 3600;
   if(st > nowUtc) st -= 86400;
   int len = ((eH - sH) % 24 + 24) % 24;
   if(len == 0) len = 24;
   long en = st + (long)len * 3600;

   hi = -DBL_MAX;
   lo = DBL_MAX;
   int n = Bars(_Symbol, _Period);
   for(int i = 0; i < n; i++)
     {
      long u = (long)iTime(_Symbol, _Period, i) - off;
      if(u < st) break;
      if(u >= en) continue;
      hi = MathMax(hi, iHigh(_Symbol, _Period, i));
      lo = MathMin(lo, iLow(_Symbol, _Period, i));
     }
   return (hi > -DBL_MAX);
  }

void HLine(const string name, const double price, const color clr, const ENUM_LINE_STYLE style, const string tip)
  {
   string n = LPRE + name;
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
   ObjectSetString(0, n, OBJPROP_TOOLTIP, tip + " " + Px(price));
  }

void DrawLevels()
  {
   double pdh = iHigh(_Symbol, PERIOD_D1, 1), pdl = iLow(_Symbol, PERIOD_D1, 1);
   double pwh = iHigh(_Symbol, PERIOD_W1, 1), pwl = iLow(_Symbol, PERIOD_W1, 1);
   if(pdh > 0) HLine("PDH", pdh, InpPDColor, STYLE_DOT,  "PDH");
   if(pdl > 0) HLine("PDL", pdl, InpPDColor, STYLE_DOT,  "PDL");
   if(pwh > 0) HLine("PWH", pwh, InpPWColor, STYLE_DASH, "PWH");
   if(pwl > 0) HLine("PWL", pwl, InpPWColor, STYLE_DASH, "PWL");
  }

//+------------------------------------------------------------------+
//| Panel position, drag and collapse                                |
//| Drag the panel by its title area. One click on the title hides   |
//| the panel, leaving a small "MZF" tab at the top; one click on    |
//| the tab shows it again. Position is remembered per chart.        |
//+------------------------------------------------------------------+

string PosKey(const string k) { return "MZFusion_panel_" + k + "_" + IntegerToString(ChartID()); }

void PanelInit()
  {
   gPX = InpPanelX;
   gPY = InpPanelY;
   gAutoBottom = (InpPanelY < 0);
   if(GlobalVariableCheck(PosKey("x")) && GlobalVariableCheck(PosKey("y")))
     {
      gPX = (int)GlobalVariableGet(PosKey("x"));
      gPY = (int)GlobalVariableGet(PosKey("y"));
      gAutoBottom = false;
     }
   if(gPY < 0) gPY = 20;
   gCollapsed = (GlobalVariableCheck(PosKey("c")) && GlobalVariableGet(PosKey("c")) > 0);
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   ChartSetInteger(0, CHART_FOREGROUND, false);   // "chart on foreground" would draw candles/grid over the panel
  }

void PanelSave()
  {
   GlobalVariableSet(PosKey("x"), gPX);
   GlobalVariableSet(PosKey("y"), gPY);
   GlobalVariableSet(PosKey("c"), gCollapsed ? 1 : 0);
  }

void PanelMouse(const long lparam, const double dparam, const string sparam)
  {
   int  x = (int)lparam, y = (int)dparam;
   bool down = ((StringToInteger(sparam) & 1) != 0);

   if(down && !gPrevDown)
     {
      // press on the title area starts a drag
      int hw = (gCollapsed ? TAB_W : InpPanelWidth), hh = (gCollapsed ? TAB_H : 44);
      if(InpShowPanel && x >= gPX && x <= gPX + hw && y >= gPY && y <= gPY + hh)
        {
         gDrag = true;
         gDragDX = x - gPX; gDragDY = y - gPY;
         gDownX = x; gDownY = y;
         gScrollWas = (bool)ChartGetInteger(0, CHART_MOUSE_SCROLL);
         ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
        }
     }
   else if(down && gDrag)
     {
      int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      int nx = (int)MathMax(0, MathMin(cw - 60, x - gDragDX));
      int ny = (int)MathMax(0, MathMin(ch - 30, y - gDragDY));
      if(nx != gPX || ny != gPY)
        {
         gPX = nx; gPY = ny;
         DrawPanel(true);
        }
     }
   else if(!down && gDrag)
     {
      gDrag = false;
      ChartSetInteger(0, CHART_MOUSE_SCROLL, gScrollWas);
      if(MathAbs(x - gDownX) < 4 && MathAbs(y - gDownY) < 4)
         gCollapsed = !gCollapsed;          // a click, not a drag: hide / show the panel
      PanelSave();
      DrawPanel(true);
      ChartRedraw(0);
     }
   gPrevDown = down;
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_MOUSE_MOVE) PanelMouse(lparam, dparam, sparam);
   else if(id == CHARTEVENT_CHART_CHANGE) DrawPanel(true);
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
   if(rates_total < MathMax(40, InpVWMA1 + 5)) return(0);

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(tick_volume, true);

   // VWMA lines first: the score used by the engine reads them
   if(prev_calculated <= 0 || prev_calculated > rates_total)
      if(!FiltersReady()) return(0);
   int vFrom = (prev_calculated <= 0 || prev_calculated > rates_total)
               ? rates_total - 1 : (int)MathMin(rates_total - 1, rates_total - prev_calculated + 1);
   for(int v = vFrom; v >= 0; v--)
     {
      V1[v] = VwmaAt(v, InpVWMA1, rates_total, high, tick_volume);
      V2[v] = VwmaAt(v, InpVWMA2, rates_total, high, tick_volume);
      V3[v] = VwmaAt(v, InpVWMA3, rates_total, high, tick_volume);
      V4[v] = VwmaAt(v, InpVWMA4, rates_total, high, tick_volume);
      VL1[v] = VwmaAt(v, InpVWMA1, rates_total, low, tick_volume);
      VL4[v] = VwmaAt(v, InpVWMA4, rates_total, low, tick_volume);
     }

   int start;
   if(prev_calculated <= 0)
     {
      if(!FiltersReady()) return(0);   // EMA / ATR history still calculating: try again next tick
      ArrayInitialize(BuyBuf, EMPTY_VALUE);
      ArrayInitialize(SellBuf, EMPTY_VALUE);
      ArrayInitialize(ReBuyBuf, EMPTY_VALUE);
      ArrayInitialize(ReSellBuf, EMPTY_VALUE);
      // arrows are kept (not deleted) so history stays on the chart
      lastBuyTime = lastSellTime = 0;
      lastFiltB = lastFiltS = 0;
      ResetIdea();
      ResetZone();
      ResetCounts();
      ClearZones();
      gLastBar = 0;
      start = (int)MathMin(rates_total - 5, 800);
     }
   else
      start = (int)MathMax(2, rates_total - prev_calculated + 1);

   if(start < 1) start = 1;

   gD  = TFBiasNow(InpTF_D);
   gH4 = TFBiasNow(InpTF_H4);
   gH1 = TFBiasNow(InpTF_H1);
   gM5 = TFBiasNow(InpTF_M5);
   gScoreB = (gD.dir==1) + (gH4.dir==1) + (gH1.dir==1) + (gM5.dir==1);
   gScoreS = (gD.dir==-1) + (gH4.dir==-1) + (gH1.dir==-1) + (gM5.dir==-1);

   for(int i = start; i >= 1; i--)
     {
      // each closed bar goes through the engine exactly once, so counters
      // (pending expiry, bars since SL) count bars, not ticks
      if(time[i] <= gLastBar) continue;
      gLastBar = time[i];
      BuyBuf[i] = SellBuf[i] = ReBuyBuf[i] = ReSellBuf[i] = EMPTY_VALUE;

      Candle bar;
      bar.o = open[i]; bar.h = high[i]; bar.l = low[i]; bar.c = close[i];
      bar.t = time[i]; bar.valid = true;
      bar.spr = SpreadPriceAt(i);

      Bias d  = TFBiasAt(InpTF_D,  time[i]);
      Bias h4 = TFBiasAt(InpTF_H4, time[i]);
      Bias h1 = TFBiasAt(InpTF_H1, time[i]);
      Bias m5 = TFBiasAt(InpTF_M5, time[i]);
      int sb = (d.dir==1) + (h4.dir==1) + (h1.dir==1) + (m5.dir==1);
      int ss = (d.dir==-1) + (h4.dir==-1) + (h1.dir==-1) + (m5.dir==-1);

      int trendDir = TrendDirAt(bar.t);

      ManageIdea(bar, d, h4, trendDir);

      double prevH = RecentSwingHigh(rates_total, i, high);
      double prevL = RecentSwingLow(rates_total, i, low);
      bool trigB = QualityBullTrigger(bar, prevH);
      bool trigS = QualityBearTrigger(bar, prevL);

      if(InpUseM5Trigger && PeriodSeconds(_Period) <= PeriodSeconds(PERIOD_M15))
        {
         Candle m5c = CandleAtShift(InpTF_M5, ClosedShiftAt(InpTF_M5, time[i]));
         if(trigB && !BullCandle(m5c)) trigB = false;
         if(trigS && !BearCandle(m5c)) trigS = false;
        }

      // with the EMA trend filter on, the one-candle bias vote is replaced by the grade
      bool allowB = (InpFiltOn || StructureAllows(1, d, h4, h1, sb, ss));
      bool allowS = (InpFiltOn || StructureAllows(-1, d, h4, h1, sb, ss));

      string whyB = "", whyS = "";
      int failsB = 0, failsS = 0;
      int gradeB = ((trigB && allowB) ? SignalGrade(1, bar, i, trendDir, whyB, failsB) : GRADE_NONE);
      int gradeS = ((trigS && allowS) ? SignalGrade(-1, bar, i, trendDir, whyS, failsS) : GRADE_NONE);

      // grade C must also clear the C filter, otherwise it is demoted to Cx (never armed)
      string rej = "";
      if(gradeB == GRADE_C && !CFilterPass(1, bar, i, failsB, trendDir, rej))
        { gradeB = GRADE_CX; whyB += "  | C filter:" + rej; }
      if(gradeS == GRADE_C && !CFilterPass(-1, bar, i, failsS, trendDir, rej))
        { gradeS = GRADE_CX; whyS += "  | C filter:" + rej; }
      DiagRecord(0, gradeB, whyB);
      DiagRecord(1, gradeS, whyS);
      double buf = StopBuffer(i);

      bool didRe = false;
      if(InpReentryOn && idea.state == IDEA_SL_WAIT && idea.reCount < InpMaxReentry
         && idea.slBarAge >= InpReentryCool)
        {
         if(idea.dir > 0 && ReOK(gradeB))
           {
            ReBuyBuf[i] = low[i];
            int rc = idea.reCount + 1;
            ArmIdea(1, bar, true, buf, gradeB, trendDir);
            idea.reCount = rc;
            lastBuyTime = bar.t;
            gCntBuy++; AddEv(EV_SIG, bar.t);
            GradeTag(i, time[i], low[i], 1, gradeB, true, whyB);
            didRe = true;
           }
         else if(idea.dir < 0 && ReOK(gradeS))
           {
            ReSellBuf[i] = high[i];
            int rc = idea.reCount + 1;
            ArmIdea(-1, bar, true, buf, gradeS, trendDir);
            idea.reCount = rc;
            lastSellTime = bar.t;
            gCntSell++; AddEv(EV_SIG, bar.t);
            GradeTag(i, time[i], high[i], -1, gradeS, true, whyS);
            didRe = true;
           }
        }

      bool armed = didRe;
      if(!didRe)
        {
         bool coolB = Cooled(bar.t, lastBuyTime, InpCooldown) && Cooled(bar.t, lastSellTime, 3);
         bool coolS = Cooled(bar.t, lastSellTime, InpCooldown) && Cooled(bar.t, lastBuyTime, 3);
         bool free = (idea.state == IDEA_IDLE);
         // an opposite signal may replace an unfilled pending order or an SL re-entry wait;
         // without this a stopped-out sell blocks every buy for the whole re-entry window
         bool oppB = (InpOppOverride && idea.dir < 0 && (idea.state == IDEA_PENDING || idea.state == IDEA_SL_WAIT));
         bool oppS = (InpOppOverride && idea.dir > 0 && (idea.state == IDEA_PENDING || idea.state == IDEA_SL_WAIT));
         bool takeB = ((free || oppB) && FreshOK(gradeB) && coolB);
         bool takeS = (!takeB && (free || oppS) && FreshOK(gradeS) && coolS);
         if(FreshOK(gradeB) && !takeB) gDBusy[0]++;
         if(FreshOK(gradeS) && !takeS) gDBusy[1]++;
         if((takeB && oppB) || (takeS && oppS))
            EndIdea(idea.state == IDEA_SL_WAIT ? " [SL HIT]" : " [REVERSED]", bar.t);

         if(takeB)
           {
            BuyBuf[i] = low[i];
            lastBuyTime = bar.t;
            ArmIdea(1, bar, false, buf, gradeB, trendDir);
            gCntBuy++; AddEv(EV_SIG, bar.t);
            GradeTag(i, time[i], low[i], 1, gradeB, false, whyB);
            armed = true;
           }
         else if(takeS)
           {
            SellBuf[i] = high[i];
            lastSellTime = bar.t;
            ArmIdea(-1, bar, false, buf, gradeS, trendDir);
            gCntSell++; AddEv(EV_SIG, bar.t);
            GradeTag(i, time[i], high[i], -1, gradeS, false, whyS);
            armed = true;
           }
        }

      // base signals whose grade is toggled off: grey letter only (no zone, no alert, no trade)
      if(!armed && InpShowFiltered)
        {
         if(gradeB != GRADE_NONE && !FreshOK(gradeB) && Cooled(bar.t, lastFiltB, InpCooldown))
           {
            lastFiltB = bar.t;
            FilteredMark(time[i], low[i], 1, gradeB, whyB);
           }
         else if(gradeS != GRADE_NONE && !FreshOK(gradeS) && Cooled(bar.t, lastFiltS, InpCooldown))
           {
            lastFiltS = bar.t;
            FilteredMark(time[i], high[i], -1, gradeS, whyS);
           }
        }
     }

   BuyBuf[0] = SellBuf[0] = ReBuyBuf[0] = ReSellBuf[0] = EMPTY_VALUE;
   if(InpShowLevels) DrawLevels();
   DrawPanel();
   DrawLiveZone();

   if(allowAlerts) CheckAlerts(time[1], close[1]);
   else allowAlerts = true;

   return(rates_total);
  }

void FireAlert(const string side, const datetime barTime, const double barClose)
  {
   string tf = EnumToString(_Period);
   StringReplace(tf, "PERIOD_", "");
   string extra = "";
   if(idea.state != IDEA_IDLE)
      extra = StringFormat(" | EN %s SL %s TP1 %s TP2 %s",
                           DoubleToString(idea.entry, _Digits),
                           DoubleToString(idea.sl, _Digits),
                           DoubleToString(idea.tp1, _Digits),
                           DoubleToString(idea.tp2, _Digits));

   if(idea.state != IDEA_IDLE)
      extra += StringFormat(" | score %d/5", ScoreAt(1, idea.dir));

   string msg = StringFormat("Mt.ZionPro Fusion %s %s | %s | close %s | %s%s",
                             side, _Symbol, tf, DoubleToString(barClose, _Digits),
                             TimeToString(barTime, TIME_DATE|TIME_MINUTES), extra);

   if(InpAlertPopup) Alert(msg);
   if(InpAlertSound) PlaySound(InpSoundFile);
   if(InpAlertPush)  SendNotification(msg);
   if(InpAlertEmail) SendMail("Mt.ZionPro Fusion " + side + " " + _Symbol, msg);
  }

void CheckAlerts(const datetime barTime, const double barClose)
  {
   if(barTime == 0) return;

   if(InpAlertFill && idea.state == IDEA_LIVE && idea.fillTime == barTime && lastFillAlert != barTime)
     {
      lastFillAlert = barTime;
      FireAlert(idea.dir > 0 ? "PENDING FILLED BUY" : "PENDING FILLED SELL", barTime, barClose);
     }

   if(barTime == lastAlertBar) return;
   bool buy    = (BuyBuf[1]    != EMPTY_VALUE);
   bool sell   = (SellBuf[1]   != EMPTY_VALUE);
   bool rebuy  = (ReBuyBuf[1]  != EMPTY_VALUE);
   bool resell = (ReSellBuf[1] != EMPTY_VALUE);
   if(!buy && !sell && !rebuy && !resell) return;
   lastAlertBar = barTime;

   string side = buy ? "BUY" : (sell ? "SELL" : (rebuy ? "RE-ENTRY BUY" : "RE-ENTRY SELL"));
   if((rebuy || resell) && !InpAlertReentry) return;
   if(idea.state != IDEA_IDLE) side = side + " " + GradeName(idea.grade);
   if(InpPendingOn) side = side + " PEND";
   FireAlert(side, barTime, barClose);
  }
//+------------------------------------------------------------------+
