//+------------------------------------------------------------------+
//| Lukes MTF EA                                                     |
//| Trades the signals of the Lukes MTF Ind indicator.               |
//| Rules: see EA_SPEC.md                                            |
//+------------------------------------------------------------------+
#property copyright "Lukes MTF EA"
#property link      ""
#property version   "1.08"

#include <Trade/Trade.mqh>

enum ENUM_EA_MODE
  {
   MODE_SIGNALS = 0,   // Signals only (no trading)
   MODE_SINGLE  = 1,   // Single trades only
   MODE_GRID    = 2    // Full grid
  };

enum ENUM_ENTRY_TYPE
  {
   ENTRY_MARKET  = 0,  // Market price at signal
   ENTRY_PENDING = 1   // Pending order at indicator Entry level
  };

enum ENUM_BASKET_TP
  {
   BASKET_MONEY    = 0,  // Money profit of the basket ($)
   BASKET_DISTANCE = 1   // Price distance beyond basket average ($)
  };

input group "=== EA Mode ==="
input ENUM_EA_MODE    InpMode        = MODE_SIGNALS;
input ENUM_ENTRY_TYPE InpEntryType   = ENTRY_PENDING;   // Pending = exactly the indicator's Entry/SL/TP1
input long            InpMagic       = 26092501;
input string          InpComment     = "LukesEA";
input int             InpSlippagePts = 30;       // max slippage (points)

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

input group "=== Single Trades ==="
input double InpSingleLot       = 0.01;
input bool   InpTPFromFill      = false;   // market entry: TP1 from fill price (same R) instead of indicator TP1
input bool   InpCloseOnOpposite = true;    // opposite signal closes the trade and reverses
input bool   InpTrailOn         = false;   // trailing stop
input int    InpTrailStartPts   = 300;     // start trailing after this profit (points)
input int    InpTrailDistPts    = 200;     // trail this far behind price (points)
input int    InpTrailStepPts    = 50;      // move SL in steps of (points)

input group "=== Grid ==="
input double         InpGridStartLot   = 0.01;
input int            InpGridDistPts    = 500;           // add a trade every N points against the basket
input double         InpGridMultiplier = 1.50;          // lot multiplier per grid level
input bool           InpGridWidenOn    = false;         // widen the gap at each new grid level
input double         InpGridGapMult    = 1.20;          // gap multiplier per level (1.20 = each gap 20% wider)
input int            InpGridMaxGapPts  = 0;             // largest allowed gap in points (0 = no cap)
input int            InpGridMaxTrades  = 5;             // max running trades (stop adding at this count)
input bool           InpBasketTPOn     = true;          // off = close all grid trades at single-trade TP1
input ENUM_BASKET_TP InpBasketTPType   = BASKET_MONEY;
input double         InpBasketTPMoney  = 5.00;          // basket TP in account money
input int            InpBasketTPPts    = 200;           // basket TP: points beyond basket average

input group "=== Grid Basket Break-even / Trailing ==="
input bool   InpBasketBEOn          = false;  // move basket stop to break-even
input int    InpBasketBEStartPts    = 150;    // activate when price is this many points past the basket average
input int    InpBasketBELockPts     = 20;     // basket stop = average + this many points (locks small profit)
input bool   InpBasketTrailOn       = false;  // trail the basket stop
input int    InpBasketTrailStartPts = 200;    // start trailing when price is this many points past the average
input int    InpBasketTrailDistPts  = 150;    // trail this many points behind price
input int    InpBasketTrailStepPts  = 20;     // move the basket stop in steps of (points)
input color  InpBasketStopColor     = clrOrange;
input bool   InpGridBrokerLevels    = true;   // put the basket TP/SL on every grid trade (visible on PC + mobile, works if MT5 is off)

input group "=== Equity Protector ==="
input bool   InpEquityProtOn  = true;
input double InpEquityProtPct = 10.0;      // close all when floating loss reaches % of current balance

input group "=== Alerts ==="
input bool   InpAlertTrades  = true;       // opens, closes, basket TP, equity stop
input bool   InpAlertSignals = false;      // indicator already alerts signals
input bool   InpAlertPopup   = true;
input bool   InpAlertSound   = true;
input bool   InpAlertPush    = true;
input string InpSoundFile    = "alert.wav";

input group "=== Visuals / Log ==="
input bool   InpDrawSignals  = true;       // dot on every EA signal candle (compare with indicator arrows)
input bool   InpShowPanel    = true;
input int    InpPanelX       = 4;        // left edge
input int    InpPanelY       = -1;       // -1 = bottom-left (indicator panel is top-left). Drag to move.
input int    InpPanelWidth   = 270;
input string InpPanelFontName = "Segoe UI Semilight"; // thin font for labels and values (thinner: "Segoe UI Light")
input string InpPanelFontHead = "Segoe UI";           // headings / title (e.g. "Segoe UI", "Calibri Light", "Arial")
input int    InpPanelFont    = 8;
input int    InpPanelRowH    = 15;
input ENUM_TIMEFRAMES InpTrendTF = PERIOD_H1;   // timeframe for the EMA trend line on the panel
input int    InpTrendFast    = 50;
input int    InpTrendSlow    = 200;
input bool   InpLogToFile    = true;       // MQL5/Files/LukesEA_log.csv
input color  InpBuyColor     = clrAqua;
input color  InpSellColor    = clrMagenta;
input color  InpReBuyColor   = clrGold;
input color  InpReSellColor  = clrYellow;

#define EAPRE   "LEA_"
#define LOGFILE "LukesEA_log.csv"

CTrade   trade;

datetime lastBuyTime   = 0;
datetime lastSellTime  = 0;
int gCntBuy = 0, gCntSell = 0, gCntTP1 = 0, gCntTP2 = 0, gCntSL = 0;

bool     gWarm          = false;   // engine replayed history
datetime gLastProcessed = 0;       // last closed bar fed to the engine
bool     gClosing       = false;   // closing everything, retry each tick until flat
datetime gNextGridTry   = 0;
string   gLastEvent     = "";
string   gLastSignal    = "none";

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

//+------------------------------------------------------------------+
//| Signal engine – copied from Lukes MTF Ind. Keep in sync.         |
//+------------------------------------------------------------------+
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

