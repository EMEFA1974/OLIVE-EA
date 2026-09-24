#property copyright "CinnamonPro"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_label1  "Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrTeal
#property indicator_width1  2

#property indicator_label2  "Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrCrimson
#property indicator_width2  2

#property indicator_label3  "ReBuy"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrGold
#property indicator_width3  2

#property indicator_label4  "ReSell"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrDarkOrange
#property indicator_width4  2

enum ENUM_PEND_TYPE
  {
   PEND_LIMIT = 0,   // pullback (buy below / sell above)
   PEND_STOP  = 1    // confirmation break (buy above / sell below)
  };

enum ENUM_ENTRY_MODE
  {
   ENTRY_MARKET = 0,
   ENTRY_LIMIT  = 1,
   ENTRY_HYBRID = 2
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
input int    InpSLSwingLook  = 24;
input int    InpCooldown     = 8;
input bool   InpRequireD     = false;
input bool   InpRequireH4    = true;
input bool   InpUseM5Trigger = false;

input group "=== Entry Mode ==="
input ENUM_ENTRY_MODE InpEntryMode      = ENTRY_HYBRID;
input double          InpConfirmShare   = 0.30;  // hybrid clip at confirmation (visual + fill sim)
input bool            InpPendingOn       = true;  // kept for compatibility; off forces market
input ENUM_PEND_TYPE  InpPendingType     = PEND_LIMIT;
input int             InpPendingPts      = 250;   // min distance from close, points
input double          InpPendingRetrace  = 0.40;  // fraction of signal candle
input double          InpPendingATR      = 0.30;  // also at least this * ATR
input bool            InpPendingUseRange = true;
input int             InpPendingExpire   = 12;
input int             InpMinSLGapPts     = 15;
input bool            InpChaseIfMissed   = true;
input double          InpChaseTriggerR   = 0.20;
input double          InpChaseMaxR       = 0.45;
input double          InpNoAddR          = 0.35;

input group "=== Straddle Distance (adjustable) ==="
input bool   InpStraddleOn      = true;
input int    InpStraddlePts     = 550;
input double InpStraddleATR     = 0.35;
input int    InpStraddleStepPts = 20;
input double InpStraddleFreezeR = 0.15; // freeze once price is this R in favor (0 = never)

input group "=== SL / TP (adjustable) ==="
input int    InpSLBufferPts    = 200;
input double InpRR1            = 1.5;
input double InpRR2            = 3.0;
input int    InpTPOffsetPts    = 60;    // pull TP1/TP2 toward price by this many points
input int    InpATRPeriod      = 14;
input double InpMinSLATR       = 1.50;
input int    InpMinSLPts       = 400;   // hard floor so SL is never a few ticks wide

input group "=== TP1 then TP2 leg ==="
input bool   InpLeg2On        = true;   // full close at TP1, then pullback for TP2
input double InpLeg2RetraceR  = 0.40;   // pullback from TP1 toward entry, in first-trade R
input int    InpLeg2Expire    = 16;     // cancel second pending after N bars
input double InpLeg2Share     = 0.50;   // display only on indicator; EA uses for size

input group "=== Recovery after SL ==="
input bool   InpRecoverOn         = true;
input int    InpMaxRecover        = 1;
input int    InpRecoverOffsetPts  = 30;    // floor distance from structure only
input double InpRecoverATR        = 0.25;  // also at least this * ATR from reclaim close
input double InpRecoverRetrace    = 0.50;  // pullback as fraction of reclaim candle range
input bool   InpRecoverUsePending = true;  // stay on LIMIT until price pulls back
input double InpRecoverShare      = 0.50;  // display only; EA uses for size
input int    InpRecoverExpire     = 12;
input bool   InpRecoverNeedReclaim= true;
input bool   InpRecoverKeepTargets= true;
input double InpRecoverKillATR    = 0.30;

input group "=== Re-entry after SL ==="
input bool   InpReentryOn      = true;
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
input int    InpPanelY       = 18;
input string InpPanelTitle   = "CINNAMON PRO";

input group "=== Zones ==="
input bool   InpShowZones     = true;
input bool   InpKeepLastZone  = false;  // only current signal zones/levels on the chart
input int    InpZoneRightBars = 18;
input color  InpZoneSL        = C'64,28,32';
input color  InpZoneTP1       = C'16,48,42';
input color  InpZoneTP2       = C'16,36,56';
input color  InpLineEntry     = C'168,168,168';
input color  InpLineSL        = C'168,78,84';
input color  InpLineTP1       = C'64,150,132';
input color  InpLineTP2       = C'64,120,168';

double BuyBuf[];
double SellBuf[];
double ReBuyBuf[];
double ReSellBuf[];

datetime lastBuyTime   = 0;
datetime lastSellTime  = 0;
datetime lastAlertBar  = 0;
datetime lastFillAlert = 0;
bool     allowAlerts   = false;
datetime gLastClosedBar = 0;

int gCntBuy = 0, gCntSell = 0, gCntTP1 = 0, gCntTP2 = 0, gCntSL = 0;

#define PREFIX "CIN_"
#define ARPRE  "CINAR_"
#define ZPRE   "CINZN_"

enum IdeaState { IDEA_IDLE = 0, IDEA_PENDING, IDEA_LIVE, IDEA_SL_WAIT };

struct Idea
  {
   IdeaState state;
   int       dir;
   double    entry, sl, tp1, tp2;
   double    origEntry, origSL, origTP2;
   double    riskEntry;
   datetime  signalTime, slTime, fillTime, artTime;
   int       reCount, slBarAge, pendAge;
   int       recoverCount;
   bool      tp1Done;
   bool      re;
   bool      leg2;
   bool      recovering;
   bool      confirmClip;
   bool      limitOpen;
   bool      chased;
   double    oldSL;
   double    slWick;
  };
Idea idea;
Idea lastZone;

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
int  gAtr    = INVALID_HANDLE;
int  gRsi    = INVALID_HANDLE;
int  gTodaySig = 0, gTodayTP1 = 0, gTodayTP2 = 0, gTodaySL = 0;
datetime gPanelDay = 0;
int      gPanelX   = -1;
int      gPanelY   = -1;
int      gDragDX   = 0;
int      gDragDY   = 0;
bool     gDragging = false;
int      gPanelW   = 220;
int      gPanelH   = 38*16 + 18;

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

   IndicatorSetString(INDICATOR_SHORTNAME, "CinnamonPro Ind v1.0");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   lastAlertBar = 0;
   lastFillAlert = 0;
   allowAlerts  = InpAlertOnLoad;
   ResetIdea();
   ResetCounts();
   if(gAtr != INVALID_HANDLE) IndicatorRelease(gAtr);
   if(gRsi != INVALID_HANDLE) IndicatorRelease(gRsi);
   gAtr = iATR(_Symbol, _Period, InpATRPeriod);
   gRsi = iRSI(_Symbol, _Period, 14, PRICE_CLOSE);
   gPanelX = InpPanelX;
   gPanelY = InpPanelY;
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(gAtr != INVALID_HANDLE) IndicatorRelease(gAtr);
   if(gRsi != INVALID_HANDLE) IndicatorRelease(gRsi);
   gAtr = INVALID_HANDLE;
   gRsi = INVALID_HANDLE;
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
   gTodaySig = gTodayTP1 = gTodayTP2 = gTodaySL = 0;
   gPanelDay = 0;
  }

