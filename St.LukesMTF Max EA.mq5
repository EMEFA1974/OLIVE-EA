//+------------------------------------------------------------------+
//| St.LukesMTF Max EA                                                   |
//| Trades the signals of the St.LukesMTF Max Ind indicator.             |
//| Rules: see EA_SPEC.md                                            |
//+------------------------------------------------------------------+
#property copyright "St.LukesMTF Max EA"
#property link      ""
#property version   "1.22"

#include <Trade/Trade.mqh>

enum ENUM_EA_MODE
  {
   MODE_SIGNALS = 0,   // Signals only (no trading)
   MODE_SINGLE  = 1,   // Single trades only
   MODE_GRID    = 2    // Full grid
  };

enum ENUM_ENTRY_TYPE
  {
   ENTRY_MARKET  = 0,  // MARKET - whole lot at market price on the signal
   ENTRY_PENDING = 1,  // PENDING - whole lot as pending order at the indicator Entry
   ENTRY_HYBRID  = 2   // HYBRID - part at market now + rest as pending at Entry
  };

enum ENUM_HYBRID_FALLBACK
  {
   HYB_ALL_PENDING = 0,  // all as PENDING order at the Entry level
   HYB_ALL_MARKET  = 1   // all at MARKET price
  };

enum ENUM_BASKET_TP
  {
   BASKET_MONEY    = 0,  // Money profit of the basket ($)
   BASKET_DISTANCE = 1   // Price distance beyond basket average (points)
  };

input group "=== EA Mode ==="
input ENUM_EA_MODE    InpMode        = MODE_SINGLE;
input ENUM_ENTRY_TYPE InpEntryType   = ENTRY_HYBRID;    // Entry type: MARKET / PENDING / HYBRID
input int             InpHybridMarketPct = 50;          // HYBRID: % of the lot opened at market
input ENUM_HYBRID_FALLBACK InpHybridFallback = HYB_ALL_PENDING; // HYBRID: lot too small to split -> put it all in as
input bool            InpHybridSplitSingle = false;     // HYBRID in Single trades: split into market + pending (false = ONE market trade)
input long            InpMagic       = 26092501;
input string          InpComment     = "LukesEA";
input int             InpSlippagePts = 30;       // max slippage (points)

enum ENUM_SLBUF_MODE
  {
   SLBUF_FIXED = 0,   // Fixed points
   SLBUF_ATR   = 1    // ATR based (never below the fixed points)
  };

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
input int    InpSLBufferPts    = 20;    // minimum SL buffer (points)
input ENUM_SLBUF_MODE InpSLBufMode = SLBUF_ATR;
input double InpSLBufATRMult   = 0.15;  // ATR mode: buffer = max(min points, ATR x this)
input int    InpSLBufATRPeriod = 14;    // ATR period (signal timeframe)
input bool   InpSLBufAddSpread = true;  // add the signal bar's spread to the buffer
input bool   InpSpreadAware    = true;  // check sell SL/TP and buy entries at the ASK (bar price + bar spread), like the broker
input double InpSLExpandPct    = 100.0;   // widen the SL distance from the entry by this % (0 = signal SL). TP unchanged. Keep same in Ind + EA
input double InpRR1            = 1.0;   // TP1 R-multiple
input double InpRR2            = 2.0;   // TP2 R-multiple
input int    InpMaxReentry     = 2;
input int    InpReentryWindow  = 24;
input int    InpReentryCool    = 3;

input group "=== Pullback Add (after TP1) ==="
input bool   InpAddOn       = true;    // after TP1: limit order back in the signal direction in the pullback (TP = TP2, SL = SL). Keep same in Ind + EA
input double InpAddDepth    = 0.50;    // add level: 0 = Entry, 0.5 = halfway, 1.0 = signal SL (previous high/low); capped before the widened SL
input int    InpAddExpire   = 24;      // cancel the add after N closed bars without a fill
input double InpAddLot      = 0.01;    // EA: lot of the pullback add trade (0 = do not trade the add)

input group "=== Single Trades ==="
input double InpSingleLot       = 0.01;    // lot of every signal trade, TP1 (also the first trade of a grid basket)
input double InpRunnerLot       = 0.01;    // Single trades: extra trade per signal with TP = TP2 (0 = off)
input bool   InpRunnerBEOn      = false;   // runner + pullback add: move SL to break-even ...
input int    InpRunnerBEPct     = 75;      // ... once price has covered this % of the way from the open to the TP
input int    InpRunnerBELockPts = 10;      // break-even SL = open price + this (points)
input bool   InpTPFromFill      = false;   // market entry: TP1 from fill price (same R) instead of indicator TP1
input bool   InpCloseOnOpposite = true;    // opposite signal closes the trade and reverses
input bool   InpTrailOn         = false;   // trailing stop
input int    InpTrailStartPts   = 300;     // start trailing after this profit (points)
input int    InpTrailDistPts    = 200;     // trail this far behind price (points)
input int    InpTrailStepPts    = 50;      // move SL in steps of (points)

input group "=== Grid ==="
input double         InpGridStartLot   = 0.01;          // lot of the FIRST extra grid trade (then x multiplier per level)
input int            InpGridDistPts    = 500;           // add a trade every N points against the basket
input double         InpGridMultiplier = 1.50;          // lot multiplier per grid level
input bool           InpGridWidenOn    = false;         // widen the gap at each new grid level
input double         InpGridGapMult    = 1.20;          // gap multiplier per level (1.20 = each gap 20% wider)
input int            InpGridMaxGapPts  = 0;             // largest allowed gap in points (0 = no cap)
input int            InpGridMaxTrades  = 5;             // max running trades (stop adding at this count)
input bool           InpBasketTPOn     = true;          // off = close all grid trades at single-trade TP1
input ENUM_BASKET_TP InpBasketTPType   = BASKET_DISTANCE;
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
input bool   InpGridBrokerLevels    = true;   // put the TP on every grid trade (visible on PC + mobile, works if MT5 is off). Grid trades never get an SL.

input group "=== Equity Protector ==="
input bool   InpEquityProtOn  = true;
input double InpEquityProtPct = 25.0;      // close all when floating loss reaches % of current balance

input group "=== Alerts ==="
input bool   InpAlertTrades  = true;       // opens, closes, basket TP, equity stop
input bool   InpAlertSignals = false;      // indicator already alerts signals
input bool   InpAlertPopup   = true;
input bool   InpAlertSound   = true;
input bool   InpAlertPush    = true;
input string InpSoundFile    = "alert.wav";

