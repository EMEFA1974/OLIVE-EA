//+------------------------------------------------------------------+
//| Mt.ZionPro EA                                                    |
//| Trades the signals of the Mt.ZionPro Ind indicator.              |
//| Signals: the Mt.ZionPro Ind arrows on the chart. Single trades.  |
//+------------------------------------------------------------------+
#property copyright "Mt.ZionPro EA"
#property link      ""
#property version   "1.10"

#include <Trade/Trade.mqh>

enum ENUM_ENTRY_TYPE
  {
   ENTRY_MARKET  = 0,  // MARKET: whole lot at market price on the signal
   ENTRY_PENDING = 1,  // PENDING: whole lot as a pending order at the indicator Entry
   ENTRY_HYBRID  = 2   // HYBRID: whole lot at market now, TP1/TP2 from its own fill
  };

enum ENUM_GRADE
  {
   GRADE_A = 0,   // A only: passes every enabled quality filter
   GRADE_B = 1,   // A + B: fails at most one filter
   GRADE_C = 2    // A + B + C: every base signal (v1.82 behaviour)
  };
#define GRADE_NONE 3

input group "=== EA ==="
input ENUM_ENTRY_TYPE InpEntryType   = ENTRY_HYBRID;    // Entry type (MARKET / PENDING / HYBRID = 1 market trade, TP from its fill)
input long            InpMagic       = 26100401;
input string          InpComment     = "Mt.ZionPro EA";
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

input group "=== Signal Source ==="
input bool   InpFollowInd    = true;              // take BUY / SELL / RE-ENTRY signals from the Mt.ZionPro Ind on this chart (own identical engine when it is not there)
input string InpIndName      = "Mt.ZionPro Ind";  // indicator short name on the chart

input group "=== Signal Quality (set the same as the indicator) ==="
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

input group "=== Signal Grade ==="
input bool       InpGradeB   = true;               // B-grade signals (fail one filter) are traded; A is always on
input bool       InpGradeC   = false;              // C-grade signals (fail two or more filters) are traded
input bool       InpReNeedA  = false;              // true = re-entries only on a fresh A-grade trigger (false = same grades as the B / C toggles)

input group "=== Single Trades ==="
input double InpSingleLot       = 0.01;    // lot of every signal trade
input bool   InpTPFromFill      = false;   // market entry: TP1 from fill price (same R) instead of indicator TP1
input bool   InpCloseOnOpposite = true;    // opposite signal closes the trade and reverses
input bool   InpTrailOn         = false;   // trailing stop
input int    InpTrailStartPts   = 300;     // start trailing after this profit (points)
input int    InpTrailDistPts    = 200;     // trail this far behind price (points)
input int    InpTrailStepPts    = 50;      // move SL in steps of (points)

input group "=== Trade Management (single trades; set the indicator the same) ==="
input bool   InpManageOn       = true;    // on = close part at TP1, SL to entry, rest runs to TP2. off = whole trade closes at TP1
input double InpPartialPct     = 50.0;    // % of the position closed at TP1 (needs lot >= 2x min lot, else the whole trade runs)
input bool   InpMoveBE         = true;    // move SL to entry after TP1
input int    InpBELockPts      = 0;       // break-even SL = entry +/- this many points (covers costs)
input bool   InpRunnerTrailOn  = false;   // after TP1 trail the runner by ATR
input double InpRunnerTrailATR = 1.5;     // runner trail distance in ATR (chart timeframe)

input group "=== Equity Protector ==="
input bool   InpEquityProtOn  = true;
input double InpEquityProtPct = 25.0;      // close all when floating loss reaches % of current balance

input group "=== Alerts ==="
input bool   InpAlertTrades  = true;       // opens, closes, TP1 partials, equity stop
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
input bool   InpLogToFile    = true;       // MQL5/Files/MtZionEA_log.csv
input color  InpBuyColor     = clrAqua;
input color  InpSellColor    = clrMagenta;
input color  InpReBuyColor   = clrGold;
input color  InpReSellColor  = clrYellow;

#define EAPRE   "MZEA_"
#define LOGFILE "MtZionEA_log.csv"

CTrade   trade;

datetime lastBuyTime   = 0;
datetime lastSellTime  = 0;
int gCntBuy = 0, gCntSell = 0, gCntTP1 = 0, gCntTP2 = 0, gCntSL = 0;

bool     gWarm          = false;   // engine replayed history
datetime gLastProcessed = 0;       // last closed bar fed to the engine
bool     gClosing       = false;   // closing everything, retry each tick until flat
string   gLastEvent     = "";
string   gLastSignal    = "none";

// signal source: the Mt.ZionPro Ind on this chart
int      gIndH          = INVALID_HANDLE;
bool     gFollow        = false;   // true = signals are the indicator's arrows
string   gLvlSync       = "-";     // indicator zone levels vs the EA's
uint     gIndTryMs      = 0;

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

