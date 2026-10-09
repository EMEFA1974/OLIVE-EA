//+------------------------------------------------------------------+
//|                                            OliveTradeManager.mq5 |
//|  Trades confirmed arrow signals from a custom indicator (.ex5)   |
//|  and manages the trade (ATR/fixed SL & TP, breakeven, trailing). |
//+------------------------------------------------------------------+
#property copyright   "Olive EA"
#property version     "1.30"
#define   EA_VERSION    "1.30"
#property description "Olive Trade Manager - enters on confirmed arrow signals from a custom indicator"
#property description "and manages the trade. Works with compiled .ex5 indicators (no source needed)."
#property description "Defaults set for XAUUSD M5 (Exness, 3-digit). All distances are in points (3-digit gold: 1000 points = $1)."

#include <Trade/Trade.mqh>

//--- enums ----------------------------------------------------------
enum ENUM_TM_SOURCE
  {
   SOURCE_AUTO    = 0, // Auto (indicator buffers, then chart arrows)
   SOURCE_BUFFERS = 1, // Indicator buffers only
   SOURCE_OBJECTS = 2  // Arrow objects drawn on the chart only
  };

enum ENUM_TM_LOTS
  {
   LOTS_FIXED = 0, // Fixed lot
   LOTS_RISK  = 1  // % of balance risked at the stop loss
  };

enum ENUM_TM_STOP
  {
   STOP_ATR   = 0, // ATR x multiplier
   STOP_FIXED = 1, // Fixed points
   STOP_NONE  = 2  // None
  };

enum ENUM_TM_OPPOSITE
  {
   OPPOSITE_REVERSE = 0, // Close and reverse
   OPPOSITE_CLOSE   = 1, // Close only
   OPPOSITE_IGNORE  = 2  // Ignore - wait until the trade closes
  };

enum ENUM_TM_TRAIL
  {
   TRAIL_ATR   = 0, // ATR x multiplier
   TRAIL_FIXED = 1  // Fixed points
  };

//--- inputs ---------------------------------------------------------
input group "=== Signal indicator ==="
input string           InpIndicatorName   = "";          // Indicator file name (empty = use the one on this chart)
input string           InpIndicatorFilter = "";          // Chart indicator name contains (empty = auto)
input ENUM_TM_SOURCE   InpSignalSource    = SOURCE_AUTO; // Signal source
input int              InpBuyBuffer       = -1;          // Buy arrow buffer (-1 = auto-detect)
input int              InpSellBuffer      = -1;          // Sell arrow buffer (-1 = auto-detect)
input int              InpSignalBar       = 1;           // Signal candle (1 = last closed candle)
input int              InpScanBars        = 2000;        // Bars scanned when auto-detecting
input string           InpObjectPrefix    = "";          // Chart arrows: object name starts with (empty = any)

input group "=== Lot size ==="
input ENUM_TM_LOTS     InpLotMode         = LOTS_FIXED;  // Lot mode
input double           InpFixedLot        = 0.01;        // Fixed lot
input double           InpRiskPercent     = 1.0;         // Risk % of balance (risk mode)
input double           InpMaxLot          = 5.0;         // Maximum lot

input group "=== Stop loss ==="
input ENUM_TM_STOP     InpSLMode          = STOP_ATR;    // Stop loss mode
input double           InpSLAtrMult       = 1.5;         // SL: ATR multiplier
input double           InpSLPoints        = 3000;        // SL: fixed points

input group "=== Take profit ==="
input ENUM_TM_STOP     InpTPMode          = STOP_ATR;    // Take profit mode
input double           InpTPAtrMult       = 3.0;         // TP: ATR multiplier
input double           InpTPPoints        = 6000;        // TP: fixed points
input double           InpTPReducePct     = 15;          // TP: reduce the distance by this % (0 = none)

input group "=== ATR ==="
input int              InpATRPeriod       = 14;             // ATR period
input ENUM_TIMEFRAMES  InpATRTimeframe    = PERIOD_CURRENT; // ATR timeframe

input group "=== Trade management ==="
input ENUM_TM_OPPOSITE InpOpposite        = OPPOSITE_IGNORE;  // Opposite signal while in a trade
input bool             InpUseBreakEven    = false;       // Use breakeven
input double           InpBETriggerPoints = 2000;        // Breakeven: trigger at profit (points)
input double           InpBELockPoints    = 200;         // Breakeven: lock in (points)
input bool             InpUseTrailing     = false;       // Use trailing stop
input ENUM_TM_TRAIL    InpTrailMode       = TRAIL_ATR;   // Trailing mode
input double           InpTrailStartPoints = 3000;       // Trailing: start at profit (points)
input double           InpTrailPoints     = 2000;        // Trailing: distance (fixed points)
input double           InpTrailAtrMult    = 2.0;         // Trailing: distance (ATR multiplier)
input double           InpTrailStepPoints = 100;         // Trailing: minimum step (points)

input group "=== Simple grid ==="
input bool             InpUseGrid         = false;       // Grid on (panel button): both trades have NO SL
input double           InpGridPoints      = 500;         // Grid distance in POINTS beyond the last trade (3-digit gold: 1000 = $1)
input int              InpMaxTrades       = 2;           // Max running EA trades incl. the 1st (grid)
input double           InpGridLotMult     = 1.0;         // Grid: each new trade lot = previous lot x this

input group "=== Equity protector ==="
input double           InpEquityProtectPct = 5.0;        // Close all EA trades when their loss reaches % of equity (0 = off)

input group "=== Filters ==="
input double           InpMaxSpreadPoints = 0;           // Max spread in points (0 = off)
input double           InpDailyLossPct    = 0;           // Daily loss limit % of balance (0 = off)

input group "=== General ==="
input bool             InpAutoTrade       = true;        // Auto-trade signals (also a panel button)
input ulong            InpMagic           = 20261008;    // Magic number
input string           InpComment         = "OliveTM";   // Order comment
input int              InpSlippagePoints  = 300;         // Max slippage (points)
input bool             InpPopupAlerts     = true;        // Popup alerts on trades
input bool             InpPushAlerts      = true;        // Push notifications on trades
input bool             InpDiagnostics     = true;        // Log what the EA sees on every candle (Experts tab)

input group "=== Signal dots ==="
input bool             InpShowDots        = true;        // Mark signal candles with dots
input color            InpBuyDotColor     = clrAqua;     // Buy dot colour (below the candle)
input color            InpSellDotColor    = clrMagenta;  // Sell dot colour (above the candle)
input color            InpSkipDotColor    = clrYellow;   // Skipped signal dot colour (no trade opened)
input int              InpDotSize         = 1;           // Dot size (1-5)
input double           InpDotGapPoints    = 300;         // Gap between candle and dot (points)
input int              InpDotHistoryBars  = 500;         // Past candles to mark at start

input group "=== Panel ==="
input bool             InpShowPanel       = true;        // Show panel
input int              InpPanelX          = 12;          // Panel start X position (drag the header to move it)
input int              InpPanelY          = 30;          // Panel start Y position
input string           InpPanelFont       = "Segoe UI";  // Panel font (e.g. Segoe UI, Segoe UI Light, Arial)

//--- constants ------------------------------------------------------
#define PFX      "OTM_"
#define DOT_PFX  "OTMD_"   // dots survive EA restarts; removed only when the EA is removed
#define PANEL_W  320

#define C_BG       C'16,20,38'
#define C_BORDER   C'110,80,230'
#define C_HEADER   C'82,48,190'
#define C_STRIPE   C'255,190,40'
#define C_SECTION  C'0,200,255'
#define C_LINE     C'45,52,90'
#define C_LABEL    C'205,212,235'
#define C_TEXT     clrWhite
#define C_MUTED    C'175,183,210'
#define C_BUY      C'0,220,130'
#define C_SELL     C'255,75,95'
#define C_WARN     C'255,185,0'
#define C_GOLD     C'255,205,70'
#define C_BTN_BUY  C'0,160,90'
#define C_BTN_SELL C'205,40,65'
#define C_BTN_CLS  C'240,130,0'
#define C_BTN_ON   C'40,115,255'
#define C_BTN_OFF  C'85,88,110'
#define C_BTN_GRID C'150,60,220'