input group "=== Visuals / Log ==="
input bool   InpDrawSignals  = true;       // dot on every EA signal candle (compare with indicator arrows)
input int    InpDotGapPts    = 100;        // dot distance from the candle: below the low (buy) / above the high (sell), points
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
int      gNoMarginLevel = 0;       // grid level already alerted for missing margin
string   gLastEvent     = "";
string   gLastSignal    = "none";
datetime gEnteredSig    = 0;       // last signal the EA entered (single trades)
datetime gAddSent       = 0;       // signal whose pullback add was already sent

enum IdeaState { IDEA_IDLE = 0, IDEA_PENDING, IDEA_LIVE, IDEA_SL_WAIT };

struct Idea
  {
   IdeaState state;
   int       dir;
   double    entry, sl, sl0, tp1, tp2;   // sl = widened SL, sl0 = signal SL
   datetime  signalTime, slTime, fillTime;
   int       reCount, slBarAge, pendAge;
   bool      tp1Done;
   bool      re;
   int       addState, addAge;   // pullback add: ADD_NONE / ADD_ARMED / ADD_FILLED / ADD_DONE
   double    addPx;              // pullback add price
   datetime  addTime, tp1Time;   // add fill bar / TP1 bar
   double    pbMax;              // deepest pullback after TP1 (0 = Entry, 1 = signal SL)
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
//| Signal engine – copied from St.LukesMTF Max Ind. Keep in sync.       |
//+------------------------------------------------------------------+
void ResetCounts()
  {
   ResetPbStats();
   gCntBuy = gCntSell = gCntTP1 = gCntTP2 = gCntSL = 0;
  }

void ResetIdea()
  {
   idea.state = IDEA_IDLE;
   idea.dir = 0;
   idea.entry = idea.sl = idea.sl0 = idea.tp1 = idea.tp2 = 0;
   idea.signalTime = idea.slTime = idea.fillTime = 0;
   idea.reCount = idea.slBarAge = idea.pendAge = 0;
   idea.tp1Done = false;
   idea.re = false;
   idea.addState = idea.addAge = 0;
   idea.addPx = idea.pbMax = 0;
   idea.addTime = idea.tp1Time = 0;
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

// average true range of the N bars ending at bar time t (signal timeframe)
double ATRAt(const datetime t)
  {
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int n = CopyRates(_Symbol, _Period, t, InpSLBufATRPeriod + 1, r);
   if(n < 2) return 0.0;
   double sum = 0;
   for(int i = 1; i < n; i++)
      sum += MathMax(r[i].high, r[i - 1].close) - MathMin(r[i].low, r[i - 1].close);
   return sum / (n - 1);
  }

// SL buffer for a signal on bar time t: fixed points, or ATR-scaled, plus spread
double PointBuf(const datetime t)
  {
   double buf = (double)InpSLBufferPts * Pt();
   if(InpSLBufMode == SLBUF_ATR)
      buf = MathMax(buf, ATRAt(t) * InpSLBufATRMult);
   if(InpSLBufAddSpread)
     {
      int sp[];
      if(CopySpread(_Symbol, _Period, t, 1, sp) == 1 && sp[0] > 0)
         buf += sp[0] * _Point;
     }
   return buf;
  }

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
   idea.sl0   = sl;
   double risk = (dir > 0 ? (entry - sl) : (sl - entry));
   if(risk <= 0.0) risk = Pt() * 10;
   // SL widened from the entry by InpSLExpandPct % (0 = signal SL). TPs keep the signal risk.
   idea.sl    = (InpSLExpandPct > 0 ? NormalizeDouble(entry - dir * risk * (1.0 + InpSLExpandPct / 100.0), _Digits) : sl);
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
      sl = bar.l - PointBuf(bar.t);
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
      sl = bar.h + PointBuf(bar.t);
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
   idea.addState = idea.addAge = 0;
   idea.addPx = idea.pbMax = 0;
   idea.addTime = idea.tp1Time = 0;
   ApplyLevels(dir, entry, sl);
   idea.state = (InpPendingOn ? IDEA_PENDING : IDEA_LIVE);
   if(idea.state == IDEA_LIVE)
      idea.fillTime = bar.t;
  }

bool TouchedLevel(const Candle &bar, const double price)
  {
   return (bar.valid && bar.l <= price && bar.h >= price);
  }

// A running signal is cancelled only when a timeframe the signal REQUIRED turns against it.
// (Before: D1 against cancelled every signal, although D1 is not required by default,
// so counter-D1 signals died one bar after they appeared.)
bool BiasTurnedAgainst(const int dir, const Bias &d, const Bias &h4)
  {
   return ((InpRequireD && d.dir == -dir) || (InpRequireH4 && h4.dir == -dir));
  }

// historical spread of the bar at time t, as a price distance
double BarSpreadPx(const datetime t)
  {
   int sp[];
   if(CopySpread(_Symbol, _Period, t, 1, sp) == 1 && sp[0] > 0) return sp[0] * _Point;
   return 0.0;
  }

//+------------------------------------------------------------------+
//| Pullback add after TP1 + pullback statistics                     |
//| After TP1 a limit order is armed back in the signal direction in |
//| the pullback zone: TP = TP2, SL = the signal's (widened) SL.      |
//| Depth unit R = signal risk: 0 = Entry, 1 = signal SL.             |
//+------------------------------------------------------------------+
#define ADD_NONE   0
#define ADD_ARMED  1
#define ADD_FILLED 2
#define ADD_DONE   3

int    gPbTP2 = 0, gPbSL = 0;                    // after TP1: went on to TP2 / hit the SL
double gPbSum = 0, gPbMax = 0;                   // pullback depth of the TP2 winners (R)
int    gPbE = 0, gPbHalf = 0, gPbFull = 0;       // TP2 winners whose pullback reached Entry / 0.5R / 1R
int    gAddWin = 0, gAddLoss = 0;
double gAddR = 0;                                // net result of the add trades in R

void ResetPbStats()
  {
   gPbTP2 = gPbSL = gPbE = gPbHalf = gPbFull = gAddWin = gAddLoss = 0;
   gPbSum = gPbMax = gAddR = 0;
  }

double SignalRisk()
  {
   double r = MathAbs(idea.entry - idea.sl0);
   return (r > 0 ? r : Pt() * 10);
  }

double AddPrice()
  {
   double px  = idea.entry - idea.dir * InpAddDepth * SignalRisk();
   double gap = MathMax((double)InpMinSLGapPts * Pt(), 5.0 * Pt());
   if(idea.dir > 0 && px < idea.sl + gap) px = idea.sl + gap;
   if(idea.dir < 0 && px > idea.sl - gap) px = idea.sl - gap;
   return NormalizeDouble(px, _Digits);
  }

// TP1 reached on bar t: start measuring the pullback, arm the add
void StartAfterTP1(const datetime t, const bool arm)
  {
   idea.tp1Time = t;
   idea.pbMax   = -InpRR1;       // TP1 itself: no pullback yet
   if(!arm || !InpAddOn) return;
   idea.addPx    = AddPrice();
   idea.addState = ADD_ARMED;
   idea.addAge   = 0;
  }

// the idea finishes after TP1: at TP2 (win) or at the SL
void CloseAfterTP1(const bool win, const bool addFillBar, const bool beyondTP2)
  {
   if(!idea.tp1Done) return;
   if(win)
     {
      gPbTP2++;
      gPbSum += idea.pbMax;
      if(gPbTP2 == 1 || idea.pbMax > gPbMax) gPbMax = idea.pbMax;
      if(idea.pbMax >= 0.0) gPbE++;
      if(idea.pbMax >= 0.5) gPbHalf++;
      if(idea.pbMax >= 1.0) gPbFull++;
     }
   else
      gPbSL++;

   if(idea.addState == ADD_FILLED)
     {
      // add filled on the TP2 bar: order unknown, counts only if the bar closed beyond TP2
      if(win && (!addFillBar || beyondTP2))
        {
         gAddWin++;
         double risk = MathAbs(idea.addPx - idea.sl);
         if(risk > 0) gAddR += MathAbs(idea.tp2 - idea.addPx) / risk;
        }
      else if(!win)
        {
         gAddLoss++;
         gAddR -= 1.0;
        }
     }
   idea.addState = ADD_DONE;
  }

void OnAddFilled() { }

void ManageIdea(const Candle &bar, const Bias &d, const Bias &h4)
  {
   if(idea.state == IDEA_IDLE) return;

   // Chart bars are BID prices. The broker fills buy entries and closes sells at the ASK,
   // so sell SL/TP and buy entries are checked against bid + the bar's spread.
   double sp  = (InpSpreadAware ? BarSpreadPx(bar.t) : 0.0);
   double aH  = bar.h + sp, aL = bar.l + sp, aC = bar.c + sp;

   bool fillBar = false;
   if(idea.state == IDEA_PENDING)
     {
      idea.pendAge++;
      if(idea.pendAge > InpPendingExpire) { EndIdea(" [EXPIRED]", bar.t); return; }
      if(BiasTurnedAgainst(idea.dir, d, h4)) { EndIdea(" [CANCELLED]", bar.t); return; }

      bool touched = (idea.dir > 0 ? (aL <= idea.entry && aH >= idea.entry)      // buy fills at the ask
                                   : TouchedLevel(bar, idea.entry));             // sell fills at the bid
      if(!touched) return;
      idea.state = IDEA_LIVE;
      idea.fillTime = bar.t;
      idea.slBarAge = 0;
      fillBar = true;      // fall through: SL / TP are checked on the fill bar too
     }

   if(!InpReentryOn && idea.state == IDEA_SL_WAIT)
     {
      EndIdea(" [SL HIT]", idea.slTime);
      return;
     }

   idea.slBarAge++;

   // buys close at the bid (chart prices), sells close at the ask (bid + spread)
   bool hitTP2 = (idea.dir > 0 ? (bar.h >= idea.tp2) : (aL <= idea.tp2));
   bool hitTP1 = (idea.dir > 0 ? (bar.h >= idea.tp1) : (aL <= idea.tp1));
   bool hitSL  = (idea.dir > 0 ? (bar.l <= idea.sl)  : (aH >= idea.sl));

   // On the fill bar the order of events is unknown (price may have reached a
   // target before the entry filled). Conservative: a target only counts if the
   // bar CLOSED beyond it; the SL always counts.
   if(fillBar)
     {
      if(hitTP1 && !(idea.dir > 0 ? bar.c >= idea.tp1 : aC <= idea.tp1)) hitTP1 = false;
      if(hitTP2 && !(idea.dir > 0 ? bar.c >= idea.tp2 : aC <= idea.tp2)) hitTP2 = false;
     }

   // after TP1: track the pullback and the add order (armed on the bar after TP1).
   // buy limit fills at the ask, sell limit at the bid
   bool addFillBar = false;
   bool beyondTP2  = (idea.dir > 0 ? bar.c >= idea.tp2 : aC <= idea.tp2);
   if(idea.state == IDEA_LIVE && idea.tp1Done)
     {
      double pb = (idea.dir > 0 ? (idea.entry - bar.l) : (aH - idea.entry)) / SignalRisk();
      if(pb > idea.pbMax) idea.pbMax = pb;
      if(idea.addState == ADD_ARMED)
        {
         idea.addAge++;
         if(idea.dir > 0 ? (aL <= idea.addPx) : (bar.h >= idea.addPx))
           {
            idea.addState = ADD_FILLED;
            idea.addTime  = bar.t;
            addFillBar    = true;
            OnAddFilled();
           }
         else if(idea.addAge > InpAddExpire)
            idea.addState = ADD_DONE;
        }
     }

   if(idea.state == IDEA_LIVE && hitSL && hitTP1)
     {
      bool closeFav = (idea.dir > 0 ? (bar.c > idea.entry) : (bar.c < idea.entry));
      if(!closeFav)
        {
         gCntSL++;
         CloseAfterTP1(false, addFillBar, beyondTP2);
         idea.state = IDEA_SL_WAIT;
         idea.slTime = bar.t;
         idea.slBarAge = 0;
         return;
        }
     }

   if(idea.state == IDEA_LIVE && hitTP2)
     {
      if(!idea.tp1Done) { gCntTP1++; idea.tp1Done = true; StartAfterTP1(bar.t, false); }
      gCntTP2++;
      CloseAfterTP1(true, addFillBar, beyondTP2);
      EndIdea(" [TP2 HIT]", bar.t);
      return;
     }

   if(idea.state == IDEA_LIVE && hitTP1 && !idea.tp1Done)
     {
      gCntTP1++;
      idea.tp1Done = true;
      StartAfterTP1(bar.t, true);
     }

   if(idea.state == IDEA_LIVE && hitSL)
     {
      gCntSL++;
      CloseAfterTP1(false, addFillBar, beyondTP2);
      idea.state = IDEA_SL_WAIT;
      idea.slTime = bar.t;
      idea.slBarAge = 0;
      return;
     }

   if(idea.state == IDEA_SL_WAIT)
     {
      if(idea.slBarAge > InpReentryWindow
         || BiasTurnedAgainst(idea.dir, d, h4))
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
   string full = "St.LukesMTF Max EA " + _Symbol + " | " + msg;
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
   // buy / re-buy: under the candle, sell / re-sell: above it
   bool   buy   = (sig > 0);
   double price = (buy ? iLow(_Symbol, _Period, i) - InpDotGapPts * Pt()
                       : iHigh(_Symbol, _Period, i) + InpDotGapPts * Pt());
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);   // small dot
   ObjectSetInteger(0, name, OBJPROP_COLOR, SigColor(sig));
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, buy ? ANCHOR_TOP : ANCHOR_BOTTOM);
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

// kind: ENTRY_MARKET / ENTRY_PENDING for this order. tpFromFill: TP1 measured from the
// market fill price with the same R multiple (hybrid market part).
double gLastOpenTP1 = 0;   // TP1 of the last order opened by OpenEntryAs

// signal time from a comment "LukesEA|<signal time>[|B|ADD]" (0 for none / grid levels)
datetime CmtSigTime(const string cmt)
  {
   int p = StringFind(cmt, "|");
   if(p < 0) return 0;
   string v = StringSubstr(cmt, p + 1);
   int q = StringFind(v, "|");
   if(q >= 0) v = StringSubstr(v, 0, q);
   return (datetime)StringToInteger(v);
  }

// TP2 for a market runner: indicator TP2, or from the fill price with the same R if it is no longer valid
double RunnerTP(const int dir, const double price, const double sl)
  {
   double tp = idea.tp2;
   double ms = MinStop();
   if(dir > 0 ? tp > price + ms : tp < price - ms) return NormalizeDouble(tp, _Digits);
   double risk = MathAbs(price - sl);
   return NormalizeDouble(dir > 0 ? price + risk * InpRR2 : price - risk * InpRR2, _Digits);
  }

// Single trades: SL distance from the entry widened by InpSLExpandPct % (pending = same level
// as the signal engine / indicator SL). TP1 keeps the signal's risk.
double ExpandSL(const int dir, const double base, const double sl)
  {
   if(InpMode != MODE_SINGLE || InpSLExpandPct <= 0) return sl;
   double risk = MathAbs(base - sl);
   return NormalizeDouble(base - dir * risk * (1.0 + InpSLExpandPct / 100.0), _Digits);
  }

bool OpenEntryAs(const int dir, const double lotIn, const bool withStops, const string tag,
                 const ENUM_ENTRY_TYPE kind, const bool tpFromFill, const int target = 1)
  {
   double lot = NormLot(lotIn);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ms  = MinStop();
   double sl  = NormalizeDouble(idea.sl0, _Digits);   // signal SL; ExpandSL widens it for the order
   string cmt = InpComment + "|" + IntegerToString((long)idea.signalTime) + (target == 2 ? "|B" : "");
   double rr  = (target == 2 ? InpRR2 : InpRR1);

   bool pending = (kind == ENTRY_PENDING);
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
   double tp1 = (target == 2 ? (pending ? NormalizeDouble(idea.tp2, _Digits) : RunnerTP(dir, price, sl))
                             : (pending ? NormalizeDouble(idea.tp1, _Digits) : MarketTP1(dir, price, sl)));
   double risk = MathAbs(price - sl);
   if(!pending && tpFromFill)
      tp1 = NormalizeDouble(dir > 0 ? price + risk * rr : price - risk * rr, _Digits);

   double slx = ExpandSL(dir, (pending ? entry : price), sl);
   double oSL = (withStops ? slx : 0.0);
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

   // hybrid market part: re-measure TP1 from the actual fill price (slippage)
   if(!pending && tpFromFill)
     {
      double fill = trade.ResultPrice();
      if(fill > 0)
        {
         double frisk = MathAbs(fill - sl);
         double ftp1  = NormalizeDouble(dir > 0 ? fill + frisk * rr : fill - frisk * rr, _Digits);
         double fslx  = ExpandSL(dir, fill, sl);
         if(MathAbs(ftp1 - tp1) >= _Point || MathAbs(fslx - slx) >= _Point)
           {
            tp1 = ftp1;
            slx = fslx;
            if(withStops)
              {
               ulong pt = trade.ResultOrder();   // position ticket = order ticket on hedging accounts
               ulong dl = trade.ResultDeal();
               if(dl > 0 && HistoryDealSelect(dl)) pt = (ulong)HistoryDealGetInteger(dl, DEAL_POSITION_ID);
               if(pt > 0 && PositionSelectByTicket(pt)) trade.PositionModify(pt, slx, tp1);
              }
           }
        }
     }

   gLastOpenTP1 = tp1;
   if(InpMode == MODE_GRID && target == 1) { SaveTP1(tp1); SaveBStop(0); }
   string what = StringFormat("%s %s lot %.2f @ %s  SL %s  TP %s", tag,
                              (pending ? EnumToString(otype) : (dir > 0 ? "BUY market" : "SELL market")),
                              lot, Px(pending ? entry : trade.ResultPrice()),
                              (withStops ? Px(slx) + (slx != sl ? StringFormat(" (signal SL %s +%.0f%%)", Px(sl), InpSLExpandPct) : "") : "none"),
                              (withStops ? Px(tp1) : "none"));
   Log("OPEN", what);
   if(InpAlertTrades) Notify("OPEN " + what);
   return true;
  }

bool OpenEntry(const int dir, const double lotIn, const bool withStops, const string tag)
  {
   return OpenEntryAs(dir, lotIn, withStops, tag,
                      (InpEntryType == ENTRY_PENDING ? ENTRY_PENDING : ENTRY_MARKET), false);
  }

// floor a lot to the volume step without raising it to the minimum
double FloorLot(const double lot)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   return MathFloor(lot / step + 1e-9) * step;
  }