// the indicator uses EndIdea to keep its chart zone; the EA only needs the reset
void EndIdea(const string status, const datetime t)
  {
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

//+------------------------------------------------------------------+
//| EA                                                               |
//+------------------------------------------------------------------+
double RecentSwingHigh(const int i)
  {
   int total = Bars(_Symbol, _Period);
   int from = i + 1;
   int to   = (int)MathMin(total - 1, i + InpSwingLook);
   if(from > total - 1) return iHigh(_Symbol, _Period, i);
   double mx = iHigh(_Symbol, _Period, from);
   for(int k = from; k <= to; k++) { double h = iHigh(_Symbol, _Period, k); if(h > mx) mx = h; }
   return mx;
  }

double RecentSwingLow(const int i)
  {
   int total = Bars(_Symbol, _Period);
   int from = i + 1;
   int to   = (int)MathMin(total - 1, i + InpSwingLook);
   if(from > total - 1) return iLow(_Symbol, _Period, i);
   double mn = iLow(_Symbol, _Period, from);
   for(int k = from; k <= to; k++) { double l = iLow(_Symbol, _Period, k); if(l < mn) mn = l; }
   return mn;
  }

// Same per-bar logic as the indicator's OnCalculate loop.
// Returns 1 = BUY, -1 = SELL, 2 = RE-BUY, -2 = RE-SELL, 0 = none.
int ProcessBar(const int i)
  {
   Candle bar;
   bar.o = iOpen(_Symbol, _Period, i);
   bar.h = iHigh(_Symbol, _Period, i);
   bar.l = iLow(_Symbol, _Period, i);
   bar.c = iClose(_Symbol, _Period, i);
   bar.t = iTime(_Symbol, _Period, i);
   bar.valid = true;
   if(bar.t == 0) return 0;

   Bias d  = TFBiasAt(InpTF_D,  bar.t);
   Bias h4 = TFBiasAt(InpTF_H4, bar.t);
   Bias h1 = TFBiasAt(InpTF_H1, bar.t);
   Bias m5 = TFBiasAt(InpTF_M5, bar.t);
   int sb = (d.dir==1) + (h4.dir==1) + (h1.dir==1) + (m5.dir==1);
   int ss = (d.dir==-1) + (h4.dir==-1) + (h1.dir==-1) + (m5.dir==-1);

   ManageIdea(bar, d, h4);

   double prevH = RecentSwingHigh(i);
   double prevL = RecentSwingLow(i);
   bool trigB = QualityBullTrigger(bar, prevH);
   bool trigS = QualityBearTrigger(bar, prevL);

   if(InpUseM5Trigger && PeriodSeconds(_Period) <= PeriodSeconds(PERIOD_M15))
     {
      Candle m5c = CandleAtShift(InpTF_M5, ClosedShiftAt(InpTF_M5, bar.t));
      if(trigB && !BullCandle(m5c)) trigB = false;
      if(trigS && !BearCandle(m5c)) trigS = false;
     }

   bool allowB = StructureAllows(1, d, h4, h1, sb, ss);
   bool allowS = StructureAllows(-1, d, h4, h1, sb, ss);

   if(InpReentryOn && idea.state == IDEA_SL_WAIT && idea.reCount < InpMaxReentry
      && idea.slBarAge >= InpReentryCool)
     {
      if(idea.dir > 0 && trigB && allowB)
        {
         int rc = idea.reCount + 1;
         ArmIdea(1, bar, true);
         idea.reCount = rc;
         lastBuyTime = bar.t;
         gCntBuy++;
         return 2;
        }
      else if(idea.dir < 0 && trigS && allowS)
        {
         int rc = idea.reCount + 1;
         ArmIdea(-1, bar, true);
         idea.reCount = rc;
         lastSellTime = bar.t;
         gCntSell++;
         return -2;
        }
     }

   bool coolB = Cooled(bar.t, lastBuyTime, InpCooldown) && Cooled(bar.t, lastSellTime, 3);
   bool coolS = Cooled(bar.t, lastSellTime, InpCooldown) && Cooled(bar.t, lastBuyTime, 3);
   bool free = (idea.state == IDEA_IDLE);

   if(free && trigB && allowB && coolB)
     {
      lastBuyTime = bar.t;
      ArmIdea(1, bar, false);
      gCntBuy++;
      return 1;
     }
   if(free && trigS && allowS && coolS)
     {
      lastSellTime = bar.t;
      ArmIdea(-1, bar, false);
      gCntSell++;
      return -1;
     }
   return 0;
  }

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
string SigName(const int sig)
  {
   if(sig == 1)  return "BUY";
   if(sig == -1) return "SELL";
   if(sig == 2)  return "RE-BUY";
   if(sig == -2) return "RE-SELL";
   return "NONE";
  }

color SigColor(const int sig)
  {
   if(sig == 1)  return InpBuyColor;
   if(sig == -1) return InpSellColor;
   if(sig == 2)  return InpReBuyColor;
   return InpReSellColor;
  }

string ModeName()
  {
   if(InpMode == MODE_SINGLE) return "Single trades";
   if(InpMode == MODE_GRID)   return "Full grid";
   return "Signals only";
  }

string Px(const double p) { return DoubleToString(p, _Digits); }

void Log(const string event, const string details)
  {
   gLastEvent = TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + "  " + event + "  " + details;
   Print("LukesEA ", event, " | ", details);
   if(!InpLogToFile) return;
   int h = FileOpen(LOGFILE, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE, ',');
   if(h == INVALID_HANDLE) return;
   if(FileSize(h) == 0)
      FileWrite(h, "time", "symbol", "magic", "mode", "event", "details");
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), _Symbol, (string)InpMagic, ModeName(), event, details);
   FileClose(h);
  }

void Notify(const string msg)
  {
   string full = "Lukes MTF EA " + _Symbol + " | " + msg;
   if(InpAlertPopup) Alert(full);
   if(InpAlertSound) PlaySound(InpSoundFile);
   if(InpAlertPush)  SendNotification(full);
  }

void DrawSignal(const int i, const int sig)
  {
   if(!InpDrawSignals) return;
   datetime t = iTime(_Symbol, _Period, i);
   if(t == 0) return;
   string name = EAPRE + "S" + IntegerToString((long)t);
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROW, 0, t, iClose(_Symbol, _Period, i));
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);   // small dot on the signal candle's close
   ObjectSetInteger(0, name, OBJPROP_COLOR, SigColor(sig));
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, "EA " + SigName(sig));
  }

