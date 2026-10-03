//+------------------------------------------------------------------+
//|                                          ImpulsePullbackMTF.mq5  |
//|   Multi-TF structure filter -> quality impulse -> pullback entry |
//|                                                                  |
//|   Signal indicator only: draws arrows, SL/TP zones and a status  |
//|   panel, and can alert. It never places or closes orders.        |
//+------------------------------------------------------------------+
#property copyright   "OLIVE-EA"
#property version     "1.20"
#property description "Tuned for XAUUSD M5. MTF structure (D/H4/H1/M5) -> quality impulse -> ~45% pullback -> confirmation."
#property description "Hollow arrows: Aqua = buy, Magenta = sell. Trade box: red SL zone, green TP1 zone, blue TP2 zone."
#property description "Signal indicator only - it does not trade."
#property indicator_chart_window
#property indicator_buffers 9
#property indicator_plots   8

#property indicator_label1  "Pullback Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrAqua
#property indicator_width1  2

#property indicator_label2  "Pullback Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrMagenta
#property indicator_width2  2

#property indicator_label3  "Direct Buy"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrAqua
#property indicator_width3  2

#property indicator_label4  "Direct Sell"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrMagenta
#property indicator_width4  2

#property indicator_label5  "Re-entry Buy"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrAqua
#property indicator_width5  2

#property indicator_label6  "Re-entry Sell"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrMagenta
#property indicator_width6  2

#property indicator_label7  "Impulse Buy"
#property indicator_type7   DRAW_ARROW
#property indicator_color7  clrAqua
#property indicator_width7  1

#property indicator_label8  "Impulse Sell"
#property indicator_type8   DRAW_ARROW
#property indicator_color8  clrMagenta
#property indicator_width8  1

//--- confirmation "reclaim" requirement
enum ENUM_RECLAIM
  {
   RECLAIM_NONE  = 0, // Not required
   RECLAIM_OPEN  = 1, // Close beyond impulse open
   RECLAIM_MID   = 2, // Close beyond impulse body midpoint
   RECLAIM_CLOSE = 3  // Close beyond impulse close
  };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "1) Multi-TF structure filter (D / H4 / H1 / M5)"
input int          InpMinAlign       = 2;      // Min TFs aligned with direction (0-4)
input bool         InpRequireH4      = true;   // H4 must agree with direction
input bool         InpRequireD       = false;  // Daily must agree with direction

input group "2) Impulse candle"
input double       InpMinBodyRatio   = 0.25;   // Min body / range
input double       InpCloseZone      = 0.55;   // Close inside this upper (buy) / lower (sell) fraction of range
input int          InpSwingLookback  = 2;      // Swing break lookback (bars)
input double       InpMinWickRatio   = 0.30;   // Rejection wick / range (alternative to swing break)
input double       InpMinImpulseATR  = 0.8;    // Min impulse range (x ATR, 0 = off)

input group "3) Pullback entry"
input bool         InpPullbackOn     = true;   // Pullback mode (false = impulse close is the entry)
input int          InpPullbackBars   = 8;      // Bars allowed for the pullback to happen
input double       InpPullbackPct    = 0.45;   // Required retrace of impulse range
input int          InpConfirmBars    = 8;      // Bars allowed for confirmation after the pullback
input double       InpConfirmBody    = 0.30;   // Confirmation candle: min body / range
input double       InpConfirmClose   = 0.50;   // Confirmation candle: close inside this upper (buy) / lower (sell) fraction
input ENUM_RECLAIM InpReclaim        = RECLAIM_NONE; // Confirmation candle must reclaim impulse level

input group "Quality filters (XAUUSD M5)"
input bool         InpUseSession     = true;   // Only signal inside the session window
input int          InpSessionStart   = 8;      // Session start hour (server time)
input int          InpSessionEnd     = 21;     // Session end hour (server time, exclusive)
input bool         InpUseEMA         = true;   // Chart-TF EMA trend filter
input int          InpEMAPeriod      = 50;     // EMA period
input int          InpEMASlopeBars   = 5;      // EMA must rise (buy) / fall (sell) over this many bars
input int          InpMaxSpreadPts   = 60;     // Max bar spread in points (0 = off)
input double       InpMinRiskATR     = 0.6;    // Min SL distance (x ATR) - tighter stops are widened to this
input double       InpMaxRiskATR     = 3.0;    // Max SL distance (x ATR, 0 = off) - wider setups are skipped

input group "Risk / targets"
input double       InpBufferATR      = 0.10;   // Buffer beyond wicks (x ATR)
input int          InpATRPeriod      = 14;     // ATR period
input double       InpTP1R           = 1.0;    // TP1 (R multiple)
input double       InpTP2R           = 2.0;    // TP2 (R multiple)
input bool         InpUseSpread      = true;   // Include bar spread for sells (ask-side SL/TP)

input group "5) Re-entry after SL"
input bool         InpReentryOn      = true;   // Allow re-entries after SL
input int          InpMaxReentries   = 2;      // Max re-entries per idea
input int          InpReentryWindow  = 24;     // Re-entry window (bars after first SL)