// HYBRID: InpHybridMarketPct % at market now (SL = signal SL, TP1 from its own fill),
// the rest as the normal pending order at the signal's Entry level.
void OpenHybrid(const int dir, const double lotIn, const bool withStops, const string tag)
  {
   double total = NormLot(lotIn);
   double mn    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mkt   = FloorLot(total * MathMax(0, MathMin(100, InpHybridMarketPct)) / 100.0);
   double pend  = FloorLot(total - mkt + 1e-9);

   if(mkt < mn - 1e-9 || pend < mn - 1e-9)
     {
      bool asMarket = (InpHybridMarketPct >= 100) ||
                      (InpHybridMarketPct > 0 && InpHybridFallback == HYB_ALL_MARKET);
      Log("HYBRID", StringFormat("%s: lot %.2f too small to split %d%%/%d%% -> all %s", tag, total,
                                 InpHybridMarketPct, 100 - InpHybridMarketPct, (asMarket ? "at market" : "as pending")));
      OpenEntryAs(dir, total, withStops, tag, (asMarket ? ENTRY_MARKET : ENTRY_PENDING), asMarket);
      return;
     }

   Log("HYBRID", StringFormat("%s: %.2f lots = %.2f market (%d%%) + %.2f pending @ %s",
                              tag, total, mkt, InpHybridMarketPct, pend, Px(idea.entry)));
   bool   mOk  = OpenEntryAs(dir, mkt,  withStops, tag + " [hybrid mkt]",  ENTRY_MARKET,  true);
   double mTP1 = gLastOpenTP1;
   OpenEntryAs(dir, pend, withStops, tag + " [hybrid pend]", ENTRY_PENDING, false);
   // grid: the market part is grid trade #1, so the "close at TP1" level is its TP1
   if(mOk && InpMode == MODE_GRID) SaveTP1(mTP1);
  }