//--- state ----------------------------------------------------------
CTrade   trade;
int      g_ind          = INVALID_HANDLE;
string   g_indName      = "";
int      g_atr          = INVALID_HANDLE;
int      g_buyBuf       = -1;
int      g_sellBuf      = -1;
int      g_source       = 0;      // 0 = not found yet, 1 = buffers, 2 = chart arrows
string   g_status       = "Starting...";
string   g_reported     = "|";    // indicators whose scan report has been printed
uint     g_nextResolve  = 0;
uint     g_nextObjScan  = 0;
bool     g_objDirty     = true;   // a chart object was created since the last arrow scan
datetime g_objScanBar   = 0;      // signal candle of the last arrow scan
int      g_arrowCount   = 0;      // arrow objects found when the signal source was set
datetime g_lastSignalBar = 0;     // candle of the last signal acted on
int      g_lastSigDir   = 0;
datetime g_lastSigTime  = 0;
bool     g_auto         = true;
bool     g_grid         = false;
uint     g_gridRetry    = 0;
string   g_message      = "";
double   g_dayClosed    = 0;
int      g_dayTrades    = 0;
int      g_dayWins      = 0;
datetime g_lossAlertDay = 0;
datetime g_histBar      = 0;      // candle when past signals were last marked
uint     g_histRetry    = 0;      // next retry while no past signals were found
datetime g_diagBar      = 0;      // candle last written to the diagnostics log
bool     g_panel        = false;
int      g_px           = 0;      // panel position (pixels from the chart's top-left)
int      g_py           = 0;
bool     g_collapsed    = false;
bool     g_dragging     = false;
bool     g_mouseDown    = false;
int      g_dragDX       = 0;
int      g_dragDY       = 0;
string   S_UP, S_DN, S_RT, S_DOT, S_SEP;

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
double NormPrice(double p)
  {
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts > 0)
      p = MathRound(p / ts) * ts;
   return NormalizeDouble(p, _Digits);
  }

string Px(double p)        { return (p > 0) ? DoubleToString(p, _Digits) : "-"; }
string Money(double v)     { return (v >= 0 ? "+" : "") + DoubleToString(v, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY); }
color  PLColor(double v)   { return (v > 0) ? C_BUY : (v < 0 ? C_SELL : C_TEXT); }
string TfName()            { return StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7); }

bool IsSignalValue(double v)
  {
   return (MathIsValidNumber(v) && v != EMPTY_VALUE && v != 0.0 && MathAbs(v) < 1e100);
  }

double AtrValue()
  {
   double a[1];
   if(g_atr == INVALID_HANDLE || CopyBuffer(g_atr, 0, 1, 1, a) != 1)
      return 0;
   return a[0];
  }

double SpreadPoints()
  {
   MqlTick tk;
   if(!SymbolInfoTick(_Symbol, tk))
      return 0;
   return (tk.ask - tk.bid) / _Point;
  }

void Msg(const string text)
  {
   g_message = TimeToString(TimeCurrent(), TIME_MINUTES) + "  " + text;
   Print(text);
  }

void Notify(const string text)
  {
   Msg(text);
   string full = "Olive TM " + _Symbol + " " + TfName() + ": " + text;
   if(InpPopupAlerts && !MQLInfoInteger(MQL_TESTER))
      Alert(full);
   if(InpPushAlerts && !MQLInfoInteger(MQL_TESTER))
      SendNotification(full);
  }

//+------------------------------------------------------------------+
//| Signal reading: buffers                                          |
//+------------------------------------------------------------------+
bool BufferValue(int buf, int shift, double &v)
  {
   double a[1];
   if(CopyBuffer(g_ind, buf, shift, 1, a) != 1)
      return false;
   v = a[0];
   return IsSignalValue(v);
  }

// One buffer carrying both directions: arrow below the candle = buy,
// above = sell; non-price values use the sign (+ buy, - sell).
int DirFromValue(double v, int shift)
  {
   double hi  = iHigh(_Symbol, _Period, shift);
   double lo  = iLow(_Symbol, _Period, shift);
   double mid = (hi + lo) / 2.0;
   double ref = MathMax(AtrValue(), hi - lo);
   if(ref <= 0)
      ref = 100 * _Point;
   if(MathAbs(v - mid) <= 20.0 * ref)
      return (v < mid) ? 1 : -1;
   return (v > 0) ? 1 : -1;
  }

// Scans every buffer of the indicator and picks the buy/sell arrow buffers.
// Returns 1 = found, 0 = no arrow buffers, -1 = indicator not ready yet.
int ResolveBuffers(int h, const string name)
  {
   int calc = BarsCalculated(h);
   if(calc <= 0)
      return -1;
   if(InpBuyBuffer >= 0 && InpSellBuffer >= 0)
     {
      g_buyBuf  = InpBuyBuffer;
      g_sellBuf = InpSellBuffer;
      return 1;
     }

   int n = MathMin(InpScanBars, calc - 1);
   if(n < 20)
      return -1;
   double hi[], lo[];
   ArraySetAsSeries(hi, true);
   ArraySetAsSeries(lo, true);
   if(CopyHigh(_Symbol, _Period, 1, n, hi) != n || CopyLow(_Symbol, _Period, 1, n, lo) != n)
      return -1;
   double avgRange = 0;
   for(int i = 0; i < n; i++)
      avgRange += hi[i] - lo[i];
   avgRange = MathMax(avgRange / n, _Point);

   int buyBuf = -1, sellBuf = -1, mixBuf = -1;
   int buyCnt = 0, sellCnt = 0, mixCnt = 0;
   string report = "";
   for(int b = 0; b < 64; b++)
     {
      double v[];
      ArraySetAsSeries(v, true);
      int got = CopyBuffer(h, b, 1, n, v);
      if(got <= 0)
         break;
      int cnt = 0, below = 0, above = 0, other = 0, pos = 0, neg = 0;
      for(int i = 0; i < got && i < n; i++)
        {
         if(!IsSignalValue(v[i]))
            continue;
         cnt++;
         double mid = (hi[i] + lo[i]) / 2.0;
         if(MathAbs(v[i] - mid) <= 20.0 * avgRange)
           {
            if(v[i] < mid)
               below++;
            else
               above++;
           }
         else
           {
            other++;
            if(v[i] > 0)
               pos++;
            else
               neg++;
           }
        }

      string verdict = "ignored";
      if(cnt == 0)
         verdict = "empty";
      else
         if(cnt > got * 0.3)
            verdict = "line (not arrows)";
         else
            if(other > cnt / 2)
              {
               if(pos > 0 && neg > 0)
                 {
                  verdict = "+/- signal values";
                  if(cnt > mixCnt) { mixBuf = b; mixCnt = cnt; }
                 }
               else
                  verdict = "flag values (direction unclear)";
              }
            else
               if(below >= cnt * 0.8)
                 {
                  verdict = "BUY arrows";
                  if(below > buyCnt) { buyBuf = b; buyCnt = below; }
                 }
               else
                  if(above >= cnt * 0.8)
                    {
                     verdict = "SELL arrows";
                     if(above > sellCnt) { sellBuf = b; sellCnt = above; }
                    }
                  else
                     if(below > 0 && above > 0)
                       {
                        verdict = "BUY+SELL arrows";
                        if(cnt > mixCnt) { mixBuf = b; mixCnt = cnt; }
                       }
      report += StringFormat("\n   buffer %d: %d values (below candle %d, above %d, other %d) -> %s",
                             b, cnt, below, above, other, verdict);
     }

   int result = 0;
   if(buyBuf >= 0 && sellBuf >= 0)
     {
      g_buyBuf  = buyBuf;
      g_sellBuf = sellBuf;
      result = 1;
     }
   else
      if(mixBuf >= 0)
        {
         g_buyBuf  = mixBuf;
         g_sellBuf = mixBuf;
         result = 1;
        }

   if(result == 1 || StringFind(g_reported, "|" + name + "|") < 0)
     {
      g_reported += name + "|";
      Print("Buffer scan of '", name, "' over ", n, " bars:", report);
      if(result == 0)
         Print("No arrow buffers found in '", name, "'. Set Buy/Sell buffer inputs or use chart-arrow mode.");
     }
   return result;
  }