//+------------------------------------------------------------------+
//| Signal engine – copied from Mt.ZionPro Ind. Keep in sync.        |
//+------------------------------------------------------------------+
void ResetCounts()
  {
   gCntBuy = gCntSell = gCntTP1 = gCntTP2 = gCntSL = 0;
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

// the indicator uses EndIdea to keep its chart zone; the EA keeps the ended idea so the
// TP1 of a still-open trade can be measured from its original SL (SignalSLR)
Idea gEnded;
bool gEndedValid = false;

void EndIdea(const string status, const datetime t)
  {
   if(idea.signalTime != 0) { gEnded = idea; gEndedValid = true; }
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
   gCntSL++;
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
      if(!idea.tp1Done) { gCntTP1++; idea.tp1Done = true; }
      gCntTP2++;
      EndIdea(" [TP2 HIT]", bar.t);
      return;
     }

   bool tp1Now = false;
   if(idea.state == IDEA_LIVE && hitTP1 && !idea.tp1Done)
     {
      gCntTP1++;
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
   return (gHTf1F != INVALID_HANDLE && gHTf1S != INVALID_HANDLE && gHTf2F != INVALID_HANDLE
           && gHTf2S != INVALID_HANDLE && gHD1 != INVALID_HANDLE && gHLoc != INVALID_HANDLE
           && gHATR != INVALID_HANDLE);
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
  }

bool HReady(const int h) { return (h != INVALID_HANDLE && BarsCalculated(h) > 0); }

// all filter data is calculated (history replay must wait for it)
bool FiltersReady()
  {
   return (HReady(gHTf1F) && HReady(gHTf1S) && HReady(gHTf2F) && HReady(gHTf2S)
           && HReady(gHD1) && HReady(gHLoc) && HReady(gHATR));
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

// A = passes every enabled filter, B = fails one, C = fails two or more
int SignalGrade(const int dir, const Candle &k, const int sh, const int trendDir, string &why)
  {
   int fails = 0;
   why = "";
   if(InpFiltOn && trendDir != dir)          { fails++; why += " trend"; }
   if(InpD1FilterOn && D1Against(dir, k.t))  { fails++; why += " D1"; }
   double atr = ATRAt(sh);
   if(InpATROn)
     {
      double rng = k.h - k.l;
      if(atr <= 0 || rng < atr * InpMinRangeATR || rng > atr * InpMaxRangeATR) { fails++; why += " range"; }
     }
   if(InpLocationOn)
     {
      double e = BufAt(gHLoc, sh);
      if(atr <= 0 || e <= 0 || MathAbs(k.c - e) > atr * InpMaxExtATR) { fails++; why += " extended"; }
     }
   if(InpStrictOn && !StrictTrigger(dir, k, sh)) { fails++; why += " candle"; }
   if(fails >= 2) return GRADE_C;
   return fails;
  }

string GradeName(const int g)
  {
   if(g == GRADE_A) return "A";
   if(g == GRADE_B) return "B";
   if(g == GRADE_C) return "C";
   return "-";
  }

// grade toggles: A always arms, B / C only when switched on
bool GradeOn(const int g)
  {
   if(g == GRADE_A) return true;
   if(g == GRADE_B) return InpGradeB;
   if(g == GRADE_C) return InpGradeC;
   return false;
  }
bool FreshOK(const int g) { return GradeOn(g); }
bool ReOK(const int g)    { return (InpReNeedA ? g == GRADE_A : GradeOn(g)); }
string GradesText(const bool re)
  {
   if(re && InpReNeedA) return "A";
   return "A" + (InpGradeB ? "B" : "") + (InpGradeC ? "C" : "");
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
   bar.spr = SpreadPriceAt(i);

   Bias d  = TFBiasAt(InpTF_D,  bar.t);
   Bias h4 = TFBiasAt(InpTF_H4, bar.t);
   Bias h1 = TFBiasAt(InpTF_H1, bar.t);
   Bias m5 = TFBiasAt(InpTF_M5, bar.t);
   int sb = (d.dir==1) + (h4.dir==1) + (h1.dir==1) + (m5.dir==1);
   int ss = (d.dir==-1) + (h4.dir==-1) + (h1.dir==-1) + (m5.dir==-1);
   int trendDir = TrendDirAt(bar.t);

   ManageIdea(bar, d, h4, trendDir);

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

   // with the EMA trend filter on, the one-candle bias vote is replaced by the grade
   bool allowB = (InpFiltOn || StructureAllows(1, d, h4, h1, sb, ss));
   bool allowS = (InpFiltOn || StructureAllows(-1, d, h4, h1, sb, ss));

   string whyB = "", whyS = "";
   int gradeB = ((trigB && allowB) ? SignalGrade(1, bar, i, trendDir, whyB) : GRADE_NONE);
   int gradeS = ((trigS && allowS) ? SignalGrade(-1, bar, i, trendDir, whyS) : GRADE_NONE);
   double buf = StopBuffer(i);

   // follow mode: the indicator's arrow on this bar decides; the levels come from the same code
   if(gFollow)
     {
      int s = IndSignalAt(i);
      if(s == 0) return 0;
      int  dir = (s > 0 ? 1 : -1);
      bool re  = (s == 2 || s == -2);
      int  g   = (dir > 0 ? gradeB : gradeS);
      if(g == GRADE_NONE) { string w; g = SignalGrade(dir, bar, i, trendDir, w); }
      int rc = (re ? ((idea.state == IDEA_SL_WAIT && idea.dir == dir) ? idea.reCount : 0) + 1 : 0);
      ArmIdea(dir, bar, re, buf, g, trendDir);
      idea.reCount = rc;
      if(dir > 0) { lastBuyTime = bar.t; gCntBuy++; }
      else        { lastSellTime = bar.t; gCntSell++; }
      return s;
     }

   if(InpReentryOn && idea.state == IDEA_SL_WAIT && idea.reCount < InpMaxReentry
      && idea.slBarAge >= InpReentryCool)
     {
      if(idea.dir > 0 && ReOK(gradeB))
        {
         int rc = idea.reCount + 1;
         ArmIdea(1, bar, true, buf, gradeB, trendDir);
         idea.reCount = rc;
         lastBuyTime = bar.t;
         gCntBuy++;
         return 2;
        }
      else if(idea.dir < 0 && ReOK(gradeS))
        {
         int rc = idea.reCount + 1;
         ArmIdea(-1, bar, true, buf, gradeS, trendDir);
         idea.reCount = rc;
         lastSellTime = bar.t;
         gCntSell++;
         return -2;
        }
     }

   bool coolB = Cooled(bar.t, lastBuyTime, InpCooldown) && Cooled(bar.t, lastSellTime, 3);
   bool coolS = Cooled(bar.t, lastSellTime, InpCooldown) && Cooled(bar.t, lastBuyTime, 3);
   bool free = (idea.state == IDEA_IDLE);

   if(free && FreshOK(gradeB) && coolB)
     {
      lastBuyTime = bar.t;
      ArmIdea(1, bar, false, buf, gradeB, trendDir);
      gCntBuy++;
      return 1;
     }
   if(free && FreshOK(gradeS) && coolS)
     {
      lastSellTime = bar.t;
      ArmIdea(-1, bar, false, buf, gradeS, trendDir);
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

string ModeName() { return "Single trades"; }

string Px(const double p) { return DoubleToString(p, _Digits); }

void Log(const string event, const string details)
  {
   gLastEvent = TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + "  " + event + "  " + details;
   Print("Mt.ZionPro EA ", event, " | ", details);
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
   string full = "Mt.ZionPro EA " + _Symbol + " | " + msg;
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
   bool   buy  = (sig > 0);   // BUY / RE-BUY
   double px   = (buy ? iLow(_Symbol, _Period, i) : iHigh(_Symbol, _Period, i));
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROW, 0, t, px);
   ObjectSetInteger(0, name, OBJPROP_TIME, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, px);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);   // small dot: under the low for buys, over the high for sells
   ObjectSetInteger(0, name, OBJPROP_COLOR, SigColor(sig));
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, buy ? ANCHOR_TOP : ANCHOR_BOTTOM);   // dot sits outside the candle
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

bool Ours()
  {
   return (PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic);
  }

bool OurOrder()
  {
   return (OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic);
  }

// the EA's open position(s) on this symbol (one trade, or two with the HYBRID split)
struct Basket
  {
   int    count;
   int    dir;         // 1 buy, -1 sell, 0 none
   double lots;
   double avg;         // volume-weighted open price
   double profit;      // profit + swap
  };

Basket GetBasket()
  {
   Basket b;
   b.count = 0; b.dir = 0; b.lots = 0; b.avg = 0; b.profit = 0;
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

//+------------------------------------------------------------------+
//| Entries                                                          |
//+------------------------------------------------------------------+
// TP1 for a market entry: indicator TP1, or from the fill price with the same R
double MarketTP1(const int dir, const double price, const double sl, const bool fromFill = false)
  {
   double tp = idea.tp1;
   double ms = MinStop();
   bool valid = (dir > 0 ? tp > price + ms : tp < price - ms);
   if(InpTPFromFill || fromFill || !valid)
     {
      double risk = MathAbs(price - sl);
      tp = (dir > 0 ? price + risk * InpRR1 : price - risk * InpRR1);
     }
   return NormalizeDouble(tp, _Digits);
  }

// TP2 for a market entry (runner target), same rules as MarketTP1
double MarketTP2(const int dir, const double price, const double sl, const bool fromFill = false)
  {
   double tp = idea.tp2;
   double ms = MinStop();
   bool valid = (dir > 0 ? tp > price + ms : tp < price - ms);
   if(InpTPFromFill || fromFill || !valid)
     {
      double risk = MathAbs(price - sl);
      tp = (dir > 0 ? price + risk * InpRR2 : price - risk * InpRR2);
     }
   return NormalizeDouble(tp, _Digits);
  }

// One order. wantPending = pending at the indicator Entry (falls back to market when price is
// already there); fromFill = TP1/TP2 measured from this order's own fill price (same R multiples).
bool OpenEntryAs(const int dir, const double lotIn, const string tag,
                 const bool wantPending, const bool fromFill)
  {
   double lot = NormLot(lotIn);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ms  = MinStop();
   double sl  = NormalizeDouble(idea.sl, _Digits);    // widened SL (placed on the order)
   double slR = NormalizeDouble(idea.slR, _Digits);   // original SL: TPs from fill use this R
   string cmt = InpComment + "|" + IntegerToString((long)idea.signalTime);

   bool pending = wantPending;
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
   double tp1 = (pending ? NormalizeDouble(idea.tp1, _Digits) : MarketTP1(dir, price, slR, fromFill));

   // trade management: the broker TP is TP2, TP1 is handled by ManageRunner (partial + BE)
   double tpOrder = tp1;
   if(InpManageOn)
      tpOrder = (pending ? NormalizeDouble(idea.tp2, _Digits) : MarketTP2(dir, price, slR, fromFill));

   bool ok;
   if(pending)
      ok = trade.OrderOpen(_Symbol, otype, lot, 0, entry, sl, tpOrder, ORDER_TIME_GTC, 0, cmt);
   else if(dir > 0)
      ok = trade.Buy(lot, _Symbol, 0, sl, tpOrder, cmt);
   else
      ok = trade.Sell(lot, _Symbol, 0, sl, tpOrder, cmt);

   uint rc = trade.ResultRetcode();
   if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED && rc != TRADE_RETCODE_DONE_PARTIAL))
     {
      Log("OPEN_FAIL", StringFormat("%s %s lot %.2f retcode %u %s", tag, (pending ? EnumToString(otype) : "market"),
                                    lot, rc, trade.ResultRetcodeDescription()));
      return false;
     }

   // TP from the real fill price (it can differ from the quote the TP was sent with)
   if(!pending && fromFill)
     {
      double fp = trade.ResultPrice();
      if(fp > 0 && MathAbs(fp - price) >= _Point / 2.0)
        {
         double ntp = (InpManageOn ? MarketTP2(dir, fp, slR, true) : MarketTP1(dir, fp, slR, true));
         ulong  ptk = trade.ResultOrder();   // the position ticket is the ticket of the order that opened it
         if(ntp != tpOrder && PositionSelectByTicket(ptk) && trade.PositionModify(ptk, sl, ntp))
            tpOrder = ntp;
        }
     }

   string what = StringFormat("%s %s lot %.2f @ %s  SL %s  TP %s", tag,
                              (pending ? EnumToString(otype) : (dir > 0 ? "BUY market" : "SELL market")),
                              lot, Px(pending ? entry : trade.ResultPrice()),
                              Px(sl), Px(tpOrder));
   Log("OPEN", what);
   if(InpAlertTrades) Notify("OPEN " + what);
   return true;
  }

// MARKET: whole lot at market. PENDING: whole lot as a pending order at the signal's Entry.
// HYBRID (default): one trade at market with the full lot, signal SL, TP from its own fill.
// Never split: one signal = one trade.
bool OpenEntry(const int dir, const double lotIn, const string tag)
  {
   if(InpEntryType == ENTRY_MARKET)  return OpenEntryAs(dir, lotIn, tag, false, false);
   if(InpEntryType == ENTRY_PENDING) return OpenEntryAs(dir, lotIn, tag, true,  false);
   return OpenEntryAs(dir, lotIn, tag + " hybrid", false, true);
  }

string EntryName()
  {
   if(InpEntryType == ENTRY_MARKET)  return "Market";
   if(InpEntryType == ENTRY_PENDING) return "Pending";
   return "Hybrid (1 market trade)";
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

   // single trades only: one signal trade at a time
   Basket b = GetBasket();
   if(b.count > 0)
     {
      if(b.dir == dir) { Log("SKIP", tag + ": trade already open in this direction"); return; }
      if(!InpCloseOnOpposite) { Log("SKIP", tag + ": opposite trade open"); return; }
      CloseAll("opposite signal " + tag);
      if(GetBasket().count > 0) { gClosing = true; Log("SKIP", tag + ": could not close opposite trade yet"); return; }
     }
   if(CountOrders() > 0) DeleteOrders("replaced by " + tag);
   OpenEntry(dir, InpSingleLot, tag);
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
//+------------------------------------------------------------------+
//| Trade management (single trades): part closed at TP1, SL to      |
//| entry, the rest runs to TP2 (optionally trailed by ATR).         |
//| "TP1 done" is kept per position in a terminal global variable.   |
//+------------------------------------------------------------------+
string PDPrefix() { return "MtZionEA_" + IntegerToString(InpMagic) + "_PD_"; }
string PDKey(const ulong tk) { return PDPrefix() + IntegerToString((long)tk); }

// drop the flags of positions that no longer exist
void CleanPDKeys()
  {
   string pre = PDPrefix();
   for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
     {
      string nm = GlobalVariableName(i);
      if(StringFind(nm, pre) != 0) continue;
      ulong tk = (ulong)StringToInteger(StringSubstr(nm, StringLen(pre)));
      if(!PositionSelectByTicket(tk)) GlobalVariableDel(nm);
     }
  }

// original (not widened) SL of the signal that opened a position, from its comment
// "<InpComment>|<signal time>"; 0 when that signal is no longer known
double SignalSLR(const string cmt)
  {
   string k = SigKey(cmt);
   if(k == "") return 0.0;
   datetime t = (datetime)StringToInteger(k);
   if(idea.signalTime == t && idea.slR > 0) return idea.slR;
   if(gEndedValid && gEnded.signalTime == t && gEnded.slR > 0) return gEnded.slR;
   return 0.0;
  }

void ManageRunner()
  {
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double ms   = MinStop();
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !Ours()) continue;
      int    d   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1);
      double op  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl  = PositionGetDouble(POSITION_SL);
      double tp  = PositionGetDouble(POSITION_TP);
      double vol = PositionGetDouble(POSITION_VOLUME);
      double px  = (d > 0 ? bid : ask);   // price the position closes at
      string key = PDKey(tk);

      // 1) TP1 not reached yet: wait for it, then close the partial
      if(!GlobalVariableCheck(key))
        {
         double risk = (d > 0 ? op - sl : sl - op);
         if(sl <= 0 || risk <= 0) { GlobalVariableSet(key, 1); continue; }   // SL already at/after entry: nothing to split
         // TP1 is measured from the original (not widened) SL, the same R the order's TP2 used
         double slR = SignalSLR(PositionGetString(POSITION_COMMENT));
         if(slR > 0 && (d > 0 ? op > slR : op < slR))
            risk = MathAbs(op - slR);
         else
            risk /= (1.0 + MathMax(0.0, InpSLWidenPct) / 100.0);
         double tp1 = op + d * risk * InpRR1;
         if(d > 0 ? px < tp1 : px > tp1) continue;

         double cv = MathFloor(vol * InpPartialPct / 100.0 / step + 1e-9) * step;
         if(InpPartialPct >= 100.0 || cv >= vol - 1e-9)
           {
            if(trade.PositionClose(tk, InpSlippagePts))
              {
               Log("TP1_CLOSE", StringFormat("ticket %I64u closed at TP1 %s", tk, Px(tp1)));
               if(InpAlertTrades) Notify("TP1 CLOSE " + Px(tp1));
               GlobalVariableDel(key);
              }
            continue;
           }
         if(cv >= vmin - 1e-9 && vol - cv >= vmin - 1e-9)
           {
            if(!trade.PositionClosePartial(tk, NormLot(cv), InpSlippagePts))
              {
               Log("PARTIAL_FAIL", StringFormat("ticket %I64u %.2f lots retcode %u %s", tk, cv,
                                                trade.ResultRetcode(), trade.ResultRetcodeDescription()));
               continue;   // retry next tick
              }
            string what = StringFormat("ticket %I64u closed %.2f of %.2f lots at TP1 %s, rest runs to %s",
                                       tk, cv, vol, Px(tp1), (tp > 0 ? Px(tp) : "no TP"));
            Log("PARTIAL", what);
            if(InpAlertTrades) Notify("PARTIAL " + what);
           }
         else if(InpPartialPct > 0)
            Log("PARTIAL_SKIP", StringFormat("ticket %I64u: %.2f lots cannot be split (min lot %.2f), whole trade runs", tk, vol, vmin));
         GlobalVariableSet(key, 1);
         if(!PositionSelectByTicket(tk)) continue;
         sl = PositionGetDouble(POSITION_SL);
         tp = PositionGetDouble(POSITION_TP);
        }

      // 2) after TP1: break-even (retried until the broker accepts it), then optional ATR trail
      double nsl = sl;
      if(InpMoveBE)
        {
         double be = NormalizeDouble(op + d * InpBELockPts * Pt(), _Digits);
         if(nsl <= 0 || (d > 0 ? be > nsl : be < nsl)) nsl = be;
        }
      if(InpRunnerTrailOn)
        {
         double atr = ATRAt(1);
         if(atr > 0)
           {
            double tr = NormalizeDouble(px - d * atr * InpRunnerTrailATR, _Digits);
            double stp = atr * 0.1;   // move in steps of 0.1 ATR (no modify spam)
            if(nsl <= 0 || (d > 0 ? tr >= nsl + stp : tr <= nsl - stp)) nsl = tr;
           }
        }
      if(nsl <= 0 || nsl == sl) continue;
      if(sl > 0 && (d > 0 ? nsl <= sl : nsl >= sl)) continue;   // only ever tighten
      if(d > 0 ? nsl > bid - ms : nsl < ask + ms) continue;     // too close to price for the broker
      if(trade.PositionModify(tk, nsl, tp))
         Log("RUNNER_SL", StringFormat("ticket %I64u SL %s -> %s", tk, (sl > 0 ? Px(sl) : "none"), Px(nsl)));
     }
  }

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