void RollPanelDay()
  {
   datetime d = iTime(_Symbol, PERIOD_D1, 0);
   if(d == 0) d = (datetime)(TimeCurrent() - TimeCurrent() % 86400);
   if(d != gPanelDay)
     {
      gPanelDay = d;
      gTodaySig = gTodayTP1 = gTodayTP2 = gTodaySL = 0;
     }
  }

void RememberZone()
  {
   if(idea.signalTime != 0 && idea.entry > 0.0 && idea.sl > 0.0)
      lastZone = idea;
  }

void ClearLastZone()
  {
   lastZone.state = IDEA_IDLE;
   lastZone.dir = 0;
   lastZone.signalTime = lastZone.slTime = lastZone.fillTime = 0;
   lastZone.entry = lastZone.sl = lastZone.tp1 = lastZone.tp2 = 0;
   lastZone.origEntry = lastZone.origSL = lastZone.origTP2 = 0;
  }

void DeleteIdeaFromChart()
  {
   ClearLastZone();
   ClearZones();
  }

void ResetIdea(const bool mitigated = true)
  {
   if(mitigated || !InpKeepLastZone)
      DeleteIdeaFromChart();
   else
      RememberZone();
   idea.state = IDEA_IDLE;
   idea.dir = 0;
   idea.entry = idea.sl = idea.tp1 = idea.tp2 = 0;
   idea.origEntry = idea.origSL = idea.origTP2 = 0;
   idea.riskEntry = 0;
   idea.signalTime = idea.slTime = idea.fillTime = idea.artTime = 0;
   idea.reCount = idea.slBarAge = idea.pendAge = 0;
   idea.recoverCount = 0;
   idea.tp1Done = false;
   idea.re = false;
   idea.leg2 = false;
   idea.recovering = false;
   idea.confirmClip = false;
   idea.limitOpen = false;
   idea.chased = false;
   idea.oldSL = idea.slWick = 0;
  }

double UserPoint()
  {
   double p = _Point;
   if(p <= 0.0) p = 0.01;
   int d = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(d == 3 || d == 5)
      p *= 10.0;
   return p;
  }

double PointBuf() { return (double)InpSLBufferPts * UserPoint(); }

bool UsePending()
  {
   if(!InpPendingOn) return false;
   return (InpEntryMode != ENTRY_MARKET);
  }

double ConfirmShare()
  {
   if(!UsePending()) return 1.0;
   if(InpEntryMode == ENTRY_LIMIT) return 0.0;
   double s = InpConfirmShare;
   if(s < 0.0) s = 0.0;
   if(s > 1.0) s = 1.0;
   return s;
  }

double FavorRInd()
  {
   if(idea.dir == 0) return 0.0;
   double ref = (idea.riskEntry > 0.0 ? idea.riskEntry : idea.entry);
   double risk = MathAbs(ref - idea.sl);
   if(risk <= 0.0) return 0.0;
   double px = (idea.dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                             : SymbolInfoDouble(_Symbol, SYMBOL_ASK));
   if(idea.dir > 0) return (px - ref) / risk;
   return (ref - px) / risk;
  }

double FavorRBar(const Candle &bar)
  {
   if(idea.dir == 0 || !bar.valid) return 0.0;
   double ref = (idea.riskEntry > 0.0 ? idea.riskEntry : idea.entry);
   double risk = MathAbs(ref - idea.sl);
   if(risk <= 0.0) return 0.0;
   if(idea.dir > 0) return (bar.c - ref) / risk;
   return (ref - bar.c) / risk;
  }

double PendingDist(const Candle &bar)
  {
   double byPts = (double)InpPendingPts * UserPoint();
   double byRng = 0.0;
   if(InpPendingUseRange && bar.h > bar.l)
      byRng = (bar.h - bar.l) * InpPendingRetrace;
   double byAtr = 0.0;
   if(InpPendingATR > 0.0 && gAtr != INVALID_HANDLE)
     {
      double a[];
      if(CopyBuffer(gAtr, 0, 1, 1, a) == 1 && a[0] > 0.0)
         byAtr = a[0] * InpPendingATR;
     }
   double d = MathMax(byPts, MathMax(byRng, byAtr));
   if(d <= 0.0) d = 10.0 * UserPoint();
   return d;
  }

void ApplyLevels(const int dir, const double entry, const double sl)
  {
   idea.dir   = dir;
   idea.entry = entry;
   idea.sl    = sl;
   double risk = (dir > 0 ? (entry - sl) : (sl - entry));
   if(risk <= 0.0) risk = UserPoint() * 10;
   double minTp1 = MathMax(risk * InpRR1, (double)InpMinSLPts * UserPoint() * 0.75);
   double minTp2 = MathMax(risk * InpRR2, minTp1 + risk * MathMax(0.5, InpRR2 - InpRR1));
   double pull = (double)InpTPOffsetPts * UserPoint();
   if(dir > 0)
     {
      idea.tp1 = entry + minTp1;
      idea.tp2 = entry + minTp2;
      if(pull > 0.0 && minTp1 - pull >= risk * MathMax(1.0, InpRR1))
        {
         idea.tp1 -= pull;
         idea.tp2 -= pull;
        }
      if(idea.tp1 <= entry) idea.tp1 = entry + minTp1;
      if(idea.tp2 <= idea.tp1) idea.tp2 = idea.tp1 + risk * MathMax(0.5, InpRR2-InpRR1);
     }
   else
     {
      idea.tp1 = entry - minTp1;
      idea.tp2 = entry - minTp2;
      if(pull > 0.0 && minTp1 - pull >= risk * MathMax(1.0, InpRR1))
        {
         idea.tp1 += pull;
         idea.tp2 += pull;
        }
      if(idea.tp1 >= entry) idea.tp1 = entry - minTp1;
      if(idea.tp2 >= idea.tp1) idea.tp2 = idea.tp1 - risk * MathMax(0.5, InpRR2-InpRR1);
     }
  }