//+------------------------------------------------------------------+
//| Signal reading: arrow objects drawn on the chart                 |
//+------------------------------------------------------------------+
int ArrowObjectDir(const string name)
  {
   if(StringSubstr(name, 0, 1) == "#")          // MT5 trade-history arrows
      return 0;
   if(StringFind(name, PFX) == 0 || StringFind(name, DOT_PFX) == 0)
      return 0;
   if(InpObjectPrefix != "" && StringFind(name, InpObjectPrefix) != 0)
      return 0;
   ENUM_OBJECT type = (ENUM_OBJECT)ObjectGetInteger(0, name, OBJPROP_TYPE);
   switch(type)
     {
      case OBJ_ARROW_UP:
      case OBJ_ARROW_BUY:
      case OBJ_ARROW_THUMB_UP:
         return 1;
      case OBJ_ARROW_DOWN:
      case OBJ_ARROW_SELL:
      case OBJ_ARROW_THUMB_DOWN:
         return -1;
      case OBJ_ARROW:
         break;
      default:
         return 0;
     }
   long code = ObjectGetInteger(0, name, OBJPROP_ARROWCODE);
   if(code == 217 || code == 221 || code == 225 || code == 233 || code == 241)
      return 1;
   if(code == 218 || code == 222 || code == 226 || code == 234 || code == 242)
      return -1;
   // other symbols: use position relative to the candle (main window only)
   if(ObjectFind(0, name) != 0)
      return 0;
   int sh = iBarShift(_Symbol, _Period, (datetime)ObjectGetInteger(0, name, OBJPROP_TIME));
   if(sh < 0)
      return 0;
   double price = ObjectGetDouble(0, name, OBJPROP_PRICE);
   double mid   = (iHigh(_Symbol, _Period, sh) + iLow(_Symbol, _Period, sh)) / 2.0;
   return (price < mid) ? 1 : -1;
  }

int ObjectSignalAt(int shift)
  {
   datetime from = iTime(_Symbol, _Period, shift);
   datetime to   = from + PeriodSeconds(_Period);
   int buy = 0, sell = 0;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, -1, -1);
      datetime t = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME);
      if(t < from || t >= to)
         continue;
      int d = ArrowObjectDir(name);
      if(d > 0)
         buy++;
      else
         if(d < 0)
            sell++;
     }
   if(buy > 0 && sell == 0)
      return 1;
   if(sell > 0 && buy == 0)
      return -1;
   return 0;
  }

int CountArrowObjects()
  {
   int cnt = 0;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = 0; i < total; i++)
      if(ArrowObjectDir(ObjectName(0, i, -1, -1)) != 0)
         cnt++;
   return cnt;
  }

//+------------------------------------------------------------------+
//| Signal reading: common                                           |
//+------------------------------------------------------------------+
int ReadSignal(int shift)
  {
   if(g_source == 1)
     {
      double v;
      if(g_buyBuf == g_sellBuf)
         return BufferValue(g_buyBuf, shift, v) ? DirFromValue(v, shift) : 0;
      bool b = BufferValue(g_buyBuf, shift, v);
      bool s = BufferValue(g_sellBuf, shift, v);
      if(b && !s)
         return 1;
      if(s && !b)
         return -1;
      return 0;
     }
   if(g_source == 2)
      return ObjectSignalAt(shift);
   return 0;
  }

// Dot under a buy candle's low or above a sell candle's high;
// skipped signals (no trade opened) get the skipped colour.
void DrawDot(int dir, int shift, bool skipped = false, bool overwrite = true)
  {
   if(!InpShowDots || dir == 0)
      return;
   datetime t = iTime(_Symbol, _Period, shift);
   if(t == 0)
      return;
   string n = DOT_PFX + IntegerToString((long)t);
   if(!overwrite && ObjectFind(0, n) >= 0)
      return;                                  // keep the colour it got when it was traded/skipped
   double price = (dir > 0) ? iLow(_Symbol, _Period, shift) - InpDotGapPoints * _Point
                            : iHigh(_Symbol, _Period, shift) + InpDotGapPoints * _Point;
   if(ObjectFind(0, n) < 0)
      ObjectCreate(0, n, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, n, OBJPROP_TIME, t);
   ObjectSetDouble(0, n, OBJPROP_PRICE, price);
   ObjectSetInteger(0, n, OBJPROP_ARROWCODE, 108);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, dir > 0 ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0, n, OBJPROP_COLOR, skipped ? InpSkipDotColor : (dir > 0 ? InpBuyDotColor : InpSellDotColor));
   ObjectSetInteger(0, n, OBJPROP_WIDTH, MathMax(1, MathMin(5, InpDotSize)));
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, n, OBJPROP_BACK, false);
  }

// Marks past signal candles with dots and remembers the most recent signal.
// Re-run on every new candle, so dots appear even if the indicator
// finished loading its history after the EA started. Reads every chart
// object (or each buffer) only once, so it stays fast with thousands of arrows.
void ScanHistory()
  {
   int maxBars = MathMin(MathMax(InpDotHistoryBars, 1), Bars(_Symbol, _Period) - 1);
   int first   = MathMax(InpSignalBar, 1);
   int found = 0, newestShift = -1, newestDir = 0;

   if(g_source == 2)
     {
      datetime oldest = iTime(_Symbol, _Period, maxBars - 1);
      datetime limit  = iTime(_Symbol, _Period, first - 1);   // only candles at or before the signal candle
      int total = ObjectsTotal(0, -1, -1);
      for(int i = 0; i < total; i++)
        {
         string   name = ObjectName(0, i, -1, -1);
         datetime t    = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME);
         if(t < oldest || t >= limit)
            continue;
         int d = ArrowObjectDir(name);
         if(d == 0)
            continue;
         int sh = iBarShift(_Symbol, _Period, t);
         if(sh < first)
            continue;
         found++;
         if(newestShift < 0 || sh < newestShift)
           {
            newestShift = sh;
            newestDir   = d;
           }
         DrawDot(d, sh, false, false);
        }
     }
   else
      if(g_source == 1 && maxBars > first)
        {
         int n = maxBars - first;
         double bv[], sv[];
         ArraySetAsSeries(bv, true);
         ArraySetAsSeries(sv, true);
         int nb = CopyBuffer(g_ind, g_buyBuf, first, n, bv);
         int ns = (g_sellBuf == g_buyBuf) ? nb : CopyBuffer(g_ind, g_sellBuf, first, n, sv);
         for(int k = 0; k < nb && k < ns; k++)
           {
            int sh = first + k, d = 0;
            if(g_buyBuf == g_sellBuf)
               d = IsSignalValue(bv[k]) ? DirFromValue(bv[k], sh) : 0;
            else
              {
               bool b = IsSignalValue(bv[k]), sl = IsSignalValue(sv[k]);
               d = (b && !sl) ? 1 : (sl && !b) ? -1 : 0;
              }
            if(d == 0)
               continue;
            found++;
            if(newestShift < 0)
              {
               newestShift = sh;
               newestDir   = d;
              }
            DrawDot(d, sh, false, false);
           }
        }

   if(newestShift >= 0 && iTime(_Symbol, _Period, newestShift) >= g_lastSigTime)
     {
      g_lastSigDir  = newestDir;
      g_lastSigTime = iTime(_Symbol, _Period, newestShift);
     }
   g_histBar   = iTime(_Symbol, _Period, 0);
   g_histRetry = (found > 0) ? 0 : GetTickCount() + 10000;
   if(found == 0)
      Print("No past signals found yet in the last ", maxBars, " candles - retrying in 10 s");
   ChartRedraw();
  }

void SetResolved(int source)
  {
   g_source = source;
   if(source == 1)
     {
      g_status = "Indicator buffers";
      Print("Signals: '", g_indName, "' buy buffer ", g_buyBuf, ", sell buffer ", g_sellBuf,
            (g_buyBuf == g_sellBuf ? " (one buffer, direction from arrow position)" : ""));
     }
   else
     {
      g_status = "Chart arrows";
      g_arrowCount = CountArrowObjects();
      Print("Signals: reading arrow objects drawn on the chart (", g_arrowCount, " found)");
     }
   ScanHistory();
  }