void ManageTrades()
  {
   if(gClosing)
     {
      CloseAll("closing all");
      if(GetBasket().count == 0) { gClosing = false; Log("FLAT", "all EA trades closed"); }
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

   if(InpManageOn) ManageRunner();
   if(InpTrailOn) Trail();
  }

//+------------------------------------------------------------------+
//| Signals from the Mt.ZionPro Ind on the chart                     |
//| The EA reads the indicator's own arrow buffers (Buy, Sell,       |
//| ReBuy, ReSell), so it trades exactly the arrows on the chart.    |
//| Entry / SL / TP come from the same code as the indicator and are |
//| checked against the indicator's zone lines.                      |
//+------------------------------------------------------------------+

void IndRelease()
  {
   if(gIndH != INVALID_HANDLE) IndicatorRelease(gIndH);
   gIndH = INVALID_HANDLE;
   gFollow = false;
  }

// look for the indicator on any window of this chart
bool IndFind()
  {
   if(!InpFollowInd) return false;
   int wins = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
   for(int w = 0; w < wins; w++)
     {
      int h = ChartIndicatorGet(0, w, InpIndName);
      if(h != INVALID_HANDLE) { gIndH = h; gFollow = true; return true; }
     }
   return false;
  }

// the indicator has calculated every bar of the chart (its arrows for the closed bars are final)
bool IndReady()
  {
   if(!gFollow) return true;
   int bc = BarsCalculated(gIndH);
   if(bc < 0)
     {
      IndRelease();
      Log("IND_LOST", InpIndName + " removed from the chart: using the EA's own (identical) signal engine");
      return true;
     }
   return (bc >= Bars(_Symbol, _Period));
  }

// arrow of the indicator on bar sh: 1 BUY, -1 SELL, 2 RE-BUY, -2 RE-SELL, 0 none
int IndSignalAt(const int sh)
  {
   int code[4] = {1, -1, 2, -2};
   for(int b = 0; b < 4; b++)
     {
      double v[1];
      if(CopyBuffer(gIndH, b, sh, 1, v) != 1) continue;
      if(v[0] != EMPTY_VALUE && v[0] != 0.0) return code[b];
     }
   return 0;
  }

// price of one of the indicator's zone lines, when it belongs to signal time t
bool IndLine(const string nm, const datetime t, double &price)
  {
   string name = "CSZN_" + nm;
   if(ObjectFind(0, name) < 0) return false;
   if((datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0) != t) return false;
   price = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
   return (price > 0);
  }

// compare the current signal's levels with the indicator's zone; on a difference the
// indicator's levels are used (EA inputs differ from the indicator's)
void IndCheckLevels()
  {
   if(!gFollow || idea.signalTime == 0 || (idea.state != IDEA_PENDING && idea.state != IDEA_LIVE) || idea.tp1Done) return;
   double en, sl, t1, t2;
   if(!IndLine("LEN0", idea.signalTime, en) || !IndLine("LSL0", idea.signalTime, sl) ||
      !IndLine("LT10", idea.signalTime, t1) || !IndLine("LT20", idea.signalTime, t2))
     {
      gLvlSync = "zone not shown";
      return;
     }
   double tol = _Point / 2.0;
   if(MathAbs(en - idea.entry) <= tol && MathAbs(sl - idea.sl) <= tol &&
      MathAbs(t1 - idea.tp1) <= tol && MathAbs(t2 - idea.tp2) <= tol)
     {
      gLvlSync = "match";
      return;
     }
   Log("LEVELS_MISMATCH", StringFormat("EA %s/%s/%s/%s vs Ind %s/%s/%s/%s (entry/SL/TP1/TP2): using the indicator's. Set the EA inputs the same as the indicator",
                                       Px(idea.entry), Px(idea.sl), Px(idea.tp1), Px(idea.tp2), Px(en), Px(sl), Px(t1), Px(t2)));
   idea.entry = en; idea.sl = sl; idea.tp1 = t1; idea.tp2 = t2;
   double r = MathAbs(t1 - en) / (InpRR1 > 0 ? InpRR1 : 1.0);
   idea.slR = (idea.dir > 0 ? en - r : en + r);
   gLvlSync = "MISMATCH: Ind used";
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
   if(!FiltersReady())
      return false;   // EMA / ATR filter data still calculating
   if(!IndReady())
      return false;   // indicator on the chart still calculating

   ResetIdea();
   ResetCounts();
   gEndedValid = false;
   lastBuyTime = lastSellTime = 0;
   int start = (int)MathMin(total - 5, 800);
   if(start < 1) start = 1;
   for(int i = start; i >= 1; i--)
     {
      int s = ProcessBar(i);
      if(s != 0) { DrawSignal(i, s); AddSignalTime(iTime(_Symbol, _Period, i)); gLastSignal = SigName(s) + " " + GradeName(idea.grade) + " " + TimeToString(iTime(_Symbol, _Period, i), TIME_DATE|TIME_MINUTES); }
     }
   gLastProcessed = iTime(_Symbol, _Period, 1);
   IndCheckLevels();
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

   if(sig != 0) IndCheckLevels();
   SyncOrders();
   if(sig == 0) return;

   gLastSignal = SigName(sig) + " " + GradeName(idea.grade) + " " + TimeToString(gLastProcessed, TIME_DATE|TIME_MINUTES);
   string lv = StringFormat("%s %s  Entry %s  SL %s  TP1 %s  TP2 %s", SigName(sig), GradeName(idea.grade),
                            Px(idea.entry), Px(idea.sl), Px(idea.tp1), Px(idea.tp2));
   Log("SIGNAL", lv);
   if(InpAlertSignals) Notify("SIGNAL " + lv);
   string blk = TradeBlocker();
   if(blk != "")
     {
      Log("SKIP", SigName(sig) + ": " + blk);
      if(InpAlertTrades) Notify("Signal NOT traded: " + blk);
      return;
     }
   if(!gClosing) ActOnSignal(sig);
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
#define PPRE    "MZEA_P_"
int  gPX = 0, gPY = 0, gPanelH = 0;
int  gOtherObjs = -1;

// objects on the chart that are not part of the indicator / EA panels
int OtherObjCount()
  {
   int n = 0, total = ObjectsTotal(0);
   for(int i = 0; i < total; i++)
     {
      string nm = ObjectName(0, i);
      if(StringFind(nm, "CSMTF_P_") == 0 || StringFind(nm, PPRE) == 0) continue;
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

// signal id of an EA entry comment "<InpComment>|<signal time>"; "" when unknown
string SigKey(const string cmt)
  {
   int p = StringFind(cmt, "|");
   if(p < 0) return "";
   string rest = StringSubstr(cmt, p + 1);
   int q = StringFind(rest, "|");
   if(q >= 0) rest = StringSubstr(rest, 0, q);
   if(StringToInteger(rest) <= 0) return "";
   return rest;
  }

// Closed EA trades today. Deals that close within 5 s of each other in the
// same direction are one trade.
// curEntered = the current signal already has an entry today.
void TodayStats(int &trades, int &wins, int &losses, double &pl,
                int &entries, bool &curEntered)
  {
   trades = wins = losses = 0; pl = 0;
   entries = 0;
   curEntered = false;
   if(!HistorySelect(DayStart(), TimeCurrent() + 60)) return;

   string   seen[];                     // signal ids already counted as an entry
   long     posId[];  string posKey[];  // position -> signal id
   datetime ot[];     long otyp[];  double opl[];  string okey[];
   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++)
     {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0) continue;
      if(HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(tk, DEAL_MAGIC) != InpMagic) continue;
      long entry = HistoryDealGetInteger(tk, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_IN)
        {
         // trade(s) of a signal: comment "<InpComment>|<signal time>"
         string cmt = HistoryDealGetString(tk, DEAL_COMMENT);
         string key = SigKey(cmt);
         if(key == "") entries++;
         else
           {
            bool dup = false;
            for(int k = ArraySize(seen) - 1; k >= 0 && !dup; k--) if(seen[k] == key) dup = true;
            if(!dup)
              {
               int m = ArraySize(seen);
               ArrayResize(seen, m + 1);
               seen[m] = key;
               entries++;
              }
           }
         int m2 = ArraySize(posId);
         ArrayResize(posId, m2 + 1);
         ArrayResize(posKey, m2 + 1);
         posId[m2]  = HistoryDealGetInteger(tk, DEAL_POSITION_ID);
         posKey[m2] = key;
         continue;
        }
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) continue;
      long pid = HistoryDealGetInteger(tk, DEAL_POSITION_ID);
      string key = "";
      for(int k = ArraySize(posId) - 1; k >= 0; k--) if(posId[k] == pid) { key = posKey[k]; break; }
      int c = ArraySize(ot);
      ArrayResize(ot, c + 1); ArrayResize(otyp, c + 1); ArrayResize(opl, c + 1); ArrayResize(okey, c + 1);
      ot[c]   = (datetime)HistoryDealGetInteger(tk, DEAL_TIME);
      otyp[c] = HistoryDealGetInteger(tk, DEAL_TYPE);
      opl[c]  = HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_SWAP)
                + HistoryDealGetDouble(tk, DEAL_COMMISSION);
      okey[c] = key;
      pl += opl[c];
     }

   string cur = IntegerToString((long)idea.signalTime);
   for(int k = ArraySize(seen) - 1; k >= 0; k--) if(seen[k] == cur) { curEntered = true; break; }

   // group the closing deals into trades
   int no = ArraySize(ot);
   int cid[];
   ArrayResize(cid, no);
   for(int i = 0; i < no; i++)
      cid[i] = ((i > 0 && otyp[i] == otyp[i - 1] && ot[i] - ot[i - 1] <= 5) ? cid[i - 1] : i);
   for(int i = 0; i < no; i++)
     {
      if(okey[i] == "") continue;
      for(int j = 0; j < i; j++)
        {
         if(okey[j] != okey[i] || cid[j] == cid[i]) continue;
         int from = cid[i], to = cid[j];
         for(int k = 0; k < no; k++) if(cid[k] == from) cid[k] = to;
         break;
        }
     }
   for(int i = 0; i < no; i++)
     {
      bool first = true;
      for(int k = 0; k < i && first; k++) if(cid[k] == cid[i]) first = false;
      if(!first) continue;
      double gp = 0;
      for(int k = i; k < no; k++) if(cid[k] == cid[i]) gp += opl[k];
      trades++;
      if(gp >= 0) wins++; else losses++;
     }
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
   if(blk != "")               { st = "NOT TRADING";  sc = C_DN; }
   else if(b.count > 0)             { st = "IN TRADE";     sc = C_UP; }
   else                             { st = "WAITING";      sc = C_WARN; }
   PText(PPRE + "T1", gPX + 10, gPY + 6, "Mt.ZionPro EA", C_TXT, InpPanelFont, ANCHOR_LEFT_UPPER, InpPanelFontHead);
   PText(PPRE + "T2", gPX + InpPanelWidth - 10, gPY + 6, "v1.10  " + ShortToString((ushort)(gCollapsed ? 0x25B6 : 0x25BC)), C_MUTE, InpPanelFont - 1, ANCHOR_RIGHT_UPPER, InpPanelFontName);
   PText(PPRE + "T3", gPX + 10, gPY + 27, _Symbol + "  " + StringSubstr(EnumToString(_Period), 7), C_LBL, InpPanelFont, ANCHOR_LEFT_UPPER, InpPanelFontName);
   PText(PPRE + "T4", gPX + InpPanelWidth - 10, gPY + 27, ShortToString((ushort)0x25CF) + " " + st, sc, InpPanelFont, ANCHOR_RIGHT_UPPER, InpPanelFontHead);

   if(!gCollapsed)
   {

   int tr, w, l; double pl;
   int ent;
   bool curIn;
   TodayStats(tr, w, l, pl, ent, curIn);
   int sigT = SignalsToday();
   int waiting = ((idea.state == IDEA_PENDING && CountOrders() > 0 && !curIn) ? 1 : 0);
   int notTraded = (int)MathMax(0, sigT - ent - waiting);
   PSection("TODAY");
   PRow("Signals", IntegerToString(sigT), C_INFO);
   PRow("  traded", IntegerToString(ent), C_TXT);
   if(waiting > 0) PRow("  pending order", IntegerToString(waiting), C_WARN);
   PRow("  not traded", IntegerToString(notTraded), (notTraded > 0 ? C_MUTE : C_TXT));
   PRow("Trades closed", IntegerToString(tr), C_TXT);
   PRow("TP (wins)", IntegerToString(w), C_UP);
   PRow("SL (losses)", IntegerToString(l), C_DN);
   PRow("Win rate", (tr > 0 ? StringFormat("%.0f%%", 100.0 * w / tr) : "-"),
        (tr == 0 ? C_MUTE : (w * 2 >= tr ? C_UP : C_DN)));
   PRow("Profit / loss", StringFormat("%+.2f %s", pl, AccountInfoString(ACCOUNT_CURRENCY)), (pl > 0 ? C_UP : (pl < 0 ? C_DN : C_TXT)));

   PSection("EA");
   PRow("Mode", ModeName(), C_TXT);
   PRow("Signals from", (gFollow ? "Mt.ZionPro Ind on chart" : "own engine (Ind not found)"), (gFollow ? C_UP : C_WARN));
   if(gFollow) PRow("Ind levels", gLvlSync, (StringFind(gLvlSync, "MISMATCH") >= 0 ? C_DN : C_TXT));
   PRow("Entry", EntryName(), C_TXT);
   PRow("Grades / re-entry", GradesText(false) + " / " + GradesText(true), C_INFO);
   PRow("SL widen", StringFormat("+%.0f%%  (TP R unchanged)", MathMax(0.0, InpSLWidenPct)), (InpSLWidenPct > 0 ? C_WARN : C_MUTE));
   PRow("Trade mgmt", (InpManageOn ? StringFormat("%.0f%% @TP1%s, rest TP2%s", InpPartialPct, (InpMoveBE ? " + BE" : ""),
                                                     (InpRunnerTrailOn ? " / trail" : "")) : "OFF (all at TP1)"),
           (InpManageOn ? C_UP : C_MUTE));
   PRow("Trading", (blk == "" ? "ENABLED" : "OFF"), (blk == "" ? C_UP : C_DN));
   if(InpEquityProtOn)
      PRow("Equity protector", StringFormat("-%.1f%%  (%.0f)", InpEquityProtPct, -AccountInfoDouble(ACCOUNT_BALANCE) * InpEquityProtPct / 100.0), C_WARN);
   else
      PRow("Equity protector", "OFF", C_MUTE);

   PSection("CURRENT");
   string sigState = StateText();
   if(idea.state != IDEA_IDLE) sigState = sigState + "  " + GradeName(idea.grade);
   PRow("Signal", sigState, (idea.state == IDEA_IDLE ? C_MUTE : (idea.dir > 0 ? InpBuyColor : InpSellColor)));
   PRow("Last signal", gLastSignal, C_LBL);
   if(b.count > 0)
     {
      PRow("Position", StringFormat("%s x%d  %.2f lots", (b.dir > 0 ? "BUY" : "SELL"), b.count, b.lots), (b.dir > 0 ? InpBuyColor : InpSellColor));
      PRow("Avg price", Px(b.avg), C_TXT);
      PRow("Floating P/L", StringFormat("%+.2f", b.profit), (b.profit >= 0 ? C_UP : C_DN));
     }
   else
      PRow("Position", "none", C_MUTE);

   if(blk != "")
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

string PosKey(const string k) { return "MtZionEA_panel_" + k + "_" + IntegerToString(ChartID()); }

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
      Print("Mt.ZionPro EA: built for M5, running on ", EnumToString(_Period));

   gWarm = false;
   gClosing = false;
   ResetIdea();
   ResetCounts();
   Log("START", StringFormat("mode %s, entry %s, digits %d", ModeName(),
                             EntryName(), _Digits));
   if(!FiltersInit())
     {
      Print("Mt.ZionPro EA: could not create the filter indicators (EMA / ATR)");
      return(INIT_FAILED);
     }
   if(IndFind()) Log("SIGNALS", "following " + InpIndName + " on this chart");
   else if(InpFollowInd) Log("SIGNALS", InpIndName + " not on this chart: using the EA's own (identical) signal engine");
   CleanPDKeys();
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
   IndRelease();
   FiltersRelease();
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
   // indicator added to the chart later: replay history from its arrows
   if(InpFollowInd && !gFollow && GetTickCount() - gIndTryMs > 5000)
     {
      gIndTryMs = GetTickCount();
      if(IndFind()) { Log("SIGNALS", "found " + InpIndName + ": following its signals"); gWarm = false; }
     }
   if(!gWarm) EnsureWarm();
   // the indicator may finish the new bar after the tick: catch up without waiting for the next tick
   if(gWarm && iTime(_Symbol, _Period, 1) > gLastProcessed && IndReady()) OnNewBars();
   if(gWarm) UpdatePanel();
  }

void OnTick()
  {
   if(!EnsureWarm()) return;
   CheckBlocker();

   if(iTime(_Symbol, _Period, 1) > gLastProcessed && IndReady())
      OnNewBars();

   ManageTrades();

   UpdatePanel();
  }
//+------------------------------------------------------------------+