double NormLot(double lot)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double mn   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   lot = MathFloor(lot / step + 1e-9) * step;
   lot = MathMax(mn, MathMin(mx, lot));
   int dg = (int)MathMax(0, MathCeil(-MathLog10(step) - 1e-9));
   return NormalizeDouble(lot, dg);
  }

double MinStop()
  {
   long lvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   return (double)lvl * _Point;
  }

// point inputs -> price distance (uses the same auto-digits unit as the signal engine)
double TrailStart() { return InpTrailStartPts * Pt(); }
double TrailDist()  { return InpTrailDistPts  * Pt(); }
double TrailStep()  { return InpTrailStepPts  * Pt(); }
// gap (points) before the next grid trade when `open` trades are running:
// gap 1 (to trade #2) = base, gap 2 = base x mult, gap 3 = base x mult^2 ...
int GridGapPts(const int open)
  {
   double g = InpGridDistPts;
   if(InpGridWidenOn && open > 1) g *= MathPow(InpGridGapMult, open - 1);
   if(InpGridMaxGapPts > 0 && g > InpGridMaxGapPts) g = InpGridMaxGapPts;
   return (int)MathRound(g);
  }
double GridDist(const int open) { return GridGapPts(open) * Pt(); }
double BasketDist() { return InpBasketTPPts   * Pt(); }

bool Ours()
  {
   return (PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic);
  }

bool OurOrder()
  {
   return (OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic);
  }

struct Basket
  {
   int    count;
   int    dir;         // 1 buy, -1 sell, 0 none
   double lots;
   double avg;         // volume-weighted open price
   double extreme;     // lowest buy / highest sell open price
   double profit;      // profit + swap
  };

Basket GetBasket()
  {
   Basket b;
   b.count = 0; b.dir = 0; b.lots = 0; b.avg = 0; b.extreme = 0; b.profit = 0;
   double pv = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !Ours()) continue;
      int    d  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1);
      double v  = PositionGetDouble(POSITION_VOLUME);
      double op = PositionGetDouble(POSITION_PRICE_OPEN);
      b.count++;
      b.dir = d;
      b.lots += v;
      pv += op * v;
      b.profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(b.extreme == 0 || (d > 0 && op < b.extreme) || (d < 0 && op > b.extreme))
         b.extreme = op;
     }
   if(b.lots > 0) b.avg = pv / b.lots;
   return b;
  }

int CountOrders()
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk != 0 && OurOrder()) n++;
     }
   return n;
  }

void CloseAll(const string why)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !Ours()) continue;
      if(!trade.PositionClose(tk, InpSlippagePts))
         Log("CLOSE_FAIL", StringFormat("ticket %I64u (%s) retcode %u %s", tk, why, trade.ResultRetcode(), trade.ResultRetcodeDescription()));
      else
         Log("CLOSE", StringFormat("ticket %I64u (%s)", tk, why));
     }
  }

void DeleteOrders(const string why)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || !OurOrder()) continue;
      if(trade.OrderDelete(tk))
         Log("ORDER_DELETE", StringFormat("ticket %I64u (%s)", tk, why));
      else
         Log("ORDER_DELETE_FAIL", StringFormat("ticket %I64u (%s) retcode %u", tk, why, trade.ResultRetcode()));
     }
  }

// grid "close at TP1" level survives restarts in a terminal global variable
string TP1Key() { return "LukesEA_" + _Symbol + "_" + IntegerToString(InpMagic) + "_TP1"; }
void   SaveTP1(const double p) { GlobalVariableSet(TP1Key(), p); }
double LoadTP1() { return (GlobalVariableCheck(TP1Key()) ? GlobalVariableGet(TP1Key()) : 0.0); }

// basket break-even / trailing stop: virtual (no SL on the grid orders, rule R8),
// kept in a terminal global variable so it survives restarts
string BStopKey() { return "LukesEA_" + _Symbol + "_" + IntegerToString(InpMagic) + "_BSTOP"; }
double LoadBStop() { return (GlobalVariableCheck(BStopKey()) ? GlobalVariableGet(BStopKey()) : 0.0); }

void DrawBStop(const double p)
  {
   string name = EAPRE + "BSTOP";
   if(p <= 0) { ObjectDelete(0, name); return; }
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, p);
   ObjectSetDouble(0, name, OBJPROP_PRICE, p);
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpBasketStopColor);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, "Basket stop " + DoubleToString(p, _Digits));
  }

void SaveBStop(const double p)
  {
   if(p <= 0) GlobalVariableDel(BStopKey());
   else       GlobalVariableSet(BStopKey(), p);
   DrawBStop(p);
  }

//+------------------------------------------------------------------+
//| Entries                                                          |
//+------------------------------------------------------------------+
// TP1 for a market entry: indicator TP1, or from the fill price with the same R
double MarketTP1(const int dir, const double price, const double sl)
  {
   double tp = idea.tp1;
   double ms = MinStop();
   bool valid = (dir > 0 ? tp > price + ms : tp < price - ms);
   if(InpTPFromFill || !valid)
     {
      double risk = MathAbs(price - sl);
      tp = (dir > 0 ? price + risk * InpRR1 : price - risk * InpRR1);
     }
   return NormalizeDouble(tp, _Digits);
  }

