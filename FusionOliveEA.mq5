//+------------------------------------------------------------------+
//|                                               FusionOliveEA.mq5  |
//|                                                                  |
//| Trades the CONFIRMED signals of FusionOliveInd, one trade at a   |
//| time, every order with SL and TP.                                |
//|                                                                  |
//| The indicator stays the single source of the signal logic: the   |
//| EA loads it with iCustom (headless: no panel, zones or alerts)   |
//| and reads its EA buffers on every closed bar:                    |
//|   kind 1/4 = signal confirmed, place the orders (entry LIMIT/STOP)|
//|   kind 2 = signal already filled on the break, enter at market   |
//|   kind 3 = the indicator dropped its pending orders, delete ours |
//|                                                                  |
//| The indicator runs with its DEFAULT inputs. To trade other       |
//| indicator settings, change the defaults in FusionOliveInd.mq5    |
//| and recompile it.                                                |
//+------------------------------------------------------------------+
#property copyright "FusionOliveEA"
#property link      ""
#property version   "1.00"
#property description "Trades the confirmed FusionOliveInd signals: one trade at a time, SL/TP, break-even, trailing."
#property tester_indicator "FusionOliveInd.ex5"

#include <Trade/Trade.mqh>

enum ENUM_ENTRY_MODE
  {
   ENTRY_AS_INDICATOR = 0,   // as the indicator: pullback limit + breakout stop, first fill wins
   ENTRY_MARKET       = 1    // market order as soon as the signal is confirmed
  };

enum ENUM_SL_MODE
  {
   SL_INDICATOR = 0,         // indicator SL (beyond the signal candle)
   SL_FIXED     = 1          // fixed distance from the entry (InpSLPts)
  };

enum ENUM_TP_MODE
  {
   TP_INDICATOR_TP1 = 0,     // indicator TP1
   TP_INDICATOR_TP2 = 1,     // indicator TP2
   TP_FIXED         = 2,     // fixed distance from the entry (InpTPPts)
   TP_RR            = 3      // InpTPRR x the SL distance
  };

enum ENUM_TRADE_DIR
  {
   DIR_BOTH = 0,             // buys and sells
   DIR_BUY  = 1,             // buys only
   DIR_SELL = 2              // sells only
  };

input group "=== Signal Source ==="
input string          InpIndName      = "FusionOliveInd"; // indicator file name in MQL5\Indicators
input bool            InpTradeReentry = true;             // also trade the indicator's re-entry signals
input ENUM_TRADE_DIR  InpDirection    = DIR_BOTH;

input group "=== Entry ==="
input ENUM_ENTRY_MODE InpEntryMode     = ENTRY_AS_INDICATOR;
input int             InpPendExpireBars = 12;  // delete unfilled pending orders after this many bars (0 = only when the indicator cancels)
input int             InpMaxSpreadPts  = 0;    // skip new trades when the spread is wider (0 = off)
input int             InpSlippagePts   = 30;   // max slippage for market orders (broker points)

input group "=== Lots ==="
input double          InpLots          = 0.01; // fixed lot size

input group "=== Stop Loss / Take Profit (points: x10 on 3/5-digit symbols, XAUUSD 100 = $1.00) ==="
input ENUM_SL_MODE    InpSLMode        = SL_INDICATOR;
input int             InpSLPts         = 500;  // SL distance when SL_FIXED
input ENUM_TP_MODE    InpTPMode        = TP_INDICATOR_TP1;
input int             InpTPPts         = 500;  // TP distance when TP_FIXED
input double          InpTPRR          = 1.5;  // TP = this x SL distance when TP_RR

input group "=== Break-even / Trailing ==="
input bool            InpBEOn          = false; // move the SL to break-even
input int             InpBETriggerPts  = 300;   // profit needed to move it
input int             InpBELockPts     = 20;    // points locked beyond the entry
input bool            InpTrailOn       = false; // trailing stop
input int             InpTrailStartPts = 400;   // profit needed before trailing starts
input int             InpTrailDistPts  = 300;   // SL distance behind the price
input int             InpTrailStepPts  = 50;    // move the SL only in steps of at least this

input group "=== Risk / Management ==="
input bool            InpCloseOnOpposite = false; // close the open trade on a confirmed opposite signal (and take it)
input double          InpDailyLossMoney  = 0;     // no new trades after this daily loss in account currency (0 = off)
input double          InpDailyProfitMoney = 0;    // no new trades after this daily profit (0 = off)
input int             InpMaxTradesPerDay = 0;     // max new trades per day (0 = off)