input group "Trade box & levels"
input bool         InpShowZones      = true;   // Draw trade boxes
input bool         InpShowLevels     = true;   // Latest trade: dotted levels + price labels
input int          InpBoxBars        = 30;     // Box width (bars from entry)
input int          InpLineExtraBars  = 15;     // Level lines extend this many bars past the box
input color        InpSLZoneColor    = C'110,22,22';  // SL zone fill
input color        InpTP1ZoneColor   = C'22,95,45';   // TP1 zone fill
input color        InpTP2ZoneColor   = C'25,35,150';  // TP2 zone fill
input color        InpEntryColor     = clrAqua;        // Entry line / label
input color        InpSLColor        = clrRed;         // SL line / label
input color        InpTP1Color       = clrMediumSeaGreen; // TP1 line / label
input color        InpTP2Color       = clrDodgerBlue;  // TP2 line / label
input bool         InpChartShift     = true;   // Enable chart shift so boxes have room on the right

input group "Display"
input int          InpMaxBars        = 10000;  // History bars to calculate
input bool         InpShowImpulse    = true;   // Mark impulse candles (WATCH start)
input bool         InpShowPanel      = true;   // Show status panel
input ENUM_BASE_CORNER InpPanelCorner = CORNER_LEFT_UPPER; // Panel corner
input int          InpPanelX         = 10;     // Panel X offset
input int          InpPanelY         = 25;     // Panel Y offset
input int          InpFontSize       = 9;      // Font size

input group "Alerts"
input bool         InpAlertWatch     = false;  // Alert on impulse / WATCH
input bool         InpAlertEntry     = true;   // Alert on entry / re-entry
input bool         InpAlertExit      = true;   // Alert on TP1 / TP2 / SL / abandon
input bool         InpAlertPopup     = true;   // Popup alert
input bool         InpAlertPush      = false;  // Push notification
input bool         InpAlertSound     = false;  // Play sound
input string       InpSoundFile      = "alert.wav"; // Sound file

//+------------------------------------------------------------------+
//| Constants / state                                                |
//+------------------------------------------------------------------+
#define TF_BEAR  -1
#define TF_MIX    0
#define TF_BULL   1

#define KIND_PULLBACK 0
#define KIND_DIRECT   1
#define KIND_REENTRY  2

#define LEVEL_COUNT   4

enum ENUM_IDEA_STATE
  {
   ST_IDLE,
   ST_WATCH,
   ST_LIVE,
   ST_SLWAIT
  };

const string PFX       = "IPMTF_";
const string PFX_ZONE  = "IPMTF_Z";
const string PFX_PANEL = "IPMTF_P";
const string PFX_LEVEL = "IPMTF_L";
const int    PANEL_LINES = 5;

//--- buffers
double BufPBLong[], BufPBShort[], BufDirLong[], BufDirShort[];
double BufReLong[], BufReShort[], BufImpLong[], BufImpShort[];
double BufEMA[];
int    g_emaHandle = INVALID_HANDLE;

//--- calculation bookkeeping
int      g_lastIdx   = -1;
datetime g_lastTime  = 0;
bool     g_alertsOn  = false;

//--- MTF state of the last processed bar
int g_sD = TF_MIX, g_sH4 = TF_MIX, g_sH1 = TF_MIX, g_sM5 = TF_MIX;

//--- idea state machine
ENUM_IDEA_STATE g_state = ST_IDLE;
int    g_dir        = 0;

//--- impulse / watch
double g_impOpen, g_impHigh, g_impLow, g_impClose, g_impBuf, g_pbLevel;
int    g_watchBars  = 0;
bool   g_touched    = false;
int    g_sinceTouch = 0;

//--- latest trade (kept after it closes, until the next one, for the level labels)
int      g_tradeId    = 0;
int      g_tradeDir   = 0;
int      g_entryIdx   = -1;
int      g_exitIdx    = -1;
datetime g_entryTime  = 0;
double   g_entry, g_sl, g_tp1, g_tp2;
bool     g_tp1Hit     = false;
string   g_status     = "";

//--- re-entry
int    g_reentries  = 0;
int    g_firstSLIdx = -1;