void EnterMain(const int dir, const double lot, const bool withStops, const string tag);

// main trade (TP1) + optional runner (TP2, single trades)
void EnterSignal(const int dir, const double lot, const bool withStops, const string tag)
  {
   EnterMain(dir, lot, withStops, tag);
   if(InpMode == MODE_SINGLE && InpRunnerLot > 0)
      OpenEntryAs(dir, InpRunnerLot, withStops, tag + " [runner TP2]",
                  (InpEntryType == ENTRY_PENDING ? ENTRY_PENDING : ENTRY_MARKET), false, 2);
  }

void EnterMain(const int dir, const double lot, const bool withStops, const string tag)
  {
   if(InpEntryType == ENTRY_HYBRID && (InpMode == MODE_GRID || !InpHybridSplitSingle))
     {
      // No split: the whole lot opens at market as ONE trade (SL = signal SL, TP1 from
      // its own fill). Full grid: a filled pending half would join the basket as an extra
      // grid trade. Single trades: two trades per signal (user decision, v1.18).
      OpenEntryAs(dir, lot, withStops, tag + " [hybrid: one market trade]", ENTRY_MARKET, true);
      return;
     }
   if(InpEntryType == ENTRY_MARKET && InpMode == MODE_GRID)
     {
      // grid signal trade at market: TP1 measured from its own fill price
      OpenEntryAs(dir, lot, withStops, tag, ENTRY_MARKET, true);
      return;
     }
   if(InpEntryType == ENTRY_HYBRID) OpenHybrid(dir, lot, withStops, tag);
   else                             OpenEntry(dir, lot, withStops, tag);
  }