bool BuildPendingPrices(const int dir, const Candle &bar, const double slAnchor,
                        double &entry, double &sl)
  {
   double gap = (double)InpMinSLGapPts * UserPoint();
   if(gap <= 0.0) gap = 5.0 * UserPoint();
   double dist = PendingDist(bar);

   double minPts = (double)MathMax(InpMinSLPts, InpSLBufferPts + InpMinSLGapPts) * UserPoint();

   if(dir > 0)
     {
      sl = slAnchor - PointBuf();
      if(UsePending())
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
      if(entry - sl < minPts)
         sl = entry - minPts;
      if(entry <= sl) return false;
     }
   else
     {
      sl = slAnchor + PointBuf();
      if(UsePending())
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
      if(sl - entry < minPts)
         sl = entry + minPts;
      if(entry >= sl) return false;
     }
   return true;
  }

void ArmIdea(const int dir, const Candle &bar, const bool re, const double slAnchor)
  {
   double entry = 0, sl = 0;
   if(!BuildPendingPrices(dir, bar, slAnchor, entry, sl))
     {
      ResetIdea();
      return;
     }
   if(InpMinSLATR > 0.0 && gAtr != INVALID_HANDLE)
     {
      double atr[];
      if(CopyBuffer(gAtr, 0, 1, 1, atr) == 1 && atr[0] > 0.0)
         if(MathAbs(entry - sl) < atr[0] * InpMinSLATR)
           {
            ResetIdea();
            return;
           }
     }
   idea.signalTime = bar.t;
   idea.slTime = 0;
   idea.fillTime = 0;
   idea.slBarAge = 0;
   idea.pendAge = 0;
   idea.tp1Done = false;
   idea.re = re;
   idea.leg2 = false;
   idea.recovering = false;
   idea.chased = false;
   idea.confirmClip = false;
   idea.limitOpen = false;
   ApplyLevels(dir, entry, sl);
   idea.origEntry = idea.entry;
   idea.origSL    = idea.sl;
   idea.origTP2   = idea.tp2;
   idea.riskEntry = bar.c;
   double share = ConfirmShare();
   if(!UsePending() || share >= 0.999)
     {
      idea.state = IDEA_LIVE;
      idea.fillTime = bar.t;
      idea.entry = bar.c;
      idea.confirmClip = true;
      idea.limitOpen = false;
     }
   else
     {
      idea.limitOpen = true;
      if(share > 0.0)
        {
         idea.state = IDEA_LIVE;
         idea.fillTime = bar.t;
         idea.confirmClip = true;
        }
      else
        {
         idea.state = IDEA_PENDING;
        }
     }
  }

bool TouchedLevel(const Candle &bar, const double price)
  {
   return (bar.valid && bar.l <= price && bar.h >= price);
  }

double StraddleGap()
  {
   double g = (double)InpStraddlePts * UserPoint();
   if(InpStraddleATR > 0.0 && gAtr != INVALID_HANDLE)
     {
      double atr[];
      if(CopyBuffer(gAtr, 0, 0, 1, atr) == 1 && atr[0] > 0.0)
         g = MathMax(g, atr[0] * InpStraddleATR);
     }
   if(g <= 0.0) g = 10.0 * UserPoint();
   return g;
  }

void ShiftIdeaLevels(const double delta)
  {
   if(MathAbs(delta) < _Point * 0.5) return;
   idea.entry += delta;
  }

void ArmLeg2()
  {
   if(!InpLeg2On || idea.dir == 0)
     {
      ResetIdea();
      return;
     }
   double firstEntry = (idea.origEntry > 0.0 ? idea.origEntry : idea.entry);
   double firstTP1   = idea.tp1;
   double firstTP2   = (idea.origTP2 > 0.0 ? idea.origTP2 : idea.tp2);
   double firstR     = MathAbs(firstTP1 - firstEntry);
   if(firstR <= _Point) firstR = MathAbs(firstEntry - idea.sl);
   if(firstR <= _Point) { ResetIdea(); return; }

   double pull = InpLeg2RetraceR;
   if(pull < 0.05) pull = 0.05;
   if(pull > 1.00) pull = 1.00;
   double newEntry = (idea.dir > 0 ? firstTP1 - pull * firstR
                                   : firstTP1 + pull * firstR);

   idea.origEntry = firstEntry;
   idea.origTP2   = firstTP2;
   idea.entry     = newEntry;
   idea.sl        = firstEntry;
   idea.tp1       = firstTP1;
   idea.tp2       = firstTP2;
   idea.leg2      = true;
   idea.tp1Done   = true;
   idea.pendAge   = 0;
   idea.fillTime  = 0;
   idea.limitOpen = true;
   idea.confirmClip = false;
   idea.chased    = false;
   idea.state     = IDEA_PENDING;
  }

void ApplyStraddle(const double price)
  {
   if(!InpStraddleOn || !UsePending()) return;
   if(idea.recovering || idea.leg2) return;
   if(idea.dir == 0) return;
   if(!idea.limitOpen && idea.state != IDEA_PENDING) return;
   if(price <= 0.0) return;
   if(InpStraddleFreezeR > 0.0 && FavorRInd() >= InpStraddleFreezeR) return;

   double gap  = StraddleGap();
   double step = (double)InpStraddleStepPts * UserPoint();
   if(step <= 0.0) step = _Point;
   double desired = idea.entry;

   if(InpPendingType == PEND_LIMIT)
     {
      if(idea.dir > 0) desired = price - gap;   // buy limit below price
      else             desired = price + gap;   // sell limit above price
     }
   else
     {
      if(idea.dir > 0) desired = price + gap;   // buy stop above price
      else             desired = price - gap;   // sell stop below price
     }

   double delta = desired - idea.entry;
   // only drift AWAY from activation (never move closer to price)
   bool away = false;
   if(InpPendingType == PEND_LIMIT)
      away = (idea.dir > 0 ? delta > step : delta < -step);
   else
      away = (idea.dir > 0 ? delta < -step : delta > step);

   if(away)
      ShiftIdeaLevels(delta);
  }