input group "=== Visuals / Notifications ==="
input bool            InpShowDots      = true;          // dot on every confirmed signal
input color           InpBuyDotColor   = clrAqua;       // under buy signals
input color           InpSellDotColor  = clrMagenta;    // over sell signals
input int             InpDotSize       = 3;             // 1-5
input int             InpDotHistoryBars = 3000;         // also mark confirmed signals of this many past bars
input bool            InpShowPanel     = true;          // status in the chart corner
input bool            InpNotify        = true;          // push notification on trade open / close
input long            InpMagic         = 260710;

// indicator buffer numbers (see FusionOliveInd: EA signal buffers)
#define B_SIG   10
#define B_SIGT  11
#define B_ENTRY 12
#define B_BRK   13
#define B_SL    14
#define B_TP1   15
#define B_TP2   16
#define B_BSL   17
#define B_BTP1  18
#define B_BTP2  19

#define DOTPRE  "FOE_DOT_"

struct EaSignal
  {
   int      code;     // dir * (kind + 10 if re-entry)
   int      dir;
   int      kind;
   bool     re;
   datetime sigTime;  // the arrow (signal) candle
   double   entry, brk, sl, tp1, tp2, bsl, btp1, btp2;
  };

CTrade   trade;
int      gH = INVALID_HANDLE;
datetime gLastBar   = 0;      // last closed bar whose signal was handled
datetime gPendSince = 0;      // bar time when our pending orders were placed
bool     gDotsDone  = false;
string   gLastMsg   = "";

//+------------------------------------------------------------------+
double Pt()
  {
   if(_Digits == 3 || _Digits == 5) return _Point * 10.0;
   return _Point;
  }

double NormPrice(const double p)
  {
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0.0) return NormalizeDouble(p, _Digits);
   return NormalizeDouble(MathRound(p / ts) * ts, _Digits);
  }

double NormLots(const double lots)
  {
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double l = lots;
   if(st > 0.0) l = MathFloor(l / st + 1e-9) * st;
   return MathMax(mn, MathMin(mx, l));
  }

// minimum distance of SL / TP / pending price from the market
double StopsDist()
  {
   long lv = MathMax(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
                     SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL));
   return (double)(lv + 1) * _Point;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpLots <= 0.0 || InpSLPts <= 0 || InpTPPts <= 0 || InpTPRR <= 0.0)
     {
      Print("FusionOliveEA: lots, SL/TP points and TP RR must be positive");
      return(INIT_PARAMETERS_INCORRECT);
     }
   gH = iCustom(_Symbol, _Period, InpIndName, true);   // true = InpHeadless
   if(gH == INVALID_HANDLE)
     {
      Print("FusionOliveEA: cannot load the indicator '", InpIndName, "' - compile it in MQL5\\Indicators first");
      return(INIT_FAILED);
     }
   trade.SetExpertMagicNumber((ulong)InpMagic);
   trade.SetDeviationInPoints((ulong)MathMax(0, InpSlippagePts));
   trade.SetTypeFillingBySymbol(_Symbol);
   gLastBar = iTime(_Symbol, _Period, 1);   // never trade a signal that closed before the EA started
   gDotsDone = false;
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(gH != INVALID_HANDLE) IndicatorRelease(gH);
   if(reason == REASON_REMOVE) ObjectsDeleteAll(0, DOTPRE);
   Comment("");
  }

//+------------------------------------------------------------------+
//| Reading the indicator                                            |
//+------------------------------------------------------------------+
double Buf(const int b, const int sh)
  {
   double v[1];
   if(CopyBuffer(gH, b, sh, 1, v) != 1) return 0.0;
   if(v[0] == EMPTY_VALUE) return 0.0;
   return v[0];
  }

bool ReadSignal(const int sh, EaSignal &s)
  {
   s.code = (int)MathRound(Buf(B_SIG, sh));
   if(s.code == 0) return false;
   int a   = MathAbs(s.code);
   s.dir   = (s.code > 0 ? 1 : -1);
   s.re    = (a >= 10);
   s.kind  = a % 10;
   s.sigTime = (datetime)(long)Buf(B_SIGT, sh);
   s.entry = Buf(B_ENTRY, sh);
   s.brk   = Buf(B_BRK, sh);
   s.sl    = Buf(B_SL, sh);
   s.tp1   = Buf(B_TP1, sh);
   s.tp2   = Buf(B_TP2, sh);
   s.bsl   = Buf(B_BSL, sh);
   s.btp1  = Buf(B_BTP1, sh);
   s.btp2  = Buf(B_BTP2, sh);
   return (s.kind >= 1 && s.kind <= 4);
  }

