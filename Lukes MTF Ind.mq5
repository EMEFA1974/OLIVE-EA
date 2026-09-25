#property copyright "Lukes MTF Ind"
#property link      ""
#property version   "1.60"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_label1  "Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrAqua
#property indicator_width1  2

#property indicator_label2  "Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrMagenta
#property indicator_width2  2

#property indicator_label3  "ReBuy"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrGold
#property indicator_width3  2

#property indicator_label4  "ReSell"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrYellow
#property indicator_width4  2

enum ENUM_PEND_TYPE
  {
   PEND_LIMIT = 0,   // pullback (buy below / sell above)
   PEND_STOP  = 1    // confirmation break (buy above / sell below)
  };

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
input double InpRR1            = 1.0;   // TP1 R-multiple
input double InpRR2            = 2.0;   // TP2 R-multiple
input int    InpMaxReentry     = 2;
input int    InpReentryWindow  = 24;
input int    InpReentryCool    = 3;

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
input bool   InpHollowObj    = true;
input color  InpBuyColor     = clrAqua;
input color  InpSellColor    = clrMagenta;
input color  InpReBuyColor   = clrGold;
input color  InpReSellColor  = clrYellow;
input int    InpArrowShift   = 12;
input int    InpPanelX       = 12;
input int    InpPanelY       = 24;

input group "=== Zones ==="
input bool   InpShowZones     = true;
input bool   InpKeepLastZone  = true;    // keep last zone (TP/SL result) until next signal
input int    InpZoneRightBars = 18;       // box extends this many bars past the current bar
input int    InpLabelBars     = 16;       // extra line length to the right of the box for the labels
input int    InpZoneFontSize  = 7;
input string InpZoneFont      = "Segoe UI Light";   // thin font for zone labels (e.g. "Segoe UI Light", "Calibri Light", "Arial")
input bool   InpAutoChartShift = true;    // turn on chart shift so the box and labels have room
input int    InpChartShiftPct = 30;       // chart shift size in % of chart width (10-50)
input color  InpZoneSL        = C'110,24,24';
input color  InpZoneTP1       = C'14,70,40';
input color  InpZoneTP2       = C'16,34,110';
input color  InpLineEntry     = C'200,200,200';
input color  InpLineSL        = C'235,90,80';
input color  InpLineTP1       = C'70,200,170';
input color  InpLineTP2       = C'70,140,235';

double BuyBuf[];
double SellBuf[];
double ReBuyBuf[];
double ReSellBuf[];

datetime lastBuyTime   = 0;
datetime lastSellTime  = 0;
datetime lastAlertBar  = 0;
datetime lastFillAlert = 0;
bool     allowAlerts   = false;

int gCntBuy = 0, gCntSell = 0, gCntTP1 = 0, gCntTP2 = 0, gCntSL = 0;

#define PREFIX "CSMTF_"
#define ARPRE  "CSAR_"
#define ZPRE   "CSZN_"

enum IdeaState { IDEA_IDLE = 0, IDEA_PENDING, IDEA_LIVE, IDEA_SL_WAIT };

struct Idea
  {
   IdeaState state;
   int       dir;
   double    entry, sl, tp1, tp2;
   datetime  signalTime, slTime, fillTime;
   int       reCount, slBarAge, pendAge;
   bool      tp1Done;
   bool      re;
  };
Idea idea;

// snapshot of the current (most recent) zone; only one is ever drawn
struct ZoneSnap
  {
   bool     valid;
   int      dir;
   bool     re;
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
   gz.entry = gz.sl = gz.tp1 = gz.tp2 = 0;
   gz.t1 = gz.tEnd = 0;
   gz.status = "";
  }