double RecoverOffsetInd()
  {
   double byPts = (double)InpRecoverOffsetPts * UserPoint();
   double byAtr = 0.0;
   if(InpRecoverATR > 0.0 && gAtr != INVALID_HANDLE)
     {
      double a[];
      if(CopyBuffer(gAtr, 0, 1, 1, a) == 1 && a[0] > 0.0)
         byAtr = a[0] * InpRecoverATR;
     }
   double d = MathMax(byPts, byAtr);
   if(d <= 0.0) d = 10.0 * UserPoint();
   return d;
  }

double RecoverPullbackDistInd(const Candle &bar)
  {
   double d = RecoverOffsetInd();
   if(bar.valid && bar.h > bar.l && InpRecoverRetrace > 0.0)
      d = MathMax(d, (bar.h - bar.l) * InpRecoverRetrace);
   double pend = PendingDist(bar);
   if(pend > 0.0)
      d = MathMax(d, pend);
   return d;
  }

bool ReclaimOkInd(const Candle &bar)
  {
   if(!InpRecoverNeedReclaim) return true;
   double ref = (idea.oldSL > 0.0 ? idea.oldSL : idea.origSL);
   if(ref <= 0.0) ref = idea.sl;
   if(ref <= 0.0 || !bar.valid) return false;
   if(idea.dir > 0) return (bar.c > ref);
   return (bar.c < ref);
  }

bool RecoveryBiasOkInd(const Bias &d, const Bias &h4, const Bias &h1)
  {
   if(idea.dir > 0)
     {
      if(InpRequireD  && d.dir  !=  1) return false;
      if(InpRequireH4 && h4.dir !=  1) return false;
      if(h1.dir == -1) return false;
      return true;
     }
   if(idea.dir < 0)
     {
      if(InpRequireD  && d.dir  != -1) return false;
      if(InpRequireH4 && h4.dir != -1) return false;
      if(h1.dir == 1) return false;
      return true;
     }
   return false;
  }

void ArmRecoveryInd(const Candle &bar)
  {
   if(idea.dir == 0) { ResetIdea(); return; }
   double oldSL = (idea.oldSL > 0.0 ? idea.oldSL : (idea.origSL > 0.0 ? idea.origSL : idea.sl));
   if(oldSL <= 0.0) { ResetIdea(); return; }

   double off = RecoverPullbackDistInd(bar);
   double keepTP1 = idea.tp1;
   double keepTP2 = (idea.origTP2 > 0.0 ? idea.origTP2 : idea.tp2);
   double newEntry, newSL;
   double gap = (double)InpMinSLGapPts * UserPoint();
   if(gap <= 0.0) gap = 5.0 * UserPoint();

   if(idea.dir > 0)
     {
      double wick = idea.slWick;
      if(wick <= 0.0 || wick > oldSL) wick = MathMin(bar.l, oldSL);
      newSL = MathMin(wick, oldSL) - PointBuf();
      newEntry = (bar.valid ? bar.c : oldSL) - off;
      if(newEntry <= newSL + gap)
         newEntry = newSL + gap;
     }
   else
     {
      double wick = idea.slWick;
      if(wick <= 0.0 || wick < oldSL) wick = MathMax(bar.h, oldSL);
      newSL = MathMax(wick, oldSL) + PointBuf();
      newEntry = (bar.valid ? bar.c : oldSL) + off;
      if(newEntry >= newSL - gap)
         newEntry = newSL - gap;
     }

   idea.recovering  = true;
   idea.recoverCount++;
   idea.leg2        = false;
   idea.re          = false;
   idea.tp1Done     = false;
   idea.chased      = false;
   idea.confirmClip = false;
   idea.limitOpen   = true;
   idea.pendAge     = 0;
   idea.fillTime    = 0;
   idea.entry       = newEntry;
   idea.riskEntry   = newEntry;
   idea.sl          = newSL;

   if(InpRecoverKeepTargets && keepTP2 > 0.0)
     {
      idea.tp1 = keepTP1;
      idea.tp2 = keepTP2;
     }
   else
      ApplyLevels(idea.dir, idea.entry, idea.sl);

   idea.state = IDEA_PENDING;
  }

void NoteStopHit(const Candle &bar)
  {
   idea.oldSL = (idea.sl > 0.0 ? idea.sl : idea.origSL);
   idea.slWick = (idea.dir > 0 ? bar.l : bar.h);
   idea.state = IDEA_SL_WAIT;
   idea.slTime = bar.t;
   idea.slBarAge = 0;
   idea.limitOpen = false;
   idea.confirmClip = false;
   idea.recovering = false;
   idea.leg2 = false;
  }