bool OpenEntry(const int dir, const double lotIn, const bool withStops, const string tag)
  {
   double lot = NormLot(lotIn);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ms  = MinStop();
   double sl  = NormalizeDouble(idea.sl, _Digits);
   string cmt = InpComment + "|" + IntegerToString((long)idea.signalTime);

   bool pending = (InpEntryType == ENTRY_PENDING);
   double entry = NormalizeDouble(idea.entry, _Digits);
   ENUM_ORDER_TYPE otype = ORDER_TYPE_BUY;
   if(pending)
     {
      if(dir > 0)
        {
         if(entry < ask - ms)      otype = ORDER_TYPE_BUY_LIMIT;
         else if(entry > ask + ms) otype = ORDER_TYPE_BUY_STOP;
         else pending = false;     // price is at the entry already
        }
      else
        {
         if(entry > bid + ms)      otype = ORDER_TYPE_SELL_LIMIT;
         else if(entry < bid - ms) otype = ORDER_TYPE_SELL_STOP;
         else pending = false;
        }
     }

   double price = (pending ? entry : (dir > 0 ? ask : bid));
   // the SL must still be on the losing side of the entry
   if(dir > 0 ? (sl >= price - ms) : (sl <= price + ms))
     {
      Log("SKIP", StringFormat("%s: price %s already beyond SL %s", tag, Px(price), Px(sl)));
      return false;
     }
   double tp1 = (pending ? NormalizeDouble(idea.tp1, _Digits) : MarketTP1(dir, price, sl));

   double oSL = (withStops ? sl  : 0.0);
   double oTP = (withStops ? tp1 : 0.0);

   bool ok;
   if(pending)
      ok = trade.OrderOpen(_Symbol, otype, lot, 0, entry, oSL, oTP, ORDER_TIME_GTC, 0, cmt);
   else if(dir > 0)
      ok = trade.Buy(lot, _Symbol, 0, oSL, oTP, cmt);
   else
      ok = trade.Sell(lot, _Symbol, 0, oSL, oTP, cmt);

   uint rc = trade.ResultRetcode();
   if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED && rc != TRADE_RETCODE_DONE_PARTIAL))
     {
      Log("OPEN_FAIL", StringFormat("%s %s lot %.2f retcode %u %s", tag, (pending ? EnumToString(otype) : "market"),
                                    lot, rc, trade.ResultRetcodeDescription()));
      return false;
     }

   if(InpMode == MODE_GRID) { SaveTP1(tp1); SaveBStop(0); }
   string what = StringFormat("%s %s lot %.2f @ %s  SL %s  TP %s", tag,
                              (pending ? EnumToString(otype) : (dir > 0 ? "BUY market" : "SELL market")),
                              lot, Px(pending ? entry : trade.ResultPrice()),
                              (withStops ? Px(sl) : "none"), (withStops ? Px(tp1) : "none"));
   Log("OPEN", what);
   if(InpAlertTrades) Notify("OPEN " + what);
   return true;
  }

//+------------------------------------------------------------------+
//| Acting on a new signal                                           |
//+------------------------------------------------------------------+
void ActOnSignal(const int sig)
  {
   int dir = (sig > 0 ? 1 : -1);
   string tag = SigName(sig);

   if(idea.state == IDEA_IDLE || idea.signalTime == 0)
     {
      Log("SKIP", tag + ": signal has no valid levels");
      return;
     }

   if(InpMode == MODE_SINGLE)
     {
      Basket b = GetBasket();
      if(b.count > 0)
        {
         if(b.dir == dir) { Log("SKIP", tag + ": trade already open in this direction"); return; }
         if(!InpCloseOnOpposite) { Log("SKIP", tag + ": opposite trade open"); return; }
         CloseAll("opposite signal " + tag);
         if(GetBasket().count > 0) { gClosing = true; Log("SKIP", tag + ": could not close opposite trade yet"); return; }
        }
      if(CountOrders() > 0) DeleteOrders("replaced by " + tag);
      OpenEntry(dir, InpSingleLot, true, tag);
      return;
     }

   if(InpMode == MODE_GRID)
     {
      Basket b = GetBasket();
      if(b.count > 0)
        {
         Log("SKIP", StringFormat("%s: grid basket running (%s x%d), one direction at a time",
                                  tag, (b.dir > 0 ? "BUY" : "SELL"), b.count));
         return;
        }
      if(CountOrders() > 0) DeleteOrders("replaced by " + tag);
      OpenEntry(dir, InpGridStartLot, false, tag + " grid#1");
     }
  }

// pending orders live only while their indicator idea is pending/live
void SyncOrders()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || !OurOrder()) continue;
      string cmt = OrderGetString(ORDER_COMMENT);
      int p = StringFind(cmt, "|");
      datetime sigT = 0;
      if(p >= 0) sigT = (datetime)StringToInteger(StringSubstr(cmt, p + 1));
      datetime setup = (datetime)OrderGetInteger(ORDER_TIME_SETUP);

      string why = "";
      if(sigT == 0 || sigT != idea.signalTime || (idea.state != IDEA_PENDING && idea.state != IDEA_LIVE))
         why = "indicator idea ended";
      else if(TimeCurrent() >= setup + (datetime)(InpPendingExpire + 1) * PeriodSeconds(_Period))
         why = "expired";
      if(why == "") continue;

      if(trade.OrderDelete(tk)) Log("ORDER_DELETE", StringFormat("ticket %I64u (%s)", tk, why));
     }
  }

//+------------------------------------------------------------------+
//| Per-tick trade management                                        |
//+------------------------------------------------------------------+
void Trail()
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double ms  = MinStop();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !Ours()) continue;
      bool   buy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double op  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl  = PositionGetDouble(POSITION_SL);
      double tp  = PositionGetDouble(POSITION_TP);
      if(buy)
        {
         if(bid - op < TrailStart()) continue;
         double nsl = NormalizeDouble(bid - TrailDist(), _Digits);
         if(nsl > bid - ms) continue;
         if(sl != 0 && nsl < sl + TrailStep()) continue;
         if(trade.PositionModify(tk, nsl, tp)) Log("TRAIL", StringFormat("ticket %I64u SL -> %s", tk, Px(nsl)));
        }
      else
        {
         if(op - ask < TrailStart()) continue;
         double nsl = NormalizeDouble(ask + TrailDist(), _Digits);
         if(nsl < ask + ms) continue;
         if(sl != 0 && nsl > sl - TrailStep()) continue;
         if(trade.PositionModify(tk, nsl, tp)) Log("TRAIL", StringFormat("ticket %I64u SL -> %s", tk, Px(nsl)));
        }
     }
  }