//--- spread (price units) of the bar being processed
double g_spr        = 0.0;

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BufPBLong,   INDICATOR_DATA);
   SetIndexBuffer(1, BufPBShort,  INDICATOR_DATA);
   SetIndexBuffer(2, BufDirLong,  INDICATOR_DATA);
   SetIndexBuffer(3, BufDirShort, INDICATOR_DATA);
   SetIndexBuffer(4, BufReLong,   INDICATOR_DATA);
   SetIndexBuffer(5, BufReShort,  INDICATOR_DATA);
   SetIndexBuffer(6, BufImpLong,  INDICATOR_DATA);
   SetIndexBuffer(7, BufImpShort, INDICATOR_DATA);
   SetIndexBuffer(8, BufEMA,      INDICATOR_CALCULATIONS);

   //--- Wingdings: 241/242 hollow arrows (all signals), 161 hollow circle (impulse)
   int codes[8]  = {241, 242, 241, 242, 241, 242, 161, 161};
   int shifts[8] = { 14, -14,  14, -14,  14, -14,  10, -10};
   for(int k = 0; k < 8; k++)
     {
      PlotIndexSetInteger(k, PLOT_ARROW, codes[k]);
      PlotIndexSetInteger(k, PLOT_ARROW_SHIFT, shifts[k]);
      PlotIndexSetDouble(k, PLOT_EMPTY_VALUE, EMPTY_VALUE);
     }
   if(!InpShowImpulse)
     {
      PlotIndexSetInteger(6, PLOT_DRAW_TYPE, DRAW_NONE);
      PlotIndexSetInteger(7, PLOT_DRAW_TYPE, DRAW_NONE);
     }

   if(InpTP2R <= InpTP1R || InpTP1R <= 0.0)
     {
      Print("ImpulsePullbackMTF: TP2 R must be greater than TP1 R, and TP1 R > 0");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMinAlign < 0 || InpMinAlign > 4 || InpSwingLookback < 1 || InpATRPeriod < 1 ||
      InpEMAPeriod < 1 || InpEMASlopeBars < 1 || InpBoxBars < 1)
     {
      Print("ImpulsePullbackMTF: invalid input (MinAlign 0-4, lookbacks / periods / box bars >= 1)");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpUseEMA)
     {
      g_emaHandle = iMA(_Symbol, _Period, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_emaHandle == INVALID_HANDLE)
        {
         Print("ImpulsePullbackMTF: cannot create EMA handle");
         return INIT_FAILED;
        }
     }

   if(InpShowZones && InpChartShift)
      ChartSetInteger(0, CHART_SHIFT, true);

   IndicatorSetString(INDICATOR_SHORTNAME, "ImpulsePullbackMTF");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   ResetState();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_emaHandle != INVALID_HANDLE)
      IndicatorRelease(g_emaHandle);
   ObjectsDeleteAll(0, PFX);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
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
   int warmup = MathMax(MathMax(InpSwingLookback, InpATRPeriod), InpEMASlopeBars) + 2;
   if(InpUseEMA)
      warmup = MathMax(warmup, InpEMAPeriod * 2);
   if(rates_total < warmup + 2)
      return 0;

   //--- higher-TF history must be available, otherwise retry on next tick
   ENUM_TIMEFRAMES tfs[4] = {PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M5};
   for(int k = 0; k < 4; k++)
      if(iBars(_Symbol, tfs[k]) < 3 || iTime(_Symbol, tfs[k], 0) == 0)
         return prev_calculated;

   //--- chart-TF EMA
   if(InpUseEMA)
     {
      if(BarsCalculated(g_emaHandle) < rates_total)
         return prev_calculated;
      if(CopyBuffer(g_emaHandle, 0, 0, rates_total, BufEMA) <= 0)
         return prev_calculated;
     }

   //--- full recalculation when needed (first run, history change)
   bool full = (prev_calculated == 0 || g_lastIdx < 0 || g_lastIdx >= rates_total ||
                time[g_lastIdx] != g_lastTime);
   if(full)
     {
      ResetState();
      ObjectsDeleteAll(0, PFX_ZONE);
      ObjectsDeleteAll(0, PFX_LEVEL);
      ArrayInitialize(BufPBLong,   EMPTY_VALUE);
      ArrayInitialize(BufPBShort,  EMPTY_VALUE);
      ArrayInitialize(BufDirLong,  EMPTY_VALUE);
      ArrayInitialize(BufDirShort, EMPTY_VALUE);
      ArrayInitialize(BufReLong,   EMPTY_VALUE);
      ArrayInitialize(BufReShort,  EMPTY_VALUE);
      ArrayInitialize(BufImpLong,  EMPTY_VALUE);
      ArrayInitialize(BufImpShort, EMPTY_VALUE);
      int start = MathMax(warmup, rates_total - InpMaxBars);
      g_lastIdx  = start - 1;
      g_alertsOn = false;   // no alerts while painting history
     }

   //--- slots not processed yet (incl. forming bar) stay empty
   for(int k = g_lastIdx + 1; k < rates_total; k++)
      ClearBuffers(k);

   //--- only closed candles are evaluated (forming bar = rates_total-1)
   int lastClosed = rates_total - 2;
   for(int i = g_lastIdx + 1; i <= lastClosed; i++)
     {
      ProcessBar(i, time, open, high, low, close, spread, g_alertsOn && i == lastClosed);
      g_lastIdx  = i;
      g_lastTime = time[i];
     }

   //--- latest trade: box width and level lines / labels
   if(g_tradeId > 0)
     {
      int right = BoxRightIdx(lastClosed);
      BoxSetRight(g_tradeId, BarTime(time, right));
      LevelsDraw(time, right);
     }

   g_alertsOn = true;
   UpdatePanel();
   return rates_total;
  }