bool IndicatorReady()
  {
   return (gH != INVALID_HANDLE && BarsCalculated(gH) >= Bars(_Symbol, _Period));
  }

//+------------------------------------------------------------------+
//| Dots on confirmed signals                                        |
//+------------------------------------------------------------------+
void DrawDot(const datetime t, const int dir)
  {
   if(!InpShowDots || t <= 0) return;
   int sh = iBarShift(_Symbol, _Period, t, true);
   if(sh < 0) return;
   string n = DOTPRE + IntegerToString((long)t) + (dir > 0 ? "B" : "S");
   double p = (dir > 0 ? iLow(_Symbol, _Period, sh) : iHigh(_Symbol, _Period, sh));
   if(ObjectFind(0, n) < 0)
      ObjectCreate(0, n, OBJ_ARROW, 0, t, p);
   ObjectSetInteger(0, n, OBJPROP_ARROWCODE, 159);   // round dot
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, (dir > 0 ? ANCHOR_TOP : ANCHOR_BOTTOM));
   ObjectSetInteger(0, n, OBJPROP_COLOR, (dir > 0 ? InpBuyDotColor : InpSellDotColor));
   ObjectSetInteger(0, n, OBJPROP_WIDTH, MathMax(1, MathMin(5, InpDotSize)));
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   ObjectSetDouble(0, n, OBJPROP_PRICE, p);
  }

// past confirmed signals, drawn once when the indicator is ready
void DrawHistoryDots()
  {
   if(!InpShowDots) { gDotsDone = true; return; }
   int n = (int)MathMin(MathMax(0, InpDotHistoryBars), Bars(_Symbol, _Period) - 2);
   if(n <= 0) { gDotsDone = true; return; }
   double sig[], st[];
   ArraySetAsSeries(sig, true);
   ArraySetAsSeries(st, true);
   if(CopyBuffer(gH, B_SIG, 1, n, sig) != n || CopyBuffer(gH, B_SIGT, 1, n, st) != n) return;   // retry next tick
   for(int k = 0; k < n; k++)
     {
      int c = (int)MathRound(sig[k] == EMPTY_VALUE ? 0.0 : sig[k]);
      int kind = MathAbs(c) % 10;
      if(c != 0 && (kind == 1 || kind == 2 || kind == 4))
         DrawDot((datetime)(long)st[k], (c > 0 ? 1 : -1));
     }
   gDotsDone = true;
  }

//+------------------------------------------------------------------+
//| Positions / orders of this EA                                    |
//+------------------------------------------------------------------+
bool OurPosition(ulong &ticket, int &dir)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      ticket = t;
      dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1);
      return true;
     }
   return false;
  }

int OurPendingCount()
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic) n++;
     }
   return n;
  }

// dir 0 = all directions
void DeletePendings(const int dir)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol || OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      int od = ((ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_BUY_STOP || ot == ORDER_TYPE_BUY_STOP_LIMIT) ? 1 : -1);
      if(dir == 0 || od == dir)
         trade.OrderDelete(t);
     }
   if(OurPendingCount() == 0) gPendSince = 0;
  }