struct Candle
  {
   double o,h,l,c;
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
   SetIndexBuffer(0, BuyBuf,    INDICATOR_DATA);
   SetIndexBuffer(1, SellBuf,   INDICATOR_DATA);
   SetIndexBuffer(2, ReBuyBuf,  INDICATOR_DATA);
   SetIndexBuffer(3, ReSellBuf, INDICATOR_DATA);
   ArraySetAsSeries(BuyBuf, true);
   ArraySetAsSeries(SellBuf, true);
   ArraySetAsSeries(ReBuyBuf, true);
   ArraySetAsSeries(ReSellBuf, true);

   PlotIndexSetInteger(0, PLOT_ARROW, 241);
   PlotIndexSetInteger(1, PLOT_ARROW, 242);
   PlotIndexSetInteger(2, PLOT_ARROW, 241);
   PlotIndexSetInteger(3, PLOT_ARROW, 242);
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT,  InpArrowShift);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, -InpArrowShift);
   PlotIndexSetInteger(2, PLOT_ARROW_SHIFT,  InpArrowShift + 10);
   PlotIndexSetInteger(3, PLOT_ARROW_SHIFT, -(InpArrowShift + 10));
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpBuyColor);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpSellColor);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, InpReBuyColor);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, InpReSellColor);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME, "Lukes MTF Ind");
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
   ObjectsDeleteAll(0, PREFIX);
   ObjectsDeleteAll(0, ARPRE);
   ObjectsDeleteAll(0, ZPRE);
  }

void ClearZones()
  {
   ObjectsDeleteAll(0, ZPRE);
  }

void ResetCounts()
  {
   gCntBuy = gCntSell = gCntTP1 = gCntTP2 = gCntSL = 0;
  }

void ResetIdea()
  {
   idea.state = IDEA_IDLE;
   idea.dir = 0;
   idea.entry = idea.sl = idea.tp1 = idea.tp2 = 0;
   idea.signalTime = idea.slTime = idea.fillTime = 0;
   idea.reCount = idea.slBarAge = idea.pendAge = 0;
   idea.tp1Done = false;
   idea.re = false;
  }

