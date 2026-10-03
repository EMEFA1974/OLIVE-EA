//+------------------------------------------------------------------+
//|                                             GenesisMT5_Ind.mq5   |
//|  GenesisMT5 Ind:                                                 |
//|   - Sydney / Asian / London / New York session boxes             |
//|     (high, low, midpoint, range and pips label)                  |
//|   - 5-factor Bull/Bear score and bias                            |
//|   - RSI(9) with its 7-period signal average                      |
//|   - Buy (aqua) / Sell (magenta) hollow entry arrows              |
//|   - Entry, SL, TP1-3 levels with risk / reward zone boxes        |
//|   - Popup and phone push notifications                           |
//|   - Equity and daily / weekly / monthly profit-target progress   |
//+------------------------------------------------------------------+
#property copyright "OLIVE-EA"
#property version   "2.00"
#property description "GenesisMT5 Ind: session boxes, 5-factor bias score, entry arrows with Entry/SL/TP zones, and phone push alerts."
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2
#property indicator_label1  "Buy Entry"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrAqua
#property indicator_width1  2
#property indicator_label2  "Sell Entry"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrMagenta
#property indicator_width2  2

enum ENUM_GMT_MODE
  {
   GMT_AUTO   = 0, // Auto (server time - GMT)
   GMT_MANUAL = 1  // Manual offset
  };

enum ENUM_SL_MODE
  {
   SL_ATR   = 0, // ATR multiple from entry
   SL_SWING = 1  // Beyond recent swing high/low
  };

//--- Time
input group "Time"
input ENUM_GMT_MODE   InpGmtMode         = GMT_AUTO;  // Broker GMT offset mode
input int             InpManualGmtOffset = 2;         // Broker GMT offset, hours (manual mode / tester)
input int             InpDaysBack        = 5;         // Days of session boxes to draw
input ENUM_TIMEFRAMES InpSessionTF       = PERIOD_M5; // Data timeframe for session high/low

//--- Sessions (all times GMT)
input group "Sessions (times in GMT, HH:MM)"
input bool   InpShowSydney   = true;          // Sydney: show
input string InpSydneyStart  = "21:00";       // Sydney: start
input string InpSydneyEnd    = "06:00";       // Sydney: end
input color  InpSydneyColor  = C'239,68,90';  // Sydney: color
input bool   InpShowAsian    = true;          // Asian (Tokyo): show
input string InpAsianStart   = "00:00";       // Asian: start
input string InpAsianEnd     = "09:00";       // Asian: end
input color  InpAsianColor   = C'245,166,35'; // Asian: color
input bool   InpShowLondon   = true;          // London: show
input string InpLondonStart  = "07:00";       // London: start
input string InpLondonEnd    = "16:00";       // London: end
input color  InpLondonColor  = C'66,133,244'; // London: color
input bool   InpShowNY       = true;          // New York: show
input string InpNYStart      = "12:00";       // New York: start
input string InpNYEnd        = "21:00";       // New York: end
input color  InpNYColor      = C'38,198,140'; // New York: color
input bool   InpFillBoxes    = true;          // Fill session boxes
input bool   InpShowMidLine  = true;          // Draw session midpoint line
input bool   InpExtendLevels = true;          // Extend latest session H/L/Mid to the right
input double InpPipSize      = 0;             // Pip size (0 = auto)

//--- Bias / score
input group "Bias score"
input ENUM_TIMEFRAMES InpBiasTF      = PERIOD_CURRENT; // Bias timeframe
input int             InpRsiPeriod   = 9;              // RSI period
input int             InpRsiSignal   = 7;              // RSI signal (SMA) period
input int             InpEmaFast     = 20;             // Fast EMA
input int             InpEmaSlow     = 50;             // Slow EMA
input double          InpOverbought  = 70;             // RSI overbought
input double          InpOversold    = 30;             // RSI oversold
input bool            InpClosedBar   = false;          // Score on last closed bar (no repaint)

//--- Targets
input group "Equity targets"
input bool   InpShowTargets  = true;   // Show equity / target section
input double InpDailyTarget  = 500;    // Daily target (account currency)
input double InpWeeklyTarget = 2500;   // Weekly target
input double InpMonthlyTarget= 10000;  // Monthly target

//--- Signals and trade levels
input group "Signals & trade levels"
input bool         InpShowSignals    = true;        // Show Buy / Sell entry arrows
input int          InpMinScore       = 4;           // Min score (of 5) required for a signal
input int          InpSignalBars     = 1000;        // Bars of history to scan for signals
input color        InpBuyArrowColor  = clrAqua;     // Buy arrow color
input color        InpSellArrowColor = clrMagenta;  // Sell arrow color
input int          InpArrowSize      = 2;           // Arrow size (1-5)
input ENUM_SL_MODE InpSlMode         = SL_ATR;      // Stop-loss mode
input int          InpAtrPeriod      = 14;          // ATR period
input double       InpSlAtrMult      = 1.5;         // SL distance, x ATR (ATR mode)
input int          InpSwingBars      = 10;          // Swing lookback bars (swing mode)
input double       InpTp1R           = 1.0;         // TP1, multiple of risk (R)
input double       InpTp2R           = 2.0;         // TP2, multiple of risk (R)
input double       InpTp3R           = 3.0;         // TP3, multiple of risk (R)
input bool         InpShowLevels     = true;        // Draw Entry / SL / TP levels and zones
input int          InpLevelsExtend   = 20;          // Extend open-trade levels N bars past price
input color        InpSlColor        = C'239,68,90';  // SL line / risk zone color
input color        InpTpColor        = C'38,198,140'; // TP lines / reward zone color

//--- Alerts
input group "Alerts & phone push notifications"
input bool InpPopupSignals = true;     // Popup alert on new Buy / Sell signal
input bool InpPushSignals  = true;     // Phone push on new Buy / Sell signal
input bool InpPushLevels   = true;     // Phone push when TP / SL is hit
input bool InpAlertStrong  = false;    // Popup alert when bias turns STRONG
input bool InpPushStrong   = false;    // Phone push when bias turns STRONG