string EntryName()
  {
   if(InpEntryType == ENTRY_MARKET)  return "Market";
   if(InpEntryType == ENTRY_PENDING) return "Pending";
   if(InpMode == MODE_GRID || !InpHybridSplitSingle) return "Hybrid (1 market trade)";
   return StringFormat("Hybrid %d%% mkt", InpHybridMarketPct);
  }

//+------------------------------------------------------------------+
//| Acting on a new signal                                           |
//+------------------------------------------------------------------+
void RememberSigRe(const datetime t, const int re);   // defined with the re-entry sync below

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
      RememberSigRe(idea.signalTime, idea.reCount);
      gEnteredSig = idea.signalTime;
      EnterSignal(dir, InpSingleLot, true, tag);
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
      EnterSignal(dir, InpSingleLot, false, tag + " grid#1");   // the signal trade uses the single-trade lot
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
      datetime sigT = CmtSigTime(cmt);
      datetime setup = (datetime)OrderGetInteger(ORDER_TIME_SETUP);

      string why = "";
      if(StringFind(cmt, "|ADD") >= 0)
        {
         // pullback add lives while the engine still waits for its fill
         if(sigT == 0 || sigT != idea.signalTime || idea.state != IDEA_LIVE || idea.addState != ADD_ARMED)
            why = "pullback add no longer valid";
        }
      else if(sigT == 0 || sigT != idea.signalTime || (idea.state != IDEA_PENDING && idea.state != IDEA_LIVE))
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

// Signal trade on its own -> TP1. Once a grid trade is added -> shared basket TP.
// Basket TP off -> every grid trade closes at TP1.
bool GridUsesTP1(const Basket &b)
  {
   return (LoadTP1() > 0 && (!InpBasketTPOn || b.count <= 1));
  }

double GridTPPrice(const Basket &b, const double px)
  {
   double tp1 = LoadTP1();
   if(GridUsesTP1(b)) return tp1;
   if(InpBasketTPType == BASKET_DISTANCE) return b.avg + b.dir * BasketDist();
   return PriceForProfit(b, InpBasketTPMoney, px);
  }



// Grid trades never carry an SL (the basket stop and the Equity Protector are enforced by
// the EA itself). All grid trades share one TP: TP1 while the signal trade is alone
// (or basket TP is off), the basket TP once grid trades were added.
void SyncGridLevels(const Basket &b)
  {
   if(b.count == 0) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double px  = (b.dir > 0 ? bid : ask);
   double ms  = MinStop() + _Point;
   double tol = 5 * Pt();   // ignore changes smaller than 5 points (avoid modify spam)

   double tp = (InpGridBrokerLevels ? NormalizeDouble(GridTPPrice(b, px), _Digits) : 0.0);
   // a TP too close to price is left off; the EA's own check still closes the basket
   if(tp > 0 && (b.dir > 0 ? tp < bid + ms : tp > ask - ms)) tp = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !Ours()) continue;
      double csl = PositionGetDouble(POSITION_SL);
      double ctp = PositionGetDouble(POSITION_TP);
      double nsl = 0.0;                       // never an SL on a grid trade
      double ntp = (tp > 0 ? tp : ctp);
      bool chg = (csl != 0 || MathAbs(ntp - ctp) >= tol || (ctp == 0 && ntp > 0));
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
   if(!GridUsesTP1(b))
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
      why = (b.count <= 1 ? "signal trade closed at TP1 " : "grid closed at single-trade TP1 ") + Px(tp1);
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
      if(CountOrders() > 0) DeleteOrders("basket closed");
      return;
     }

   SyncGridLevels(b);

   // 2) add a grid trade
   if(b.count >= InpGridMaxTrades) return;
   if(TimeCurrent() < gNextGridTry) return;
   bool add = (b.dir > 0 ? ask <= b.extreme - GridDist(b.count) : bid >= b.extreme + GridDist(b.count));
   if(!add) return;

   // extra grid trades: #2 = grid start lot, #3 = start x mult, #4 = start x mult^2 ...
   double lot = NormLot(InpGridStartLot * MathPow(InpGridMultiplier, MathMax(0, b.count - 1)));
   string cmt = InpComment + "|grid" + IntegerToString(b.count + 1);

   // enough free margin? otherwise alert once for this level and re-check every 30 s
   double need = 0;
   ENUM_ORDER_TYPE ot = (b.dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   if(OrderCalcMargin(ot, _Symbol, lot, (b.dir > 0 ? ask : bid), need)
      && need > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
     {
      gNextGridTry = TimeCurrent() + 30;
      if(gNoMarginLevel != b.count + 1)
        {
         gNoMarginLevel = b.count + 1;
         string msg = StringFormat("grid#%d lot %.2f needs margin %.2f, free %.2f. Lower the Grid lot / multiplier or max grid trades.",
                                   b.count + 1, lot, need, AccountInfoDouble(ACCOUNT_MARGIN_FREE));
         Log("GRID_NO_MARGIN", msg);
         Notify("GRID NO MARGIN " + msg);
        }
      return;
     }
   bool ok = (b.dir > 0 ? trade.Buy(lot, _Symbol, 0, 0, 0, cmt) : trade.Sell(lot, _Symbol, 0, 0, 0, cmt));
   uint rc = trade.ResultRetcode();
   if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_DONE_PARTIAL))
     {
      // e.g. requote / price changed / off quotes: short retry
      gNextGridTry = TimeCurrent() + 3;
      Log("GRID_FAIL", StringFormat("level %d lot %.2f retcode %u %s", b.count + 1, lot, rc, trade.ResultRetcodeDescription()));
      return;
     }
   string what = StringFormat("grid#%d %s lot %.2f @ %s (last %s, distance %d pts)", b.count + 1,
                              (b.dir > 0 ? "BUY" : "SELL"), lot, Px(trade.ResultPrice()), Px(b.extreme), GridGapPts(b.count));
   gNoMarginLevel = 0;
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
   if(InpMode == MODE_SINGLE && InpRunnerBEOn) RunnerBE();
   if(InpMode == MODE_GRID) ManageGrid(b);
  }