// Finds the indicator and its signal buffers; retried until it succeeds.
void TryResolve()
  {
   uint now = GetTickCount();
   if(now < g_nextResolve)
      return;
   g_nextResolve = now + 3000;

   bool pending = false;
   if(InpSignalSource != SOURCE_OBJECTS)
     {
      if(InpIndicatorName != "")
        {
         if(g_ind == INVALID_HANDLE)
           {
            g_indName = InpIndicatorName;
            g_ind = iCustom(_Symbol, _Period, InpIndicatorName);
            if(g_ind == INVALID_HANDLE)
              {
               g_status = "Cannot load indicator";
               Print("Cannot load '", InpIndicatorName, "' - put it in MQL5\\Indicators and check the name. Error ", GetLastError());
              }
           }
         if(g_ind != INVALID_HANDLE)
           {
            int r = ResolveBuffers(g_ind, g_indName);
            if(r > 0)
              {
               SetResolved(1);
               return;
              }
            pending = (r < 0);
            g_status = pending ? "Indicator calculating..." : "No arrow buffers found";
           }
        }
      else
        {
         bool any = false;
         int wins = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
         for(int w = 0; w < wins; w++)
           {
            int cnt = ChartIndicatorsTotal(0, w);
            for(int i = 0; i < cnt; i++)
              {
               string nm = ChartIndicatorName(0, w, i);
               if(InpIndicatorFilter != "" && StringFind(nm, InpIndicatorFilter) < 0)
                  continue;
               int h = ChartIndicatorGet(0, w, nm);
               if(h == INVALID_HANDLE)
                  continue;
               any = true;
               int r = ResolveBuffers(h, nm);
               if(r > 0)
                 {
                  if(g_ind != INVALID_HANDLE)
                     IndicatorRelease(g_ind);
                  g_ind = h;
                  g_indName = nm;
                  SetResolved(1);
                  return;
                 }
               if(r < 0)
                  pending = true;
               IndicatorRelease(h);
              }
           }
         g_status = !any ? "No indicator on chart" : (pending ? "Indicator calculating..." : "No arrow buffers found");
        }
     }
   if(pending)
      return;
   if(InpSignalSource == SOURCE_OBJECTS || (InpSignalSource == SOURCE_AUTO && CountArrowObjects() > 0))
      SetResolved(2);
  }

//+------------------------------------------------------------------+
//| Positions & stats                                                |
//+------------------------------------------------------------------+
bool IsEAPosition()
  {
   return PositionGetString(POSITION_SYMBOL) == _Symbol && (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic;
  }

// Direction of the EA trade: 1 buy, -1 sell, 0 none.
int EAPosition(ulong &ticket)
  {
   ticket = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsEAPosition())
         continue;
      ticket = t;
      return (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
     }
   return 0;
  }

bool CloseEAPositions()
  {
   bool ok = true;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsEAPosition())
         continue;
      if(!trade.PositionClose(t))
        {
         ok = false;
         Msg("Close failed: " + trade.ResultRetcodeDescription());
        }
     }
   return ok;
  }

// Floating P/L of EA trades (ea=true) or of the other trades on this symbol.
double FloatingPL(bool ea, int &count)
  {
   double pl = 0;
   count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(((ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic) != ea)
         continue;
      pl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      count++;
     }
   return pl;
  }

void UpdateDayStats()
  {
   g_dayClosed = 0;
   g_dayTrades = 0;
   g_dayWins   = 0;
   datetime dayStart = (datetime)(((long)TimeCurrent() / 86400) * 86400);
   if(!HistorySelect(dayStart, TimeCurrent() + 86400))
      return;
   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol || (ulong)HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic)
         continue;
      double pl = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_COMMISSION);
      g_dayClosed += pl;
      ENUM_DEAL_ENTRY e = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY);
      if(e == DEAL_ENTRY_OUT || e == DEAL_ENTRY_OUT_BY || e == DEAL_ENTRY_INOUT)
        {
         g_dayTrades++;
         if(HistoryDealGetDouble(d, DEAL_PROFIT) > 0)
            g_dayWins++;
        }
     }
  }

bool DailyLossHit()
  {
   if(InpDailyLossPct <= 0)
      return false;
   int cnt;
   double total    = g_dayClosed + FloatingPL(true, cnt);
   double startBal = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayClosed;
   bool hit = (total <= -startBal * InpDailyLossPct / 100.0);
   if(hit)
     {
      datetime today = (datetime)(((long)TimeCurrent() / 86400) * 86400);
      if(g_lossAlertDay != today)
        {
         g_lossAlertDay = today;
         Notify("Daily loss limit reached - no new trades today");
        }
     }
   return hit;
  }

string EntryBlockReason()
  {
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return "Algo Trading is off in the terminal";
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return "Algo trading not allowed for this EA";
   double spread = SpreadPoints();
   if(InpMaxSpreadPoints > 0 && spread > InpMaxSpreadPoints)
      return StringFormat("spread %.0f > max %.0f points", spread, InpMaxSpreadPoints);
   if(DailyLossHit())
      return "daily loss limit reached";
   return "";
  }

//+------------------------------------------------------------------+
//| Trading                                                          |
//+------------------------------------------------------------------+
double CalcLots(double slDist)
  {
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0)
      step = 0.01;

   double lots = InpFixedLot;
   if(InpLotMode == LOTS_RISK)
     {
      if(slDist <= 0)
         Msg("Risk lot needs a stop loss - using fixed lot");
      else
        {
         double risk = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
         double tv   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
         if(tv <= 0)
            tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         if(tv > 0 && ts > 0)
            lots = risk / (slDist / ts * tv);
        }
     }

   lots = MathFloor(lots / step + 1e-9) * step;
   if(InpMaxLot > 0)
      lots = MathMin(lots, InpMaxLot);
   lots = MathMin(lots, vmax);
   if(lots < vmin)
     {
      if(InpLotMode == LOTS_RISK)
         Msg(StringFormat("Risk lot below broker minimum - using %.2f", vmin));
      lots = vmin;
     }
   int vd = (int)MathMax(0, MathCeil(-MathLog10(step) - 1e-9));
   return NormalizeDouble(lots, vd);
  }

// SL and TP distances (price units) from the inputs; false if ATR isn't ready.
bool StopDistances(double &slDist, double &tpDist)
  {
   slDist = 0;
   tpDist = 0;
   MqlTick tk;
   if(!SymbolInfoTick(_Symbol, tk))
      return false;
   double atr = AtrValue();
   if((InpSLMode == STOP_ATR || InpTPMode == STOP_ATR) && atr <= 0)
      return false;
   if(InpSLMode == STOP_ATR)
      slDist = atr * InpSLAtrMult;
   else
      if(InpSLMode == STOP_FIXED)
         slDist = InpSLPoints * _Point;
   if(InpTPMode == STOP_ATR)
      tpDist = atr * InpTPAtrMult;
   else
      if(InpTPMode == STOP_FIXED)
         tpDist = InpTPPoints * _Point;
   if(InpTPReducePct > 0 && InpTPReducePct < 100)
      tpDist *= 1.0 - InpTPReducePct / 100.0;
   double minDist = (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) + 2) * _Point + (tk.ask - tk.bid);
   if(slDist > 0 && slDist < minDist)
      slDist = minDist;
   if(tpDist > 0 && tpDist < minDist)
      tpDist = minDist;
   return true;
  }

bool OpenTrade(int dir, const string why)
  {
   MqlTick tk;
   if(!SymbolInfoTick(_Symbol, tk))
      return false;
   double slDist, tpDist;
   if(!StopDistances(slDist, tpDist))
     {
      Msg("ATR not ready - trade skipped");
      return false;
     }

   double price = (dir > 0) ? tk.ask : tk.bid;
   double sl = 0, tp = 0;
   // grid on: no SL; a 2nd trade (also without SL) opens one grid distance
   // against it, and the equity protector limits the loss
   double gridDist  = InpGridPoints * _Point;
   bool   grid      = (g_grid && gridDist > 0);
   double gridLevel = 0;
   if(grid)
      gridLevel = NormPrice(dir > 0 ? price - gridDist : price + gridDist);
   else
      if(slDist > 0)
         sl = NormPrice(dir > 0 ? price - slDist : price + slDist);
   if(tpDist > 0)
      tp = NormPrice(dir > 0 ? price + tpDist : price - tpDist);

   double lots = CalcLots(slDist);
   double margin = 0;
   if(OrderCalcMargin(dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lots, price, margin) &&
      margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
     {
      Msg(StringFormat("Not enough free margin for %.2f lots", lots));
      return false;
     }

   bool ok = (dir > 0) ? trade.Buy(lots, _Symbol, price, sl, tp, InpComment)
                       : trade.Sell(lots, _Symbol, price, sl, tp, InpComment);
   uint rc = trade.ResultRetcode();
   if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_DONE_PARTIAL && rc != TRADE_RETCODE_PLACED))
     {
      Msg(StringFormat("%s failed: %u %s", dir > 0 ? "BUY" : "SELL", rc, trade.ResultRetcodeDescription()));
      return false;
     }
   Notify(StringFormat("%s %.2f lots at %s (%s)  SL %s  TP %s%s", dir > 0 ? "BUY" : "SELL", lots,
                       Px(trade.ResultPrice() > 0 ? trade.ResultPrice() : price), why,
                       grid ? "none (grid)" : Px(sl), Px(tp), grid ? "  grid at " + Px(gridLevel) : ""));
   return true;
  }