//--- Panel
input group "Panel"
input string           InpTitle      = "GenesisMT5 Ind";     // Panel title
input ENUM_BASE_CORNER InpCorner     = CORNER_LEFT_UPPER;    // Panel corner
input int              InpX          = 10;                   // Panel X offset
input int              InpY          = 25;                   // Panel Y offset
input int              InpFontSize   = 9;                    // Font size
input color            InpPanelBg    = C'30,34,45';          // Row background
input color            InpPanelBg2   = C'38,43,56';          // Alternate row background
input color            InpGridColor  = C'70,76,92';          // Grid / border color
input color            InpHeaderBg   = C'72,52,160';         // Header background
input color            InpTextColor  = C'220,224,232';       // Label text color
input color            InpBullColor  = C'38,198,140';        // Bullish color
input color            InpBearColor  = C'239,68,90';         // Bearish color
input color            InpNeutralColor = C'245,200,66';      // Neutral / warning color

#define PFX   "GEN5_"
#define IND_NAME "GenesisMT5 Ind"
#define NSESS 4

struct SessionDef
  {
   string            name;
   string            key;
   bool              on;
   int               startMin;
   int               endMin;
   color             clr;
  };

struct SessionStat
  {
   bool              valid;
   bool              active;
   datetime          t0;
   datetime          t1;
   double            hi;
   double            lo;
  };

struct Row
  {
   string            k;
   string            v;
   color             vc;
   string            tip;
  };

SessionDef  g_s[NSESS];
SessionStat g_last[NSESS];   // latest instance of each session (active or most recent)
SessionStat g_prevDone;      // most recently completed session of any kind
Row         g_rows[];

struct TradeInfo
  {
   bool              valid;
   int               dir;      // +1 buy, -1 sell
   int               bar;      // bar index (oldest = 0) of the signal bar
   datetime          t;        // signal bar time
   datetime          closeT;   // bar time where SL or TP3 was hit (0 = open)
   double            entry;
   double            sl;
   double            tp1;
   double            tp2;
   double            tp3;
   int               score;
   int               hits;     // TPs reached: 0..3
   bool              stopped;  // SL reached
  };

int    g_hRsi = INVALID_HANDLE, g_hFast = INVALID_HANDLE, g_hSlow = INVALID_HANDLE;
// chart-timeframe handles for signals
int    g_hRsiC = INVALID_HANDLE, g_hFastC = INVALID_HANDLE, g_hSlowC = INVALID_HANDLE, g_hAtrC = INVALID_HANDLE;
double g_buy[], g_sell[];
TradeInfo g_tr;
int      g_lastTotal = 0;
bool     g_signalsReady = false;   // first signal scan done (suppresses alerts on history)
datetime g_alertedSignalT = 0;
datetime g_trackedT = 0;           // trade whose TP/SL state has been seeded
double g_pip = 0;
int    g_panelW = 0, g_panelH = 0;
ulong  g_lastRefresh = 0, g_lastPL = 0;
double g_plDay = 0, g_plWeek = 0, g_plMonth = 0;
string g_lastStrong = "";
bool   g_alertArmed = false;

//+------------------------------------------------------------------+
int ParseHM(const string s)
  {
   string p[];
   if(StringSplit(s, ':', p) != 2)
      return -1;
   int h = (int)StringToInteger(p[0]);
   int m = (int)StringToInteger(p[1]);
   if(h < 0 || h > 23 || m < 0 || m > 59)
      return -1;
   return h * 60 + m;
  }

//+------------------------------------------------------------------+
bool SetSession(const int i, const string name, const string key, const bool on,
                const string st, const string en, const color c)
  {
   g_s[i].name     = name;
   g_s[i].key      = key;
   g_s[i].on       = on;
   g_s[i].startMin = ParseHM(st);
   g_s[i].endMin   = ParseHM(en);
   g_s[i].clr      = c;
   if(on && (g_s[i].startMin < 0 || g_s[i].endMin < 0))
     {
      PrintFormat("%s: invalid session time '%s' - '%s' (use HH:MM)", name, st, en);
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   bool ok = true;
   if(!SetSession(0, "Sydney",   "Sydney H/L", InpShowSydney, InpSydneyStart, InpSydneyEnd, InpSydneyColor)) ok = false;
   if(!SetSession(1, "Asian",    "Asian H/L",  InpShowAsian,  InpAsianStart,  InpAsianEnd,  InpAsianColor)) ok = false;
   if(!SetSession(2, "London",   "London H/L", InpShowLondon, InpLondonStart, InpLondonEnd, InpLondonColor)) ok = false;
   if(!SetSession(3, "New York", "NY H/L",     InpShowNY,     InpNYStart,     InpNYEnd,     InpNYColor)) ok = false;
   if(!ok)
      return INIT_PARAMETERS_INCORRECT;

   if(InpRsiPeriod < 2 || InpRsiSignal < 1 || InpEmaFast < 1 || InpEmaSlow <= InpEmaFast)
     {
      Print("Invalid RSI/EMA periods (need RSI>=2, signal>=1, slow EMA > fast EMA)");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_hRsi  = iRSI(_Symbol, InpBiasTF, InpRsiPeriod, PRICE_CLOSE);
   g_hFast = iMA(_Symbol, InpBiasTF, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   g_hSlow = iMA(_Symbol, InpBiasTF, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   g_hRsiC  = iRSI(_Symbol, PERIOD_CURRENT, InpRsiPeriod, PRICE_CLOSE);
   g_hFastC = iMA(_Symbol, PERIOD_CURRENT, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   g_hSlowC = iMA(_Symbol, PERIOD_CURRENT, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   g_hAtrC  = iATR(_Symbol, PERIOD_CURRENT, InpAtrPeriod);
   if(g_hRsi == INVALID_HANDLE || g_hFast == INVALID_HANDLE || g_hSlow == INVALID_HANDLE
      || g_hRsiC == INVALID_HANDLE || g_hFastC == INVALID_HANDLE || g_hSlowC == INVALID_HANDLE
      || g_hAtrC == INVALID_HANDLE)
     {
      Print("Failed to create indicator handles: ", GetLastError());
      return INIT_FAILED;
     }

   // Pip: gold (2 digits) and 3/5-digit FX quote one extra digit, so pip = 10 points.
   g_pip = InpPipSize;
   if(g_pip <= 0)
      g_pip = (_Digits == 2 || _Digits == 3 || _Digits == 5) ? _Point * 10 : _Point;

   // --- hollow entry arrows (Wingdings 241 = outlined up, 242 = outlined down)
   SetIndexBuffer(0, g_buy, INDICATOR_DATA);
   SetIndexBuffer(1, g_sell, INDICATOR_DATA);
   ArraySetAsSeries(g_buy, false);
   ArraySetAsSeries(g_sell, false);
   int aw = MathMax(1, MathMin(5, InpArrowSize));
   PlotIndexSetInteger(0, PLOT_ARROW, 241);
   PlotIndexSetInteger(1, PLOT_ARROW, 242);
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, 12);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, -12);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpBuyArrowColor);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpSellArrowColor);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, aw);
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, aw);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME, IND_NAME);

   if((InpPushSignals || InpPushLevels || InpPushStrong) && !MQLInfoInteger(MQL_TESTER)
      && !TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED))
      Print(IND_NAME, ": push notifications are OFF. Enable them in Tools > Options > Notifications ",
            "and enter your MetaQuotes ID (from the MT5 mobile app: Settings > Messages).");

   g_tr.valid = false;
   ObjectsDeleteAll(0, PFX);
   EventSetTimer(1);
   Refresh(true);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectsDeleteAll(0, PFX);
   if(g_hRsi != INVALID_HANDLE)
      IndicatorRelease(g_hRsi);
   if(g_hFast != INVALID_HANDLE)
      IndicatorRelease(g_hFast);
   if(g_hSlow != INVALID_HANDLE)
      IndicatorRelease(g_hSlow);
   if(g_hRsiC != INVALID_HANDLE)
      IndicatorRelease(g_hRsiC);
   if(g_hFastC != INVALID_HANDLE)
      IndicatorRelease(g_hFastC);
   if(g_hSlowC != INVALID_HANDLE)
      IndicatorRelease(g_hSlowC);
   if(g_hAtrC != INVALID_HANDLE)
      IndicatorRelease(g_hAtrC);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[], const double &high[],
                const double &low[], const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
  {
   if(prev_calculated == 0)
     {
      ArrayInitialize(g_buy, EMPTY_VALUE);
      ArrayInitialize(g_sell, EMPTY_VALUE);
      g_lastTotal = 0;
     }
   // signals are evaluated on closed bars, so rescan only when a new bar appears
   if(rates_total != g_lastTotal && ComputeSignals(rates_total, time, high, low, close))
      g_lastTotal = rates_total;
   UpdateTrade(rates_total, time, high, low);
   DrawTrade(rates_total, time);
   Refresh(false);
   return rates_total;
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   Refresh(true);
  }