//+------------------------------------------------------------------+
//| State machine - one closed bar                                    |
//+------------------------------------------------------------------+
void ProcessBar(const int i, const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[],
                const int &spread[], const bool alerts)
  {
   g_spr = InpUseSpread ? spread[i] * _Point : 0.0;

   //--- MTF structure as of this bar's close
   datetime tClose = time[i] + PeriodSeconds(_Period);
   g_sD  = TFState(PERIOD_D1, tClose);
   g_sH4 = TFState(PERIOD_H4, tClose);
   g_sH1 = TFState(PERIOD_H1, tClose);
   g_sM5 = TFState(PERIOD_M5, tClose);

   //--- LIVE: manage targets / stop
   if(g_state == ST_LIVE)
     {
      ManageTrade(i, time, high, low, alerts);
      return;
     }

   //--- SL_WAIT: look for a re-entry impulse
   if(g_state == ST_SLWAIT)
     {
      bool expired = (i - g_firstSLIdx > InpReentryWindow);
      bool flipped = FlipAgainst(g_dir);
      if(!expired && !flipped)
        {
         if(Allowed(g_dir) && QualityOK(g_dir, i, time, close, spread) &&
            IsImpulse(g_dir, i, open, high, low, close))
           {
            g_reentries++;
            if(!OpenTrade(g_dir, i, KIND_REENTRY, time, high, low, close, alerts))
               g_reentries--;
           }
         return;
        }
      Abandon(expired ? "re-entry window expired" : "structure flipped", alerts);
      // fall through: this bar may start a new idea
     }

   //--- WATCH: wait for the pullback, then a confirming candle
   if(g_state == ST_WATCH)
     {
      g_watchBars++;
      string why = "";
      if(FlipAgainst(g_dir))
         why = "structure flipped";
      else if(g_dir > 0 ? (low[i] < g_impLow - g_impBuf) : (high[i] > g_impHigh + g_impBuf))
         why = "impulse extreme broken";
      else if(g_touched)
        {
         g_sinceTouch++;
         if(IsConfirm(g_dir, i, open, high, low, close) && Allowed(g_dir) &&
            QualityOK(g_dir, i, time, close, spread) &&
            OpenTrade(g_dir, i, KIND_PULLBACK, time, high, low, close, alerts))
            return;
         if(g_sinceTouch >= InpConfirmBars)
            why = "no confirmation";
        }
      else
        {
         bool touch = (g_dir > 0) ? (low[i] <= g_pbLevel) : (high[i] >= g_pbLevel);
         if(touch)
           {
            g_touched    = true;
            g_sinceTouch = 0;
           }
         else if(Allowed(g_dir) && QualityOK(g_dir, i, time, close, spread) &&
                 IsImpulse(g_dir, i, open, high, low, close))
           {
            // fresh impulse in the same direction before any pullback: re-anchor
            StartWatch(g_dir, i, open, high, low, close, alerts);
            return;
           }
         else if(g_watchBars >= InpPullbackBars)
            why = "no pullback";
        }

      if(why == "")
         return;
      Abandon(why, alerts);
      // fall through: this bar may start a new idea
     }

   //--- IDLE: structure + quality filters must pass first, then a quality impulse
   int dir = 0;
   if(Allowed(1) && QualityOK(1, i, time, close, spread) && IsImpulse(1, i, open, high, low, close))
      dir = 1;
   else if(Allowed(-1) && QualityOK(-1, i, time, close, spread) && IsImpulse(-1, i, open, high, low, close))
      dir = -1;
   if(dir == 0)
      return;

   g_reentries  = 0;
   g_firstSLIdx = -1;
   if(InpPullbackOn)
      StartWatch(dir, i, open, high, low, close, alerts);
   else
      OpenTrade(dir, i, KIND_DIRECT, time, high, low, close, alerts);
  }

//+------------------------------------------------------------------+
void StartWatch(const int dir, const int i, const double &open[],
                const double &high[], const double &low[], const double &close[],
                const bool alerts)
  {
   g_state      = ST_WATCH;
   g_dir        = dir;
   g_impOpen    = open[i];
   g_impHigh    = high[i];
   g_impLow     = low[i];
   g_impClose   = close[i];
   g_impBuf     = InpBufferATR * ATRAt(i, high, low, close);
   double range = g_impHigh - g_impLow;
   g_pbLevel    = (dir > 0) ? g_impHigh - InpPullbackPct * range
                            : g_impLow  + InpPullbackPct * range;
   g_watchBars  = 0;
   g_touched    = false;
   g_sinceTouch = 0;

   if(dir > 0)
      BufImpLong[i] = low[i];
   else
      BufImpShort[i] = high[i];

   if(alerts && InpAlertWatch)
      Notify(StringFormat("WAIT PB %s - impulse closed, pullback level %s",
                          SideName(dir), DoubleToString(g_pbLevel, _Digits)));
  }

//+------------------------------------------------------------------+
//| Returns false (and changes nothing) when the setup is rejected   |
//+------------------------------------------------------------------+
bool OpenTrade(const int dir, const int i, const int kind, const datetime &time[],
               const double &high[], const double &low[], const double &close[],
               const bool alerts)
  {
   double atr   = ATRAt(i, high, low, close);
   double entry = close[i];
   //--- SL beyond the entry candle wick (ask side for sells)
   double sl    = (dir > 0) ? low[i] - InpBufferATR * atr
                            : high[i] + g_spr + InpBufferATR * atr;
   double risk  = MathAbs(entry - sl);

   //--- too tight: widen to the minimum so normal gold noise does not tag it
   if(InpMinRiskATR > 0.0 && risk < InpMinRiskATR * atr)
     {
      risk = InpMinRiskATR * atr;
      sl   = entry - dir * risk;
     }
   if(risk <= _Point)
      return false;
   //--- too wide: 2R would be unrealistic, skip
   if(InpMaxRiskATR > 0.0 && risk > InpMaxRiskATR * atr)
      return false;

   //--- previous trade's box must not run into this one
   if(g_tradeId > 0)
      BoxSetRight(g_tradeId, time[MathMin(BoxRightIdx(i), i)]);

   g_state     = ST_LIVE;
   g_dir       = dir;
   g_tradeDir  = dir;
   g_entryIdx  = i;
   g_exitIdx   = -1;
   g_entryTime = time[i];
   g_entry     = entry;
   g_sl        = sl;
   g_tp1       = entry + dir * risk * InpTP1R;
   g_tp2       = entry + dir * risk * InpTP2R;
   g_tp1Hit    = false;
   g_status    = "ACTIVE";
   g_tradeId++;

   double mark = (dir > 0) ? low[i] : high[i];
   if(kind == KIND_PULLBACK)
     {
      if(dir > 0) BufPBLong[i] = mark;
      else        BufPBShort[i] = mark;
     }
   else if(kind == KIND_DIRECT)
     {
      if(dir > 0) BufDirLong[i] = mark;
      else        BufDirShort[i] = mark;
     }
   else
     {
      if(dir > 0) BufReLong[i] = mark;
      else        BufReShort[i] = mark;
     }

   BoxCreate(g_tradeId, time[i], BarTime(time, i + InpBoxBars));

   if(alerts && InpAlertEntry)
     {
      string label = (kind == KIND_REENTRY)
                     ? StringFormat("RE-ENTRY %d/%d %s", g_reentries, InpMaxReentries, SideName(dir))
                     : StringFormat("%s %s", SideName(dir), kind == KIND_PULLBACK ? "pullback entry" : "entry");
      Notify(StringFormat("%s @ %s  SL %s  TP1 %s  TP2 %s", label,
                          DoubleToString(g_entry, _Digits), DoubleToString(g_sl, _Digits),
                          DoubleToString(g_tp1, _Digits), DoubleToString(g_tp2, _Digits)));
     }
   return true;
  }