void ManageIdea(const Candle &bar, const Bias &d, const Bias &h4)
  {
   if(idea.state == IDEA_IDLE) return;

   if(idea.limitOpen || idea.state == IDEA_PENDING)
     {
      if(idea.state == IDEA_PENDING || idea.limitOpen)
         idea.pendAge++;
      int exp = InpPendingExpire;
      if(idea.leg2)       exp = InpLeg2Expire;
      if(idea.recovering) exp = InpRecoverExpire;
      if(idea.pendAge > exp)
        {
         if(idea.recovering)
           {
            idea.recovering = false;
            idea.limitOpen = false;
            idea.state = IDEA_SL_WAIT;
            idea.slBarAge = MathMax(idea.slBarAge, InpRecoverExpire);
            return;
           }
         if(idea.confirmClip)
           {
            idea.limitOpen = false;
            idea.chased = true;
           }
         else
           {
            ResetIdea();
            return;
           }
        }

      if(!idea.recovering)
         ApplyStraddle(bar.c);

      if(idea.dir > 0 && (d.dir < 0 || h4.dir < 0)) { ResetIdea(); return; }
      if(idea.dir < 0 && (d.dir > 0 || h4.dir > 0)) { ResetIdea(); return; }
      if(idea.leg2 && idea.origSL > 0.0)
        {
         if(idea.dir > 0 && bar.l <= idea.origSL) { ResetIdea(); return; }
         if(idea.dir < 0 && bar.h >= idea.origSL) { ResetIdea(); return; }
        }
      if(idea.recovering && InpRecoverKillATR > 0.0 && gAtr != INVALID_HANDLE)
        {
         double a[];
         if(CopyBuffer(gAtr, 0, 1, 1, a) == 1 && a[0] > 0.0)
           {
            if(idea.dir > 0 && bar.c <= idea.sl - a[0] * InpRecoverKillATR) { ResetIdea(); return; }
            if(idea.dir < 0 && bar.c >= idea.sl + a[0] * InpRecoverKillATR) { ResetIdea(); return; }
           }
        }

      double rBar = FavorRBar(bar);
      if(idea.limitOpen && idea.confirmClip && !idea.recovering && rBar >= InpNoAddR)
        {
         idea.limitOpen = false;
         idea.chased = true;
        }
      else if(idea.limitOpen && !idea.confirmClip && !idea.recovering && !idea.chased
              && InpChaseIfMissed && rBar >= InpChaseTriggerR && rBar <= InpChaseMaxR)
        {
         if((idea.dir > 0 && bar.l > idea.sl) || (idea.dir < 0 && bar.h < idea.sl))
           {
            idea.state = IDEA_LIVE;
            idea.fillTime = bar.t;
            idea.limitOpen = false;
            idea.chased = true;
            idea.entry = bar.c;
           }
        }
      else if(TouchedLevel(bar, idea.entry))
        {
         idea.state = IDEA_LIVE;
         idea.fillTime = bar.t;
         idea.slBarAge = 0;
         idea.limitOpen = false;
        }

      if(idea.state == IDEA_PENDING)
         return;
     }

   if(!InpReentryOn && !InpRecoverOn && idea.state == IDEA_SL_WAIT)
     {
      ResetIdea();
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
         gCntSL++; gTodaySL++;
         NoteStopHit(bar);
         if(!InpRecoverOn && !InpReentryOn) ResetIdea();
         return;
        }
     }

   if(idea.state == IDEA_LIVE && hitTP2)
     {
      if(!idea.tp1Done) { gCntTP1++; gTodayTP1++; idea.tp1Done = true; }
      gCntTP2++; gTodayTP2++;
      ResetIdea(false);
      return;
     }

   if(idea.state == IDEA_LIVE && hitTP1 && !idea.tp1Done)
     {
      gCntTP1++; gTodayTP1++;
      idea.tp1Done = true;
      if(InpLeg2On && !idea.leg2)
        {
         ArmLeg2();
         return;
        }
      if(InpLeg2On && idea.leg2)
         ResetIdea();
     }

   if(idea.state == IDEA_LIVE && hitSL)
     {
      gCntSL++; gTodaySL++;
      NoteStopHit(bar);
      if(!InpRecoverOn && !InpReentryOn) ResetIdea();
      return;
     }

   if(idea.state == IDEA_SL_WAIT)
     {
      int waitBars = InpReentryWindow;
      if(InpRecoverOn) waitBars = MathMax(waitBars, InpRecoverExpire);
      if(idea.slBarAge > waitBars) ResetIdea();
      if(idea.dir > 0 && (d.dir < 0 || h4.dir < 0)) ResetIdea();
      if(idea.dir < 0 && (d.dir > 0 || h4.dir > 0)) ResetIdea();
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
   if(t1 <= 0) return;
   if(t2 <= t1) t2 = t1 + PeriodSeconds(_Period) * 20;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, fill);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, fill);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
  }

void PutLine(const string name, datetime t1, datetime t2, double price, color clr)
  {
   if(t1 <= 0 || price <= 0.0) return;
   if(t2 <= t1) t2 = t1 + PeriodSeconds(_Period) * 20;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 2);
  }