//+------------------------------------------------------------------+
//| Time helpers                                                     |
//+------------------------------------------------------------------+
datetime NowServer()
  {
   if(MQLInfoInteger(MQL_TESTER))
      return TimeCurrent();
   datetime t = TimeTradeServer();
   return (t > 0) ? t : TimeCurrent();
  }

int BrokerOffsetSec()
  {
   if(InpGmtMode == GMT_MANUAL || MQLInfoInteger(MQL_TESTER))
      return InpManualGmtOffset * 3600;
   long d = (long)TimeTradeServer() - (long)TimeGMT();
   return (int)(MathRound(d / 1800.0) * 1800); // round to 30 min
  }

//+------------------------------------------------------------------+
//| Drawing helpers                                                  |
//+------------------------------------------------------------------+
color Blend(const color fg, const color bg, const double a)
  {
   uint f = (uint)fg, b = (uint)bg;
   int r = (int)MathRound((f & 0xFF) * a + (b & 0xFF) * (1 - a));
   int g = (int)MathRound(((f >> 8) & 0xFF) * a + ((b >> 8) & 0xFF) * (1 - a));
   int bl = (int)MathRound(((f >> 16) & 0xFF) * a + ((b >> 16) & 0xFF) * (1 - a));
   return (color)((bl << 16) | (g << 8) | r);
  }

void ObjCommon(const string n)
  {
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
  }

void RectSet(const string n, const datetime t0, const double p0, const datetime t1, const double p1,
             const color c, const bool fill, const ENUM_LINE_STYLE st)
  {
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_RECTANGLE, 0, t0, p0, t1, p1);
      ObjCommon(n);
     }
   ObjectMove(0, n, 0, t0, p0);
   ObjectMove(0, n, 1, t1, p1);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_FILL, fill);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
   ObjectSetInteger(0, n, OBJPROP_STYLE, st);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
  }

void LineSet(const string n, const datetime t0, const double p0, const datetime t1, const double p1,
             const color c, const ENUM_LINE_STYLE st, const bool ray, const int width = 1)
  {
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_TREND, 0, t0, p0, t1, p1);
      ObjCommon(n);
     }
   ObjectMove(0, n, 0, t0, p0);
   ObjectMove(0, n, 1, t1, p1);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_STYLE, st);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, ray);
   ObjectSetInteger(0, n, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
  }

void TextSet(const string n, const datetime t, const double p, const string txt, const color c)
  {
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_TEXT, 0, t, p);
      ObjCommon(n);
     }
   ObjectMove(0, n, 0, t, p);
   ObjectSetString(0, n, OBJPROP_TEXT, txt);
   ObjectSetString(0, n, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
  }

string BoxName(const int s, const int k)
  {
   return PFX + "B_" + IntegerToString(s) + "_" + IntegerToString(k) + "_";
  }

void DeleteBox(const int s, const int k)
  {
   ObjectsDeleteAll(0, BoxName(s, k));
  }

//+------------------------------------------------------------------+
//| Session high/low between two server times                        |
//+------------------------------------------------------------------+
bool RangeHL(const datetime from, const datetime to, double &hi, double &lo)
  {
   datetime stop = to - 1;
   if(stop < from)
      return false;
   double h[], l[];
   int nh = CopyHigh(_Symbol, InpSessionTF, from, stop, h);
   int nl = CopyLow(_Symbol, InpSessionTF, from, stop, l);
   if(nh <= 0 || nl <= 0)
      return false;
   hi = h[ArrayMaximum(h)];
   lo = l[ArrayMinimum(l)];
   return true;
  }