//+------------------------------------------------------------------+
void ManageTrade(const int i, const datetime &time[], const double &high[],
                 const double &low[], const bool alerts)
  {
   //--- chart prices are bid; a sell is closed at ask = bid + spread
   bool hitSL  = (g_dir > 0) ? (low[i]  <= g_sl)  : (high[i] + g_spr >= g_sl);
   bool hitTP1 = (g_dir > 0) ? (high[i] >= g_tp1) : (low[i]  + g_spr <= g_tp1);
   bool hitTP2 = (g_dir > 0) ? (high[i] >= g_tp2) : (low[i]  + g_spr <= g_tp2);

   //--- SL and a target inside the same candle: assume the worse case (SL first)
   if(hitSL)
     {
      g_exitIdx = i;
      g_status  = g_tp1Hit ? "SL HIT after TP1" : "SL HIT";
      BoxSetRight(g_tradeId, BarTime(time, BoxRightIdx(i)));
      if(g_reentries == 0)
         g_firstSLIdx = i;   // re-entry window starts at the idea's first SL
      bool canRetry = InpReentryOn && g_reentries < InpMaxReentries &&
                      (i - g_firstSLIdx) < InpReentryWindow;
      g_state = canRetry ? ST_SLWAIT : ST_IDLE;
      if(alerts && InpAlertExit)
         Notify(StringFormat("%s stopped out @ %s%s", SideName(g_dir), DoubleToString(g_sl, _Digits),
                             canRetry ? " - SL_WAIT for re-entry" : " - idea abandoned"));
      return;
     }

   if(hitTP2)
     {
      g_exitIdx = i;
      g_tp1Hit  = true;
      g_status  = "TP2 HIT";
      BoxSetRight(g_tradeId, BarTime(time, BoxRightIdx(i)));
      g_state = ST_IDLE;
      if(alerts && InpAlertExit)
         Notify(StringFormat("%s TP2 hit @ %s - idea complete", SideName(g_dir), DoubleToString(g_tp2, _Digits)));
      return;
     }

   if(hitTP1 && !g_tp1Hit)
     {
      g_tp1Hit = true;
      g_status = "TP1 HIT";
      if(alerts && InpAlertExit)
         Notify(StringFormat("%s TP1 hit @ %s", SideName(g_dir), DoubleToString(g_tp1, _Digits)));
     }
  }

//+------------------------------------------------------------------+
void Abandon(const string why, const bool alerts)
  {
   if(alerts && InpAlertExit)
      Notify(StringFormat("%s idea cancelled (%s)", SideName(g_dir), why));
   g_state = ST_IDLE;
  }

//+------------------------------------------------------------------+
//| Rules                                                            |
//+------------------------------------------------------------------+
//--- BULL / BEAR / MIX from the last two CLOSED candles of tf as of time t
int TFState(const ENUM_TIMEFRAMES tf, const datetime t)
  {
   int idx = iBarShift(_Symbol, tf, t, false);
   if(idx < 0)
      return TF_MIX;
   datetime ot = iTime(_Symbol, tf, idx);
   if(ot == 0)
      return TF_MIX;
   if(ot + PeriodSeconds(tf) > t)
      idx++;                         // that bar is still forming at time t
   if(idx + 1 >= iBars(_Symbol, tf))
      return TF_MIX;

   double o1 = iOpen(_Symbol, tf, idx),  c1 = iClose(_Symbol, tf, idx);
   double h1 = iHigh(_Symbol, tf, idx),  l1 = iLow(_Symbol, tf, idx);
   double h2 = iHigh(_Symbol, tf, idx + 1), l2 = iLow(_Symbol, tf, idx + 1);
   if(o1 == 0 || c1 == 0 || h2 == 0 || l2 == 0)
      return TF_MIX;

   if(c1 > o1 && h1 > h2 && l1 > l2)
      return TF_BULL;               // up candle + HH/HL
   if(c1 < o1 && h1 < h2 && l1 < l2)
      return TF_BEAR;               // down candle + LH/LL
   return TF_MIX;
  }

//--- structure filter for a direction, using the current MTF states
bool Allowed(const int dir)
  {
   int with    = (dir > 0) ? TF_BULL : TF_BEAR;
   int against = -with;
   int score   = (g_sD == with ? 1 : 0) + (g_sH4 == with ? 1 : 0) +
                 (g_sH1 == with ? 1 : 0) + (g_sM5 == with ? 1 : 0);
   if(score < InpMinAlign)
      return false;
   if(InpRequireH4 && g_sH4 != with)
      return false;
   if(InpRequireD && g_sD != with)
      return false;
   if(g_sH1 == against)
      return false;
   return true;
  }