// Moves the virtual basket stop (break-even, then trailing). Returns true when it is hit.
bool BasketStopHit(const Basket &b, const double bid, const double ask, string &why)
  {
   double stop = LoadBStop();
   if(!InpBasketBEOn && !InpBasketTrailOn && stop <= 0) return false;

   int    d     = b.dir;
   double px    = (d > 0 ? bid : ask);            // price the basket would close at
   double fav   = (d > 0 ? px - b.avg : b.avg - px);
   double ptu   = Pt();
   double nstop = stop;

   // break-even: lock average + N points
   if(InpBasketBEOn && fav >= InpBasketBEStartPts * ptu)
     {
      double be = NormalizeDouble(b.avg + d * InpBasketBELockPts * ptu, _Digits);
      if(nstop <= 0 || (d > 0 ? be > nstop : be < nstop)) nstop = be;
     }

   // trailing: N points behind price, only once that is past the average
   if(InpBasketTrailOn && fav >= InpBasketTrailStartPts * ptu)
     {
      double tr = NormalizeDouble(px - d * InpBasketTrailDistPts * ptu, _Digits);
      bool profitable = (d > 0 ? tr > b.avg : tr < b.avg);
      double step = InpBasketTrailStepPts * ptu;
      if(profitable && (nstop <= 0 || (d > 0 ? tr >= nstop + step : tr <= nstop - step))) nstop = tr;
     }

   if(nstop != stop && nstop > 0)
     {
      Log(stop <= 0 ? "BASKET_BE" : "BASKET_TRAIL",
          StringFormat("basket stop %s -> %s (avg %s, price %s)", (stop > 0 ? Px(stop) : "none"), Px(nstop), Px(b.avg), Px(px)));
      SaveBStop(nstop);
      stop = nstop;
     }
   else if(stop > 0 && ObjectFind(0, EAPRE + "BSTOP") < 0)
      DrawBStop(stop);   // redraw after a restart

   if(stop > 0 && (d > 0 ? bid <= stop : ask >= stop))
     {
      why = "basket stop hit " + Px(stop);
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Basket TP/SL as real levels on every grid trade                  |
//| All trades share ONE TP and ONE SL price, so they still close    |
//| together as a basket (rule R8: no individual TP/SL per trade).   |
//+------------------------------------------------------------------+
int gPrevGridCount = 0;

// account money per 1.0 price move for the whole basket
double MoneyPerPrice(const double lots)
  {
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0 || ts <= 0 || lots <= 0) return 0;
   return lots * tv / ts;
  }

// price at which the basket P/L equals `money`
double PriceForProfit(const Basket &b, const double money, const double px)
  {
   double mpp = MoneyPerPrice(b.lots);
   if(mpp <= 0) return 0;
   return px + b.dir * (money - b.profit) / mpp;
  }

double GridTPPrice(const Basket &b, const double px)
  {
   double tp1 = LoadTP1();
   if(!InpBasketTPOn && tp1 > 0) return tp1;
   if(InpBasketTPType == BASKET_DISTANCE) return b.avg + b.dir * BasketDist();
   return PriceForProfit(b, InpBasketTPMoney, px);
  }

// tightest of: basket break-even/trailing stop, Equity Protector price
double GridSLPrice(const Basket &b, const double px)
  {
   double sl = LoadBStop();
   if(InpEquityProtOn)
     {
      double limit = -AccountInfoDouble(ACCOUNT_BALANCE) * InpEquityProtPct / 100.0;
      double eq = PriceForProfit(b, limit, px);
      if(eq > 0 && (sl <= 0 || (b.dir > 0 ? eq > sl : eq < sl))) sl = eq;
     }
   return sl;
  }

void SyncGridLevels(const Basket &b)
  {
   if(!InpGridBrokerLevels || b.count == 0) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double px  = (b.dir > 0 ? bid : ask);
   double ms  = MinStop() + _Point;
   double tol = 5 * Pt();   // ignore changes smaller than 5 points (avoid modify spam)

   double tp = NormalizeDouble(GridTPPrice(b, px), _Digits);
   double sl = NormalizeDouble(GridSLPrice(b, px), _Digits);
   // a level too close to price is left off; the EA's own check still closes the basket
   if(tp > 0 && (b.dir > 0 ? tp < bid + ms : tp > ask - ms)) tp = 0;
   if(sl > 0 && (b.dir > 0 ? sl > bid - ms : sl < ask + ms)) sl = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !Ours()) continue;
      double csl = PositionGetDouble(POSITION_SL);
      double ctp = PositionGetDouble(POSITION_TP);
      double nsl = (sl > 0 ? sl : csl);
      double ntp = (tp > 0 ? tp : ctp);
      bool chg = (MathAbs(nsl - csl) >= tol || MathAbs(ntp - ctp) >= tol
                  || (csl == 0 && nsl > 0) || (ctp == 0 && ntp > 0));
      if(!chg) continue;
      if(trade.PositionModify(tk, nsl, ntp))
         Log("GRID_LEVELS", StringFormat("ticket %I64u  SL %s  TP %s", tk, (nsl > 0 ? Px(nsl) : "none"), (ntp > 0 ? Px(ntp) : "none")));
     }
  }

void ManageGrid(const Basket &b)
  {
   if(b.count == 0)
     {
      if(gPrevGridCount > 0)
        {
         Log("BASKET_CLOSED", "grid basket closed by its TP/SL on the broker side");
         if(InpAlertTrades) Notify("BASKET CLOSED by TP/SL");
        }
      gPrevGridCount = 0;
      if(LoadBStop() > 0) SaveBStop(0);
      return;
     }
   gPrevGridCount = b.count;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // 1) basket exit
   bool   close = false;
   string why   = "";
   double tp1   = LoadTP1();
   if(InpBasketTPOn || tp1 <= 0)
     {
      if(InpBasketTPType == BASKET_MONEY)
        {
         close = (b.profit >= InpBasketTPMoney);
         why = StringFormat("basket TP money %.2f >= %.2f", b.profit, InpBasketTPMoney);
        }
      else
        {
         close = (b.dir > 0 ? bid >= b.avg + BasketDist() : ask <= b.avg - BasketDist());
         why = StringFormat("basket TP distance: avg %s +/- %d pts", Px(b.avg), InpBasketTPPts);
        }
     }
   else
     {
      close = (b.dir > 0 ? bid >= tp1 : ask <= tp1);
      why = "grid closed at single-trade TP1 " + Px(tp1);
     }
   string bwhy = "";
   if(!close && BasketStopHit(b, bid, ask, bwhy)) { close = true; why = bwhy; }
   if(close)
     {
      SaveBStop(0);
      string msg = StringFormat("%s | %d trades, %.2f lots, P/L %.2f", why, b.count, b.lots, b.profit);
      Log("BASKET_CLOSE", msg);
      if(InpAlertTrades) Notify("BASKET CLOSE " + msg);
      gClosing = true;
      CloseAll("basket close");
      return;
     }

   SyncGridLevels(b);

   // 2) add a grid trade
   if(b.count >= InpGridMaxTrades) return;
   if(TimeCurrent() < gNextGridTry) return;
   bool add = (b.dir > 0 ? ask <= b.extreme - GridDist(b.count) : bid >= b.extreme + GridDist(b.count));
   if(!add) return;

   double lot = NormLot(InpGridStartLot * MathPow(InpGridMultiplier, b.count));
   string cmt = InpComment + "|grid" + IntegerToString(b.count + 1);
   bool ok = (b.dir > 0 ? trade.Buy(lot, _Symbol, 0, 0, 0, cmt) : trade.Sell(lot, _Symbol, 0, 0, 0, cmt));
   uint rc = trade.ResultRetcode();
   if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_DONE_PARTIAL))
     {
      gNextGridTry = TimeCurrent() + 10;
      Log("GRID_FAIL", StringFormat("level %d lot %.2f retcode %u %s", b.count + 1, lot, rc, trade.ResultRetcodeDescription()));
      return;
     }
   string what = StringFormat("grid#%d %s lot %.2f @ %s (last %s, distance %d pts)", b.count + 1,
                              (b.dir > 0 ? "BUY" : "SELL"), lot, Px(trade.ResultPrice()), Px(b.extreme), GridGapPts(b.count));
   Log("GRID_ADD", what);
   if(InpAlertTrades) Notify("GRID ADD " + what);
  }