//+------------------------------------------------------------------+
//| Re-entry after a REAL stop-out (single trades)                   |
//| MARKET / HYBRID trades open at once, but the signal engine tracks |
//| the signal as a pending entry that can expire. When the real      |
//| trade is stopped out later, the engine has forgotten the signal   |
//| and no re-entry follows. So the EA watches its own trades: a      |
//| trade closed by its SL with a loss starts the re-entry wait.      |
//+------------------------------------------------------------------+
datetime gSigReT[];  int gSigReN[];        // signal time -> re-entry count at entry
datetime gDealScanFrom = 0;
int      gPrevSingleCount = -1;

void RememberSigRe(const datetime t, const int re)
  {
   int n = ArraySize(gSigReT);
   if(n >= 200) { ArrayRemove(gSigReT, 0, 100); ArrayRemove(gSigReN, 0, 100); n = ArraySize(gSigReT); }
   ArrayResize(gSigReT, n + 1); ArrayResize(gSigReN, n + 1);
   gSigReT[n] = t; gSigReN[n] = re;
  }

int KnownSigRe(const datetime t)
  {
   for(int i = ArraySize(gSigReT) - 1; i >= 0; i--) if(gSigReT[i] == t) return gSigReN[i];
   return 0;
  }

void SyncReentryFromDeals()
  {
   if(InpMode != MODE_SINGLE || !InpReentryOn) return;
   int cnt = GetBasket().count;
   bool fewer = (gPrevSingleCount >= 0 && cnt < gPrevSingleCount);
   gPrevSingleCount = cnt;
   if(!fewer) return;

   if(gDealScanFrom == 0) gDealScanFrom = TimeCurrent() - 3600;
   if(!HistorySelect(gDealScanFrom, TimeCurrent() + 60)) return;
   datetime newest = gDealScanFrom - 1;
   long pids[]; int dirs[];
   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0) continue;
      if(HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol || HistoryDealGetInteger(tk, DEAL_MAGIC) != InpMagic) continue;
      long e = HistoryDealGetInteger(tk, DEAL_ENTRY);
      if(e != DEAL_ENTRY_OUT && e != DEAL_ENTRY_OUT_BY) continue;
      datetime t = (datetime)HistoryDealGetInteger(tk, DEAL_TIME);
      if(t < gDealScanFrom) continue;
      if(t > newest) newest = t;
      double pl = HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_SWAP) + HistoryDealGetDouble(tk, DEAL_COMMISSION);
      if(HistoryDealGetInteger(tk, DEAL_REASON) != DEAL_REASON_SL || pl >= 0) continue;   // break-even / trailing stops are not losses
      int n = ArraySize(pids);
      ArrayResize(pids, n + 1); ArrayResize(dirs, n + 1);
      pids[n] = HistoryDealGetInteger(tk, DEAL_POSITION_ID);
      dirs[n] = (HistoryDealGetInteger(tk, DEAL_TYPE) == DEAL_TYPE_SELL ? 1 : -1);  // closing a buy = sell deal
     }
   gDealScanFrom = newest + 1;   // next scan starts after the newest deal seen

   for(int k = 0; k < ArraySize(pids); k++)
     {
      if(!HistorySelectByPosition(pids[k])) continue;
      datetime sigT = 0;
      for(int j = 0; j < HistoryDealsTotal(); j++)
        {
         ulong dt = HistoryDealGetTicket(j);
         if(dt > 0 && HistoryDealGetInteger(dt, DEAL_ENTRY) == DEAL_ENTRY_IN)
           {
            datetime ct = CmtSigTime(HistoryDealGetString(dt, DEAL_COMMENT));
            if(ct != 0) sigT = ct;
           }
        }
      if(sigT == 0) continue;
      if(idea.state == IDEA_SL_WAIT && idea.signalTime == sigT) continue;      // engine saw it too
      if(idea.state != IDEA_IDLE && idea.signalTime != sigT) continue;         // a newer signal is running

      int re = (idea.signalTime == sigT ? idea.reCount : KnownSigRe(sigT));
      idea.state     = IDEA_SL_WAIT;
      idea.dir       = dirs[k];
      idea.signalTime = sigT;
      idea.slTime    = iTime(_Symbol, _Period, 0);
      idea.slBarAge  = 0;
      idea.reCount   = re;
      idea.tp1Done   = false;
      Log("REENTRY_SYNC", StringFormat("%s trade of signal %s stopped out with a loss -> re-entry wait (%d/%d)",
                                       (dirs[k] > 0 ? "BUY" : "SELL"), TimeToString(sigT, TIME_DATE|TIME_MINUTES), re, InpMaxReentry));
     }
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

//+------------------------------------------------------------------+
//| Pullback add after TP1 (single trades)                           |
//+------------------------------------------------------------------+
// open position / pending order of signal sigT? add = only pullback add ones
bool HaveFor(const datetime sigT, const bool add)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !Ours()) continue;
      string c = PositionGetString(POSITION_COMMENT);
      if(CmtSigTime(c) == sigT && (!add || StringFind(c, "|ADD") >= 0)) return true;
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || !OurOrder()) continue;
      string c = OrderGetString(ORDER_COMMENT);
      if(CmtSigTime(c) == sigT && (!add || StringFind(c, "|ADD") >= 0)) return true;
     }
   return false;
  }