//--- H4 (or D, when required) turned against the idea
bool FlipAgainst(const int dir)
  {
   int against = (dir > 0) ? TF_BEAR : TF_BULL;
   return (g_sH4 == against) || (InpRequireD && g_sD == against);
  }

//--- session / spread / EMA trend filters
bool QualityOK(const int dir, const int i, const datetime &time[], const double &close[],
               const int &spread[])
  {
   if(InpUseSession)
     {
      MqlDateTime dt;
      TimeToStruct(time[i], dt);
      bool in = (InpSessionStart <= InpSessionEnd)
                ? (dt.hour >= InpSessionStart && dt.hour < InpSessionEnd)
                : (dt.hour >= InpSessionStart || dt.hour < InpSessionEnd);
      if(!in)
         return false;
     }
   if(InpMaxSpreadPts > 0 && spread[i] > InpMaxSpreadPts)
      return false;
   if(InpUseEMA)
     {
      if(i < InpEMASlopeBars)
         return false;
      double e  = BufEMA[i];
      double e0 = BufEMA[i - InpEMASlopeBars];
      if(e == EMPTY_VALUE || e0 == EMPTY_VALUE || e <= 0.0 || e0 <= 0.0)
         return false;
      if(dir > 0 && !(close[i] > e && e > e0))
         return false;
      if(dir < 0 && !(close[i] < e && e < e0))
         return false;
     }
   return true;
  }

//--- quality impulse candle
bool IsImpulse(const int dir, const int i, const double &open[], const double &high[],
               const double &low[], const double &close[])
  {
   double range = high[i] - low[i];
   if(range <= 0.0 || i < InpSwingLookback)
      return false;
   if(MathAbs(close[i] - open[i]) / range < InpMinBodyRatio)
      return false;
   if(InpMinImpulseATR > 0.0 && range < InpMinImpulseATR * ATRAt(i, high, low, close))
      return false;

   double swing = (dir > 0) ? high[i - 1] : low[i - 1];
   for(int k = 2; k <= InpSwingLookback; k++)
      swing = (dir > 0) ? MathMax(swing, high[i - k]) : MathMin(swing, low[i - k]);

   if(dir > 0)
     {
      if(close[i] <= open[i])
         return false;
      if((close[i] - low[i]) / range < 1.0 - InpCloseZone)
         return false;
      bool brk  = close[i] > swing;
      bool wick = (MathMin(open[i], close[i]) - low[i]) / range >= InpMinWickRatio;
      return brk || wick;
     }

   if(close[i] >= open[i])
      return false;
   if((high[i] - close[i]) / range < 1.0 - InpCloseZone)
      return false;
   bool brk  = close[i] < swing;
   bool wick = (high[i] - MathMax(open[i], close[i])) / range >= InpMinWickRatio;
   return brk || wick;
  }

//--- confirmation candle after the pullback
bool IsConfirm(const int dir, const int i, const double &open[], const double &high[],
               const double &low[], const double &close[])
  {
   double range = high[i] - low[i];
   if(range <= 0.0 || MathAbs(close[i] - open[i]) / range < InpConfirmBody)
      return false;

   double level = 0.0;
   switch(InpReclaim)
     {
      case RECLAIM_OPEN:  level = g_impOpen; break;
      case RECLAIM_MID:   level = (g_impOpen + g_impClose) / 2.0; break;
      case RECLAIM_CLOSE: level = g_impClose; break;
      default:            break;
     }

   if(dir > 0)
     {
      if(close[i] <= open[i] || low[i] < g_impLow - g_impBuf)
         return false;
      if((close[i] - low[i]) / range < 1.0 - InpConfirmClose)
         return false;
      return (InpReclaim == RECLAIM_NONE || close[i] > level);
     }
   if(close[i] >= open[i] || high[i] > g_impHigh + g_impBuf)
      return false;
   if((high[i] - close[i]) / range < 1.0 - InpConfirmClose)
      return false;
   return (InpReclaim == RECLAIM_NONE || close[i] < level);
  }

//--- simple average true range ending at bar i
double ATRAt(const int i, const double &high[], const double &low[], const double &close[])
  {
   int n = MathMin(InpATRPeriod, i);
   if(n < 1)
      return high[i] - low[i];
   double sum = 0.0;
   for(int k = 0; k < n; k++)
     {
      int j = i - k;
      sum += MathMax(high[j], close[j - 1]) - MathMin(low[j], close[j - 1]);
     }
   return sum / n;
  }

//+------------------------------------------------------------------+
//| Drawing: trade box                                               |
//|   red   = entry -> SL                                            |
//|   green = entry -> TP1                                           |
//|   blue  = TP1   -> TP2                                           |
//+------------------------------------------------------------------+
void ClearBuffers(const int k)
  {
   BufPBLong[k]  = EMPTY_VALUE;
   BufPBShort[k] = EMPTY_VALUE;
   BufDirLong[k] = EMPTY_VALUE;
   BufDirShort[k]= EMPTY_VALUE;
   BufReLong[k]  = EMPTY_VALUE;
   BufReShort[k] = EMPTY_VALUE;
   BufImpLong[k] = EMPTY_VALUE;
   BufImpShort[k]= EMPTY_VALUE;
  }