void ManageTrades()
  {
   if(gClosing)
     {
      CloseAll("closing all");
      if(GetBasket().count == 0) { gClosing = false; gPrevGridCount = 0; Log("FLAT", "all EA trades closed"); }
      return;
     }

   Basket b = GetBasket();

   // Equity Protector: floating loss vs % of current balance
   if(InpEquityProtOn && b.count > 0)
     {
      double bal   = AccountInfoDouble(ACCOUNT_BALANCE);
      double limit = -bal * InpEquityProtPct / 100.0;
      if(b.profit <= limit)
        {
         string msg = StringFormat("floating %.2f <= -%.1f%% of balance %.2f (%.2f). Closing all, waiting for next signal.",
                                   b.profit, InpEquityProtPct, bal, limit);
         Log("EQUITY_STOP", msg);
         Notify("EQUITY PROTECTOR " + msg);
         gClosing = true;
         CloseAll("equity protector");
         DeleteOrders("equity protector");
         return;
        }
     }

   if(InpMode == MODE_SINGLE && InpTrailOn) Trail();
   if(InpMode == MODE_GRID) ManageGrid(b);
  }

//+------------------------------------------------------------------+
//| Engine driver                                                    |
//+------------------------------------------------------------------+
bool WarmUp()
  {
   int total = Bars(_Symbol, _Period);
   if(total < 40) return false;
   if(iTime(_Symbol, InpTF_D, 1) == 0 || iTime(_Symbol, InpTF_H4, 1) == 0 ||
      iTime(_Symbol, InpTF_H1, 1) == 0 || iTime(_Symbol, InpTF_M5, 1) == 0)
      return false;   // higher timeframe history still loading

   ResetIdea();
   ResetCounts();
   lastBuyTime = lastSellTime = 0;
   int start = (int)MathMin(total - 5, 800);
   if(start < 1) start = 1;
   for(int i = start; i >= 1; i--)
     {
      int s = ProcessBar(i);
      if(s != 0) { DrawSignal(i, s); AddSignalTime(iTime(_Symbol, _Period, i)); gLastSignal = SigName(s) + " " + TimeToString(iTime(_Symbol, _Period, i), TIME_DATE|TIME_MINUTES); }
     }
   gLastProcessed = iTime(_Symbol, _Period, 1);
   return true;
  }

void OnNewBars()
  {
   int from = 1;
   int sh = iBarShift(_Symbol, _Period, gLastProcessed, true);
   if(sh > 1) from = sh - 1;

   int sig = 0;
   for(int i = from; i >= 1; i--)
     {
      sig = ProcessBar(i);
      if(sig != 0) { DrawSignal(i, sig); AddSignalTime(iTime(_Symbol, _Period, i)); }
     }
   gLastProcessed = iTime(_Symbol, _Period, 1);

   if(InpMode != MODE_SIGNALS) SyncOrders();
   if(sig == 0) return;

   gLastSignal = SigName(sig) + " " + TimeToString(gLastProcessed, TIME_DATE|TIME_MINUTES);
   string lv = StringFormat("%s  Entry %s  SL %s  TP1 %s  TP2 %s", SigName(sig),
                            Px(idea.entry), Px(idea.sl), Px(idea.tp1), Px(idea.tp2));
   Log("SIGNAL", lv);
   if(InpAlertSignals) Notify("SIGNAL " + lv);
   string blk = TradeBlocker();
   if(blk != "" && InpMode != MODE_SIGNALS)
     {
      Log("SKIP", SigName(sig) + ": " + blk);
      if(InpAlertTrades) Notify("Signal NOT traded: " + blk);
      return;
     }
   if(InpMode != MODE_SIGNALS && !gClosing) ActOnSignal(sig);
  }

string StateText()
  {
   if(idea.state == IDEA_PENDING) return (idea.dir > 0 ? "PENDING LONG" : "PENDING SHORT");
   if(idea.state == IDEA_LIVE)    return (idea.dir > 0 ? "LIVE LONG" : "LIVE SHORT");
   if(idea.state == IDEA_SL_WAIT) return StringFormat("SL HIT  re %d/%d", idea.reCount, InpMaxReentry);
   return "IDLE";
  }

// why the EA cannot trade right now ("" = it can)
string TradeBlocker()
  {
   if(InpMode == MODE_SIGNALS)
      return "MODE = SIGNALS ONLY: no trades. Set InpMode to Single trades or Full grid.";
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return "ALGO TRADING IS OFF: press the 'Algo Trading' button in the MT5 toolbar.";
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return "EA NOT ALLOWED TO TRADE: EA settings > Common > tick 'Allow Algo Trading'.";
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      return "ACCOUNT CANNOT TRADE: logged in with investor (read-only) password?";
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      return "BROKER DISABLED EA TRADING on this account.";
   long tm = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(tm == SYMBOL_TRADE_MODE_DISABLED || tm == SYMBOL_TRADE_MODE_CLOSEONLY)
      return "TRADING DISABLED/CLOSE-ONLY for " + _Symbol + " (market closed?).";
   return "";
  }