// TP1 hit: limit order back in the signal direction at the add level, TP = TP2, SL = signal SL.
// Price already past the add level (deeper pullback) -> at market, a better price.
void PlaceAddOrder()
  {
   if(InpMode != MODE_SINGLE || !InpAddOn || InpAddLot <= 0) return;
   if(idea.state != IDEA_LIVE || idea.addState != ADD_ARMED || idea.signalTime == 0) return;
   if(gAddSent == idea.signalTime || gClosing || TradeBlocker() != "") return;
   if(idea.signalTime != gEnteredSig && !HaveFor(idea.signalTime, false)) return;   // EA did not trade this signal
   gAddSent = idea.signalTime;
   if(HaveFor(idea.signalTime, true)) return;                                       // already there (restart)

   int    dir = idea.dir;
   double lot = NormLot(InpAddLot);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ms  = MinStop();
   double px  = NormalizeDouble(idea.addPx, _Digits);
   double sl  = NormalizeDouble(idea.sl, _Digits);
   double tp  = NormalizeDouble(idea.tp2, _Digits);
   string cmt = InpComment + "|" + IntegerToString((long)idea.signalTime) + "|ADD";
   string tag = (dir > 0 ? "BUY" : "SELL");
   tag += " pullback add";

   bool   limit = (dir > 0 ? px < ask - ms : px > bid + ms);
   double price = (limit ? px : (dir > 0 ? ask : bid));
   if(dir > 0 ? (sl >= price - ms || tp <= price + ms) : (sl <= price + ms || tp >= price - ms))
     {
      Log("SKIP", StringFormat("%s: price %s outside SL %s / TP2 %s", tag, Px(price), Px(sl), Px(tp)));
      return;
     }
   bool ok;
   if(limit)        ok = trade.OrderOpen(_Symbol, (dir > 0 ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT), lot, 0, px, sl, tp, ORDER_TIME_GTC, 0, cmt);
   else if(dir > 0) ok = trade.Buy(lot, _Symbol, 0, sl, tp, cmt);
   else             ok = trade.Sell(lot, _Symbol, 0, sl, tp, cmt);

   uint rc = trade.ResultRetcode();
   if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED && rc != TRADE_RETCODE_DONE_PARTIAL))
     {
      Log("OPEN_FAIL", StringFormat("%s lot %.2f retcode %u %s", tag, lot, rc, trade.ResultRetcodeDescription()));
      return;
     }
   string what = StringFormat("%s %s lot %.2f @ %s  SL %s  TP2 %s", tag, (limit ? "LIMIT" : "market"), lot,
                              Px(limit ? px : trade.ResultPrice()), Px(sl), Px(tp));
   Log("OPEN", what);
   if(InpAlertTrades) Notify("OPEN " + what);
  }

// runner (TP2) and pullback add: SL to break-even once price covered InpRunnerBEPct % of the way to the TP
void RunnerBE()
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double ms  = MinStop();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !Ours()) continue;
      string c = PositionGetString(POSITION_COMMENT);
      if(StringFind(c, "|B") < 0 && StringFind(c, "|ADD") < 0) continue;
      bool   buy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double op  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl  = PositionGetDouble(POSITION_SL);
      double tp  = PositionGetDouble(POSITION_TP);
      if(tp == 0) continue;
      double lock = InpRunnerBELockPts * Pt();
      double nsl  = NormalizeDouble(buy ? op + lock : op - lock, _Digits);
      if(buy ? (sl >= nsl - _Point / 2) : (sl != 0 && sl <= nsl + _Point / 2)) continue;   // already at break-even
      double need = MathAbs(tp - op) * InpRunnerBEPct / 100.0;
      double cur  = (buy ? bid - op : op - ask);
      if(cur < need) continue;
      if(buy ? nsl > bid - ms : nsl < ask + ms) continue;
      if(trade.PositionModify(tk, nsl, tp)) Log("RUNNER_BE", StringFormat("ticket %I64u SL -> %s", tk, Px(nsl)));
     }
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

   if(InpMode != MODE_SIGNALS) { SyncOrders(); PlaceAddOrder(); }
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
string gTodayKeys[];   // signal keys entered today (for the "pending order" row)

// signal key from an entry comment "LukesEA|<signal time>" ("" for grid levels)
string SigKey(const string cmt)
  {
   if(StringFind(cmt, "|grid") >= 0) return "";
   datetime t = CmtSigTime(cmt);
   return (t > 0 ? IntegerToString((long)t) : "");
  }

bool KeyIn(const string &arr[], const string k)
  {
   for(int i = ArraySize(arr) - 1; i >= 0; i--) if(arr[i] == k) return true;
   return false;
  }

void AddStr(string &arr[], const string v)
  {
   int n = ArraySize(arr); ArrayResize(arr, n + 1); arr[n] = v;
  }