string DayName(const datetime t)
  {
   static const string d[7] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return d[dt.day_of_week];
  }

//+------------------------------------------------------------------+
//| Build all session boxes and the latest stats                     |
//+------------------------------------------------------------------+
void ComputeSessions()
  {
   int      off    = BrokerOffsetSec();
   datetime nowSrv = NowServer();
   datetime nowGmt = nowSrv - off;
   datetime dayGmt = nowGmt - (nowGmt % 86400);
   int      days   = MathMax(0, MathMin(InpDaysBack, 60));
   color    chartBg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);

   g_prevDone.valid = false;
   for(int s = 0; s < NSESS; s++)
     {
      g_last[s].valid = false;
      if(!g_s[s].on)
        {
         ObjectsDeleteAll(0, PFX + "B_" + IntegerToString(s) + "_");
         continue;
        }

      int dur = (g_s[s].endMin - g_s[s].startMin + 1440) % 1440;
      if(dur == 0)
         dur = 1440;

      for(int k = 0; k <= days; k++)
        {
         datetime t0g = dayGmt - k * 86400 + g_s[s].startMin * 60;
         double hi = 0, lo = 0;
         datetime t0 = t0g + off;
         datetime t1 = t0 + dur * 60;
         datetime stopT = (t1 < nowSrv + 1) ? t1 : nowSrv + 1;
         if(t0g > nowGmt || !RangeHL(t0, stopT, hi, lo))
           {
            DeleteBox(s, k); // future session or no data (weekend / holiday)
            continue;
           }
         bool active = (nowSrv < t1);

         if(!g_last[s].valid)   // k ascends, so the first valid one is the latest
           {
            g_last[s].valid  = true;
            g_last[s].active = active;
            g_last[s].t0 = t0;
            g_last[s].t1 = t1;
            g_last[s].hi = hi;
            g_last[s].lo = lo;
           }
         if(!active && (!g_prevDone.valid || t1 > g_prevDone.t1))
           {
            g_prevDone.valid = true;
            g_prevDone.active = false;
            g_prevDone.t0 = t0;
            g_prevDone.t1 = t1;
            g_prevDone.hi = hi;
            g_prevDone.lo = lo;
           }

         // --- draw
         string n   = BoxName(s, k);
         color  c   = g_s[s].clr;
         double mid = (hi + lo) / 2.0;
         if(InpFillBoxes)
            RectSet(n + "F", t0, hi, t1, lo, Blend(c, chartBg, 0.22), true, STYLE_SOLID);
         else
            ObjectDelete(0, n + "F");
         RectSet(n + "E", t0, hi, t1, lo, c, false, active ? STYLE_DASH : STYLE_SOLID);
         if(InpShowMidLine)
            LineSet(n + "M", t0, mid, t1, mid, c, STYLE_DOT, false);
         else
            ObjectDelete(0, n + "M");
         double range = hi - lo;
         string lbl = StringFormat("%s • %s • %s • %.1f pips", g_s[s].name, DayName(t0),
                                   DoubleToString(range, _Digits), range / g_pip);
         TextSet(n + "T", t0, hi, lbl, c);
        }

      // --- extended levels of the latest instance
      string ln = PFX + "B_" + IntegerToString(s) + "_L";
      if(InpExtendLevels && g_last[s].valid)
        {
         double m = (g_last[s].hi + g_last[s].lo) / 2.0;
         LineSet(ln + "H", g_last[s].t1, g_last[s].hi, g_last[s].t1 + 60, g_last[s].hi, g_s[s].clr, STYLE_DOT, true);
         LineSet(ln + "L", g_last[s].t1, g_last[s].lo, g_last[s].t1 + 60, g_last[s].lo, g_s[s].clr, STYLE_DOT, true);
         LineSet(ln + "M", g_last[s].t1, m, g_last[s].t1 + 60, m, Blend(g_s[s].clr, chartBg, 0.5), STYLE_DOT, true);
        }
      else
         ObjectsDeleteAll(0, ln);
     }
  }

//+------------------------------------------------------------------+
//| Realized + floating P/L for today / this week / this month       |
//+------------------------------------------------------------------+
void ComputePL()
  {
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   datetime dayStart = now - (now % 86400);
   int dow = (dt.day_of_week + 6) % 7;            // Monday = 0
   datetime weekStart = dayStart - dow * 86400;
   dt.day = 1;
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime monthStart = StructToTime(dt);
   datetime from = (weekStart < monthStart) ? weekStart : monthStart;

   g_plDay = g_plWeek = g_plMonth = 0;
   if(HistorySelect(from, now + 86400))
     {
      int n = HistoryDealsTotal();
      for(int i = 0; i < n; i++)
        {
         ulong tk = HistoryDealGetTicket(i);
         if(tk == 0)
            continue;
         long type = HistoryDealGetInteger(tk, DEAL_TYPE);
         if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL)
            continue;                             // skip deposits, credits, etc.
         datetime t = (datetime)HistoryDealGetInteger(tk, DEAL_TIME);
         double pl = HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_SWAP)
                   + HistoryDealGetDouble(tk, DEAL_COMMISSION) + HistoryDealGetDouble(tk, DEAL_FEE);
         if(t >= dayStart)
            g_plDay += pl;
         if(t >= weekStart)
            g_plWeek += pl;
         if(t >= monthStart)
            g_plMonth += pl;
        }
     }
   double floating = AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE);
   g_plDay   += floating;
   g_plWeek  += floating;
   g_plMonth += floating;
  }

//+------------------------------------------------------------------+
//| Panel                                                            |
//+------------------------------------------------------------------+
void AddRow(const string k, const string v, const color vc, const string tip = "")
  {
   int n = ArraySize(g_rows);
   ArrayResize(g_rows, n + 1);
   g_rows[n].k   = k;
   g_rows[n].v   = v;
   g_rows[n].vc  = vc;
   g_rows[n].tip = tip;
  }

void PanelXY(const int lx, const int ly, int &x, int &y)
  {
   bool right = (InpCorner == CORNER_RIGHT_UPPER || InpCorner == CORNER_RIGHT_LOWER);
   bool lower = (InpCorner == CORNER_LEFT_LOWER || InpCorner == CORNER_RIGHT_LOWER);
   x = right ? InpX + g_panelW - lx : InpX + lx;
   y = lower ? InpY + g_panelH - ly : InpY + ly;
  }