string gLastBlocker = "-";

void CheckBlocker()
  {
   string b = TradeBlocker();
   if(b == gLastBlocker) return;
   gLastBlocker = b;
   if(b == "") Log("TRADING_OK", "EA is allowed to trade");
   else        Log("NOT_TRADING", b);
  }

//+------------------------------------------------------------------+
//| Dashboard panel                                                  |
//+------------------------------------------------------------------+
#define PPRE    "LEA_P_"
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
datetime gSigTimes[];
uint   gLastPanelMs = 0;

void AddSignalTime(const datetime t)
  {
   int n = ArraySize(gSigTimes);
   if(n > 0 && gSigTimes[n - 1] == t) return;
   if(n >= 500) { ArrayRemove(gSigTimes, 0, 100); n = ArraySize(gSigTimes); }
   ArrayResize(gSigTimes, n + 1);
   gSigTimes[n] = t;
  }

datetime DayStart() { datetime t = TimeCurrent(); return t - (t % 86400); }

int SignalsToday()
  {
   datetime d = DayStart();
   int c = 0;
   for(int i = ArraySize(gSigTimes) - 1; i >= 0; i--) if(gSigTimes[i] >= d) c++;
   return c;
  }

// Closed EA trades today. Deals that close within 5 s of each other in the
// same direction are one trade (a grid basket closing together counts once).
void TodayStats(int &trades, int &wins, int &losses, double &pl)
  {
   trades = wins = losses = 0; pl = 0;
   if(!HistorySelect(DayStart(), TimeCurrent() + 60)) return;
   int n = HistoryDealsTotal();
   datetime gT = 0; long gType = -1; double gPL = 0; bool open = false;
   for(int i = 0; i < n; i++)
     {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0) continue;
      if(HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(tk, DEAL_MAGIC) != InpMagic) continue;
      long entry = HistoryDealGetInteger(tk, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) continue;
      datetime t   = (datetime)HistoryDealGetInteger(tk, DEAL_TIME);
      long     typ = HistoryDealGetInteger(tk, DEAL_TYPE);
      double   p   = HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_SWAP)
                     + HistoryDealGetDouble(tk, DEAL_COMMISSION);
      pl += p;
      if(open && typ == gType && t - gT <= 5) { gPL += p; gT = t; continue; }
      if(open) { trades++; if(gPL >= 0) wins++; else losses++; }
      open = true; gT = t; gType = typ; gPL = p;
     }
   if(open) { trades++; if(gPL >= 0) wins++; else losses++; }
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

void UpdatePanel(const bool force = false)
  {
   if(!InpShowPanel) return;
   uint now = GetTickCount();
   if(!force && gLastPanelMs != 0 && now - gLastPanelMs < 500) return;   // redraw at most twice a second
   gLastPanelMs = now;

   Basket b = GetBasket();
   string blk = TradeBlocker();
   color  c;
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
   if(InpMode == MODE_SIGNALS)      { st = "SIGNALS ONLY"; sc = C_INFO; }
   else if(blk != "")               { st = "NOT TRADING";  sc = C_DN; }
   else if(b.count > 0)             { st = "IN TRADE";     sc = C_UP; }
   else                             { st = "WAITING";      sc = C_WARN; }
   PText(PPRE + "T1", gPX + 10, gPY + 6, "LUKES MTF EA", C_TXT, InpPanelFont + 3, ANCHOR_LEFT_UPPER, InpPanelFontHead);
   PText(PPRE + "T2", gPX + InpPanelWidth - 10, gPY + 6, "v1.08  " + ShortToString((ushort)(gCollapsed ? 0x25B6 : 0x25BC)), C_MUTE, InpPanelFont - 1, ANCHOR_RIGHT_UPPER, InpPanelFontName);
   PText(PPRE + "T3", gPX + 10, gPY + 27, _Symbol + "  " + StringSubstr(EnumToString(_Period), 7), C_LBL, InpPanelFont, ANCHOR_LEFT_UPPER, InpPanelFontName);
   PText(PPRE + "T4", gPX + InpPanelWidth - 10, gPY + 27, ShortToString((ushort)0x25CF) + " " + st, sc, InpPanelFont, ANCHOR_RIGHT_UPPER, InpPanelFontHead);

   if(!gCollapsed)
   {

   PSection("MARKET");
   string v;
   v = SessionName(c);      PRow("Session", v, c);
   v = TrendText(c);        PRow("Trend (" + StringSubstr(EnumToString(InpTrendTF), 7) + ")", v, c);
   v = BiasText(InpTF_D, c);  PRow("D1", v, c);
   v = BiasText(InpTF_H4, c); PRow("H4", v, c);
   v = BiasText(InpTF_H1, c); PRow("H1", v, c);
   v = BiasText(InpTF_M5, c); PRow("M5", v, c);
   Bias bd = TFBiasNow(InpTF_D), b4 = TFBiasNow(InpTF_H4), b1 = TFBiasNow(InpTF_H1), b5 = TFBiasNow(InpTF_M5);
   int sb = (bd.dir==1) + (b4.dir==1) + (b1.dir==1) + (b5.dir==1);
   int ss = (bd.dir==-1) + (b4.dir==-1) + (b1.dir==-1) + (b5.dir==-1);
   PRow("Align B / S", StringFormat("%d / %d", sb, ss), (sb >= InpMinAlign ? C_UP : (ss >= InpMinAlign ? C_DN : C_MUTE)));
   double spr = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / Pt();
   PRow("Spread", StringFormat("%.0f pts", spr), (spr > 50 ? C_WARN : C_TXT));

   int tr, w, l; double pl;
   TodayStats(tr, w, l, pl);
   PSection("TODAY");
   PRow("Signals", IntegerToString(SignalsToday()), C_INFO);
   PRow("Trades closed", IntegerToString(tr), C_TXT);
   PRow("TP (wins)", IntegerToString(w), C_UP);
   PRow("SL (losses)", IntegerToString(l), C_DN);
   PRow("Win rate", (tr > 0 ? StringFormat("%.0f%%", 100.0 * w / tr) : "-"),
        (tr == 0 ? C_MUTE : (w * 2 >= tr ? C_UP : C_DN)));
   PRow("Profit / loss", StringFormat("%+.2f %s", pl, AccountInfoString(ACCOUNT_CURRENCY)), (pl > 0 ? C_UP : (pl < 0 ? C_DN : C_TXT)));

   PSection("EA");
   PRow("Mode", ModeName(), (InpMode == MODE_SIGNALS ? C_INFO : C_TXT));
   PRow("Entry", (InpEntryType == ENTRY_MARKET ? "Market" : "Pending"), C_TXT);
   PRow("Trading", (blk == "" ? "ENABLED" : "OFF"), (blk == "" ? C_UP : C_DN));
   if(InpEquityProtOn)
      PRow("Equity protector", StringFormat("-%.1f%%  (%.0f)", InpEquityProtPct, -AccountInfoDouble(ACCOUNT_BALANCE) * InpEquityProtPct / 100.0), C_WARN);
   else
      PRow("Equity protector", "OFF", C_MUTE);

   PSection("CURRENT");
   string sigState = StateText();
   PRow("Signal", sigState, (idea.state == IDEA_IDLE ? C_MUTE : (idea.dir > 0 ? InpBuyColor : InpSellColor)));
   if(idea.state != IDEA_IDLE)
     {
      PRow("Entry / SL", Px(idea.entry) + " / " + Px(idea.sl), C_TXT);
      PRow("TP1 / TP2", Px(idea.tp1) + " / " + Px(idea.tp2), C_TXT);
     }
   PRow("Last signal", gLastSignal, C_LBL);
   if(b.count > 0)
     {
      PRow("Position", StringFormat("%s x%d  %.2f lots", (b.dir > 0 ? "BUY" : "SELL"), b.count, b.lots), (b.dir > 0 ? InpBuyColor : InpSellColor));
      PRow("Avg price", Px(b.avg), C_TXT);
      PRow("Floating P/L", StringFormat("%+.2f", b.profit), (b.profit >= 0 ? C_UP : C_DN));
      if(InpMode == MODE_GRID)
        {
         PRow("Grid", StringFormat("%d/%d  gap %d", b.count, InpGridMaxTrades, GridGapPts((int)MathMax(1, b.count))), C_TXT);
         double bs = LoadBStop();
         if(InpBasketBEOn || InpBasketTrailOn) PRow("Basket stop", (bs > 0 ? Px(bs) : "not active"), (bs > 0 ? C_UP : C_MUTE));
        }
     }
   else
      PRow("Position", "none", C_MUTE);

   if(blk != "" && InpMode != MODE_SIGNALS)
     {
      PSection("WARNING");
      PRow(blk, " ", C_DN);
     }

   }

   // remove rows left over from a longer previous draw
   for(int i = gRow; i < gMaxRow; i++)
     {
      ObjectDelete(0, PPRE + "L" + IntegerToString(i));
      ObjectDelete(0, PPRE + "V" + IntegerToString(i));
     }
   gMaxRow = gRow;

   // background
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
      UpdatePanel(true);
     }
   ObjectSetInteger(0, bg, OBJPROP_ZORDER, 0);
   ChartRedraw(0);
  }


