#property copyright "Lukes MTF Ind"
#property link      ""
#property version   "1.81"
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
input int    InpPanelX       = 4;        // left edge
input int    InpPanelY       = 20;       // top-left (EA panel goes bottom-left). Drag to move.
input int    InpPanelWidth   = 270;
input string InpPanelFontName = "Segoe UI Semilight"; // thin font for labels and values (thinner: "Segoe UI Light")
input string InpPanelFontHead = "Segoe UI";           // headings / title (e.g. "Segoe UI", "Calibri Light", "Arial")
input int    InpPanelFont    = 8;
input int    InpPanelRowH    = 15;
input ENUM_TIMEFRAMES InpTrendTF = PERIOD_H1;   // timeframe for the EMA trend line on the panel
input int    InpTrendFast    = 50;
input int    InpTrendSlow    = 200;

input group "=== Zones ==="
input bool   InpShowZones     = true;
input bool   InpKeepLastZone  = true;    // keep last zone (TP/SL result) until next signal
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

double BuyBuf[];
double SellBuf[];
double ReBuyBuf[];
double ReSellBuf[];

datetime lastBuyTime   = 0;
datetime lastSellTime  = 0;
datetime lastAlertBar  = 0;
datetime lastFillAlert = 0;
bool     allowAlerts   = false;
datetime gLastBar      = 0;      // last closed bar fed to the signal engine

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
   gEmaFast = iMA(_Symbol, InpTrendTF, InpTrendFast, 0, MODE_EMA, PRICE_CLOSE);
   gEmaSlow = iMA(_Symbol, InpTrendTF, InpTrendSlow, 0, MODE_EMA, PRICE_CLOSE);
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
   gCntBuy = gCntSell = gCntTP1 = gCntTP2 = gCntSL = gCntLoss = 0;
   ArrayResize(gEvT, 0);
   ArrayResize(gEvK, 0);
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
   double risk = (dir > 0 ? (entry - sl) : (sl - entry));
   if(risk <= 0.0) risk = Pt() * 10;
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
   double gap = (double)InpMinSLGapPts * Pt();
   if(gap <= 0.0) gap = 5.0 * Pt();
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
         gCntSL++; AddEv(EV_SL, bar.t);
         if(!idea.tp1Done) { gCntLoss++; AddEv(EV_LOSS, bar.t); }
         idea.state = IDEA_SL_WAIT;
         idea.slTime = bar.t;
         idea.slBarAge = 0;
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

   if(idea.state == IDEA_LIVE && hitTP1 && !idea.tp1Done)
     {
      gCntTP1++; AddEv(EV_TP1, bar.t);
      idea.tp1Done = true;
     }

   if(idea.state == IDEA_LIVE && hitSL)
     {
      gCntSL++; AddEv(EV_SL, bar.t);
      if(!idea.tp1Done) { gCntLoss++; AddEv(EV_LOSS, bar.t); }
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
#define PPRE    "CSMTF_P_"
int  gPX = 0, gPY = 0, gPanelH = 0;
int  gOtherObjs = -1;

// objects on the chart that are not part of either Lukes panel
int OtherObjCount()
  {
   int n = 0, total = ObjectsTotal(0);
   for(int i = 0; i < total; i++)
     {
      string nm = ObjectName(0, i);
      if(StringFind(nm, "CSMTF_P_") == 0 || StringFind(nm, "LEA_P_") == 0) continue;
      n++;
     }
   return n;
  }
bool gCollapsed = false, gAutoBottom = false;
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

   // header
   string st; color sc;
   if(idea.state == IDEA_PENDING)      { st = (idea.dir > 0 ? "PENDING BUY" : "PENDING SELL"); sc = C_WARN; }
   else if(idea.state == IDEA_LIVE)    { st = (idea.dir > 0 ? "LIVE BUY" : "LIVE SELL"); sc = (idea.dir > 0 ? InpBuyColor : InpSellColor); }
   else if(idea.state == IDEA_SL_WAIT) { st = "SL HIT"; sc = C_DN; }
   else                                { st = "WAIT"; sc = C_WARN; }
   PText(PPRE + "T1", gPX + 10, gPY + 6, "LUKES MTF IND", C_TXT, InpPanelFont + 3, ANCHOR_LEFT_UPPER, InpPanelFontHead);
   PText(PPRE + "T2", gPX + InpPanelWidth - 10, gPY + 6, "v1.81  " + ShortToString((ushort)(gCollapsed ? 0x25B6 : 0x25BC)), C_MUTE, InpPanelFont - 1, ANCHOR_RIGHT_UPPER, InpPanelFontName);
   PText(PPRE + "T3", gPX + 10, gPY + 27, _Symbol + "  " + StringSubstr(EnumToString(_Period), 7), C_LBL, InpPanelFont, ANCHOR_LEFT_UPPER, InpPanelFontName);
   PText(PPRE + "T4", gPX + InpPanelWidth - 10, gPY + 27, ShortToString((ushort)0x25CF) + " " + st, sc, InpPanelFont, ANCHOR_RIGHT_UPPER, InpPanelFontHead);

   if(!gCollapsed)
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
   double spr = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / Pt();
   PRow("Spread", StringFormat("%.0f pts", spr), (spr > 50 ? C_WARN : C_TXT));

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
      PRow("Status", side + "  " + StateText(), SignalColor(idea.dir, idea.re));
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
   gPanelH = (gCollapsed ? 46 : 46 + gRow * InpPanelRowH + 10);
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
//| Panel position, drag and collapse                                |
//| Drag the panel by its title area. Click the title (without       |
//| moving) to collapse / expand. Position is remembered per chart.  |
//+------------------------------------------------------------------+

string PosKey(const string k) { return "LukesInd_panel_" + k + "_" + IntegerToString(ChartID()); }

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
      if(InpShowPanel && x >= gPX && x <= gPX + InpPanelWidth && y >= gPY && y <= gPY + 44)
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
         gCollapsed = !gCollapsed;          // a click, not a drag
      PanelSave();
      DrawPanel(true);
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
            gCntBuy++; AddEv(EV_SIG, bar.t);
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
            gCntSell++; AddEv(EV_SIG, bar.t);
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
            gCntBuy++; AddEv(EV_SIG, bar.t);
            HollowArrow(time[i], low[i], 1, InpBuyColor, false);
           }
         else if(free && trigS && allowS && coolS)
           {
            SellBuf[i] = high[i];
            lastSellTime = bar.t;
            ArmIdea(-1, bar, false);
            gCntSell++; AddEv(EV_SIG, bar.t);
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