void PanelRect(const string n, const int lx, const int ly, const int w, const int h, const color bg)
  {
   int x, y;
   PanelXY(lx, ly, x, y);
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjCommon(n);
     }
   ObjectSetInteger(0, n, OBJPROP_CORNER, InpCorner);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_COLOR, InpGridColor);
   ObjectSetInteger(0, n, OBJPROP_BACK, false);
  }

void PanelText(const string n, const int lx, const int ly, const string txt, const color c,
               const bool bold, const string tip)
  {
   int x, y;
   PanelXY(lx, ly, x, y);
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjCommon(n);
     }
   ObjectSetInteger(0, n, OBJPROP_CORNER, InpCorner);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, n, OBJPROP_TEXT, txt);
   ObjectSetString(0, n, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, InpFontSize);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, tip == "" ? "\n" : tip);
  }

void RenderPanel()
  {
   int fs = MathMax(6, InpFontSize);
   int rh = fs * 2 + 6;
   int c1 = fs * 11;
   int c2 = fs * 22;
   int n  = ArraySize(g_rows);
   g_panelW = c1 + c2;
   g_panelH = rh * n;
   int ty = (rh - (int)(fs * 1.4)) / 2;

   PanelRect(PFX + "P_BG", 0, 0, g_panelW, g_panelH, InpPanelBg);
   for(int i = 0; i < n; i++)
     {
      string id = IntegerToString(i);
      bool header = (i == 0);
      color bg = header ? InpHeaderBg : ((i % 2) ? InpPanelBg : InpPanelBg2);
      PanelRect(PFX + "P_R" + id, 0, i * rh, g_panelW, rh, bg);
      PanelText(PFX + "P_K" + id, 6, i * rh + ty, g_rows[i].k, header ? clrWhite : InpTextColor, header, "");
      PanelText(PFX + "P_V" + id, c1 + 6, i * rh + ty, g_rows[i].v, g_rows[i].vc, true, g_rows[i].tip);
     }
  }

//+------------------------------------------------------------------+
string Px(const double p)
  {
   return DoubleToString(p, _Digits);
  }

string Money(const double v)
  {
   string cur = AccountInfoString(ACCOUNT_CURRENCY);
   string sign = (v < 0) ? "-" : "";
   string s = DoubleToString(MathAbs(v), 2);
   return (cur == "USD") ? sign + "$" + s : sign + s + " " + cur;
  }

string TargetText(const double pl, const double target)
  {
   string s = (pl >= 0 ? "+" : "") + Money(pl) + " / " + Money(target);
   if(target > 0)
      s += StringFormat(" (%.0f%%)", 100.0 * pl / target);
   return s;
  }

string Countdown()
  {
   datetime bar = iTime(_Symbol, _Period, 0);
   if(bar == 0)
      return "-";
   long left = (long)bar + PeriodSeconds(_Period) - (long)NowServer();
   if(left < 0)
      left = 0;
   long d = left / 86400;
   left %= 86400;
   string s = StringFormat("%02d:%02d:%02d", (int)(left / 3600), (int)((left % 3600) / 60), (int)(left % 60));
   return (d > 0) ? IntegerToString(d) + "d " + s : s;
  }