//+------------------------------------------------------------------+
//| Simple grid                                                      |
//| Works only from the EA trades that are open, so nothing has to   |
//| be remembered between ticks or restarts.                         |
//+------------------------------------------------------------------+
// Open EA trades: count, direction (1/-1, 0 = none), TP of the first trade,
// lot of the latest trade and the price where the next grid trade opens.
int GridInfo(int &count, double &nextLevel, double &tp, double &lastLot)
  {
   count     = 0;
   nextLevel = 0;
   tp        = 0;
   lastLot   = 0;
   int      dir = 0;
   double   worst = 0;
   datetime firstTime = 0, lastTime = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsEAPosition())
         continue;
      count++;
      bool     isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double   open  = PositionGetDouble(POSITION_PRICE_OPEN);
      datetime time  = (datetime)PositionGetInteger(POSITION_TIME);
      dir   = isBuy ? 1 : -1;
      worst = (worst == 0) ? open : (isBuy ? MathMin(worst, open) : MathMax(worst, open));
      if(firstTime == 0 || time < firstTime)
        {
         firstTime = time;
         tp = PositionGetDouble(POSITION_TP);
        }
      if(time >= lastTime)
        {
         lastTime = time;
         lastLot  = PositionGetDouble(POSITION_VOLUME);
        }
     }
   if(count > 0)
      nextLevel = NormPrice(dir > 0 ? worst - InpGridPoints * _Point : worst + InpGridPoints * _Point);
   return dir;
  }

// Grid mode: EA trades carry no stop loss. Removes any SL that sits on the
// losing side of the entry (a breakeven/trailing SL in profit is kept).
void GridStripSL()
  {
   static uint nextTry = 0;
   if(GetTickCount() < nextTry)
      return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsEAPosition())
         continue;
      bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      if(sl <= 0 || (isBuy ? sl >= open : sl <= open))
         continue;
      if(trade.PositionModify(t, 0, PositionGetDouble(POSITION_TP)))
         Msg("Grid: SL removed from trade #" + IntegerToString((long)t));
      else
        {
         Msg("Grid: could not remove SL - " + trade.ResultRetcodeDescription());
         nextTry = GetTickCount() + 5000;
        }
     }
  }

void ManageGrid()
  {
   if(!g_grid || InpGridPoints <= 0)
      return;
   GridStripSL();
   int    count;
   double level, tp, lastLot;
   int    dir = GridInfo(count, level, tp, lastLot);
   if(dir == 0 || count >= InpMaxTrades)
      return;
   MqlTick tk;
   if(!SymbolInfoTick(_Symbol, tk))
      return;
   if(dir > 0 ? tk.bid > level : tk.ask < level)
      return;                                   // next grid level not reached yet
   if(GetTickCount() < g_gridRetry)
      return;
   g_gridRetry = GetTickCount() + 5000;

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0)
      step = 0.01;
   double lots = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
                         MathFloor(lastLot * InpGridLotMult / step + 1e-9) * step);
   if(InpMaxLot > 0)
      lots = MathMin(lots, InpMaxLot);
   lots = NormalizeDouble(lots, (int)MathMax(0, MathCeil(-MathLog10(step) - 1e-9)));
   double price = (dir > 0) ? tk.ask : tk.bid;
   bool ok = (dir > 0) ? trade.Buy(lots, _Symbol, price, 0, tp, InpComment + " grid")
                       : trade.Sell(lots, _Symbol, price, 0, tp, InpComment + " grid");
   uint rc = trade.ResultRetcode();
   if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_DONE_PARTIAL && rc != TRADE_RETCODE_PLACED))
     {
      Msg(StringFormat("Grid trade failed: %u %s - retrying", rc, trade.ResultRetcodeDescription()));
      return;
     }
   Notify(StringFormat("Grid trade %d/%d: %s %.2f lots at %s  SL none  TP %s (shared)", count + 1, InpMaxTrades,
                       dir > 0 ? "BUY" : "SELL", lots, Px(trade.ResultPrice() > 0 ? trade.ResultPrice() : price), Px(tp)));
  }

// Grid switched off with a single EA trade open: give it a normal SL.
void GridDisarm()
  {
   ulong ticket;
   int    count;
   double level, tp, lastLot, slDist, tpDist;
   if(GridInfo(count, level, tp, lastLot) == 0 || count != 1 || EAPosition(ticket) == 0)
      return;                                   // several grid trades open: just stop adding more
   if(!StopDistances(slDist, tpDist) || slDist <= 0 || !PositionSelectByTicket(ticket) ||
      PositionGetDouble(POSITION_SL) > 0)
      return;
   bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   double open  = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = NormPrice(isBuy ? open - slDist : open + slDist);
   double cur   = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if((isBuy ? cur > sl : cur < sl) && trade.PositionModify(ticket, sl, PositionGetDouble(POSITION_TP)))
      Msg("Grid off - SL set to " + Px(sl));
   else
      Msg("Grid off - price is past the normal SL, trade left without SL");
  }

//+------------------------------------------------------------------+
//| Equity protector                                                 |
//+------------------------------------------------------------------+
// Closes all EA trades when their floating loss reaches the set % of the
// current equity; the EA then simply waits for the next signal.
void CheckEquityProtector()
  {
   if(InpEquityProtectPct <= 0)
      return;
   int cnt;
   double pl = FloatingPL(true, cnt);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(cnt == 0 || pl >= 0 || equity <= 0)
      return;
   double lossPct = -pl / equity * 100.0;
   if(lossPct < InpEquityProtectPct)
      return;
   static uint nextTry = 0;
   if(GetTickCount() < nextTry)
      return;                                   // a close is already in progress / failed just now
   nextTry = GetTickCount() + 3000;
   Notify(StringFormat("Equity protector: EA loss %s = %.1f%% of equity - closing %d trade(s), waiting for next signal",
                       Money(pl), lossPct, cnt));
   CloseEAPositions();
  }

// Acts on a signal; returns true only if a new trade was opened.
bool TradeSignal(int dir, datetime bar)
  {
   string side = (dir > 0) ? "BUY" : "SELL";
   Msg(side + " signal on " + TimeToString(bar, TIME_DATE | TIME_MINUTES) + " candle");
   if(!g_auto)
     {
      Msg(side + " skipped: auto-trading is off");
      return false;
     }

   ulong ticket;
   int cur = EAPosition(ticket);
   if(cur != 0 && (cur == dir || InpOpposite == OPPOSITE_IGNORE))
     {
      Msg(side + " signal ignored - trade still running");
      return false;
     }
   if(cur != 0)
     {
      if(!CloseEAPositions())
         return false;
      if(InpOpposite == OPPOSITE_CLOSE)
         return false;
     }
   string block = EntryBlockReason();
   if(block != "")
     {
      Msg(side + " skipped: " + block);
      return false;
     }
   return OpenTrade(dir, "signal");
  }

void OnSignal(int dir, datetime bar)
  {
   g_lastSigDir  = dir;
   g_lastSigTime = bar;
   bool traded = TradeSignal(dir, bar);
   DrawDot(dir, iBarShift(_Symbol, _Period, bar), !traded);
   ChartRedraw();
  }

string RawBuffer(int buf, int shift)
  {
   double a[1];
   if(CopyBuffer(g_ind, buf, shift, 1, a) != 1)
      return "read error " + IntegerToString(GetLastError());
   if(!IsSignalValue(a[0]))
      return "empty";
   return DoubleToString(a[0], _Digits);
  }