void ClosePosition(const ulong ticket)
  {
   if(!trade.PositionClose(ticket))
      PrintFormat("FusionOliveEA: close failed %u %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Daily limits                                                     |
//+------------------------------------------------------------------+
void TodayStats(double &closedPL, int &opened)
  {
   closedPL = 0.0;
   opened = 0;
   MqlDateTime d;
   TimeToStruct(TimeCurrent(), d);
   d.hour = 0; d.min = 0; d.sec = 0;
   datetime day0 = StructToTime(d);
   if(!HistorySelect(day0, TimeCurrent() + 60)) return;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong dl = HistoryDealGetTicket(i);
      if(dl == 0) continue;
      if(HistoryDealGetString(dl, DEAL_SYMBOL) != _Symbol || HistoryDealGetInteger(dl, DEAL_MAGIC) != InpMagic) continue;
      long e = HistoryDealGetInteger(dl, DEAL_ENTRY);
      if(e == DEAL_ENTRY_IN) opened++;
      if(e == DEAL_ENTRY_OUT || e == DEAL_ENTRY_INOUT || e == DEAL_ENTRY_OUT_BY)
         closedPL += HistoryDealGetDouble(dl, DEAL_PROFIT) + HistoryDealGetDouble(dl, DEAL_SWAP)
                     + HistoryDealGetDouble(dl, DEAL_COMMISSION);
     }
  }

bool RiskAllows(string &why)
  {
   double pl; int opened;
   TodayStats(pl, opened);
   if(InpDailyLossMoney > 0.0 && pl <= -InpDailyLossMoney) { why = "daily loss limit"; return false; }
   if(InpDailyProfitMoney > 0.0 && pl >= InpDailyProfitMoney) { why = "daily profit target"; return false; }
   if(InpMaxTradesPerDay > 0 && opened >= InpMaxTradesPerDay) { why = "max trades per day"; return false; }
   if(InpMaxSpreadPts > 0)
     {
      double spr = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(spr > InpMaxSpreadPts * Pt()) { why = "spread too wide"; return false; }
     }
   return true;
  }

//+------------------------------------------------------------------+
//| SL / TP for one order at price e (leg: 0 = limit/market, 1 = break)|
//+------------------------------------------------------------------+
void Levels(const EaSignal &s, const int leg, const double e, double &sl, double &tp)
  {
   double isl  = (leg == 1 && s.bsl  > 0.0 ? s.bsl  : s.sl);
   double itp1 = (leg == 1 && s.btp1 > 0.0 ? s.btp1 : s.tp1);
   double itp2 = (leg == 1 && s.btp2 > 0.0 ? s.btp2 : s.tp2);
   if(InpSLMode == SL_FIXED || isl <= 0.0) sl = e - s.dir * InpSLPts * Pt();
   else                                    sl = isl;
   double risk = MathAbs(e - sl);
   switch(InpTPMode)
     {
      case TP_INDICATOR_TP1: tp = (itp1 > 0.0 ? itp1 : e + s.dir * risk); break;
      case TP_INDICATOR_TP2: tp = (itp2 > 0.0 ? itp2 : e + s.dir * 2.0 * risk); break;
      case TP_FIXED:         tp = e + s.dir * InpTPPts * Pt(); break;
      default:               tp = e + s.dir * InpTPRR * risk; break;
     }
   sl = NormPrice(sl);
   tp = NormPrice(tp);
  }

bool LevelsValid(const int dir, const double e, const double sl, const double tp)
  {
   return (dir > 0 ? (sl < e && tp > e) : (sl > e && tp < e));
  }

void Notify(const string msg)
  {
   gLastMsg = TimeToString(TimeCurrent(), TIME_MINUTES) + " " + msg;
   Print("FusionOliveEA: ", msg);
   if(InpNotify) SendNotification("FusionOliveEA " + _Symbol + ": " + msg);
  }

// market order, levels measured from the current price
bool EnterMarket(const EaSignal &s, const int leg, const string why)
  {
   double e = (s.dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID));
   double sl, tp;
   Levels(s, leg, e, sl, tp);
   double md = StopsDist();
   if(!LevelsValid(s.dir, e, sl, tp) || MathAbs(e - sl) < md || MathAbs(tp - e) < md)
     {
      Notify(StringFormat("%s skipped: price %s already beyond SL/TP (SL %s TP %s)", (s.dir > 0 ? "BUY" : "SELL"),
                          DoubleToString(e, _Digits), DoubleToString(sl, _Digits), DoubleToString(tp, _Digits)));
      return false;
     }
   string cm = "FusionOlive " + why;
   bool ok = (s.dir > 0 ? trade.Buy(NormLots(InpLots), _Symbol, 0.0, sl, tp, cm)
                        : trade.Sell(NormLots(InpLots), _Symbol, 0.0, sl, tp, cm));
   if(ok && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED))
     {
      Notify(StringFormat("%s %.2f at market (%s) SL %s TP %s", (s.dir > 0 ? "BUY" : "SELL"), NormLots(InpLots), why,
                          DoubleToString(sl, _Digits), DoubleToString(tp, _Digits)));
      return true;
     }
   PrintFormat("FusionOliveEA: market %s failed %u %s", (s.dir > 0 ? "buy" : "sell"),
               trade.ResultRetcode(), trade.ResultRetcodeDescription());
   return false;
  }