//+------------------------------------------------------------------+
//| Main refresh                                                     |
//+------------------------------------------------------------------+
void Refresh(const bool force)
  {
   ulong now = GetTickCount64();
   if(!force && now - g_lastRefresh < 250)
      return;
   g_lastRefresh = now;

   ComputeSessions();

   if(InpShowTargets && (g_lastPL == 0 || now - g_lastPL >= 5000))
     {
      ComputePL();
      g_lastPL = now;
     }

   // --- indicator values
   int    shift = InpClosedBar ? 1 : 0;
   double rsiArr[], fast[], slow[];
   bool   haveInd = CopyBuffer(g_hRsi, 0, shift, InpRsiSignal, rsiArr) == InpRsiSignal
                    && CopyBuffer(g_hFast, 0, shift, 1, fast) == 1
                    && CopyBuffer(g_hSlow, 0, shift, 1, slow) == 1;
   double close = iClose(_Symbol, InpBiasTF, shift);
   double rsi = 0, sig = 0;
   int bull = 0, bear = 0;
   string detail = "";

   if(haveInd && close > 0)
     {
      rsi = rsiArr[InpRsiSignal - 1];
      for(int i = 0; i < InpRsiSignal; i++)
         sig += rsiArr[i];
      sig /= InpRsiSignal;

      // factor 5 uses the midpoint of the last completed session
      double sMid = g_prevDone.valid ? (g_prevDone.hi + g_prevDone.lo) / 2.0 : 0;
      Score(close, fast[0], slow[0], rsi, sig, sMid, bull, bear);
      detail = StringFormat("Close %s vs EMA%d %s | EMA%d %s | RSI %.1f vs 50 | RSI vs signal %.1f | Last session mid %s",
                            Px(close), InpEmaSlow, Px(slow[0]), InpEmaFast, Px(fast[0]), rsi, sig,
                            g_prevDone.valid ? Px(sMid) : "n/a");
     }

   // --- bias
   string bias;
   color  biasClr;
   if(!haveInd)          { bias = "LOADING...";     biasClr = InpNeutralColor; }
   else if(bull == 5)    { bias = "STRONG BULLISH"; biasClr = InpBullColor; }
   else if(bear == 5)    { bias = "STRONG BEARISH"; biasClr = InpBearColor; }
   else if(bull >= 4)    { bias = "BULLISH";        biasClr = InpBullColor; }
   else if(bear >= 4)    { bias = "BEARISH";        biasClr = InpBearColor; }
   else if(bull > bear)  { bias = "LEAN BULLISH";   biasClr = InpNeutralColor; }
   else if(bear > bull)  { bias = "LEAN BEARISH";   biasClr = InpNeutralColor; }
   else                  { bias = "NEUTRAL";        biasClr = InpNeutralColor; }

   // --- momentum warning: the score ignores exhaustion, so flag it explicitly
   string mom = "NORMAL";
   color  momClr = InpTextColor;
   if(haveInd && rsi <= InpOversold)
     {
      mom = (bear >= 4) ? "OVERSOLD - late to sell" : "OVERSOLD";
      momClr = InpNeutralColor;
     }
   else if(haveInd && rsi >= InpOverbought)
     {
      mom = (bull >= 4) ? "OVERBOUGHT - late to buy" : "OVERBOUGHT";
      momClr = InpNeutralColor;
     }

   // --- active sessions
   string sess = "";
   color  sessClr = InpTextColor;
   for(int s = 0; s < NSESS; s++)
      if(g_last[s].valid && g_last[s].active)
        {
         if(sess == "")
            sessClr = g_s[s].clr;
         sess += (sess == "" ? "" : " + ") + g_s[s].name;
        }
   if(sess == "")
      sess = "OFF-SESSION";
   StringToUpper(sess);

   // --- rows
   ArrayResize(g_rows, 0);
   AddRow(InpTitle, _Symbol + "  •  MT5", clrWhite);
   AddRow("Bias", bias, biasClr, detail);
   AddRow("Session", sess, sessClr);
   for(int s = 0; s < NSESS; s++)
     {
      if(!g_s[s].on)
         continue;
      string v = g_last[s].valid ? Px(g_last[s].hi) + " / " + Px(g_last[s].lo) : "n/a";
      if(g_last[s].valid && g_last[s].active)
         v += "  (live)";
      AddRow(g_s[s].key, v, g_last[s].valid ? InpTextColor : clrGray);
     }
   AddRow(StringFormat("RSI (%d/%d)", InpRsiPeriod, InpRsiSignal),
          haveInd ? StringFormat("%.1f / %.1f", rsi, sig) : "-",
          !haveInd ? InpTextColor : (rsi > sig ? InpBullColor : InpBearColor));
   AddRow("Momentum", mom, momClr);
   AddRow("Bull Score", StringFormat("%d / 5", bull), bull > 0 ? InpBullColor : clrGray, detail);
   AddRow("Bear Score", StringFormat("%d / 5", bear), bear > 0 ? InpBearColor : clrGray, detail);
   AddRow("Bar closes in", Countdown(), InpTextColor);
   if(g_tr.valid)
     {
      color dc = g_tr.dir > 0 ? InpBuyArrowColor : InpSellArrowColor;
      AddRow("Last Signal", StringFormat("%s @ %s  (%d/5)", g_tr.dir > 0 ? "BUY" : "SELL", Px(g_tr.entry), g_tr.score),
             dc, "Signal bar: " + TimeToString(g_tr.t, TIME_DATE | TIME_MINUTES));
      AddRow("Stop Loss", StringFormat("%s  (%.1f pips)", Px(g_tr.sl), MathAbs(g_tr.entry - g_tr.sl) / g_pip), InpSlColor);
      AddRow("TP1 / TP2 / TP3", Px(g_tr.tp1) + " / " + Px(g_tr.tp2) + " / " + Px(g_tr.tp3), InpTpColor);
      AddRow("Trade Status", TradeStatus(), g_tr.stopped && g_tr.hits == 0 ? InpSlColor
                                           : (g_tr.hits > 0 ? InpTpColor : InpTextColor));
     }
   else
      AddRow("Last Signal", "none in last " + IntegerToString(InpSignalBars) + " bars", clrGray);
   if(InpShowTargets)
     {
      AddRow("Equity", Money(AccountInfoDouble(ACCOUNT_EQUITY)), clrWhite);
      AddRow("Daily",   TargetText(g_plDay,   InpDailyTarget),   g_plDay   >= 0 ? InpBullColor : InpBearColor);
      AddRow("Weekly",  TargetText(g_plWeek,  InpWeeklyTarget),  g_plWeek  >= 0 ? InpBullColor : InpBearColor);
      AddRow("Monthly", TargetText(g_plMonth, InpMonthlyTarget), g_plMonth >= 0 ? InpBullColor : InpBearColor);
     }
   RenderPanel();

   // --- alerts on a fresh STRONG bias
   bool strong = (bias == "STRONG BULLISH" || bias == "STRONG BEARISH");
   if(g_alertArmed && strong && bias != g_lastStrong)
     {
      string msg = StringFormat("%s %s: %s (RSI %.1f)", _Symbol, EnumToString(_Period), bias, rsi);
      Notify(msg, InpAlertStrong, InpPushStrong);
     }
   if(haveInd)
     {
      g_lastStrong = strong ? bias : "";
      g_alertArmed = true;   // don't alert on the very first calculation
     }

   ChartRedraw();
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 5-factor score (shared by dashboard bias and entry signals)      |
//+------------------------------------------------------------------+
void Score(const double close, const double fast, const double slow, const double rsi,
           const double sig, const double mid, int &bull, int &bear)
  {
   bull = 0;
   bear = 0;
   // 1. Trend: price vs slow EMA
   if(close > slow) bull++; else if(close < slow) bear++;
   // 2. Structure: fast EMA vs slow EMA
   if(fast > slow) bull++; else if(fast < slow) bear++;
   // 3. Momentum: RSI vs 50
   if(rsi > 50) bull++; else if(rsi < 50) bear++;
   // 4. Momentum direction: RSI vs its signal
   if(rsi > sig) bull++; else if(rsi < sig) bear++;
   // 5. Price vs a reference midpoint (session / previous day); skipped when unknown
   if(mid > 0)
     {
      if(close > mid) bull++; else if(close < mid) bear++;
     }
  }

//+------------------------------------------------------------------+
//| Notifications                                                    |
//+------------------------------------------------------------------+
void Notify(const string msg, const bool popup, const bool push)
  {
   if(popup)
      Alert(msg);
   if(push && !MQLInfoInteger(MQL_TESTER))
      if(!SendNotification(msg))
         Print(IND_NAME, ": push failed (", GetLastError(), "). Check Tools > Options > Notifications / MetaQuotes ID.");
  }

string TfName()
  {
   string tf = EnumToString((ENUM_TIMEFRAMES)_Period);
   StringReplace(tf, "PERIOD_", "");
   return tf;
  }

//+------------------------------------------------------------------+
//| Midpoint of the previous day's range (signal factor 5)           |
//+------------------------------------------------------------------+
double PrevDayMid(const datetime t)
  {
   int d = iBarShift(_Symbol, PERIOD_D1, t, false);
   if(d < 0)
      return 0;
   double h = iHigh(_Symbol, PERIOD_D1, d + 1);
   double l = iLow(_Symbol, PERIOD_D1, d + 1);
   if(h <= 0 || l <= 0)
      return 0;
   return (h + l) / 2.0;
  }

//+------------------------------------------------------------------+
//| Build Entry / SL / TP levels for a signal on bar i               |
//+------------------------------------------------------------------+
void SetTrade(const int dir, const int i, const datetime t, const double entry, const double atr,
              const int score, const double &high[], const double &low[])
  {
   double sl;
   if(InpSlMode == SL_SWING)
     {
      int from = MathMax(0, i - MathMax(1, InpSwingBars) + 1);
      double ext = (dir > 0) ? low[i] : high[i];
      for(int k = from; k <= i; k++)
         ext = (dir > 0) ? MathMin(ext, low[k]) : MathMax(ext, high[k]);
      sl = ext - dir * atr * 0.2;               // small buffer beyond the swing
     }
   else
      sl = entry - dir * atr * InpSlAtrMult;

   double risk = dir * (entry - sl);
   if(risk <= _Point)                            // swing on the wrong side: fall back to ATR
     {
      risk = atr * InpSlAtrMult;
      sl = entry - dir * risk;
     }

   g_tr.valid   = true;
   g_tr.dir     = dir;
   g_tr.bar     = i;
   g_tr.t       = t;
   g_tr.closeT  = 0;
   g_tr.entry   = entry;
   g_tr.sl      = NormalizeDouble(sl, _Digits);
   g_tr.tp1     = NormalizeDouble(entry + dir * risk * InpTp1R, _Digits);
   g_tr.tp2     = NormalizeDouble(entry + dir * risk * InpTp2R, _Digits);
   g_tr.tp3     = NormalizeDouble(entry + dir * risk * InpTp3R, _Digits);
   g_tr.score   = score;
   g_tr.hits    = 0;
   g_tr.stopped = false;
  }

//+------------------------------------------------------------------+
//| Entry signals on closed bars of the chart timeframe              |
//|  BUY : RSI crosses above its signal, bull score >= min,          |
//|        RSI below overbought.  SELL is the mirror image.          |
//+------------------------------------------------------------------+
bool ComputeSignals(const int total, const datetime &time[], const double &high[],
                    const double &low[], const double &close[])
  {
   int warm = InpEmaSlow + InpRsiSignal + 2;
   int n = MathMin(total, MathMax(10, InpSignalBars) + warm);
   if(n < warm + 2)
      return false;

   double rsi[], fast[], slow[], atr[];
   if(CopyBuffer(g_hRsiC, 0, 0, n, rsi) != n || CopyBuffer(g_hFastC, 0, 0, n, fast) != n
      || CopyBuffer(g_hSlowC, 0, 0, n, slow) != n || CopyBuffer(g_hAtrC, 0, 0, n, atr) != n)
      return false;                              // indicators still calculating

   int base = total - n;                         // bar index of element 0
   double sig[];
   ArrayResize(sig, n);
   double sum = 0;
   for(int j = 0; j < n; j++)
     {
      sum += rsi[j];
      if(j >= InpRsiSignal)
         sum -= rsi[j - InpRsiSignal];
      sig[j] = (j >= InpRsiSignal - 1) ? sum / InpRsiSignal : EMPTY_VALUE;
     }

   TradeInfo old = g_tr;
   g_tr.valid = false;
   for(int i = base; i < total; i++)
     {
      g_buy[i]  = EMPTY_VALUE;
      g_sell[i] = EMPTY_VALUE;
     }

   for(int j = InpRsiSignal; j < n - 1; j++)     // n-1 is the live bar: skip it
     {
      int i = base + j;
      if(i < InpEmaSlow || rsi[j] <= 0 || atr[j] <= 0)
         continue;
      bool up = rsi[j] > sig[j] && rsi[j - 1] <= sig[j - 1];
      bool dn = rsi[j] < sig[j] && rsi[j - 1] >= sig[j - 1];
      if(!up && !dn)
         continue;

      int bull, bear;
      Score(close[i], fast[j], slow[j], rsi[j], sig[j], PrevDayMid(time[i]), bull, bear);
      if(up && bull >= InpMinScore && rsi[j] < InpOverbought)
        {
         if(InpShowSignals)
            g_buy[i] = low[i] - atr[j] * 0.2;
         SetTrade(1, i, time[i], close[i], atr[j], bull, high, low);
        }
      else if(dn && bear >= InpMinScore && rsi[j] > InpOversold)
        {
         if(InpShowSignals)
            g_sell[i] = high[i] + atr[j] * 0.2;
         SetTrade(-1, i, time[i], close[i], atr[j], bear, high, low);
        }
     }

   // keep TP/SL progress of a trade we were already tracking
   if(g_tr.valid && old.valid && old.t == g_tr.t)
     {
      g_tr.hits    = old.hits;
      g_tr.stopped = old.stopped;
      g_tr.closeT  = old.closeT;
     }

   // alert only for a signal on the bar that just closed, never for history
   if(g_tr.valid && g_tr.t != g_alertedSignalT)
     {
      if(g_signalsReady && g_tr.bar == total - 2)
        {
         string msg = StringFormat("%s | %s %s | %s @ %s | SL %s | TP1 %s TP2 %s TP3 %s | Score %d/5",
                                   IND_NAME, _Symbol, TfName(), g_tr.dir > 0 ? "BUY" : "SELL",
                                   Px(g_tr.entry), Px(g_tr.sl), Px(g_tr.tp1), Px(g_tr.tp2), Px(g_tr.tp3), g_tr.score);
         Notify(msg, InpPopupSignals, InpPushSignals);
        }
      g_alertedSignalT = g_tr.t;
     }
   g_signalsReady = true;
   return true;
  }

//+------------------------------------------------------------------+
//| Track TP / SL hits of the latest signal (runs every tick)        |
//+------------------------------------------------------------------+
void UpdateTrade(const int total, const datetime &time[], const double &high[], const double &low[])
  {
   if(!g_tr.valid || g_tr.bar >= total)
      return;
   int d = g_tr.dir;
   int hits = 0;
   bool stopped = false;
   datetime ct = 0;
   for(int i = g_tr.bar + 1; i < total; i++)
     {
      // SL first: when one bar touches both, assume the worse outcome
      if((d > 0) ? (low[i] <= g_tr.sl) : (high[i] >= g_tr.sl))
        {
         stopped = true;
         ct = time[i];
         break;
        }
      double fav = (d > 0) ? high[i] : low[i];
      if(hits < 1 && d * (fav - g_tr.tp1) >= 0)
         hits = 1;
      if(hits < 2 && d * (fav - g_tr.tp2) >= 0)
         hits = 2;
      if(d * (fav - g_tr.tp3) >= 0)
        {
         hits = 3;
         ct = time[i];
         break;
        }
     }

   // first look at a historical trade: seed silently; a fresh trade may alert at once
   bool notify = (g_trackedT == g_tr.t) || (g_tr.bar >= total - 2);
   if(notify && (InpPushLevels || InpPopupSignals))
     {
      string head = StringFormat("%s | %s %s %s @ %s | ", IND_NAME, _Symbol, TfName(),
                                 d > 0 ? "BUY" : "SELL", Px(g_tr.entry));
      double tps[3];
      tps[0] = g_tr.tp1;
      tps[1] = g_tr.tp2;
      tps[2] = g_tr.tp3;
      for(int k = g_tr.hits; k < hits; k++)
         Notify(head + StringFormat("TP%d HIT at %s", k + 1, Px(tps[k])), InpPopupSignals, InpPushLevels);
      if(stopped && !g_tr.stopped)
         Notify(head + "SL HIT at " + Px(g_tr.sl), InpPopupSignals, InpPushLevels);
     }
   g_trackedT   = g_tr.t;
   g_tr.hits    = hits;
   g_tr.stopped = stopped;
   g_tr.closeT  = ct;
  }

string TradeStatus()
  {
   if(g_tr.stopped)
      return g_tr.hits > 0 ? StringFormat("TP%d HIT, then SL - closed", g_tr.hits) : "SL HIT - closed";
   if(g_tr.hits >= 3)
      return "TP3 HIT - closed";
   if(g_tr.hits > 0)
      return StringFormat("TP%d HIT - running", g_tr.hits);
   return "RUNNING";
  }

//+------------------------------------------------------------------+
//| Entry / SL / TP lines, zone boxes and texts for the latest trade |
//+------------------------------------------------------------------+
void DrawTrade(const int total, const datetime &time[])
  {
   string p = PFX + "T_";
   if(!InpShowLevels || !g_tr.valid || total < 1)
     {
      ObjectsDeleteAll(0, p);
      return;
     }
   int      ps = PeriodSeconds(_Period);
   datetime t0 = g_tr.t;
   datetime t1 = (g_tr.closeT > 0) ? g_tr.closeT + ps : time[total - 1] + ps * MathMax(1, InpLevelsExtend);
   color    bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   color    dc = g_tr.dir > 0 ? InpBuyArrowColor : InpSellArrowColor;
   bool     closed = g_tr.closeT > 0;

   // zones: risk (entry -> SL) and reward (entry -> TP3)
   RectSet(p + "ZR", t0, g_tr.entry, t1, g_tr.sl, Blend(InpSlColor, bg, 0.28), true, STYLE_SOLID);
   RectSet(p + "ZW", t0, g_tr.entry, t1, g_tr.tp3, Blend(InpTpColor, bg, 0.22), true, STYLE_SOLID);
   RectSet(p + "ZRE", t0, g_tr.entry, t1, g_tr.sl, InpSlColor, false, STYLE_SOLID);
   RectSet(p + "ZWE", t0, g_tr.entry, t1, g_tr.tp3, InpTpColor, false, STYLE_SOLID);

   // lines
   LineSet(p + "LE", t0, g_tr.entry, t1, g_tr.entry, dc, STYLE_SOLID, false, 2);
   LineSet(p + "LS", t0, g_tr.sl, t1, g_tr.sl, InpSlColor, STYLE_SOLID, false, 2);
   LineSet(p + "L1", t0, g_tr.tp1, t1, g_tr.tp1, InpTpColor, STYLE_DASH, false);
   LineSet(p + "L2", t0, g_tr.tp2, t1, g_tr.tp2, InpTpColor, STYLE_DASH, false);
   LineSet(p + "L3", t0, g_tr.tp3, t1, g_tr.tp3, InpTpColor, STYLE_SOLID, false, 2);

   // texts at the right edge of the zone
   double dist = MathAbs(g_tr.entry - g_tr.sl);
   string side = g_tr.dir > 0 ? "BUY" : "SELL";
   TextSet(p + "TE", t1, g_tr.entry, StringFormat(" ENTRY %s  %s%s", side, Px(g_tr.entry), closed ? "  (closed)" : ""), dc);
   TextSet(p + "TS", t1, g_tr.sl, StringFormat(" SL  %s  (-%.1f pips)%s", Px(g_tr.sl), dist / g_pip,
                                               g_tr.stopped ? "  HIT" : ""), InpSlColor);
   TextSet(p + "T1", t1, g_tr.tp1, StringFormat(" TP1  %s  (+%.1f pips)%s", Px(g_tr.tp1),
                                                MathAbs(g_tr.tp1 - g_tr.entry) / g_pip, g_tr.hits >= 1 ? "  HIT" : ""), InpTpColor);
   TextSet(p + "T2", t1, g_tr.tp2, StringFormat(" TP2  %s  (+%.1f pips)%s", Px(g_tr.tp2),
                                                MathAbs(g_tr.tp2 - g_tr.entry) / g_pip, g_tr.hits >= 2 ? "  HIT" : ""), InpTpColor);
   TextSet(p + "T3", t1, g_tr.tp3, StringFormat(" TP3  %s  (+%.1f pips)%s", Px(g_tr.tp3),
                                                MathAbs(g_tr.tp3 - g_tr.entry) / g_pip, g_tr.hits >= 3 ? "  HIT" : ""), InpTpColor);
  }
//+------------------------------------------------------------------+