// One line per candle: what the indicator showed and why the EA did or did not trade.
void Diagnostics()
  {
   if(!InpDiagnostics)
      return;
   datetime bar0 = iTime(_Symbol, _Period, 0);
   if(bar0 == g_diagBar || TimeCurrent() - bar0 < 5)
      return;
   g_diagBar = bar0;
   datetime bar = iTime(_Symbol, _Period, InpSignalBar);
   string line = "[diag] candle " + TimeToString(bar, TIME_DATE | TIME_MINUTES) + ": ";
   if(g_source == 0)
      line += "signals not found yet (" + g_status + ")";
   else
      if(g_source == 1)
         line += (g_buyBuf == g_sellBuf)
                 ? StringFormat("buffer #%d = %s", g_buyBuf, RawBuffer(g_buyBuf, InpSignalBar))
                 : StringFormat("buy #%d = %s, sell #%d = %s", g_buyBuf, RawBuffer(g_buyBuf, InpSignalBar),
                                g_sellBuf, RawBuffer(g_sellBuf, InpSignalBar));
      else
         line += StringFormat("chart arrows (%d objects on chart)", ObjectsTotal(0, -1, -1));
   int sig = (g_source != 0) ? ReadSignal(InpSignalBar) : 0;
   line += " -> " + (sig > 0 ? "BUY" : sig < 0 ? "SELL" : "no signal");
   if(sig != 0)
      line += (bar == g_lastSignalBar) ? " (handled)" : " (not handled yet)";
   ulong t;
   int pos = EAPosition(t);
   string block = EntryBlockReason();
   line += " | auto " + (g_auto ? "on" : "OFF") + " | EA trade " + (pos > 0 ? "BUY" : pos < 0 ? "SELL" : "none") +
           (block != "" ? " | blocked: " + block : "");
   int    gcount;
   double glevel, gtp, glot;
   if(!g_grid)
      line += " | grid off";
   else
      if(GridInfo(gcount, glevel, gtp, glot) == 0)
         line += " | grid on, no trade";
      else
         line += StringFormat(" | grid %d/%d, next at %s", gcount, InpMaxTrades, Px(glevel));
   Print(line);
  }

void CheckSignal()
  {
   if(g_source == 0)
      return;
   datetime bar = iTime(_Symbol, _Period, InpSignalBar);
   if(bar == 0 || bar == g_lastSignalBar)
      return;
   if(g_source == 2 && !MQLInfoInteger(MQL_TESTER))
     {
      // scanning thousands of objects is slow: only look again when an object
      // was created, a new candle started, or every 5 s as a safety net
      uint now = GetTickCount();
      if(!g_objDirty && bar == g_objScanBar && now < g_nextObjScan)
         return;
      g_objDirty    = false;
      g_objScanBar  = bar;
      g_nextObjScan = now + 5000;
     }
   int dir = ReadSignal(InpSignalBar);
   if(dir == 0)
      return;
   g_lastSignalBar = bar;
   OnSignal(dir, bar);
  }

void ManagePositions()
  {
   if(!InpUseBreakEven && !InpUseTrailing)
      return;
   if(g_grid)
      return;                                   // grid mode: trades run without SL (equity protector instead)
   MqlTick tk;
   if(!SymbolInfoTick(_Symbol, tk))
      return;
   double stopLvl = (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) + 1) * _Point;
   double step    = MathMax(InpTrailStepPoints * _Point, _Point);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsEAPosition())
         continue;
      bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      double cur   = isBuy ? tk.bid : tk.ask;
      double profitPts = (isBuy ? cur - open : open - cur) / _Point;
      double newSL = sl;
      string what  = "";

      if(InpUseBreakEven && profitPts >= InpBETriggerPoints)
        {
         double be = NormPrice(isBuy ? open + InpBELockPoints * _Point : open - InpBELockPoints * _Point);
         if(isBuy ? (newSL == 0 || be > newSL) : (newSL == 0 || be < newSL))
           {
            newSL = be;
            what  = "Breakeven";
           }
        }
      if(InpUseTrailing && profitPts >= InpTrailStartPoints)
        {
         double dist = (InpTrailMode == TRAIL_ATR) ? AtrValue() * InpTrailAtrMult : InpTrailPoints * _Point;
         if(dist > 0)
           {
            double tr = NormPrice(isBuy ? cur - dist : cur + dist);
            if(isBuy ? (newSL == 0 || tr >= newSL + step) : (newSL == 0 || tr <= newSL - step))
              {
               newSL = tr;
               what  = "Trailing stop";
              }
           }
        }
      if(newSL == sl)
         continue;
      if(isBuy ? (cur - newSL < stopLvl) : (newSL - cur < stopLvl))
         continue;
      if(trade.PositionModify(t, newSL, tp))
         Msg(what + ": SL moved to " + Px(newSL));
     }
  }

void PanelTrade(int dir)
  {
   ulong ticket;
   int cur = EAPosition(ticket);
   if(cur != 0)
     {
      Msg("EA trade still running - close it first");
      return;
     }
   OpenTrade(dir, "panel");
  }

//+------------------------------------------------------------------+
//| Panel                                                            |
//+------------------------------------------------------------------+
void Rect(const string name, int x, int y, int w, int h, color bg, color border)
  {
   string n = PFX + name;
   if(ObjectFind(0, n) < 0)
      ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_COLOR, border);
   ObjectSetInteger(0, n, OBJPROP_BACK, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
  }

void Label(const string name, int x, int y, const string text, color clr, int size = 9,
           ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER)
  {
   string n = PFX + name;
   bool exists = (ObjectFind(0, n) >= 0);
   if(!exists)
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   if(exists)
      return;                 // only moved: keep the live text and colour
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, n, OBJPROP_FONT, InpPanelFont);
   ObjectSetString(0, n, OBJPROP_TEXT, text);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
  }

void Button(const string name, int x, int y, int w, int h, const string text, color bg)
  {
   string n = PFX + name;
   bool exists = (ObjectFind(0, n) >= 0);
   if(!exists)
      ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   if(exists)
      return;
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, n, OBJPROP_FONT, InpPanelFont);
   ObjectSetString(0, n, OBJPROP_TEXT, text);
   ObjectSetInteger(0, n, OBJPROP_STATE, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
  }

void SetText(const string name, const string text, color clr)
  {
   string n = PFX + name;
   ObjectSetString(0, n, OBJPROP_TEXT, text);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
  }

int Section(const string key, const string title, int y)
  {
   int x = g_px;
   Label("sec_" + key, x + 12, y, title, C_SECTION, 8);
   Rect("ln_" + key, x + 90, y + 7, PANEL_W - 102, 1, C_LINE, C_LINE);
   return y + 16;
  }

int Row(const string key, const string label, int y)
  {
   int x = g_px;
   Label("l_" + key, x + 14, y, label, C_LABEL, 8);
   Label("v_" + key, x + PANEL_W - 12, y, "-", C_TEXT, 8, ANCHOR_RIGHT_UPPER);
   return y + 16;
  }