// Closed trades today. A closed "trade" = deals closing together (grid basket, within 5 s)
// and/or deals of the same signal (both HYBRID parts), counted once.
void TodayStats(int &trades, int &wins, int &losses, double &pl,
                int &entries, int &gridAdds, int &gridBaskets)
  {
   trades = wins = losses = 0; pl = 0;
   entries = gridAdds = gridBaskets = 0;
   ArrayResize(gTodayKeys, 0);
   if(!HistorySelect(DayStart(), TimeCurrent() + 60)) return;
   int n = HistoryDealsTotal();

   long   posIds[];  string posKeys[];      // position -> signal key
   double gpPL[];    string gpKey[];  int gpSize[];
   int    ng = 0;
   datetime gT = 0; long gType = -1; bool open = false;
   for(int i = 0; i < n; i++)
     {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0) continue;
      if(HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(tk, DEAL_MAGIC) != InpMagic) continue;
      long entry = HistoryDealGetInteger(tk, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_IN)
        {
         // first trade(s) of a signal: comment "LukesEA|<signal time>"; grid levels: "LukesEA|gridN"
         string cmt = HistoryDealGetString(tk, DEAL_COMMENT);
         string k   = SigKey(cmt);
         if(StringFind(cmt, "|grid") >= 0) gridAdds++;
         else if(k == "" || !KeyIn(gTodayKeys, k)) { entries++; if(k != "") AddStr(gTodayKeys, k); }
         int m = ArraySize(posIds);
         ArrayResize(posIds, m + 1); ArrayResize(posKeys, m + 1);
         posIds[m] = HistoryDealGetInteger(tk, DEAL_POSITION_ID); posKeys[m] = k;
         continue;
        }
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) continue;
      datetime t   = (datetime)HistoryDealGetInteger(tk, DEAL_TIME);
      long     typ = HistoryDealGetInteger(tk, DEAL_TYPE);
      double   p   = HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_SWAP)
                     + HistoryDealGetDouble(tk, DEAL_COMMISSION);
      pl += p;
      long   pid = HistoryDealGetInteger(tk, DEAL_POSITION_ID);
      string k   = "";
      for(int j = ArraySize(posIds) - 1; j >= 0; j--) if(posIds[j] == pid) { k = posKeys[j]; break; }

      if(open && typ == gType && t - gT <= 5)
        {
         gpPL[ng - 1] += p; gpSize[ng - 1]++; gT = t;
         if(gpKey[ng - 1] == "") gpKey[ng - 1] = k;
         continue;
        }
      ArrayResize(gpPL, ng + 1); ArrayResize(gpKey, ng + 1); ArrayResize(gpSize, ng + 1);
      gpPL[ng] = p; gpKey[ng] = k; gpSize[ng] = 1; ng++;
      open = true; gT = t; gType = typ;
     }

   // merge groups belonging to the same signal (e.g. HYBRID parts closing at different times)
   for(int i = 0; i < ng; i++)
     {
      if(gpSize[i] == 0 || gpKey[i] == "") continue;
      for(int j = i + 1; j < ng; j++)
         if(gpSize[j] > 0 && gpKey[j] == gpKey[i]) { gpPL[i] += gpPL[j]; gpSize[i] += gpSize[j]; gpSize[j] = 0; }
     }
   for(int i = 0; i < ng; i++)
     {
      if(gpSize[i] == 0) continue;
      trades++;
      if(gpPL[i] >= 0) wins++; else losses++;
      if(gpSize[i] > 1 && InpMode == MODE_GRID) gridBaskets++;
     }
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
   PText(PPRE + "T1", gPX + 10, gPY + 6, "St.LukesMTF Max EA", C_TXT, InpPanelFont + 3, ANCHOR_LEFT_UPPER, InpPanelFontHead);
   PText(PPRE + "T2", gPX + InpPanelWidth - 10, gPY + 6, "v1.22  " + ShortToString((ushort)(gCollapsed ? 0x25B6 : 0x25BC)), C_MUTE, InpPanelFont - 1, ANCHOR_RIGHT_UPPER, InpPanelFontName);
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
   int ent, gAdd, gBsk;
   TodayStats(tr, w, l, pl, ent, gAdd, gBsk);
   int sigT = SignalsToday();
   int waiting = 0;
   for(int oi = OrdersTotal() - 1; oi >= 0; oi--)
     {
      ulong ot = OrderGetTicket(oi);
      if(ot == 0 || !OurOrder()) continue;
      string okey = SigKey(OrderGetString(ORDER_COMMENT));
      if(okey == "" || !KeyIn(gTodayKeys, okey)) { waiting = 1; break; }
     }
   int notTraded = (int)MathMax(0, sigT - ent - waiting);
   PSection("TODAY");
   PRow("Signals", IntegerToString(sigT), C_INFO);
   PRow("  traded", IntegerToString(ent), C_TXT);
   if(waiting > 0) PRow("  pending order", IntegerToString(waiting), C_WARN);
   PRow("  not traded", IntegerToString(notTraded), (notTraded > 0 ? C_MUTE : C_TXT));
   PRow("Grid trades added", IntegerToString(gAdd), (gAdd > 0 ? C_WARN : C_TXT));
   PRow("Grid baskets closed", IntegerToString(gBsk), C_TXT);
   PRow("Trades closed", IntegerToString(tr), C_TXT);
   PRow("TP (wins)", IntegerToString(w), C_UP);
   PRow("SL (losses)", IntegerToString(l), C_DN);
   PRow("Win rate", (tr > 0 ? StringFormat("%.0f%%", 100.0 * w / tr) : "-"),
        (tr == 0 ? C_MUTE : (w * 2 >= tr ? C_UP : C_DN)));
   PRow("Profit / loss", StringFormat("%+.2f %s", pl, AccountInfoString(ACCOUNT_CURRENCY)), (pl > 0 ? C_UP : (pl < 0 ? C_DN : C_TXT)));

   PSection("EA");
   PRow("Mode", ModeName(), (InpMode == MODE_SIGNALS ? C_INFO : C_TXT));
   PRow("Entry", EntryName(), C_TXT);
   if(InpMode == MODE_SINGLE && InpSLExpandPct > 0)
      PRow("SL widened", StringFormat("+%.0f%%", InpSLExpandPct), C_WARN);
   if(InpMode == MODE_SINGLE)
     {
      PRow("Runner (TP2)", (InpRunnerLot > 0 ? StringFormat("%.2f lots%s", InpRunnerLot, (InpRunnerBEOn ? StringFormat("  BE at %d%%", InpRunnerBEPct) : "")) : "OFF"),
           (InpRunnerLot > 0 ? C_TXT : C_MUTE));
      PRow("Pullback add", (InpAddOn && InpAddLot > 0 ? StringFormat("%.2f lots @ %.2fR", InpAddLot, InpAddDepth) : "OFF"),
           (InpAddOn && InpAddLot > 0 ? C_TXT : C_MUTE));
     }
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
      if(idea.addState == ADD_ARMED)  PRow("Add order", "LIMIT @ " + Px(idea.addPx), C_WARN);
      if(idea.addState == ADD_FILLED) PRow("Add order", "FILLED @ " + Px(idea.addPx), C_WARN);
     }
   PRow("Last signal", gLastSignal, C_LBL);
   if(b.count > 0)
     {
      PRow("Position", StringFormat("%s x%d  %.2f lots", (b.dir > 0 ? "BUY" : "SELL"), b.count, b.lots), (b.dir > 0 ? InpBuyColor : InpSellColor));
      PRow("Avg price", Px(b.avg), C_TXT);
      PRow("Floating P/L", StringFormat("%+.2f", b.profit), (b.profit >= 0 ? C_UP : C_DN));
      if(InpMode == MODE_GRID)
        {
         PRow("Grid trades open", StringFormat("%d/%d  gap %d", b.count, InpGridMaxTrades, GridGapPts((int)MathMax(1, b.count))), C_TXT);
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
                             EntryName(), _Digits));
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
   SyncReentryFromDeals();

   if(iTime(_Symbol, _Period, 1) > gLastProcessed)
      OnNewBars();

   if(InpMode != MODE_SIGNALS || GetBasket().count > 0)
      ManageTrades();

   UpdatePanel();
  }
//+------------------------------------------------------------------+