void PutLabel(const string name, datetime t, double price, const string text, color clr)
  {
   if(price <= 0.0 || t <= 0) return;
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price))
      return;
   ObjectSetInteger(0, name, OBJPROP_TIME, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetString(0, name, OBJPROP_TEXT, "   " + text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
  }

void DrawLiveZone()
  {
   if(!InpShowZones)
     {
      ClearZones();
      return;
     }

   Idea z = idea;
   if(z.state == IDEA_IDLE || z.signalTime == 0 || z.entry <= 0.0 || z.sl <= 0.0)
     {
      ClearZones();
      return;
     }

   datetime t1 = z.signalTime;
   datetime nowT = iTime(_Symbol, _Period, 0);
   if(nowT <= 0) nowT = TimeCurrent();
   int boxBars = MathMax(10, InpZoneRightBars);
   datetime tBox = nowT + (datetime)boxBars * PeriodSeconds(_Period);
   if(tBox <= t1)
      tBox = t1 + PeriodSeconds(_Period) * 10;
   datetime tLab = nowT + PeriodSeconds(_Period);
   datetime tLine = tLab + (datetime)40 * PeriodSeconds(_Period);

   PutRect(ZPRE+"ZSL0",  t1, z.entry, tBox, z.sl,  InpZoneSL);
   PutRect(ZPRE+"ZT10",  t1, z.entry, tBox, z.tp1, InpZoneTP1);
   PutRect(ZPRE+"ZT20",  t1, z.tp1,   tBox, z.tp2, InpZoneTP2);

   PutLine(ZPRE+"LEN0", t1, tLine, z.entry, InpLineEntry);
   PutLine(ZPRE+"LSL0", t1, tLine, z.sl,    InpLineSL);
   PutLine(ZPRE+"LT10", t1, tLine, z.tp1,   InpLineTP1);
   PutLine(ZPRE+"LT20", t1, tLine, z.tp2,   InpLineTP2);

   string tag = "";
   if(z.recovering) tag += " RC";
   else if(z.re) tag += " RE";
   if(z.state == IDEA_PENDING)
     {
      if(z.recovering) tag += "  REC LIMIT";
      else tag += (z.leg2 ? "  L2 LIMIT" : (InpPendingType == PEND_LIMIT ? "  LIMIT" : "  STOP"));
     }
   if(z.state == IDEA_SL_WAIT) tag += " [SL hit]";
   if(z.state == IDEA_LIVE)    tag += " [FILLED]";
   if(idea.state == IDEA_IDLE && InpKeepLastZone) tag += " [LAST]";

   PutLabel(ZPRE+"NEN0", tLab, z.entry, "Entry  " + DoubleToString(z.entry, _Digits) + tag, InpLineEntry);
   PutLabel(ZPRE+"NSL0", tLab, z.sl,    "SL  "    + DoubleToString(z.sl,    _Digits),       InpLineSL);
   PutLabel(ZPRE+"NT10", tLab, z.tp1,   "TP1  "   + DoubleToString(z.tp1,   _Digits),       InpLineTP1);
   PutLabel(ZPRE+"NT20", tLab, z.tp2,   "TP2  "   + DoubleToString(z.tp2,   _Digits),       InpLineTP2);

   ChartRedraw(0);
  }

string StateText()
  {
   if(idea.recovering && idea.state == IDEA_PENDING)
      return (idea.dir > 0 ? "REC LONG" : "REC SHORT");
   if(idea.recovering && idea.state == IDEA_LIVE)
      return (idea.dir > 0 ? "REC LIVE L" : "REC LIVE S");
   if(idea.state == IDEA_PENDING)
      return (idea.dir > 0 ? "PEND LONG" : "PEND SHORT");
   if(idea.state == IDEA_LIVE)
      return (idea.dir > 0 ? "LIVE LONG" : "LIVE SHORT");
   if(idea.state == IDEA_SL_WAIT)
      return StringFormat("SL HIT  rc %d/%d re %d/%d", idea.recoverCount, InpMaxRecover, idea.reCount, InpMaxReentry);
   return "WAIT";
  }

string BiasWord(const Bias &b)
  {
   if(b.dir > 0) return (b.strong ? "BULL Q" : "BULL");
   if(b.dir < 0) return (b.strong ? "BEAR Q" : "BEAR");
   return "MIX";
  }

string SessionNow()
  {
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return "OFF";
   int h = dt.hour;
   if(h >= 7 && h < 16) return "LONDON";
   if(h >= 13 && h < 22) return "NEW YORK";
   if(h >= 0 && h < 8)   return "ASIA";
   return "OFF";
  }

double Buf1(const int handle, const int sh)
  {
   if(handle == INVALID_HANDLE) return 0.0;
   double a[];
   if(CopyBuffer(handle, 0, sh, 1, a) != 1) return 0.0;
   return a[0];
  }

void PanelKV(const string id, const int x, const int y, const int w,
             const string left, const string right, const color lc, const color rc)
  {
   DrawRow(id+"L", x + 8, y, left, lc);
   DrawRight(id+"R", x + w - 8, y, right, rc);
  }

void DrawPanel()
  {
   if(!InpShowPanel) return;
   RollPanelDay();

   if(gPanelX < 0) gPanelX = InpPanelX;
   if(gPanelY < 0) gPanelY = InpPanelY;
   int x = gPanelX, y0 = gPanelY;
   const int w = 220, h = 16;
   gPanelW = w;
   gPanelH = 40*h + 18;
   int y = y0 + 6;
   const color bg = C'8,12,20';
   const color bd = C'28,40,56';
   const color hdr = C'56,168,220';
   const color lab = C'168,180,196';
   const color wh  = clrWhite;
   const color gold = C'232,176,64';
   const color green = C'72,210,120';
   const color orange = C'232,120,56';
   const color blue = C'64,140,255';

   CreateRect(PREFIX+"BG", x, y0, w, 40*h + 18, bg, bd);

   string tf = EnumToString(_Period);
   StringReplace(tf, "PERIOD_", "");
   DrawRow(PREFIX+"TTL", x + 8, y, InpPanelTitle, wh);
   DrawRight(PREFIX+"VER", x + w - 8, y, "v1.0", gold);
   y += h + 2;
   DrawRow(PREFIX+"SUB", x + 8, y, StringFormat("%s  %s", _Symbol, tf), C'140,150,164');
   string wait = StateText();
   color wc = (idea.state == IDEA_IDLE ? gold : (idea.state == IDEA_LIVE ? green : orange));
   DrawRight(PREFIX+"WAIT", x + w - 8, y, "• "+wait, wc);
   y += h + 4;

   DrawRow(PREFIX+"HM", x + 8, y, "MARKET", hdr); y += h;
   string sess = SessionNow();
   PanelKV(PREFIX+"SE", x, y, w, "Session", sess, lab, (sess=="OFF"?C'120,128,140':green)); y += h;
   string tr = (gH4.dir<0 ? "HTF DOWN" : (gH4.dir>0 ? "HTF UP" : "HTF MIX"));
   PanelKV(PREFIX+"TR", x, y, w, "Trend", tr, lab, DirColor(gH4.dir)); y += h;
   string mode = "MARKET";
   if(UsePending() && InpEntryMode == ENTRY_LIMIT)  mode = "LIMIT";
   if(UsePending() && InpEntryMode == ENTRY_HYBRID) mode = StringFormat("HYB %.0f/%.0f", 100.0*ConfirmShare(), 100.0*(1.0-ConfirmShare()));
   PanelKV(PREFIX+"MO", x, y, w, "Mode", mode, lab, wh); y += h;
   PanelKV(PREFIX+"TI", x, y, w, "Trade info", "Cinnamon", lab, gold); y += h;
   bool trend = ((gD.dir!=0 && gD.dir==gH4.dir) || (gH4.dir!=0 && gH4.dir==gH1.dir));
   PanelKV(PREFIX+"RG", x, y, w, "Regime", (trend?"TREND":"RANGE"), lab, (trend?blue:gold)); y += h;
   PanelKV(PREFIX+"HT", x, y, w, "HTF gate", (InpRequireH4?"CONSERV":"NORMAL"), lab, gold); y += h;
   PanelKV(PREFIX+"D1", x, y, w, "D1", BiasWord(gD), lab, DirColor(gD.dir)); y += h;
   PanelKV(PREFIX+"H4", x, y, w, "H4", BiasWord(gH4), lab, DirColor(gH4.dir)); y += h;
   PanelKV(PREFIX+"H1", x, y, w, "H1", BiasWord(gH1), lab, DirColor(gH1.dir)); y += h;
   string al = StringFormat("%d / %d", gScoreB, gScoreS);
   color ac = (gScoreB>=InpMinAlign?green:(gScoreS>=InpMinAlign?orange:lab));
   PanelKV(PREFIX+"AL", x, y, w, "Align B/S", al, lab, ac); y += h;

   double atr = Buf1(gAtr, 1);
   double box = 0.0;
   if(idea.entry>0 && idea.sl>0) box = MathAbs(idea.entry-idea.sl);
   else if(lastZone.entry>0 && lastZone.sl>0) box = MathAbs(lastZone.entry-lastZone.sl);
   string boxs = (atr>0 && box>0 ? StringFormat("%.2fx", box/atr) : "-");
   PanelKV(PREFIX+"BX", x, y, w, "Box / ATR", boxs, lab, wh); y += h;

   Candle h1a = CandleAtShift(InpTF_H1, 1);
   Candle h1b = CandleAtShift(InpTF_H1, 2);
   double slp = 0.0;
   if(h1a.valid && h1b.valid && atr>0.0) slp = (h1a.c-h1b.c)/atr;
   PanelKV(PREFIX+"HS", x, y, w, "H1 slope", StringFormat("%.2f ATR", slp), lab, gold); y += h;
   PanelKV(PREFIX+"CF", x, y, w, "Confirm on", "H4 + M5", lab, wh); y += h;

   double rsi = Buf1(gRsi, 1);
   PanelKV(PREFIX+"RS", x, y, w, "RSI", DoubleToString(rsi, 1), lab, (rsi>=55?green:(rsi<=45?orange:wh))); y += h;
   PanelKV(PREFIX+"AT", x, y, w, "ATR", (atr>0?("$"+DoubleToString(atr, 2)):"-"), lab, wh); y += h;
   double spr = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   PanelKV(PREFIX+"SP", x, y, w, "Spread", "$"+DoubleToString(spr, 2), lab, wh); y += h + 3;

   DrawRow(PREFIX+"HC", x + 8, y, "SIGNAL COUNTER", hdr); y += h;
   int sigs = gCntBuy + gCntSell;
   PanelKV(PREFIX+"SQ", x, y, w, "Signals - Qty", IntegerToString(sigs), lab, wh); y += h;
   PanelKV(PREFIX+"T1", x, y, w, "TP1 - Qty", IntegerToString(gCntTP1), lab, green); y += h;
   PanelKV(PREFIX+"T2", x, y, w, "TP2 - Qty", IntegerToString(gCntTP2), lab, green); y += h;
   PanelKV(PREFIX+"SL", x, y, w, "SL - Qty", IntegerToString(gCntSL), lab, orange); y += h;
   int run = (idea.state==IDEA_LIVE || idea.state==IDEA_PENDING ? 1 : 0);
   PanelKV(PREFIX+"RN", x, y, w, "Running", IntegerToString(run), lab, wh); y += h;
   int done = gCntTP1 + gCntSL;
   string wr = (done>0 ? StringFormat("%.0f%%", 100.0*gCntTP1/done) : "-");
   PanelKV(PREFIX+"WR", x, y, w, "Win rate", wr, lab, gold); y += h;
   PanelKV(PREFIX+"TD", x, y, w, "Today", StringFormat("%d / 10", gTodaySig), lab, wh); y += h;
   PanelKV(PREFIX+"RT", x, y, w, "Range today", StringFormat("%d / 10", gTodayTP1+gTodaySL), lab, wh); y += h + 3;

   DrawRow(PREFIX+"HR", x + 8, y, "RE-ENTRY", hdr); y += h;
   PanelKV(PREFIX+"RE", x, y, w, "Re-entry", (InpReentryOn?"ON":"OFF"), lab, (InpReentryOn?green:C'120,128,140')); y += h;
   PanelKV(PREFIX+"RC", x, y, w, "Recovery",
           StringFormat("%s %d/%d", (InpRecoverOn?"ON":"OFF"), idea.recoverCount, InpMaxRecover),
           lab, (InpRecoverOn?green:C'120,128,140')); y += h;
   PanelKV(PREFIX+"SW", x, y, w, "SL watches", StringFormat("%d / %d", idea.reCount, InpMaxReentry), lab, wh); y += h;
   string zn = "idle";
   if(idea.state==IDEA_PENDING) zn = (idea.recovering ? "recover" : "pending");
   if(idea.state==IDEA_LIVE)    zn = (idea.recovering ? "rec-live" : "live");
   if(idea.state==IDEA_SL_WAIT) zn = (InpRecoverOn && idea.recoverCount < InpMaxRecover ? "rec-wait" : "sl-wait");
   PanelKV(PREFIX+"ZN", x, y, w, "Zone", zn, lab, (zn=="idle"?lab:gold)); y += h + 3;

   DrawRow(PREFIX+"HSG", x + 8, y, "CURRENT SIGNAL", hdr); y += h;
   string cs = "No signal in lookback";
   if(idea.state != IDEA_IDLE)
      cs = StringFormat("%s  %s", (idea.dir>0?"BUY":"SELL"), TimeToString(idea.signalTime, TIME_MINUTES));
   else if(lastZone.signalTime != 0)
      cs = StringFormat("LAST %s", TimeToString(lastZone.signalTime, TIME_DATE|TIME_MINUTES));
   DrawRow(PREFIX+"CS", x + 8, y, cs, lab); y += h;
   string live = "no reclaim bar";
   if(idea.state==IDEA_LIVE) live = (idea.recovering ? "recovery live" : (idea.limitOpen ? "clip + limit" : "filled / managing"));
   if(idea.state==IDEA_PENDING) live = (idea.recovering ? "recovery pending" : (idea.leg2 ? "leg-2 pending" : "pending / straddle"));
   if(idea.state==IDEA_SL_WAIT) live = "sl-wait / reclaim";
   PanelKV(PREFIX+"LV", x, y, w, "Live", live, lab, lab);
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
   bool born = (ObjectFind(0, name) < 0);
   if(born)
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
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, "Drag to move panel");
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 5);
  }