//+------------------------------------------------------------------+
//| Panel position, drag and collapse                                |
//| Drag the panel by its title area. Click the title (without       |
//| moving) to collapse / expand. Position is remembered per chart.  |
//+------------------------------------------------------------------+

string PosKey(const string k) { return "LukesEA_panel_" + k + "_" + IntegerToString(ChartID()); }

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
         UpdatePanel(true);
        }
     }
   else if(!down && gDrag)
     {
      gDrag = false;
      ChartSetInteger(0, CHART_MOUSE_SCROLL, gScrollWas);
      if(MathAbs(x - gDownX) < 4 && MathAbs(y - gDownY) < 4)
         gCollapsed = !gCollapsed;          // a click, not a drag
      PanelSave();
      UpdatePanel(true);
     }
   gPrevDown = down;
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_MOUSE_MOVE) PanelMouse(lparam, dparam, sparam);
   else if(id == CHARTEVENT_CHART_CHANGE) UpdatePanel(true);
  }

//+------------------------------------------------------------------+
//| Events                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePts);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetMarginMode();
   trade.LogLevel(LOG_LEVEL_ERRORS);

   if(_Period != PERIOD_M5)
      Print("LukesEA: built for M5, running on ", EnumToString(_Period));

   gWarm = false;
   gClosing = false;
   ResetIdea();
   ResetCounts();
   Log("START", StringFormat("mode %s, entry %s, digits %d", ModeName(),
                             (InpEntryType == ENTRY_MARKET ? "market" : "pending"), _Digits));
   gEmaFast = iMA(_Symbol, InpTrendTF, InpTrendFast, 0, MODE_EMA, PRICE_CLOSE);
   gEmaSlow = iMA(_Symbol, InpTrendTF, InpTrendSlow, 0, MODE_EMA, PRICE_CLOSE);
   ArrayResize(gSigTimes, 0);
   PanelInit();
   Comment("");
   EventSetTimer(1);   // warm up + refresh the panel even when no tick arrives
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(gDrag) ChartSetInteger(0, CHART_MOUSE_SCROLL, gScrollWas);
   ObjectsDeleteAll(0, EAPRE);
   if(gEmaFast != INVALID_HANDLE) IndicatorRelease(gEmaFast);
   if(gEmaSlow != INVALID_HANDLE) IndicatorRelease(gEmaSlow);
   Comment("");
  }

bool EnsureWarm()
  {
   if(gWarm) return true;
   gWarm = WarmUp();
   if(!gWarm) return false;
   Basket b = GetBasket();
   Log("READY", StringFormat("engine replayed history, state %s; found %d EA trades, %d pending orders",
                             StateText(), b.count, CountOrders()));
   return true;
  }

void OnTimer()
  {
   if(!gWarm) EnsureWarm();
   if(gWarm) UpdatePanel();
  }

void OnTick()
  {
   if(!EnsureWarm()) return;
   CheckBlocker();

   if(iTime(_Symbol, _Period, 1) > gLastProcessed)
      OnNewBars();

   if(InpMode != MODE_SIGNALS || GetBasket().count > 0)
      ManageTrades();

   UpdatePanel();
  }
//+------------------------------------------------------------------+