// pending order at price p (limit = pullback leg, stop = breakout leg)
bool PlacePending(const EaSignal &s, const bool isStop, const double price)
  {
   double p = NormPrice(price);
   double sl, tp;
   bool breakLeg = (isStop && s.brk > 0.0 && MathAbs(price - s.brk) < _Point);
   Levels(s, (breakLeg ? 1 : 0), p, sl, tp);
   if(!LevelsValid(s.dir, p, sl, tp)) return false;
   double lots = NormLots(InpLots);
   string cm = (isStop ? "FusionOlive break" : "FusionOlive pullback");
   bool ok;
   if(s.dir > 0) ok = (isStop ? trade.BuyStop(lots, p, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cm)
                              : trade.BuyLimit(lots, p, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cm));
   else          ok = (isStop ? trade.SellStop(lots, p, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cm)
                              : trade.SellLimit(lots, p, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cm));
   if(ok && trade.ResultRetcode() == TRADE_RETCODE_DONE)
     {
      Notify(StringFormat("%s %s %.2f at %s SL %s TP %s", (s.dir > 0 ? "BUY" : "SELL"), (isStop ? "STOP" : "LIMIT"),
                          lots, DoubleToString(p, _Digits), DoubleToString(sl, _Digits), DoubleToString(tp, _Digits)));
      return true;
     }
   PrintFormat("FusionOliveEA: pending %s failed %u %s", cm, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   return false;
  }

// kind 1/4 in indicator mode: main entry (limit for kind 1, stop for kind 4) + breakout stop when the
// indicator runs the hybrid entry. A level the price already reached becomes a market entry.
void PlaceAsIndicator(const EaSignal &s)
  {
   double px = (s.dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID));
   double md = StopsDist();
   bool mainStop = (s.kind == 4);

   // breakout leg already triggered: the move is under way, enter now
   if(s.brk > 0.0 && (s.dir > 0 ? px >= s.brk - md : px <= s.brk + md))
     {
      EnterMarket(s, 1, "break passed");
      return;
     }
   if(s.entry > 0.0)
     {
      // limit: reached when the price came back to it; stop: reached when the price went through it
      bool reached = (mainStop ? (s.dir > 0 ? px >= s.entry - md : px <= s.entry + md)
                               : (s.dir > 0 ? px <= s.entry + md : px >= s.entry - md));
      if(reached)
        {
         EnterMarket(s, 0, (mainStop ? "stop passed" : "pullback reached"));
         return;
        }
     }
   bool placed = false;
   if(s.entry > 0.0 && PlacePending(s, mainStop, s.entry)) placed = true;
   if(s.brk > 0.0 && PlacePending(s, true, s.brk)) placed = true;
   if(placed) gPendSince = iTime(_Symbol, _Period, 0);
  }

void HandleSignal(const EaSignal &s)
  {
   string side = (s.dir > 0 ? "BUY" : "SELL");
   if(s.kind == 3)
     {
      if(OurPendingCount() > 0) { DeletePendings(s.dir); Notify(side + " pending orders cancelled by the indicator"); }
      return;
     }
   DrawDot(s.sigTime, s.dir);
   if(s.re && !InpTradeReentry) return;
   if((InpDirection == DIR_BUY && s.dir < 0) || (InpDirection == DIR_SELL && s.dir > 0)) return;

   ulong pt; int pdir;
   if(OurPosition(pt, pdir))
     {
      if(InpCloseOnOpposite && pdir == -s.dir)
        {
         ClosePosition(pt);
         Notify(side + " signal: opposite trade closed");
         if(OurPosition(pt, pdir)) return;   // close failed: still single trade
        }
      else
         return;                              // one trade at a time
     }
   DeletePendings(0);                         // a new signal replaces unfilled orders

   string why = "";
   if(!RiskAllows(why)) { Notify(side + " signal skipped: " + why); return; }

   if(s.kind == 2 || InpEntryMode == ENTRY_MARKET)
      EnterMarket(s, (s.kind == 2 && s.brk > 0.0 ? 1 : 0), (s.kind == 2 ? "filled on break" : "confirmed"));
   else
      PlaceAsIndicator(s);
  }