void PanelCreate()
  {
   int x = g_px, y = g_py, w = PANEL_W;
   int bw = (w - 20 - 4 * 5) / 5;

   Rect("bg", x, y, w, 100, C_BG, C_BORDER);
   Rect("hdr", x + 1, y + 1, w - 2, 36, C_HEADER, C_HEADER);
   Rect("stripe", x + 1, y + 37, w - 2, 2, C_STRIPE, C_STRIPE);
   Label("title", x + 12, y + 5, "OLIVE TRADE MANAGER", clrWhite, 8);
   Label("sub", x + 12, y + 20, _Symbol + "  " + S_SEP + "  " + TfName() + "  " + S_SEP + "  v" + EA_VERSION, C'225,215,255', 8);
   Label("state", x + w - 38, y + 12, "", C_WARN, 8, ANCHOR_RIGHT_UPPER);
   Button("toggle", x + w - 30, y + 8, 22, 22, g_collapsed ? S_RT : S_DN, C_HEADER);
   if(g_collapsed)
     {
      ObjectSetInteger(0, PFX + "bg", OBJPROP_YSIZE, 40);
      g_panel = true;
      return;
     }

   int cy = y + 47;
   cy = Section("sig", "SIGNAL", cy);
   cy = Row("src", "Source", cy);
   cy = Row("ind", "Indicator", cy);
   cy = Row("buf", "Buffers", cy);
   cy = Row("last", "Last signal", cy);
   cy += 4;
   cy = Section("pos", "POSITION", cy);
   cy = Row("pos", "EA trade", cy);
   cy = Row("entry", "Entry", cy);
   cy = Row("sltp", "SL / TP", cy);
   cy = Row("pl", "Floating P/L", cy);
   cy = Row("man", "Manual trades", cy);
   cy = Row("grid", "Grid", cy);
   cy = Row("guard", "Equity protector", cy);
   cy += 4;
   cy = Section("mkt", "MARKET", cy);
   cy = Row("spread", "Spread", cy);
   cy = Row("atr", "ATR", cy);
   cy = Row("lots", "Lot size", cy);
   cy = Row("stops", "SL / TP mode", cy);
   cy += 4;
   cy = Section("day", "TODAY", cy);
   cy = Row("dpl", "Closed P/L", cy);
   cy = Row("dtr", "Trades / Wins", cy);
   cy = Row("eq", "Balance / Equity", cy);
   cy += 6;

   Button("btn_buy", x + 10, cy, bw, 24, S_UP + " BUY", C_BTN_BUY);
   Button("btn_sell", x + 10 + (bw + 5), cy, bw, 24, S_DN + " SELL", C_BTN_SELL);
   Button("btn_close", x + 10 + 2 * (bw + 5), cy, bw, 24, "CLOSE", C_BTN_CLS);
   Button("btn_auto", x + 10 + 3 * (bw + 5), cy, bw, 24, "AUTO ON", C_BTN_ON);
   Button("btn_grid", x + 10 + 4 * (bw + 5), cy, bw, 24, "GRID OFF", C_BTN_OFF);
   cy += 30;
   Label("msg", x + 12, cy, "", C_MUTED, 8);
   cy += 17;

   ObjectSetInteger(0, PFX + "bg", OBJPROP_YSIZE, cy - y);
   g_panel = true;
  }

string PanelKey(const string what) { return "OliveTM_" + IntegerToString(ChartID()) + "_" + what; }

void PanelSaveState()
  {
   GlobalVariableSet(PanelKey("x"), g_px);
   GlobalVariableSet(PanelKey("y"), g_py);
   GlobalVariableSet(PanelKey("c"), g_collapsed ? 1 : 0);
  }

void PanelLoadState()
  {
   g_px = InpPanelX;
   g_py = InpPanelY;
   g_collapsed = false;
   if(GlobalVariableCheck(PanelKey("x")))
     {
      g_px = (int)GlobalVariableGet(PanelKey("x"));
      g_py = (int)GlobalVariableGet(PanelKey("y"));
      g_collapsed = GlobalVariableGet(PanelKey("c")) > 0;
     }
  }

// Button states survive restarts (new settings, timeframe change, MT5 restart).
// Changing the matching input in the settings overrides the saved state.
bool RestoreToggle(const string what, bool inputValue)
  {
   string inp = PanelKey(what + "_input"), cur = PanelKey(what);
   bool inputChanged = !GlobalVariableCheck(inp) || ((GlobalVariableGet(inp) > 0) != inputValue);
   GlobalVariableSet(inp, inputValue ? 1 : 0);
   if(inputChanged || !GlobalVariableCheck(cur))
     {
      GlobalVariableSet(cur, inputValue ? 1 : 0);
      return inputValue;
     }
   return GlobalVariableGet(cur) > 0;
  }

void SaveToggles()
  {
   GlobalVariableSet(PanelKey("auto"), g_auto ? 1 : 0);
   GlobalVariableSet(PanelKey("grid"), g_grid ? 1 : 0);
  }

void PanelRebuild()
  {
   ObjectsDeleteAll(0, PFX);
   PanelCreate();
   UpdatePanel();
  }

// Drag the panel by its header: press on the header and move the mouse.
void PanelMouse(int mx, int my, bool down)
  {
   if(!down)
     {
      if(g_dragging)
        {
         g_dragging = false;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
         PanelSaveState();
        }
      g_mouseDown = false;
      return;
     }
   if(!g_dragging)
     {
      if(g_mouseDown)
         return;              // press started elsewhere (e.g. scrolling the chart)
      g_mouseDown = true;
      if(mx >= g_px && mx <= g_px + PANEL_W - 34 && my >= g_py && my <= g_py + 38)
        {
         g_dragging = true;
         g_dragDX = mx - g_px;
         g_dragDY = my - g_py;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
        }
      return;
     }
   int nx = MathMax(0, mx - g_dragDX);
   int ny = MathMax(0, my - g_dragDY);
   if(nx == g_px && ny == g_py)
      return;
   g_px = nx;
   g_py = ny;
   PanelCreate();
   ChartRedraw();
  }