// finish the running idea but keep its levels as the current zone
void EndIdea(const string status, const datetime t)
  {
   if(idea.state != IDEA_IDLE && idea.signalTime != 0)
     {
      gz.valid  = true;
      gz.dir    = idea.dir;
      gz.re     = idea.re;
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

double PointBuf() { return (double)InpSLBufferPts * _Point; }

double PendingDist(const Candle &bar)
  {
   double byPts = (double)InpPendingPts * _Point;
   double byRng = 0.0;
   if(InpPendingUseRange && bar.h > bar.l)
      byRng = (bar.h - bar.l) * InpPendingRetrace;
   double d = MathMax(byPts, byRng);
   if(d <= 0.0) d = 10.0 * _Point;
   return d;
  }

void ApplyLevels(const int dir, const double entry, const double sl)
  {
   idea.dir   = dir;
   idea.entry = entry;
   idea.sl    = sl;
   double risk = (dir > 0 ? (entry - sl) : (sl - entry));
   if(risk <= 0.0) risk = _Point * 10;
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

bool BuildPendingPrices(const int dir, const Candle &bar, double &entry, double &sl)
  {
   double gap = (double)InpMinSLGapPts * _Point;
   if(gap <= 0.0) gap = 5.0 * _Point;
   double dist = PendingDist(bar);

   if(dir > 0)
     {
      sl = bar.l - PointBuf();
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
      sl = bar.h + PointBuf();
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

void ArmIdea(const int dir, const Candle &bar, const bool re)
  {
   double entry = 0, sl = 0;
   if(!BuildPendingPrices(dir, bar, entry, sl))
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
   ApplyLevels(dir, entry, sl);
   idea.state = (InpPendingOn ? IDEA_PENDING : IDEA_LIVE);
   if(idea.state == IDEA_LIVE)
      idea.fillTime = bar.t;
  }

bool TouchedLevel(const Candle &bar, const double price)
  {
   return (bar.valid && bar.l <= price && bar.h >= price);
  }

void ManageIdea(const Candle &bar, const Bias &d, const Bias &h4)
  {
   if(idea.state == IDEA_IDLE) return;

   if(idea.state == IDEA_PENDING)
     {
      idea.pendAge++;
      if(idea.pendAge > InpPendingExpire) { EndIdea(" [EXPIRED]", bar.t); return; }
      if(idea.dir > 0 && (d.dir < 0 || h4.dir < 0)) { EndIdea(" [CANCELLED]", bar.t); return; }
      if(idea.dir < 0 && (d.dir > 0 || h4.dir > 0)) { EndIdea(" [CANCELLED]", bar.t); return; }

      if(TouchedLevel(bar, idea.entry))
        {
         idea.state = IDEA_LIVE;
         idea.fillTime = bar.t;
         idea.slBarAge = 0;
        }
      return;
     }

   if(!InpReentryOn && idea.state == IDEA_SL_WAIT)
     {
      EndIdea(" [SL HIT]", idea.slTime);
      return;
     }

   idea.slBarAge++;

   bool hitTP2 = (idea.dir > 0 ? (bar.h >= idea.tp2) : (bar.l <= idea.tp2));
   bool hitTP1 = (idea.dir > 0 ? (bar.h >= idea.tp1) : (bar.l <= idea.tp1));
   bool hitSL  = (idea.dir > 0 ? (bar.l <= idea.sl)  : (bar.h >= idea.sl));

   if(idea.state == IDEA_LIVE && hitSL && hitTP1)
     {
      bool closeFav = (idea.dir > 0 ? (bar.c > idea.entry) : (bar.c < idea.entry));
      if(!closeFav)
        {
         gCntSL++;
         idea.state = IDEA_SL_WAIT;
         idea.slTime = bar.t;
         idea.slBarAge = 0;
         return;
        }
     }

   if(idea.state == IDEA_LIVE && hitTP2)
     {
      if(!idea.tp1Done) { gCntTP1++; idea.tp1Done = true; }
      gCntTP2++;
      EndIdea(" [TP2 HIT]", bar.t);
      return;
     }

   if(idea.state == IDEA_LIVE && hitTP1 && !idea.tp1Done)
     {
      gCntTP1++;
      idea.tp1Done = true;
     }

   if(idea.state == IDEA_LIVE && hitSL)
     {
      gCntSL++;
      idea.state = IDEA_SL_WAIT;
      idea.slTime = bar.t;
      idea.slBarAge = 0;
      return;
     }

   if(idea.state == IDEA_SL_WAIT)
     {
      if(idea.slBarAge > InpReentryWindow
         || (idea.dir > 0 && (d.dir < 0 || h4.dir < 0))
         || (idea.dir < 0 && (d.dir > 0 || h4.dir > 0)))
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
   k.valid = false; k.o = k.h = k.l = k.c = 0; k.t = 0;
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

double RecentSwingHigh(const int rates_total, const int i, const double &high[])
  {
   int from = i + 1;
   int to   = MathMin(rates_total - 1, i + InpSwingLook);
   if(from > rates_total - 1) return high[i];
   double mx = high[from];
   for(int k = from; k <= to; k++) if(high[k] > mx) mx = high[k];
   return mx;
  }

double RecentSwingLow(const int rates_total, const int i, const double &low[])
  {
   int from = i + 1;
   int to   = MathMin(rates_total - 1, i + InpSwingLook);
   if(from > rates_total - 1) return low[i];
   double mn = low[from];
   for(int k = from; k <= to; k++) if(low[k] < mn) mn = low[k];
   return mn;
  }

void HollowArrow(const datetime t, const double price, const int dir, const color clr, const bool re)
  {
   if(!InpHollowObj || t == 0) return;
   string name = ARPRE + TimeToString(t, TIME_DATE|TIME_MINUTES) + (dir > 0 ? "_U" : "_D") + (re ? "R" : "");
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, dir > 0 ? 241 : 242);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, dir > 0 ? ANCHOR_TOP : ANCHOR_BOTTOM);
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

   bool show = InpShowZones && gz.valid && gz.t1 != 0
               && (gz.tEnd == 0 || InpKeepLastZone);
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
   string side = (gz.dir > 0 ? (gz.re ? "RE-BUY" : "BUY") : (gz.re ? "RE-SELL" : "SELL"));

   PutRect(ZPRE+"ZSL0",  t1, gz.entry, t2, gz.sl,  InpZoneSL);
   PutRect(ZPRE+"ZT10",  t1, gz.entry, t2, gz.tp1, InpZoneTP1);
   PutRect(ZPRE+"ZT20",  t1, gz.tp1,   t2, gz.tp2, InpZoneTP2);

   PutLine(ZPRE+"LEN0", t1, t3, gz.entry, sig);
   PutLine(ZPRE+"LSL0", t1, t3, gz.sl,    InpLineSL);
   PutLine(ZPRE+"LT10", t1, t3, gz.tp1,   InpLineTP1);
   PutLine(ZPRE+"LT20", t1, t3, gz.tp2,   InpLineTP2);

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

void DrawPanel()
  {
   if(!InpShowPanel) return;
   const int rows = 9, w = 210, h = 18, x = InpPanelX, y = InpPanelY;
   CreateRect(PREFIX+"BG", x, y, w, rows*h + 8, C'18,22,28', C'50,58,68');
   DrawRow(PREFIX+"T", x, y + 2,       "STRUCTURE  D H4 H1 M5", clrSilver);
   DrawRow(PREFIX+"D", x, y + 2 + h,   RowText("D1", gD),  DirColor(gD.dir));
   DrawRow(PREFIX+"4", x, y + 2 + h*2, RowText("H4", gH4), DirColor(gH4.dir));
   DrawRow(PREFIX+"1", x, y + 2 + h*3, RowText("H1", gH1), DirColor(gH1.dir));
   DrawRow(PREFIX+"5", x, y + 2 + h*4, RowText("M5", gM5), DirColor(gM5.dir));
   string st = StringFormat("ALIGN  B:%d  S:%d", gScoreB, gScoreS);
   color  sc = (gScoreB >= InpMinAlign ? InpBuyColor : (gScoreS >= InpMinAlign ? InpSellColor : clrSilver));
   DrawRow(PREFIX+"A", x, y + 2 + h*5, st, sc);
   color ic = clrSilver;
   if(idea.state == IDEA_PENDING) ic = clrGold;
   if(idea.state == IDEA_LIVE)    ic = (idea.dir > 0 ? InpBuyColor : InpSellColor);
   if(idea.state == IDEA_SL_WAIT) ic = clrGold;
   DrawRow(PREFIX+"I", x, y + 2 + h*6, StateText(), ic);
   string cnt = StringFormat("BUY %d   SELL %d", gCntBuy, gCntSell);
   DrawRow(PREFIX+"C1", x, y + 2 + h*7, cnt, clrSilver);
   string out = StringFormat("TP1 %d  TP2 %d  SL %d", gCntTP1, gCntTP2, gCntSL);
   DrawRow(PREFIX+"C2", x, y + 2 + h*8, out, clrSilver);
  }

string RowText(const string name, const Bias &b)
  {
   string dir = (b.dir > 0 ? "BULL" : (b.dir < 0 ? "BEAR" : "MIX"));
   return name + "   " + dir + (b.strong ? "  Q" : "   ");
  }

color DirColor(const int dir)
  {
   if(dir > 0) return InpBuyColor;
   if(dir < 0) return InpSellColor;
   return clrGray;
  }

void CreateRect(const string name, int x, int y, int w, int hgt, color bg, color bd)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, hgt);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, bd);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

void DrawRow(const string name, int x, int y, const string text, color clr)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x + 10);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
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
   if(rates_total < 40) return(0);

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int start;
   if(prev_calculated <= 0)
     {
      ArrayInitialize(BuyBuf, EMPTY_VALUE);
      ArrayInitialize(SellBuf, EMPTY_VALUE);
      ArrayInitialize(ReBuyBuf, EMPTY_VALUE);
      ArrayInitialize(ReSellBuf, EMPTY_VALUE);
      // arrows are kept (not deleted) so history stays on the chart
      lastBuyTime = lastSellTime = 0;
      ResetIdea();
      ResetZone();
      ResetCounts();
      ClearZones();
      start = MathMin(rates_total - 5, 800);
     }
   else
      start = 2;

   if(start < 1) start = 1;

   gD  = TFBiasNow(InpTF_D);
   gH4 = TFBiasNow(InpTF_H4);
   gH1 = TFBiasNow(InpTF_H1);
   gM5 = TFBiasNow(InpTF_M5);
   gScoreB = (gD.dir==1) + (gH4.dir==1) + (gH1.dir==1) + (gM5.dir==1);
   gScoreS = (gD.dir==-1) + (gH4.dir==-1) + (gH1.dir==-1) + (gM5.dir==-1);

   for(int i = start; i >= 1; i--)
     {
      BuyBuf[i] = SellBuf[i] = ReBuyBuf[i] = ReSellBuf[i] = EMPTY_VALUE;

      Candle bar;
      bar.o = open[i]; bar.h = high[i]; bar.l = low[i]; bar.c = close[i];
      bar.t = time[i]; bar.valid = true;

      Bias d  = TFBiasAt(InpTF_D,  time[i]);
      Bias h4 = TFBiasAt(InpTF_H4, time[i]);
      Bias h1 = TFBiasAt(InpTF_H1, time[i]);
      Bias m5 = TFBiasAt(InpTF_M5, time[i]);
      int sb = (d.dir==1) + (h4.dir==1) + (h1.dir==1) + (m5.dir==1);
      int ss = (d.dir==-1) + (h4.dir==-1) + (h1.dir==-1) + (m5.dir==-1);

      ManageIdea(bar, d, h4);

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

      bool allowB = StructureAllows(1, d, h4, h1, sb, ss);
      bool allowS = StructureAllows(-1, d, h4, h1, sb, ss);

      bool didRe = false;
      if(InpReentryOn && idea.state == IDEA_SL_WAIT && idea.reCount < InpMaxReentry
         && idea.slBarAge >= InpReentryCool)
        {
         if(idea.dir > 0 && trigB && allowB)
           {
            ReBuyBuf[i] = low[i];
            int rc = idea.reCount + 1;
            ArmIdea(1, bar, true);
            idea.reCount = rc;
            lastBuyTime = bar.t;
            gCntBuy++;
            HollowArrow(time[i], low[i], 1, InpReBuyColor, true);
            didRe = true;
           }
         else if(idea.dir < 0 && trigS && allowS)
           {
            ReSellBuf[i] = high[i];
            int rc = idea.reCount + 1;
            ArmIdea(-1, bar, true);
            idea.reCount = rc;
            lastSellTime = bar.t;
            gCntSell++;
            HollowArrow(time[i], high[i], -1, InpReSellColor, true);
            didRe = true;
           }
        }

      if(!didRe)
        {
         bool coolB = Cooled(bar.t, lastBuyTime, InpCooldown) && Cooled(bar.t, lastSellTime, 3);
         bool coolS = Cooled(bar.t, lastSellTime, InpCooldown) && Cooled(bar.t, lastBuyTime, 3);
         bool free = (idea.state == IDEA_IDLE);

         if(free && trigB && allowB && coolB)
           {
            BuyBuf[i] = low[i];
            lastBuyTime = bar.t;
            ArmIdea(1, bar, false);
            gCntBuy++;
            HollowArrow(time[i], low[i], 1, InpBuyColor, false);
           }
         else if(free && trigS && allowS && coolS)
           {
            SellBuf[i] = high[i];
            lastSellTime = bar.t;
            ArmIdea(-1, bar, false);
            gCntSell++;
            HollowArrow(time[i], high[i], -1, InpSellColor, false);
           }
        }
     }

   BuyBuf[0] = SellBuf[0] = ReBuyBuf[0] = ReSellBuf[0] = EMPTY_VALUE;
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

   string msg = StringFormat("Lukes MTF %s %s | %s | close %s | %s%s",
                             side, _Symbol, tf, DoubleToString(barClose, _Digits),
                             TimeToString(barTime, TIME_DATE|TIME_MINUTES), extra);

   if(InpAlertPopup) Alert(msg);
   if(InpAlertSound) PlaySound(InpSoundFile);
   if(InpAlertPush)  SendNotification(msg);
   if(InpAlertEmail) SendMail("Lukes MTF " + side + " " + _Symbol, msg);
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
   if(InpPendingOn) side = side + " PEND";
   FireAlert(side, barTime, barClose);
  }
//+------------------------------------------------------------------+