//+------------------------------------------------------------------+
//| Break-even / trailing / OCO / expiry                             |
//+------------------------------------------------------------------+
void ManagePosition()
  {
   ulong t; int dir;
   if(!OurPosition(t, dir)) return;
   if(OurPendingCount() > 0) DeletePendings(0);   // OCO: one leg filled, the other goes
   if(!InpBEOn && !InpTrailOn) return;
   if(!PositionSelectByTicket(t)) return;

   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl   = PositionGetDouble(POSITION_SL);
   double tp   = PositionGetDouble(POSITION_TP);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double px   = (dir > 0 ? bid : ask);
   double profitPts = dir * (px - open) / Pt();
   double md   = StopsDist();
   double best = sl;

   if(InpBEOn && profitPts >= InpBETriggerPts)
     {
      double c = NormPrice(open + dir * InpBELockPts * Pt());
      if(best == 0.0 || (dir > 0 ? c > best : c < best)) best = c;
     }
   if(InpTrailOn && profitPts >= InpTrailStartPts)
     {
      double c = NormPrice(px - dir * InpTrailDistPts * Pt());
      double step = MathMax(0, InpTrailStepPts) * Pt();
      bool farEnough = (sl == 0.0 || MathAbs(c - sl) >= step);
      if(farEnough && (best == 0.0 || (dir > 0 ? c > best : c < best))) best = c;
     }
   if(best == 0.0 || MathAbs(best - sl) < _Point / 2.0) return;
   if(dir > 0 ? best > bid - md : best < ask + md) return;   // too close to the price for the broker
   if(!trade.PositionModify(t, best, tp))
      PrintFormat("FusionOliveEA: SL move failed %u %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
  }

void ManagePendings()
  {
   if(InpPendExpireBars <= 0 || gPendSince == 0) return;
   if(OurPendingCount() == 0) { gPendSince = 0; return; }
   int age = iBarShift(_Symbol, _Period, gPendSince, false);
   if(age >= InpPendExpireBars)
     {
      DeletePendings(0);
      Notify("pending orders expired");
     }
  }

//+------------------------------------------------------------------+
void ShowPanel()
  {
   if(!InpShowPanel) return;
   static uint last = 0;                      // the history scan is not needed on every tick
   uint now = GetTickCount();
   if(last != 0 && (uint)(now - last) < 1000) return;
   last = now;
   ulong t; int dir;
   string pos = "none";
   if(OurPosition(t, dir) && PositionSelectByTicket(t))
      pos = StringFormat("%s %.2f @ %s  SL %s  TP %s  P/L %.2f", (dir > 0 ? "BUY" : "SELL"),
                         PositionGetDouble(POSITION_VOLUME),
                         DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), _Digits),
                         DoubleToString(PositionGetDouble(POSITION_SL), _Digits),
                         DoubleToString(PositionGetDouble(POSITION_TP), _Digits),
                         PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP));
   double pl; int opened;
   TodayStats(pl, opened);
   Comment(StringFormat("FusionOliveEA  |  magic %I64d  |  lots %.2f\n"
                        "Position: %s\nPending orders: %d\nToday: %d trades, closed P/L %.2f\n"
                        "Trailing %s  |  Break-even %s\nLast: %s",
                        InpMagic, NormLots(InpLots), pos, OurPendingCount(), opened, pl,
                        (InpTrailOn ? "on" : "off"), (InpBEOn ? "on" : "off"), gLastMsg));
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   ManagePosition();
   ManagePendings();

   if(IndicatorReady())
     {
      if(!gDotsDone) DrawHistoryDots();
      // one decision per closed bar, after the indicator has processed that bar
      datetime t1 = iTime(_Symbol, _Period, 1);
      if(t1 != 0 && t1 != gLastBar)
        {
         gLastBar = t1;
         EaSignal s;
         if(ReadSignal(1, s)) HandleSignal(s);
        }
     }
   ShowPanel();
  }

// notification when a trade of this EA closes
void OnTradeTransaction(const MqlTradeTransaction &tr, const MqlTradeRequest &rq, const MqlTradeResult &rs)
  {
   if(tr.type != TRADE_TRANSACTION_DEAL_ADD || tr.deal == 0) return;
   if(!HistoryDealSelect(tr.deal)) return;
   if(HistoryDealGetInteger(tr.deal, DEAL_MAGIC) != InpMagic || HistoryDealGetString(tr.deal, DEAL_SYMBOL) != _Symbol) return;
   long e = HistoryDealGetInteger(tr.deal, DEAL_ENTRY);
   if(e == DEAL_ENTRY_OUT || e == DEAL_ENTRY_OUT_BY)
     {
      double p = HistoryDealGetDouble(tr.deal, DEAL_PROFIT) + HistoryDealGetDouble(tr.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(tr.deal, DEAL_COMMISSION);
      Notify(StringFormat("trade closed at %s, P/L %.2f", DoubleToString(HistoryDealGetDouble(tr.deal, DEAL_PRICE), _Digits), p));
     }
   else if(e == DEAL_ENTRY_IN && OurPendingCount() > 0)
      DeletePendings(0);   // OCO as soon as one leg fills
  }
//+------------------------------------------------------------------+