void UpdatePanel()
  {
   if(!g_panel)
      return;

   //--- header state
   string block = EntryBlockReason();
   if(g_source == 0)
      SetText("state", S_DOT + " SEARCHING", C_WARN);
   else
      if(!g_auto)
         SetText("state", S_DOT + " PAUSED", C_BTN_CLS);
      else
         if(block != "")
            SetText("state", S_DOT + " BLOCKED", C_SELL);
         else
            SetText("state", S_DOT + " ACTIVE", C_BUY);
   if(g_collapsed)
     {
      ChartRedraw();
      return;
     }

   //--- signal
   SetText("v_src", g_status, g_source == 0 ? C_WARN : C_TEXT);
   string ind = (g_indName == "") ? "-" : g_indName;
   if(StringLen(ind) > 24)
      ind = StringSubstr(ind, 0, 23) + "..";
   SetText("v_ind", ind, C_GOLD);
   if(g_source == 1)
      SetText("v_buf", g_buyBuf == g_sellBuf ? StringFormat("single #%d", g_buyBuf)
              : StringFormat("buy #%d   sell #%d", g_buyBuf, g_sellBuf), C_TEXT);
   else
      SetText("v_buf", g_source == 2 ? "chart arrows" : "-", C_TEXT);
   if(g_lastSigDir != 0)
      SetText("v_last", (g_lastSigDir > 0 ? S_UP + " BUY  " : S_DN + " SELL  ") +
              TimeToString(g_lastSigTime, TIME_DATE | TIME_MINUTES), g_lastSigDir > 0 ? C_BUY : C_SELL);
   else
      SetText("v_last", "none yet", C_MUTED);

   //--- position
   ulong ticket;
   int dir = EAPosition(ticket);
   int cnt;
   double eaPL = FloatingPL(true, cnt);
   if(dir != 0 && PositionSelectByTicket(ticket))
     {
      SetText("v_pos", StringFormat("%s %s %.2f%s", dir > 0 ? S_UP : S_DN, dir > 0 ? "BUY" : "SELL",
                                    PositionGetDouble(POSITION_VOLUME), cnt > 1 ? StringFormat("  (%d trades)", cnt) : ""),
              dir > 0 ? C_BUY : C_SELL);
      SetText("v_entry", Px(PositionGetDouble(POSITION_PRICE_OPEN)), C_TEXT);
      SetText("v_sltp", Px(PositionGetDouble(POSITION_SL)) + "  /  " + Px(PositionGetDouble(POSITION_TP)), C_TEXT);
      SetText("v_pl", Money(eaPL), PLColor(eaPL));
     }
   else
     {
      SetText("v_pos", "flat", C_MUTED);
      SetText("v_entry", "-", C_MUTED);
      SetText("v_sltp", "-", C_MUTED);
      SetText("v_pl", "-", C_MUTED);
     }
   int manCnt;
   double manPL = FloatingPL(false, manCnt);
   if(manCnt > 0)
      SetText("v_man", StringFormat("%d open  ", manCnt) + Money(manPL), PLColor(manPL));
   else
      SetText("v_man", "none", C_MUTED);

   double glevel, gtp, glot;
   int    gcount;
   int    gdir = GridInfo(gcount, glevel, gtp, glot);
   if(!g_grid)
      SetText("v_grid", "off" + (cnt > 1 ? StringFormat("  (%d trades open)", cnt) : ""), C_MUTED);
   else
      if(gdir == 0)
         SetText("v_grid", StringFormat("on  %.0f points = %s, max %d", InpGridPoints,
                                        DoubleToString(InpGridPoints * _Point, _Digits), InpMaxTrades), C_TEXT);
      else
         if(gcount < InpMaxTrades)
            SetText("v_grid", StringFormat("next at %s  (%d/%d)", Px(glevel), gcount, InpMaxTrades), C_GOLD);
         else
            SetText("v_grid", StringFormat("max reached  (%d/%d)", gcount, InpMaxTrades), C_WARN);

   if(InpEquityProtectPct <= 0)
      SetText("v_guard", "off", C_MUTED);
   else
     {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      double lossPct = (eaPL < 0 && eq > 0) ? -eaPL / eq * 100.0 : 0;
      SetText("v_guard", StringFormat("loss %.1f%%  /  max %.1f%%", lossPct, InpEquityProtectPct),
              lossPct >= InpEquityProtectPct * 0.7 ? C_SELL : (lossPct > 0 ? C_WARN : C_TEXT));
     }

   //--- market
   double sp = SpreadPoints();
   SetText("v_spread", StringFormat("%.0f points", sp), (InpMaxSpreadPoints > 0 && sp > InpMaxSpreadPoints) ? C_SELL : C_TEXT);
   double atr = AtrValue();
   SetText("v_atr", atr > 0 ? StringFormat("%.0f points (%d)", atr / _Point, InpATRPeriod) : "-", C_GOLD);
   SetText("v_lots", InpLotMode == LOTS_FIXED ? StringFormat("fixed %.2f", InpFixedLot)
           : StringFormat("risk %.1f%%", InpRiskPercent), C_TEXT);
   string sl = InpSLMode == STOP_ATR ? StringFormat("ATR x%.1f", InpSLAtrMult)
               : InpSLMode == STOP_FIXED ? StringFormat("%.0f pts", InpSLPoints) : "none";
   string tp = InpTPMode == STOP_ATR ? StringFormat("ATR x%.1f", InpTPAtrMult)
               : InpTPMode == STOP_FIXED ? StringFormat("%.0f pts", InpTPPoints) : "none";
   if(InpTPMode != STOP_NONE && InpTPReducePct > 0 && InpTPReducePct < 100)
      tp += StringFormat(" -%.0f%%", InpTPReducePct);
   SetText("v_stops", sl + "  /  " + tp, C_TEXT);

   //--- today
   SetText("v_dpl", Money(g_dayClosed), PLColor(g_dayClosed));
   SetText("v_dtr", StringFormat("%d  /  %d", g_dayTrades, g_dayWins), C_TEXT);
   SetText("v_eq", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "  /  " +
           DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2), C_TEXT);

   //--- buttons & message
   ObjectSetString(0, PFX + "btn_grid", OBJPROP_TEXT, g_grid ? "GRID ON" : "GRID OFF");
   ObjectSetInteger(0, PFX + "btn_grid", OBJPROP_BGCOLOR, g_grid ? C_BTN_GRID : C_BTN_OFF);
   ObjectSetInteger(0, PFX + "btn_grid", OBJPROP_BORDER_COLOR, g_grid ? C_BTN_GRID : C_BTN_OFF);
   ObjectSetString(0, PFX + "btn_auto", OBJPROP_TEXT, g_auto ? "AUTO ON" : "AUTO OFF");
   ObjectSetInteger(0, PFX + "btn_auto", OBJPROP_BGCOLOR, g_auto ? C_BTN_ON : C_BTN_OFF);
   ObjectSetInteger(0, PFX + "btn_auto", OBJPROP_BORDER_COLOR, g_auto ? C_BTN_ON : C_BTN_OFF);
   if(block != "" && g_source != 0)
      SetText("msg", "Blocked: " + block, C_WARN);
   else
      SetText("msg", g_message, C_MUTED);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Event handlers                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   S_UP  = ShortToString(0x25B2);
   S_DN  = ShortToString(0x25BC);
   S_RT  = ShortToString(0x25B6);
   S_DOT = ShortToString(0x25CF);
   S_SEP = ShortToString(0x2022);

   if(InpSignalBar < 0 || InpFixedLot <= 0 || InpATRPeriod <= 0 || InpMaxTrades < 1)
     {
      Print("Invalid inputs: signal candle must be >= 0, fixed lot, ATR period and max trades > 0");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpSignalBar == 0)
      Print("Warning: signal candle 0 reads the live candle - arrows there can still disappear");

   g_auto = RestoreToggle("auto", InpAutoTrade);
   g_grid = RestoreToggle("grid", InpUseGrid);
   Print("Auto-trading ", g_auto ? "ON" : "OFF", ", grid ", g_grid ? "ON" : "OFF",
         StringFormat(" (distance %.0f points, max %d trades)", InpGridPoints, InpMaxTrades));
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_atr = iATR(_Symbol, InpATRTimeframe, InpATRPeriod);
   if(g_atr == INVALID_HANDLE)
     {
      Print("Cannot create ATR, error ", GetLastError());
      return INIT_FAILED;
     }

   // never trade a signal that was already on the chart when the EA started
   g_lastSignalBar = iTime(_Symbol, _Period, InpSignalBar);

   if(InpShowPanel && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE)))
     {
      PanelLoadState();
      PanelCreate();
      if(!MQLInfoInteger(MQL_TESTER))
         ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
     }
   if(!MQLInfoInteger(MQL_TESTER))
      ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, true);
   UpdateDayStats();
   TryResolve();
   EventSetTimer(1);
   UpdatePanel();
   Print("Olive Trade Manager v", EA_VERSION, " started on ", _Symbol, " ", TfName(), ", point ", DoubleToString(_Point, _Digits));
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_dragging)
      ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
   ObjectsDeleteAll(0, PFX);
   if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE)
      ObjectsDeleteAll(0, DOT_PFX);
   if(g_ind != INVALID_HANDLE)
      IndicatorRelease(g_ind);
   if(g_atr != INVALID_HANDLE)
      IndicatorRelease(g_atr);
   ChartRedraw();
  }

void OnTick()
  {
   if(g_source == 0)
      TryResolve();
   CheckEquityProtector();
   CheckSignal();
   ManageGrid();
   ManagePositions();
  }

void OnTimer()
  {
   if(g_source == 0)
      TryResolve();
   else
      if(g_histBar != iTime(_Symbol, _Period, 0) || (g_histRetry > 0 && GetTickCount() >= g_histRetry))
         ScanHistory();
   UpdateDayStats();
   Diagnostics();
   UpdatePanel();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol || (ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic)
      return;
   ENUM_DEAL_ENTRY e = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(e != DEAL_ENTRY_OUT && e != DEAL_ENTRY_OUT_BY)
      return;
   double pl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_SWAP) +
               HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   ENUM_DEAL_REASON r = (ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal, DEAL_REASON);
   string why = (r == DEAL_REASON_SL) ? "stop loss" : (r == DEAL_REASON_TP) ? "take profit" : "close";
   Notify("Trade closed by " + why + ": " + Money(pl));
   UpdateDayStats();
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CREATE)
     {
      if(StringFind(sparam, PFX) != 0 && StringFind(sparam, DOT_PFX) != 0)
         g_objDirty = true;                     // maybe a new signal arrow
      return;
     }
   if(!g_panel)
      return;
   if(id == CHARTEVENT_MOUSE_MOVE)
     {
      PanelMouse((int)lparam, (int)dparam, ((int)StringToInteger(sparam) & 1) == 1);
      return;
     }
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;
   if(sparam == PFX + "toggle")
     {
      g_collapsed = !g_collapsed;
      PanelSaveState();
      PanelRebuild();
      return;
     }
   if(StringFind(sparam, PFX + "btn_") != 0)
      return;
   string b = StringSubstr(sparam, StringLen(PFX));
   if(b == "btn_buy")
      PanelTrade(1);
   else
      if(b == "btn_sell")
         PanelTrade(-1);
      else
         if(b == "btn_close")
           {
            ulong t;
            if(EAPosition(t) == 0)
               Msg("No EA trade to close");
            else
               CloseEAPositions();
           }
         else
            if(b == "btn_auto")
              {
               g_auto = !g_auto;
               SaveToggles();
               Msg(g_auto ? "Auto-trading ON" : "Auto-trading OFF");
              }
            else
               if(b == "btn_grid")
                 {
                  g_grid = !g_grid;
                  SaveToggles();
                  Msg(g_grid ? "Grid ON" : "Grid OFF");
                  if(!g_grid)
                     GridDisarm();              // grid on: ManageGrid removes the SL on the next tick
                 }
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   UpdatePanel();
  }
//+------------------------------------------------------------------+