//--- bar time for any index, extrapolated into the future past the last bar
datetime BarTime(const datetime &time[], const int idx)
  {
   int last = ArraySize(time) - 1;
   if(idx <= last)
      return time[MathMax(idx, 0)];
   return time[last] + (datetime)((idx - last) * PeriodSeconds(_Period));
  }

//--- right edge of the latest trade's box: at least InpBoxBars wide,
//--- and never ending before the exit (or, while live, the current bar)
int BoxRightIdx(const int currentIdx)
  {
   int end = (g_exitIdx >= 0) ? g_exitIdx : currentIdx + 2;
   return MathMax(g_entryIdx + InpBoxBars, end);
  }

string ZoneName(const int id)
  {
   return PFX_ZONE + IntegerToString(id);
  }

void RectCreate(const string name, const datetime t0, const double p0,
                const datetime t1, const double p1, const color clr)
  {
   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t0, p0, t1, p1))
      return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

void BoxCreate(const int id, const datetime t0, const datetime t1)
  {
   if(!InpShowZones)
      return;
   string n = ZoneName(id);
   RectCreate(n + "_SL",  t0, g_entry, t1, g_sl,  InpSLZoneColor);
   RectCreate(n + "_TP1", t0, g_entry, t1, g_tp1, InpTP1ZoneColor);
   RectCreate(n + "_TP2", t0, g_tp1,   t1, g_tp2, InpTP2ZoneColor);
  }

void BoxSetRight(const int id, const datetime t1)
  {
   if(!InpShowZones)
      return;
   string n = ZoneName(id);
   ObjectSetInteger(0, n + "_SL",  OBJPROP_TIME, 1, t1);
   ObjectSetInteger(0, n + "_TP1", OBJPROP_TIME, 1, t1);
   ObjectSetInteger(0, n + "_TP2", OBJPROP_TIME, 1, t1);
  }

//+------------------------------------------------------------------+
//| Drawing: latest trade levels                                     |
//|   dotted lines from the entry candle past the box, label above   |
//|   each line starting at the box's right edge                     |
//+------------------------------------------------------------------+
void LevelInfo(const int k, double &price, string &text, color &clr)
  {
   switch(k)
     {
      case 0:
         price = g_tp2;
         text  = StringFormat("TP2  %s", DoubleToString(g_tp2, _Digits));
         clr   = InpTP2Color;
         break;
      case 1:
         price = g_tp1;
         text  = StringFormat("TP1  %s", DoubleToString(g_tp1, _Digits));
         clr   = InpTP1Color;
         break;
      case 2:
         price = g_entry;
         text  = StringFormat("Entry  %s  %s [%s]", DoubleToString(g_entry, _Digits),
                              g_tradeDir > 0 ? "BUY" : "SELL", g_status);
         clr   = InpEntryColor;
         break;
      default:
         price = g_sl;
         text  = StringFormat("SL  %s", DoubleToString(g_sl, _Digits));
         clr   = InpSLColor;
         break;
     }
  }

void LevelsDraw(const datetime &time[], const int boxRightIdx)
  {
   if(!InpShowLevels)
      return;
   datetime tBox  = BarTime(time, boxRightIdx);
   datetime tLine = BarTime(time, boxRightIdx + InpLineExtraBars);

   for(int k = 0; k < LEVEL_COUNT; k++)
     {
      double price = 0.0;
      string text  = "";
      color  clr   = clrNONE;
      LevelInfo(k, price, text, clr);

      //--- dotted level line: entry candle -> past the box
      string ln = PFX_LEVEL + "L" + IntegerToString(k);
      if(ObjectFind(0, ln) < 0)
        {
         ObjectCreate(0, ln, OBJ_TREND, 0, g_entryTime, price, tLine, price);
         ObjectSetInteger(0, ln, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, ln, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, ln, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, ln, OBJPROP_HIDDEN, true);
        }
      ObjectSetInteger(0, ln, OBJPROP_TIME, 0, g_entryTime);
      ObjectSetInteger(0, ln, OBJPROP_TIME, 1, tLine);
      ObjectSetDouble(0, ln, OBJPROP_PRICE, 0, price);
      ObjectSetDouble(0, ln, OBJPROP_PRICE, 1, price);
      ObjectSetInteger(0, ln, OBJPROP_COLOR, clr);

      //--- label sitting on the line, from the box's right edge
      string tg = PFX_LEVEL + "T" + IntegerToString(k);
      if(ObjectFind(0, tg) < 0)
        {
         ObjectCreate(0, tg, OBJ_TEXT, 0, tBox, price);
         ObjectSetInteger(0, tg, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
         ObjectSetString(0, tg, OBJPROP_FONT, "Arial");
         ObjectSetInteger(0, tg, OBJPROP_FONTSIZE, InpFontSize);
         ObjectSetInteger(0, tg, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, tg, OBJPROP_HIDDEN, true);
        }
      ObjectSetInteger(0, tg, OBJPROP_TIME, 0, tBox);
      ObjectSetDouble(0, tg, OBJPROP_PRICE, 0, price);
      ObjectSetString(0, tg, OBJPROP_TEXT, text);
      ObjectSetInteger(0, tg, OBJPROP_COLOR, clr);
     }
  }

//+------------------------------------------------------------------+
//| Panel                                                            |
//+------------------------------------------------------------------+
string StateName(const int s)
  {
   return (s == TF_BULL) ? "BULL" : (s == TF_BEAR) ? "BEAR" : "MIX";
  }

string SideName(const int dir)
  {
   return (dir > 0) ? "BUY" : "SELL";
  }

void PanelLine(const int k, const string text, const color clr)
  {
   string name = PFX_PANEL + IntegerToString(k);
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
     }
   bool lower = (InpPanelCorner == CORNER_LEFT_LOWER || InpPanelCorner == CORNER_RIGHT_LOWER);
   bool right = (InpPanelCorner == CORNER_RIGHT_UPPER || InpPanelCorner == CORNER_RIGHT_LOWER);
   ENUM_ANCHOR_POINT anchor = lower ? (right ? ANCHOR_RIGHT_LOWER : ANCHOR_LEFT_LOWER)
                                    : (right ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
   int step = InpFontSize + 8;
   int row  = lower ? (PANEL_LINES - 1 - k) : k;

   ObjectSetInteger(0, name, OBJPROP_CORNER, InpPanelCorner);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpPanelX);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpPanelY + row * step);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }

void UpdatePanel()
  {
   if(!InpShowPanel)
      return;

   string tf = StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7);
   bool tuned = (_Period == PERIOD_M5 && StringFind(_Symbol, "XAU") >= 0);
   PanelLine(0, StringFormat("Impulse Pullback MTF  %s %s%s", _Symbol, tf,
                             tuned ? "" : "  (tuned for XAUUSD M5)"),
             tuned ? clrWhite : clrOrange);

   PanelLine(1, StringFormat("D %-4s  H4 %-4s  H1 %-4s  M5 %-4s",
                             StateName(g_sD), StateName(g_sH4), StateName(g_sH1), StateName(g_sM5)),
             g_sH4 == TF_BULL ? clrAqua : g_sH4 == TF_BEAR ? clrMagenta : clrSilver);

   int bull = (g_sD == TF_BULL ? 1 : 0) + (g_sH4 == TF_BULL ? 1 : 0) + (g_sH1 == TF_BULL ? 1 : 0) + (g_sM5 == TF_BULL ? 1 : 0);
   int bear = (g_sD == TF_BEAR ? 1 : 0) + (g_sH4 == TF_BEAR ? 1 : 0) + (g_sH1 == TF_BEAR ? 1 : 0) + (g_sM5 == TF_BEAR ? 1 : 0);
   PanelLine(2, StringFormat("Bull %d/4  Bear %d/4   Buy %s  Sell %s", bull, bear,
                             Allowed(1) ? "OK" : "--", Allowed(-1) ? "OK" : "--"),
             clrSilver);

   string s1, s2 = "";
   color  c1 = clrSilver;
   switch(g_state)
     {
      case ST_WATCH:
         s1 = StringFormat("WAIT PB %s  (%s)", SideName(g_dir),
                           g_touched ? StringFormat("pulled back, confirm %d/%d", g_sinceTouch, InpConfirmBars)
                                     : StringFormat("bar %d/%d", g_watchBars, InpPullbackBars));
         s2 = StringFormat("PB level %s   invalid beyond %s", DoubleToString(g_pbLevel, _Digits),
                           DoubleToString(g_dir > 0 ? g_impLow - g_impBuf : g_impHigh + g_impBuf, _Digits));
         c1 = clrYellow;
         break;
      case ST_LIVE:
         s1 = StringFormat("LIVE %s%s  [%s]", SideName(g_dir), g_reentries > 0 ? " (re-entry)" : "", g_status);
         s2 = StringFormat("E %s  SL %s  TP1 %s  TP2 %s", DoubleToString(g_entry, _Digits),
                           DoubleToString(g_sl, _Digits), DoubleToString(g_tp1, _Digits),
                           DoubleToString(g_tp2, _Digits));
         c1 = (g_dir > 0) ? clrAqua : clrMagenta;
         break;
      case ST_SLWAIT:
         s1 = StringFormat("SL_WAIT %s", SideName(g_dir));
         s2 = StringFormat("Re-entries %d/%d   window %d/%d bars", g_reentries, InpMaxReentries,
                           g_lastIdx - g_firstSLIdx, InpReentryWindow);
         c1 = clrOrange;
         break;
      default:
         s1 = "IDLE - waiting for impulse";
         break;
     }
   PanelLine(3, s1, c1);
   PanelLine(4, s2, clrSilver);
  }

//+------------------------------------------------------------------+
//| Misc                                                             |
//+------------------------------------------------------------------+
void ResetState()
  {
   g_state      = ST_IDLE;
   g_dir        = 0;
   g_watchBars  = 0;
   g_touched    = false;
   g_sinceTouch = 0;
   g_tradeId    = 0;
   g_tradeDir   = 0;
   g_entryIdx   = -1;
   g_exitIdx    = -1;
   g_entryTime  = 0;
   g_tp1Hit     = false;
   g_status     = "";
   g_reentries  = 0;
   g_firstSLIdx = -1;
   g_lastIdx    = -1;
   g_lastTime   = 0;
  }

void Notify(const string msg)
  {
   string tf   = StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7);
   string text = StringFormat("ImpulsePullbackMTF %s %s: %s", _Symbol, tf, msg);
   if(InpAlertPopup)
      Alert(text);
   if(InpAlertPush)
      SendNotification(text);
   if(InpAlertSound)
      PlaySound(InpSoundFile);
  }
//+------------------------------------------------------------------+