void DrawRow(const string name, int x, int y, const string text, color clr)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 20);
  }

void DrawRight(const string name, int xr, int y, const string text, color clr)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, xr);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 21);
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

   const bool full = (prev_calculated <= 0);
   const bool newBar = (!full && time[1] != gLastClosedBar);
   int start = 0;
   if(full)
     {
      ArrayInitialize(BuyBuf, EMPTY_VALUE);
      ArrayInitialize(SellBuf, EMPTY_VALUE);
      ArrayInitialize(ReBuyBuf, EMPTY_VALUE);
      ArrayInitialize(ReSellBuf, EMPTY_VALUE);
      lastBuyTime = lastSellTime = 0;
      lastZone.signalTime = 0;
      lastZone.entry = lastZone.sl = lastZone.tp1 = lastZone.tp2 = 0;
      lastZone.state = IDEA_IDLE;
      ResetIdea();
      ResetCounts();
      ClearZones();
      gLastClosedBar = 0;
      start = MathMin(rates_total - 5, 800);
     }
   else if(newBar)
      start = 1;

   if(start < 1 && full) start = 1;

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

      if(idea.state == IDEA_IDLE && lastZone.signalTime != 0 && lastZone.sl > 0.0)
        {
         bool lastMitigated = (lastZone.dir > 0 ? (bar.l <= lastZone.sl) : (bar.h >= lastZone.sl));
         if(lastMitigated)
           {
            ClearLastZone();
            ClearZones();
           }
        }

      if(idea.state == IDEA_SL_WAIT)
        {
         if(idea.dir > 0 && bar.l < idea.slWick) idea.slWick = bar.l;
         if(idea.dir < 0 && bar.h > idea.slWick) idea.slWick = bar.h;
        }

      bool recoverBusy = false;
      if(InpRecoverOn && idea.state == IDEA_SL_WAIT
         && idea.recoverCount < InpMaxRecover
         && idea.slBarAge <= InpRecoverExpire)
        {
         recoverBusy = true;
         if(ReclaimOkInd(bar) && RecoveryBiasOkInd(d, h4, h1))
           {
            ArmRecoveryInd(bar);
            recoverBusy = idea.recovering;
            if(idea.recovering)
              {
               idea.artTime = time[i];
               if(idea.dir > 0) ReBuyBuf[i] = low[i];
               else             ReSellBuf[i] = high[i];
               HollowArrow(time[i], (idea.dir > 0 ? low[i] : high[i]), idea.dir,
                           (idea.dir > 0 ? InpReBuyColor : InpReSellColor), true);
              }
           }
        }

      double prevH = RecentSwingHigh(rates_total, i, high);
      double prevL = RecentSwingLow(rates_total, i, low);
      int slTo = MathMin(rates_total - 1, i + InpSLSwingLook);
      double slLo = low[i], slHi = high[i];
      for(int k = i; k <= slTo; k++)
        {
         if(low[k]  < slLo) slLo = low[k];
         if(high[k] > slHi) slHi = high[k];
        }
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
         && idea.slBarAge >= InpReentryCool
         && !idea.recovering && !recoverBusy)
        {
         if(idea.dir > 0 && trigB && allowB)
           {
            ReBuyBuf[i] = low[i];
            int rc = idea.reCount + 1;
            ArmIdea(1, bar, true, slLo);
            idea.reCount = rc;
            lastBuyTime = bar.t;
            gCntBuy++; gTodaySig++;
            HollowArrow(time[i], low[i], 1, InpReBuyColor, true);
            didRe = true;
           }
         else if(idea.dir < 0 && trigS && allowS)
           {
            ReSellBuf[i] = high[i];
            int rc = idea.reCount + 1;
            ArmIdea(-1, bar, true, slHi);
            idea.reCount = rc;
            lastSellTime = bar.t;
            gCntSell++; gTodaySig++;
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
            ArmIdea(1, bar, false, slLo);
            gCntBuy++; gTodaySig++;
            HollowArrow(time[i], low[i], 1, InpBuyColor, false);
           }
         else if(free && trigS && allowS && coolS)
           {
            SellBuf[i] = high[i];
            lastSellTime = bar.t;
            ArmIdea(-1, bar, false, slHi);
            gCntSell++; gTodaySig++;
            HollowArrow(time[i], high[i], -1, InpSellColor, false);
           }
        }
     }

   if(start >= 1)
      gLastClosedBar = time[1];

   if(idea.signalTime != 0 && idea.entry > 0.0 && idea.sl > 0.0)
      lastZone = idea;

   if((idea.limitOpen || idea.state == IDEA_PENDING) && !idea.recovering && !idea.leg2)
      ApplyStraddle(close[0]);

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

   string msg = StringFormat("Cinnamon %s %s | %s | close %s | %s%s",
                             side, _Symbol, tf, DoubleToString(barClose, _Digits),
                             TimeToString(barTime, TIME_DATE|TIME_MINUTES), extra);

   if(InpAlertPopup) Alert(msg);
   if(InpAlertSound) PlaySound(InpSoundFile);
   if(InpAlertPush)  SendNotification(msg);
   if(InpAlertEmail) SendMail("Cinnamon " + side + " " + _Symbol, msg);
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


void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_MOUSE_MOVE) return;
   int mx = (int)lparam;
   int my = (int)dparam;
   bool down = ((int)StringToInteger(sparam) & 1) == 1;
   if(down && !gDragging)
     {
      if(mx >= gPanelX && mx <= gPanelX + gPanelW && my >= gPanelY && my <= gPanelY + 28)
        {
         gDragging = true;
         gDragDX = mx - gPanelX;
         gDragDY = my - gPanelY;
        }
     }
   if(gDragging && down)
     {
      int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      gPanelX = mx - gDragDX;
      gPanelY = my - gDragDY;
      if(gPanelX < 0) gPanelX = 0;
      if(gPanelY < 0) gPanelY = 0;
      if(gPanelX > cw - 40) gPanelX = cw - 40;
      if(gPanelY > ch - 40) gPanelY = ch - 40;
      ObjectSetInteger(0, PREFIX+"BG", OBJPROP_XDISTANCE, gPanelX);
      ObjectSetInteger(0, PREFIX+"BG", OBJPROP_YDISTANCE, gPanelY);
      DrawPanel();
      ChartRedraw(0);
     }
   if(!down) gDragging = false;
  }
