//+------------------------------------------------------------------+
//| Lukes MTF EA                                                     |
//| Trades the signals of the Lukes MTF Ind indicator.               |
//| Rules: see EA_SPEC.md                                            |
//+------------------------------------------------------------------+
#property copyright "Lukes MTF EA"
#property link      ""
#property version   "1.01"

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
input ENUM_ENTRY_TYPE InpEntryType   = ENTRY_MARKET;
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
input int            InpGridMaxTrades  = 5;             // max running trades (stop adding at this count)
input bool           InpBasketTPOn     = true;          // off = close all grid trades at single-trade TP1
input ENUM_BASKET_TP InpBasketTPType   = BASKET_MONEY;
input double         InpBasketTPMoney  = 5.00;          // basket TP in account money
input int            InpBasketTPPts    = 200;           // basket TP: points beyond basket average

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
   int to   = MathMin(total - 1, i + InpSwingLook);
   if(from > total - 1) return iHigh(_Symbol, _Period, i);
   double mx = iHigh(_Symbol, _Period, from);
   for(int k = from; k <= to; k++) { double h = iHigh(_Symbol, _Period, k); if(h > mx) mx = h; }
   return mx;
  }

double RecentSwingLow(const int i)
  {
   int total = Bars(_Symbol, _Period);
   int from = i + 1;
   int to   = MathMin(total - 1, i + InpSwingLook);
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
double GridDist()   { return InpGridDistPts   * Pt(); }
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

   if(InpMode == MODE_GRID) SaveTP1(tp1);
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

void ManageGrid(const Basket &b)
  {
   if(b.count == 0) return;
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
   if(close)
     {
      string msg = StringFormat("%s | %d trades, %.2f lots, P/L %.2f", why, b.count, b.lots, b.profit);
      Log("BASKET_CLOSE", msg);
      if(InpAlertTrades) Notify("BASKET CLOSE " + msg);
      gClosing = true;
      CloseAll("basket close");
      return;
     }

   // 2) add a grid trade
   if(b.count >= InpGridMaxTrades) return;
   if(TimeCurrent() < gNextGridTry) return;
   bool add = (b.dir > 0 ? ask <= b.extreme - GridDist() : bid >= b.extreme + GridDist());
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
                              (b.dir > 0 ? "BUY" : "SELL"), lot, Px(trade.ResultPrice()), Px(b.extreme), InpGridDistPts);
   Log("GRID_ADD", what);
   if(InpAlertTrades) Notify("GRID ADD " + what);
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
   int start = MathMin(total - 5, 800);
   if(start < 1) start = 1;
   for(int i = start; i >= 1; i--)
     {
      int s = ProcessBar(i);
      if(s != 0) { DrawSignal(i, s); gLastSignal = SigName(s) + " " + TimeToString(iTime(_Symbol, _Period, i), TIME_DATE|TIME_MINUTES); }
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
      if(sig != 0) DrawSignal(i, sig);
     }
   gLastProcessed = iTime(_Symbol, _Period, 1);

   if(InpMode != MODE_SIGNALS) SyncOrders();
   if(sig == 0) return;

   gLastSignal = SigName(sig) + " " + TimeToString(gLastProcessed, TIME_DATE|TIME_MINUTES);
   string lv = StringFormat("%s  Entry %s  SL %s  TP1 %s  TP2 %s", SigName(sig),
                            Px(idea.entry), Px(idea.sl), Px(idea.tp1), Px(idea.tp2));
   Log("SIGNAL", lv);
   if(InpAlertSignals) Notify("SIGNAL " + lv);
   if(InpMode != MODE_SIGNALS && !gClosing) ActOnSignal(sig);
  }

string StateText()
  {
   if(idea.state == IDEA_PENDING) return (idea.dir > 0 ? "PENDING LONG" : "PENDING SHORT");
   if(idea.state == IDEA_LIVE)    return (idea.dir > 0 ? "LIVE LONG" : "LIVE SHORT");
   if(idea.state == IDEA_SL_WAIT) return StringFormat("SL HIT  re %d/%d", idea.reCount, InpMaxReentry);
   return "IDLE";
  }

void UpdatePanel()
  {
   if(!InpShowPanel) return;
   Basket b = GetBasket();
   string s = "Lukes MTF EA  |  " + ModeName() + "  |  Entry: " + (InpEntryType == ENTRY_MARKET ? "Market" : "Pending") + "\n";
   s += "Signal engine: " + StateText();
   if(idea.state != IDEA_IDLE)
      s += StringFormat("   Entry %s  SL %s  TP1 %s  TP2 %s", Px(idea.entry), Px(idea.sl), Px(idea.tp1), Px(idea.tp2));
   s += "\nLast signal: " + gLastSignal + "\n";
   if(b.count > 0)
      s += StringFormat("Trades: %d %s  lots %.2f  avg %s  P/L %.2f\n", b.count, (b.dir > 0 ? "BUY" : "SELL"), b.lots, Px(b.avg), b.profit);
   else
      s += "Trades: none\n";
   if(InpMode == MODE_GRID)
      s += StringFormat("Grid: max %d  dist %d pts  x%.2f  exit: %s\n", InpGridMaxTrades, InpGridDistPts, InpGridMultiplier,
                        (InpBasketTPOn ? (InpBasketTPType == BASKET_MONEY ? StringFormat("basket $%.2f", InpBasketTPMoney)
                                                                          : StringFormat("avg +/- %d pts", InpBasketTPPts))
                                       : "TP1 " + Px(LoadTP1())));
   if(InpEquityProtOn)
      s += StringFormat("Equity Protector: -%.1f%% = %.2f\n", InpEquityProtPct, -AccountInfoDouble(ACCOUNT_BALANCE) * InpEquityProtPct / 100.0);
   s += "Last event: " + gLastEvent;
   Comment(s);
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
   EventSetTimer(1);   // warm up even if no tick arrives (market closed)
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectsDeleteAll(0, EAPRE);
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
   if(!gWarm && EnsureWarm()) UpdatePanel();
   if(gWarm) EventKillTimer();
  }

void OnTick()
  {
   if(!EnsureWarm()) return;

   if(iTime(_Symbol, _Period, 1) > gLastProcessed)
      OnNewBars();

   if(InpMode != MODE_SIGNALS || GetBasket().count > 0)
      ManageTrades();

   UpdatePanel();
  }
//+------------------------------------------------------------------+
