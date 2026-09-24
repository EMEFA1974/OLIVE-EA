#property copyright "CinnamonPro"
#property version   "1.50"
#property strict
#property description "CinnamonPro EA v1.5 — replica executor aligned to the indicator, optional SL-free grid."

#include <Trade/Trade.mqh>

enum ENUM_PEND_TYPE
  {
   PEND_LIMIT = 0,
   PEND_STOP  = 1
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
input ENUM_ENTRY_MODE InpEntryMode      = ENTRY_MARKET;
input double          InpConfirmShare   = 0.30;
input bool            InpPendingOn       = true;
input ENUM_PEND_TYPE  InpPendingType     = PEND_LIMIT;
input int             InpPendingPts      = 250;
input double          InpPendingRetrace  = 0.40;
input double          InpPendingATR      = 0.30;
input bool            InpPendingUseRange = true;
input int             InpPendingExpire   = 12;
input int             InpMinSLGapPts     = 15;
input bool            InpChaseIfMissed   = true;
input double          InpChaseTriggerR   = 0.20;
input double          InpChaseMaxR       = 0.45;
input double          InpNoAddR          = 0.35;

input group "=== Straddle Distance ==="
input bool   InpStraddleOn      = true;
input int    InpStraddlePts     = 550;
input double InpStraddleATR     = 0.35;
input int    InpStraddleStepPts = 20;
input double InpStraddleFreezeR = 0.15;

input group "=== SL / TP ==="
input int    InpSLBufferPts    = 200;
input double InpRR1            = 1.5;
input double InpRR2            = 3.0;
input int    InpTPOffsetPts    = 60;
input int    InpATRPeriod      = 14;
input double InpMinSLATR       = 1.50;
input int    InpMinSLPts       = 400;

input group "=== TP1 then TP2 leg ==="
input bool   InpLeg2On        = true;
input double InpLeg2RetraceR  = 0.40;
input int    InpLeg2Expire    = 16;
input double InpLeg2Share     = 0.50;

input group "=== Recovery after SL ==="
input bool   InpRecoverOn         = true;
input int    InpMaxRecover        = 1;
input int    InpRecoverOffsetPts  = 30;
input double InpRecoverATR        = 0.25;
input double InpRecoverRetrace    = 0.50;
input bool   InpRecoverUsePending = true;
input double InpRecoverShare      = 0.50;
input int    InpRecoverExpire     = 12;
input bool   InpRecoverNeedReclaim= true;
input bool   InpRecoverKeepTargets= true;
input double InpRecoverKillATR    = 0.30;

input group "=== Re-entry after SL ==="
input bool   InpReentryOn      = true;
input int    InpMaxReentry     = 2;
input int    InpReentryWindow  = 24;
input int    InpReentryCool    = 3;

input group "=== Money / Lot ==="
input double InpFixedLot        = 0.01;
input double InpRiskPercent     = 0.50;
input double InpATRLotMult      = 1.00;
input int    InpMagic           = 193194;
input int    InpDeviationPts    = 40;
input int    InpMaxSpreadPts    = 150;
input bool   InpTradeEnabled    = true;
input int    InpMaxRunningTrades= 1;     // cap when Grid is OFF (Grid ON uses Max Levels)

input group "=== Grid ==="
input bool   InpGridOn             = false;  // 1 ON/OFF. false = one replica trade + its SL/TP
input bool   InpGridStartFixedLot  = true;   // 2 true = first lot is FixedLot. false = ATR lot
input int    InpGridDistancePts    = 400;    // points between grid adds (fixed)
input bool   InpGridBasketTPOn     = true;   // 3 true = close basket at Basket TP. false = each ticket TP1
input int    InpGridBasketTPPts    = 250;    // basket target from average entry, points
input double InpGridMultiplier     = 1.50;   // lot of next add = previous * this
input int    InpGridMaxLevels      = 5;      // 4 max running trades when Grid is ON
input bool   InpGridNeedValidDir   = true;   // add next level only while HTF direction is valid

input group "=== Visuals ==="
input bool   InpShowZones     = true;
input bool   InpShowPanel     = true;
input color  InpBuyColor      = clrAqua;
input color  InpSellColor     = clrMagenta;
input color  InpReBuyColor    = clrGold;
input color  InpReSellColor   = clrYellow;
input color  InpZoneSL        = C'64,28,32';
input color  InpZoneTP1       = C'16,48,42';
input color  InpZoneTP2       = C'16,36,56';
input color  InpLineEntry     = C'200,200,200';
input color  InpLineSL        = C'220,90,96';
input color  InpLineTP1       = C'64,200,160';
input color  InpLineTP2       = C'64,150,220';
input color  InpLineBasketTP  = C'255,196,72';
input int    InpZoneRightBars = 18;      // box extends this many bars right of the current bar
input int    InpLineExtBars   = 16;      // levels continue past the box so labels sit on them
input ENUM_LINE_STYLE InpLineStyle = STYLE_DOT;
input int    InpLineWidth     = 1;
input int    InpLabelSize     = 8;
input string InpLabelFont     = "Consolas";
input bool   InpHollowObj     = true;
input int    InpHollowCodeUp  = 241;     // hollow signal arrow, Wingdings code
input int    InpHollowCodeDn  = 242;
input int    InpHollowWidth   = 1;
input double InpHollowOffATR  = 0.60;    // hollow arrow distance from wick, x ATR (digit independent)
input string InpPanelTitle    = "CINNAMON PRO EA";

#define PREFIX "CINEA_"
#define ZPRE   "CINEAZ_"

enum IdeaState { IDEA_IDLE = 0, IDEA_PENDING, IDEA_LIVE, IDEA_SL_WAIT };

struct Idea
  {
   IdeaState state;
   int       dir;
   double    entry, sl, tp1, tp2;
   double    origEntry, origSL, origTP2;
   double    riskEntry;
   datetime  signalTime, slTime, fillTime, artTime;
   datetime  zoneTime;          // bar where the current set of levels was armed
   int       reCount, slBarAge, pendAge;
   int       recoverCount;
   bool      tp1Done, re, leg2, recovering;
   bool      confirmClip, limitOpen, chased;
   double    oldSL, slWick;
   bool      firstSent;
  };

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

Idea     idea;
Idea     lastZone;
Bias     gD, gH4, gH1, gM5;
int      gScoreB = 0, gScoreS = 0;
int      gAtr = INVALID_HANDLE;
datetime lastBuyTime = 0, lastSellTime = 0;
datetime gLastClosedBar = 0;
CTrade   trade;
int      gPanelX = 12, gPanelY = 18;
bool     gAllowTrade = false;
bool     gWarmed     = false;
#define ARPRE "CINEAAR_"

//+------------------------------------------------------------------+
double UserPoint()
  {
   double p = _Point;
   if(p <= 0.0) p = 0.01;
   int d = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(d == 3 || d == 5) p *= 10.0;
   return p;
  }

double PointBuf() { return (double)InpSLBufferPts * UserPoint(); }

// Round to the broker tick: identical levels on 2- and 3-digit feeds and no
// "invalid price / invalid stops" rejections from unrounded values.
double NormPrice(const double p)
  {
   if(p <= 0.0) return p;
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0.0) ts = _Point;
   if(ts <= 0.0) return NormalizeDouble(p, _Digits);
   return NormalizeDouble(MathRound(p / ts) * ts, _Digits);
  }

void NormalizeIdea()
  {
   idea.entry = NormPrice(idea.entry);
   idea.sl    = NormPrice(idea.sl);
   idea.tp1   = NormPrice(idea.tp1);
   idea.tp2   = NormPrice(idea.tp2);
  }

// Inputs are in "user points" (0.01 on gold for both 2- and 3-digit feeds);
// convert to the broker's raw points where the terminal expects those.
int RawPoints(const int userPts)
  {
   if(_Point <= 0.0) return userPts;
   return (int)MathRound((double)userPts * UserPoint() / _Point);
  }

int DevPoints() { return RawPoints(InpDeviationPts); }

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

double NormalizeLot(double lot)
  {
   if(lot <= 0.0) return 0.0;
   double minl = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxl = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(minl <= 0.0) minl = 0.01;
   if(maxl <= 0.0) maxl = 100.0;
   if(step <= 0.0) step = 0.01;
   if(lot + 1e-12 < minl) lot = minl;
   if(lot > maxl) lot = maxl;
   int steps = (int)MathRound(lot / step);
   lot = steps * step;
   if(lot + 1e-12 < minl) lot = minl;
   if(lot > maxl) lot = maxl;
   int digits = 2;
   if(step >= 1.0) digits = 0;
   else if(step >= 0.1) digits = 1;
   else if(step >= 0.01) digits = 2;
   else if(step >= 0.001) digits = 3;
   else digits = 4;
   return NormalizeDouble(lot, digits);
  }

int MaxRunningAllowed()
  {
   if(InpGridOn) return MathMax(1, InpGridMaxLevels);
   return MathMax(1, InpMaxRunningTrades);
  }

bool RoomForNewTrade(const int extra = 1)
  {
   return (PositionsOurs() + PendingsOurs() + extra <= MaxRunningAllowed());
  }

double BasketTPPrice(const int dir)
  {
   double avg = WeightedAvg(dir);
   if(avg <= 0.0)
      avg = (idea.entry > 0.0 ? idea.entry : LastPosOpen(dir));
   if(avg <= 0.0) return 0.0;
   double dist = (double)InpGridBasketTPPts * UserPoint();
   if(dist <= 0.0) dist = 50.0 * UserPoint();
   if(dir > 0) return NormPrice(avg + dist);
   return NormPrice(avg - dist);
  }

double OrderSL(const double sl)
  {
   return sl;
  }

double OrderTP(const double tp1, const double tp2)
  {
   if(InpGridOn)
     {
      if(InpGridBasketTPOn) return BasketTPPrice(idea.dir);
      return tp1;
     }
   if(!InpLeg2On) return tp1;
   return tp2;
  }

ENUM_ORDER_TYPE_FILLING FillType()
  {
   long fm = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fm & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   if((fm & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
  }

double CurrentATR()
  {
   if(gAtr == INVALID_HANDLE) return 0.0;
   double a[];
   if(CopyBuffer(gAtr, 0, 1, 1, a) != 1) return 0.0;
   return a[0];
  }

double ATRLot(const double slDist)
  {
   double atr = CurrentATR();
   double dist = slDist;
   if(dist <= 0.0)
      dist = (atr > 0.0 ? atr * MathMax(0.20, InpATRLotMult) : InpMinSLPts * UserPoint());
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSz <= 0.0) tickSz = _Point;
   if(tickVal <= 0.0) tickVal = 1.0;
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   if(risk <= 0.0) risk = 1.0;
   double lossPerLot = (dist / tickSz) * tickVal;
   if(lossPerLot <= 0.0) return NormalizeLot(InpFixedLot);
   return NormalizeLot(risk / lossPerLot);
  }

double FirstLot()
  {
   if(!InpGridOn)
      return NormalizeLot(InpFixedLot);
   if(InpGridStartFixedLot)
      return NormalizeLot(InpFixedLot);
   return ATRLot(MathAbs(idea.entry - idea.sl));
  }

double GridLot(const int levelIndex)
  {
   double base = FirstLot();
   double mult = InpGridMultiplier;
   if(mult < 1.0) mult = 1.0;
   double lot = base * MathPow(mult, MathMax(0, levelIndex));
   return NormalizeLot(lot);
  }

bool SpreadOk()
  {
   if(InpMaxSpreadPts <= 0) return true;
   long spr = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spr <= RawPoints(InpMaxSpreadPts));
  }

int PositionsOurs(const int dir = 0)
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(dir > 0 && type != POSITION_TYPE_BUY) continue;
      if(dir < 0 && type != POSITION_TYPE_SELL) continue;
      n++;
     }
   return n;
  }

int PendingsOurs(const int dir = 0)
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      long type = OrderGetInteger(ORDER_TYPE);
      if(dir > 0 && type != ORDER_TYPE_BUY_LIMIT && type != ORDER_TYPE_BUY_STOP) continue;
      if(dir < 0 && type != ORDER_TYPE_SELL_LIMIT && type != ORDER_TYPE_SELL_STOP) continue;
      n++;
     }
   return n;
  }

double LastPosOpen(const int dir)
  {
   double px = 0;
   datetime newest = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(dir > 0 && type != POSITION_TYPE_BUY) continue;
      if(dir < 0 && type != POSITION_TYPE_SELL) continue;
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(t >= newest)
        {
         newest = t;
         px = PositionGetDouble(POSITION_PRICE_OPEN);
        }
     }
   return px;
  }

double WeightedAvg(const int dir)
  {
   double num = 0, den = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(dir > 0 && type != POSITION_TYPE_BUY) continue;
      if(dir < 0 && type != POSITION_TYPE_SELL) continue;
      double v = PositionGetDouble(POSITION_VOLUME);
      double p = PositionGetDouble(POSITION_PRICE_OPEN);
      num += p * v;
      den += v;
     }
   if(den <= 0.0) return 0.0;
   return num / den;
  }

double BasketProfit()
  {
   double p = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      p += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   return p;
  }

void DeletePendings(const int dir = 0)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      long type = OrderGetInteger(ORDER_TYPE);
      if(dir > 0 && type != ORDER_TYPE_BUY_LIMIT && type != ORDER_TYPE_BUY_STOP) continue;
      if(dir < 0 && type != ORDER_TYPE_SELL_LIMIT && type != ORDER_TYPE_SELL_STOP) continue;
      trade.OrderDelete(ticket);
     }
  }

void CloseAllOurs()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      trade.PositionClose(ticket);
     }
   DeletePendings();
  }

void PatchStops(const double sl, const double tp)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      double nsl = NormPrice(sl);
      double ntp = NormPrice(tp);
      if(MathAbs(curSL - nsl) < _Point && MathAbs(curTP - ntp) < _Point) continue;
      trade.PositionModify(ticket, nsl, ntp);
     }
  }

bool OpenMarket(const int dir, const double lot, const double slIn, const double tpIn, const string cmt)
  {
   double sl = NormPrice(slIn), tp = NormPrice(tpIn);
   double vol = NormalizeLot(lot);
   if(!gAllowTrade || !InpTradeEnabled || vol <= 0.0 || !SpreadOk()) return false;
   if(!RoomForNewTrade(1)) return false;
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(DevPoints());
   trade.SetTypeFilling(FillType());
   bool ok = false;
   if(dir > 0) ok = trade.Buy(vol, _Symbol, 0.0, sl, tp, cmt);
   else        ok = trade.Sell(vol, _Symbol, 0.0, sl, tp, cmt);
   if(!ok)
     {
      Print("OpenMarket retry without stops ", trade.ResultRetcode(), " ",
            trade.ResultRetcodeDescription(), " lot=", DoubleToString(vol, 2));
      if(dir > 0) ok = trade.Buy(vol, _Symbol, 0.0, 0.0, 0.0, cmt);
      else        ok = trade.Sell(vol, _Symbol, 0.0, 0.0, 0.0, cmt);
      if(ok && (sl > 0.0 || tp > 0.0))
         trade.PositionModify(_Symbol, sl, tp);
     }
   if(!ok)
      Print("OpenMarket failed ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription(),
            " lot=", DoubleToString(vol, 2), " sl=", sl, " tp=", tp);
   return ok;
  }

bool OpenPending(const int dir, const double lot, const double priceIn, const double slIn, const double tpIn, const string cmt)
  {
   double price = NormPrice(priceIn), sl = NormPrice(slIn), tp = NormPrice(tpIn);
   double vol = NormalizeLot(lot);
   if(!gAllowTrade || !InpTradeEnabled || vol <= 0.0 || price <= 0.0) return false;
   if(!RoomForNewTrade(1)) return false;
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(DevPoints());
   trade.SetTypeFilling(FillType());
   bool ok = false;
   if(dir > 0)
     {
      if(InpPendingType == PEND_LIMIT) ok = trade.BuyLimit(vol, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
      else                             ok = trade.BuyStop(vol, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
     }
   else
     {
      if(InpPendingType == PEND_LIMIT) ok = trade.SellLimit(vol, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
      else                             ok = trade.SellStop(vol, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
     }
   if(!ok)
      Print("OpenPending failed ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription(),
            " lot=", DoubleToString(vol, 2), " px=", price);
   return ok;
  }

void ResetIdea(const bool mitigated = true)
  {
   if(mitigated && gAllowTrade)
      DeletePendings();
   if(idea.signalTime != 0 && idea.entry > 0.0)
      lastZone = idea;
   idea.state = IDEA_IDLE;
   idea.dir = 0;
   idea.entry = idea.sl = idea.tp1 = idea.tp2 = 0;
   idea.origEntry = idea.origSL = idea.origTP2 = 0;
   idea.riskEntry = 0;
   idea.signalTime = idea.slTime = idea.fillTime = idea.artTime = 0;
   idea.zoneTime = 0;
   idea.reCount = idea.slBarAge = idea.pendAge = 0;
   idea.recoverCount = 0;
   idea.tp1Done = idea.re = idea.leg2 = idea.recovering = false;
   idea.confirmClip = idea.limitOpen = idea.chased = false;
   idea.oldSL = idea.slWick = 0;
   idea.firstSent = false;
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
   if(InpPendingATR > 0.0)
     {
      double a = CurrentATR();
      if(a > 0.0) byAtr = a * InpPendingATR;
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
   // Offset may only decorate the target; never shrink TP1 below the full RR1 distance.
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
   NormalizeIdea();
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
         if(InpPendingType == PEND_LIMIT) entry = bar.c - dist;
         else                             entry = bar.h + dist;
         if(entry <= sl + gap) entry = sl + gap;
        }
      else entry = bar.c;
      if(entry - sl < minPts) sl = entry - minPts;
      if(entry <= sl) return false;
     }
   else
     {
      sl = slAnchor + PointBuf();
      if(UsePending())
        {
         if(InpPendingType == PEND_LIMIT) entry = bar.c + dist;
         else                             entry = bar.l - dist;
         if(entry >= sl - gap) entry = sl - gap;
        }
      else entry = bar.c;
      if(sl - entry < minPts) sl = entry + minPts;
      if(entry >= sl) return false;
     }
   return true;
  }

string CmtMain() { return idea.re ? "CIN-RE" : (idea.recovering ? "CIN-RC" : "CIN"); }
string CmtGrid() { return "CIN-GRID"; }

void PlaceGridLadder()
  {
   if(!InpGridOn || !gAllowTrade || idea.dir == 0) return;
   double gap = (double)InpGridDistancePts * UserPoint();
   if(gap <= 0.0) return;
   double sl = OrderSL(idea.sl);
   double tp = OrderTP(idea.tp1, idea.tp2);
   double base = (idea.entry > 0.0 ? idea.entry : LastPosOpen(idea.dir));
   if(base <= 0.0) return;
   int have = PositionsOurs(idea.dir) + PendingsOurs(idea.dir);
   int maxn = MaxRunningAllowed();
   for(int lvl = 1; have < maxn && lvl < maxn; lvl++)
     {
      double px = NormPrice(idea.dir > 0 ? base - gap * lvl : base + gap * lvl);
      double lot = GridLot(lvl);
      if(lot <= 0.0) break;
      if(idea.dir > 0)
         trade.BuyLimit(lot, px, _Symbol, sl, tp, ORDER_TIME_GTC, 0, CmtGrid());
      else
         trade.SellLimit(lot, px, _Symbol, sl, tp, ORDER_TIME_GTC, 0, CmtGrid());
      have++;
     }
  }

void SendReplicaOrders(const bool marketClip, const bool leaveLimit)
  {
   if(idea.firstSent) return;
   idea.firstSent = true;
   if(!gAllowTrade) return;
   if(!RoomForNewTrade(1)) return;

   double sl = OrderSL(idea.sl);
   double tp = OrderTP(idea.tp1, idea.tp2);
   double full = NormalizeLot(FirstLot());
   if(full <= 0.0)
     {
      Print("Fixed/ATR lot normalized to 0. Check InpFixedLot vs broker min lot.");
      return;
     }

   if(InpGridOn)
     {
      if(PositionsOurs(idea.dir) == 0)
         OpenMarket(idea.dir, full, sl, tp, CmtMain());
      PlaceGridLadder();
      return;
     }

   double share = ConfirmShare();
   if(idea.recovering) share = (InpRecoverUsePending ? 0.0 : 1.0);
   if(idea.leg2) share = 0.0;
   if(!leaveLimit) share = 1.0;
   if(!marketClip) share = 0.0;

   double minl = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(minl <= 0.0) minl = 0.01;
   double clip = NormalizeLot(full * share);
   double rest = NormalizeLot(full - clip);
   if(clip > 0.0 && clip < minl) { clip = 0.0; rest = full; }
   if(rest > 0.0 && rest < minl) { rest = 0.0; clip = full; }
   if(clip <= 0.0 && rest <= 0.0) { clip = full; rest = 0.0; }

   if(marketClip && clip >= minl)
      OpenMarket(idea.dir, clip, sl, tp, CmtMain());
   if(leaveLimit && rest >= minl)
      OpenPending(idea.dir, rest, idea.entry, sl, tp, CmtMain());
   else if(!marketClip && clip < minl && rest < minl)
      OpenPending(idea.dir, full, idea.entry, sl, tp, CmtMain());
  }

void ArmIdea(const int dir, const Candle &bar, const bool re, const double slAnchor)
  {
   double entry = 0, sl = 0;
   if(!BuildPendingPrices(dir, bar, slAnchor, entry, sl))
     {
      ResetIdea();
      return;
     }
   if(InpMinSLATR > 0.0)
     {
      double atr = CurrentATR();
      if(atr > 0.0 && MathAbs(entry - sl) < atr * InpMinSLATR)
        {
         if(dir > 0) sl = entry - atr * InpMinSLATR;
         else        sl = entry + atr * InpMinSLATR;
        }
     }
   idea.signalTime = bar.t;
   idea.zoneTime = bar.t;
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
   idea.firstSent = false;
   ApplyLevels(dir, entry, sl);
   idea.origEntry = idea.entry;
   idea.origSL    = idea.sl;
   idea.origTP2   = idea.tp2;
   idea.riskEntry = bar.c;
   lastZone = idea;

   double share = ConfirmShare();
   if(!UsePending() || share >= 0.999)
     {
      idea.state = IDEA_LIVE;
      idea.fillTime = bar.t;
      idea.entry = bar.c;
      idea.confirmClip = true;
      idea.limitOpen = false;
      SendReplicaOrders(true, false);
     }
   else
     {
      idea.limitOpen = true;
      if(share > 0.0)
        {
         idea.state = IDEA_LIVE;
         idea.fillTime = bar.t;
         idea.confirmClip = true;
         SendReplicaOrders(true, true);
        }
      else
        {
         idea.state = IDEA_PENDING;
         SendReplicaOrders(false, true);
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
   double atr = CurrentATR();
   if(InpStraddleATR > 0.0 && atr > 0.0)
      g = MathMax(g, atr * InpStraddleATR);
   if(g <= 0.0) g = 10.0 * UserPoint();
   return g;
  }

void ModifyOurPendings(const double newPrice)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      string cmt = OrderGetString(ORDER_COMMENT);
      if(StringFind(cmt, "GRID") >= 0) continue;
      double sl = OrderGetDouble(ORDER_SL);
      double tp = OrderGetDouble(ORDER_TP);
      long type = OrderGetInteger(ORDER_TYPE);
      if(type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP ||
         type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP)
         trade.OrderModify(ticket, NormPrice(newPrice), sl, tp, ORDER_TIME_GTC, 0);
     }
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
      desired = (idea.dir > 0 ? price - gap : price + gap);
   else
      desired = (idea.dir > 0 ? price + gap : price - gap);

   double delta = desired - idea.entry;
   bool away = false;
   if(InpPendingType == PEND_LIMIT)
      away = (idea.dir > 0 ? delta > step : delta < -step);
   else
      away = (idea.dir > 0 ? delta < -step : delta > step);

   if(away)
     {
      idea.entry = NormPrice(idea.entry + delta);
      ModifyOurPendings(idea.entry);
     }
  }

double RecoverOffsetInd()
  {
   double byPts = (double)InpRecoverOffsetPts * UserPoint();
   double byAtr = 0.0;
   double a = CurrentATR();
   if(InpRecoverATR > 0.0 && a > 0.0) byAtr = a * InpRecoverATR;
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
   if(pend > 0.0) d = MathMax(d, pend);
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

   // Park recovery at / just inside the old SL — not next to current price.
   double inside = MathMax(gap, (double)InpRecoverOffsetPts * UserPoint());
   if(idea.dir > 0)
     {
      double wick = idea.slWick;
      if(wick <= 0.0 || wick > oldSL) wick = MathMin(bar.l, oldSL);
      newSL = MathMin(wick, oldSL) - PointBuf();
      newEntry = oldSL + inside;
      if(newEntry <= newSL + gap) newEntry = newSL + gap;
     }
   else
     {
      double wick = idea.slWick;
      if(wick <= 0.0 || wick < oldSL) wick = MathMax(bar.h, oldSL);
      newSL = MathMax(wick, oldSL) + PointBuf();
      newEntry = oldSL - inside;
      if(newEntry >= newSL - gap) newEntry = newSL - gap;
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
   idea.firstSent   = false;

   if(InpRecoverKeepTargets && keepTP2 > 0.0)
     {
      idea.tp1 = keepTP1;
      idea.tp2 = keepTP2;
     }
   else
      ApplyLevels(idea.dir, idea.entry, idea.sl);

   NormalizeIdea();
   idea.riskEntry = idea.entry;
   idea.zoneTime  = bar.t;
   idea.state = IDEA_PENDING;
   SendReplicaOrders(false, true);
  }

void ArmLeg2(const datetime barTime)
  {
   if(!InpLeg2On || idea.dir == 0 || InpGridOn)
     {
      if(!InpGridOn) ResetIdea();
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
   idea.firstSent = false;
   idea.zoneTime  = barTime;
   NormalizeIdea();
   idea.state     = IDEA_PENDING;
   double lot = NormalizeLot(FirstLot() * InpLeg2Share);
   double tp = idea.tp2;
   OpenPending(idea.dir, lot, idea.entry, idea.sl, tp, "CIN-L2");
   idea.firstSent = true;
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
   DeletePendings();
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

bool DirectionStillValid()
  {
   if(idea.dir == 0) return false;
   return StructureAllows(idea.dir, gD, gH4, gH1, gScoreB, gScoreS);
  }

void ManageGrid()
  {
   if(!InpGridOn || idea.dir == 0) return;
   int live = PositionsOurs(idea.dir);
   if(live <= 0) return;

   PatchStops(OrderSL(idea.sl), OrderTP(idea.tp1, idea.tp2));

   if(InpGridBasketTPOn)
     {
      double avg = WeightedAvg(idea.dir);
      double dist = (double)InpGridBasketTPPts * UserPoint();
      if(dist > 0.0 && avg > 0.0)
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         bool hit = (idea.dir > 0 ? bid >= avg + dist : ask <= avg - dist);
         if(hit)
           {
            CloseAllOurs();
            ResetIdea(false);
            return;
           }
        }
     }

   if(InpGridNeedValidDir && !DirectionStillValid())
     {
      DeletePendings(idea.dir);
      return;
     }

   if(live + PendingsOurs(idea.dir) >= MaxRunningAllowed()) return;
   PlaceGridLadder();
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
      if(idea.recovering) exp = 100000;   // recovery pending lives until TP1
      if(idea.pendAge > exp)
        {
         if(idea.confirmClip)
           {
            idea.limitOpen = false;
            idea.chased = true;
            DeletePendings();
           }
         else
           {
            ResetIdea();
            return;
           }
        }

      if(!idea.recovering)
         ApplyStraddle(bar.c);

      if(!idea.recovering)
        {
         if(idea.dir > 0 && (d.dir < 0 || h4.dir < 0)) { ResetIdea(); return; }
         if(idea.dir < 0 && (d.dir > 0 || h4.dir > 0)) { ResetIdea(); return; }
        }

      if(idea.recovering)
        {
         bool hitTP1rec = (idea.dir > 0 ? (bar.h >= idea.tp1) : (bar.l <= idea.tp1));
         if(hitTP1rec)
           {
            DeletePendings();
            idea.recovering = false;
            idea.limitOpen = false;
            ResetIdea(false);
            return;
           }
        }

      double rBar = FavorRBar(bar);
      if(idea.limitOpen && idea.confirmClip && !idea.recovering && rBar >= InpNoAddR)
        {
         idea.limitOpen = false;
         idea.chased = true;
         DeletePendings();
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
            if(PositionsOurs(idea.dir) == 0)
               OpenMarket(idea.dir, FirstLot(), idea.sl,
                          (InpGridOn && InpGridBasketTPOn) ? 0.0 : idea.tp2, CmtMain());
           }
        }
      else if(TouchedLevel(bar, idea.entry) || PositionsOurs(idea.dir) > 0)
        {
         idea.state = IDEA_LIVE;
         if(idea.fillTime == 0) idea.fillTime = bar.t;
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

   if(InpGridOn)
      return;

   if(PositionsOurs() == 0 && PendingsOurs() == 0 && idea.state == IDEA_LIVE && !idea.limitOpen)
     {
      if(hitSL) { NoteStopHit(bar); return; }
      if(hitTP2) { ResetIdea(false); return; }
      if(hitTP1 && InpLeg2On && !idea.leg2) { ArmLeg2(bar.t); return; }
      if(hitTP1) { ResetIdea(false); return; }
     }

   if(idea.state == IDEA_LIVE && hitSL && PositionsOurs() == 0)
     {
      NoteStopHit(bar);
      if(!InpRecoverOn && !InpReentryOn) ResetIdea();
      return;
     }

   if(idea.state == IDEA_LIVE && hitTP2 && !InpGridOn)
     {
      idea.tp1Done = true;
      CloseAllOurs();
      ResetIdea(false);
      return;
     }

   if(idea.state == IDEA_LIVE && hitTP1 && !idea.tp1Done && !InpGridOn)
     {
      idea.tp1Done = true;
      if(InpLeg2On && !idea.leg2)
        {
         // leave runner logic to broker SL/TP; arm pullback leg
         ArmLeg2(bar.t);
         return;
        }
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

void ClearZones()
  {
   ObjectsDeleteAll(0, ZPRE);
  }

// Distance of the hollow arrow from the wick. ATR based so it looks the same
// on 2-digit and 3-digit feeds (raw points would differ by 10x).
double ArrowGap(const datetime t, const double hi, const double lo)
  {
   double atr = 0.0;
   if(gAtr != INVALID_HANDLE)
     {
      double a[];
      if(CopyBuffer(gAtr, 0, t, 1, a) == 1 && a[0] > 0.0 && a[0] != EMPTY_VALUE)
         atr = a[0];
     }
   if(atr <= 0.0) atr = hi - lo;
   if(atr <= 0.0) atr = 10.0 * UserPoint();
   return atr * MathMax(0.0, InpHollowOffATR);
  }

// Hollow (outlined) signal arrow. These are never removed with the zones, so
// every past signal keeps its arrow.
void HollowArrow(const datetime t, const double hi, const double lo, const int dir, const color clr, const bool re)
  {
   if(!InpHollowObj || t == 0 || hi <= 0.0 || lo <= 0.0) return;
   string name = ARPRE + IntegerToString((long)t) + (dir > 0 ? "_U" : "_D") + (re ? "R" : "");
   double gap = ArrowGap(t, hi, lo);
   double price = (dir > 0 ? lo - gap : hi + gap);
   if(ObjectFind(0, name) < 0)
      if(!ObjectCreate(0, name, OBJ_ARROW, 0, t, price))
         return;
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, dir > 0 ? InpHollowCodeUp : InpHollowCodeDn);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, MathMax(1, InpHollowWidth));
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, dir > 0 ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

void PutRect(const string name, datetime t1, double p1, datetime t2, double p2, color fill)
  {
   if(t1 <= 0 || p1 <= 0.0 || p2 <= 0.0) return;
   if(t2 <= t1) t2 = t1 + PeriodSeconds(_Period) * 20;
   if(ObjectFind(0, name) < 0)
      if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2))
         return;
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
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
  }

// Thin dotted level that stops a few bars past the box (no ray), so the
// label drawn at the box edge sits on it.
void PutLine(const string name, datetime t1, datetime t2, double price, color clr)
  {
   if(t1 <= 0 || price <= 0.0) return;
   if(t2 <= t1) t2 = t1 + PeriodSeconds(_Period) * 20;
   if(ObjectFind(0, name) < 0)
      if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price))
         return;
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, InpLineStyle);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, MathMax(1, InpLineWidth));
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 2);
  }

// Label anchored by its lower-left corner on the level price: the text sits
// on top of the line. Updated in place (no delete/re-create) to avoid flicker.
void PutLabel(const string name, datetime t, double price, const string text, color clr)
  {
   if(price <= 0.0 || t <= 0) return;
   if(ObjectFind(0, name) < 0)
      if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price))
         return;
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   if(ObjectGetString(0, name, OBJPROP_TEXT) != text)
      ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, MathMax(6, InpLabelSize));
   ObjectSetString(0, name, OBJPROP_FONT, InpLabelFont);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
  }

string PriceText(const double p)
  {
   return DoubleToString(NormPrice(p), _Digits);
  }

// Only the idea that is pending or live is drawn. Anything else (idle,
// SL hit / waiting) wipes every zone object, so nothing is left behind.
void DrawLiveZone()
  {
   Idea z = idea;
   bool active = (z.state == IDEA_PENDING || z.state == IDEA_LIVE);
   if(!InpShowZones || !active || z.dir == 0 || z.signalTime == 0
      || z.entry <= 0.0 || z.sl <= 0.0 || z.tp1 <= 0.0 || z.tp2 <= 0.0)
     {
      ClearZones();
      return;
     }

   int ps = PeriodSeconds(_Period);
   datetime t1 = (z.zoneTime > 0 ? z.zoneTime : z.signalTime);
   datetime nowT = iTime(_Symbol, _Period, 0);
   if(nowT <= 0) nowT = TimeCurrent();
   datetime tBox = nowT + (datetime)MathMax(2, InpZoneRightBars) * ps;
   if(tBox <= t1) tBox = t1 + (datetime)10 * ps;
   datetime tLab = tBox + ps;
   datetime tEnd = tBox + (datetime)MathMax(4, InpLineExtBars) * ps;

   PutRect(ZPRE+"ZSL0", t1, z.entry, tBox, z.sl,  InpZoneSL);
   PutRect(ZPRE+"ZT10", t1, z.entry, tBox, z.tp1, InpZoneTP1);
   PutRect(ZPRE+"ZT20", t1, z.tp1,   tBox, z.tp2, InpZoneTP2);

   PutLine(ZPRE+"LEN0", t1, tEnd, z.entry, InpLineEntry);
   PutLine(ZPRE+"LSL0", t1, tEnd, z.sl,    InpLineSL);
   PutLine(ZPRE+"LT10", t1, tEnd, z.tp1,   InpLineTP1);
   PutLine(ZPRE+"LT20", t1, tEnd, z.tp2,   InpLineTP2);

   string tag = "";
   if(InpGridOn)    tag += " GRID";
   if(z.recovering) tag += " RC";
   else if(z.re)    tag += " RE";
   if(z.state == IDEA_PENDING)
     {
      if(z.recovering) tag += " [REC LIMIT]";
      else tag += (z.leg2 ? " [L2 LIMIT]" : (InpPendingType == PEND_LIMIT ? " [LIMIT]" : " [STOP]"));
     }
   if(z.state == IDEA_LIVE) tag += " [FILLED]";

   PutLabel(ZPRE+"NEN0", tLab, z.entry, "Entry  " + PriceText(z.entry) + tag, InpLineEntry);
   PutLabel(ZPRE+"NSL0", tLab, z.sl,    "SL  "    + PriceText(z.sl),         InpLineSL);
   PutLabel(ZPRE+"NT10", tLab, z.tp1,   "TP1  "   + PriceText(z.tp1),        InpLineTP1);
   PutLabel(ZPRE+"NT20", tLab, z.tp2,   "TP2  "   + PriceText(z.tp2),        InpLineTP2);

   double btp = 0.0;
   if(InpGridOn && InpGridBasketTPOn)
      btp = BasketTPPrice(z.dir);
   if(btp > 0.0)
     {
      PutLine(ZPRE+"LBTP", t1, tEnd, btp, InpLineBasketTP);
      PutLabel(ZPRE+"NBTP", tLab, btp, "Basket TP  " + PriceText(btp), InpLineBasketTP);
     }
   else
     {
      ObjectDelete(0, ZPRE+"LBTP");
      ObjectDelete(0, ZPRE+"NBTP");
     }

   ChartRedraw(0);
  }

void DrawPanel()
  {
   if(!InpShowPanel) return;
   const int w = 230, h = 18;
   int x = gPanelX, y = gPanelY;
   if(ObjectFind(0, PREFIX+"BG") < 0)
      ObjectCreate(0, PREFIX+"BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PREFIX+"BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, PREFIX+"BG", OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, PREFIX+"BG", OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, PREFIX+"BG", OBJPROP_XSIZE, w);
   ObjectSetInteger(0, PREFIX+"BG", OBJPROP_YSIZE, 16 * h + 12);
   ObjectSetInteger(0, PREFIX+"BG", OBJPROP_BGCOLOR, C'8,12,20');
   ObjectSetInteger(0, PREFIX+"BG", OBJPROP_BORDER_COLOR, C'28,40,56');
   ObjectSetInteger(0, PREFIX+"BG", OBJPROP_BACK, false);

   string rows[16];
   string st = "WAIT";
   if(idea.state == IDEA_PENDING) st = (idea.dir > 0 ? "PEND LONG" : "PEND SHORT");
   if(idea.state == IDEA_LIVE)    st = (idea.dir > 0 ? "LIVE LONG" : "LIVE SHORT");
   if(idea.state == IDEA_SL_WAIT) st = "SL WAIT";
   rows[0] = InpPanelTitle + "  v1.5";
   rows[1] = _Symbol + "  " + EnumToString(_Period);
   rows[2] = "State   " + st;
   rows[3] = "Lot     " + DoubleToString(FirstLot(), 2) + (InpGridOn && !InpGridStartFixedLot ? " ATR" : " FIX");
   rows[4] = "Grid    " + string(InpGridOn ? "ON" : "OFF") + "  x" + DoubleToString(InpGridMultiplier, 2);
   rows[5] = "GridDist " + IntegerToString(InpGridDistancePts) + " pts";
   rows[6] = "BasketTP " + string(InpGridBasketTPOn ? "ON" : "TP1");
   rows[7] = "Pos/Pend " + IntegerToString(PositionsOurs()) + " / " + IntegerToString(PendingsOurs());
   rows[8] = "D1/H4/H1 " + IntegerToString(gD.dir) + " " + IntegerToString(gH4.dir) + " " + IntegerToString(gH1.dir);
   rows[9] = "Align B/S " + IntegerToString(gScoreB) + " / " + IntegerToString(gScoreS);
   rows[10] = "Entry  " + (idea.entry > 0 ? DoubleToString(idea.entry, _Digits) : "-");
   rows[11] = "SL     " + (idea.sl > 0 ? DoubleToString(idea.sl, _Digits) : "-");
   rows[12] = "TP1    " + (idea.tp1 > 0 ? DoubleToString(idea.tp1, _Digits) : "-");
   rows[13] = "TP2    " + (idea.tp2 > 0 ? DoubleToString(idea.tp2, _Digits) : "-");
   rows[14] = "Spread " + DoubleToString((double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point / UserPoint(), 1) + " pts";
   rows[15] = InpTradeEnabled ? "TRADE ON" : "TRADE OFF";

   for(int i = 0; i < 16; i++)
     {
      string nm = PREFIX + "R" + IntegerToString(i);
      if(ObjectFind(0, nm) < 0)
         ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x + 8);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y + 6 + i * h);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, (i == 0 ? clrGold : clrWhite));
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, nm, OBJPROP_FONT, "Consolas");
      ObjectSetString(0, nm, OBJPROP_TEXT, rows[i]);
     }
  }

void ReplayHistory()
  {
   MqlRates r[];
   int n = CopyRates(_Symbol, _Period, 0, 800, r);
   if(n < 40) return;
   ArraySetAsSeries(r, true);
   bool savedTrade = gAllowTrade;
   gAllowTrade = false;
   ObjectsDeleteAll(0, ARPRE);   // arrows are rebuilt by the replay
   ClearZones();
   lastBuyTime = lastSellTime = 0;
   ResetIdea();
   int start = MathMin(n - 5, 800);
   for(int i = start; i >= 1; i--)
     {
      Candle bar;
      bar.o = r[i].open; bar.h = r[i].high; bar.l = r[i].low; bar.c = r[i].close;
      bar.t = r[i].time; bar.valid = true;

      Bias d  = TFBiasAt(InpTF_D,  bar.t);
      Bias h4 = TFBiasAt(InpTF_H4, bar.t);
      Bias h1 = TFBiasAt(InpTF_H1, bar.t);
      Bias m5 = TFBiasAt(InpTF_M5, bar.t);
      int sb = (d.dir==1) + (h4.dir==1) + (h1.dir==1) + (m5.dir==1);
      int ss = (d.dir==-1) + (h4.dir==-1) + (h1.dir==-1) + (m5.dir==-1);

      ManageIdea(bar, d, h4);

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
            if(idea.recovering)
               HollowArrow(bar.t, bar.h, bar.l, idea.dir, (idea.dir > 0 ? InpReBuyColor : InpReSellColor), true);
           }
        }

      double prevH = r[i].high, prevL = r[i].low;
      int lookTo = MathMin(n - 1, i + InpSwingLook);
      for(int k = i + 1; k <= lookTo; k++)
        {
         if(r[k].high > prevH) prevH = r[k].high;
         if(r[k].low  < prevL) prevL = r[k].low;
        }
      double slLo = r[i].low, slHi = r[i].high;
      int slTo = MathMin(n - 1, i + InpSLSwingLook);
      for(int k = i; k <= slTo; k++)
        {
         if(r[k].low  < slLo) slLo = r[k].low;
         if(r[k].high > slHi) slHi = r[k].high;
        }

      bool trigB = QualityBullTrigger(bar, prevH);
      bool trigS = QualityBearTrigger(bar, prevL);
      bool allowB = StructureAllows(1, d, h4, h1, sb, ss);
      bool allowS = StructureAllows(-1, d, h4, h1, sb, ss);

      bool didRe = false;
      if(InpReentryOn && idea.state == IDEA_SL_WAIT && idea.reCount < InpMaxReentry
         && idea.slBarAge >= InpReentryCool && !idea.recovering && !recoverBusy)
        {
         if(idea.dir > 0 && trigB && allowB)
           {
            int rc = idea.reCount + 1;
            ArmIdea(1, bar, true, slLo);
            idea.reCount = rc;
            lastBuyTime = bar.t;
            HollowArrow(bar.t, bar.h, bar.l, 1, InpReBuyColor, true);
            didRe = true;
           }
         else if(idea.dir < 0 && trigS && allowS)
           {
            int rc = idea.reCount + 1;
            ArmIdea(-1, bar, true, slHi);
            idea.reCount = rc;
            lastSellTime = bar.t;
            HollowArrow(bar.t, bar.h, bar.l, -1, InpReSellColor, true);
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
            lastBuyTime = bar.t;
            ArmIdea(1, bar, false, slLo);
            HollowArrow(bar.t, bar.h, bar.l, 1, InpBuyColor, false);
           }
         else if(free && trigS && allowS && coolS)
           {
            lastSellTime = bar.t;
            ArmIdea(-1, bar, false, slHi);
            HollowArrow(bar.t, bar.h, bar.l, -1, InpSellColor, false);
           }
        }
     }
   if(idea.signalTime != 0 && idea.entry > 0.0)
      lastZone = idea;
   gAllowTrade = savedTrade;
   gLastClosedBar = r[0].time;
  }

void ProcessClosedBar()
  {
   MqlRates r[];
   if(CopyRates(_Symbol, _Period, 1, InpSLSwingLook + 8, r) < InpSLSwingLook + 3)
      return;
   ArraySetAsSeries(r, true);

   Candle bar;
   bar.o = r[0].open; bar.h = r[0].high; bar.l = r[0].low; bar.c = r[0].close;
   bar.t = r[0].time; bar.valid = true;

   Bias d  = TFBiasAt(InpTF_D,  bar.t);
   Bias h4 = TFBiasAt(InpTF_H4, bar.t);
   Bias h1 = TFBiasAt(InpTF_H1, bar.t);
   Bias m5 = TFBiasAt(InpTF_M5, bar.t);
   int sb = (d.dir==1) + (h4.dir==1) + (h1.dir==1) + (m5.dir==1);
   int ss = (d.dir==-1) + (h4.dir==-1) + (h1.dir==-1) + (m5.dir==-1);

   ManageIdea(bar, d, h4);

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
         if(idea.recovering)
            HollowArrow(bar.t, bar.h, bar.l, idea.dir, (idea.dir > 0 ? InpReBuyColor : InpReSellColor), true);
        }
     }

   double prevH = r[1].high;
   double prevL = r[1].low;
   int look = MathMin(InpSwingLook, ArraySize(r) - 2);
   for(int k = 1; k <= look; k++)
     {
      if(r[k].high > prevH) prevH = r[k].high;
      if(r[k].low  < prevL) prevL = r[k].low;
     }
   double slLo = bar.l, slHi = bar.h;
   int slTo = MathMin(InpSLSwingLook, ArraySize(r) - 1);
   for(int k = 0; k <= slTo; k++)
     {
      if(r[k].low  < slLo) slLo = r[k].low;
      if(r[k].high > slHi) slHi = r[k].high;
     }

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

   bool didRe = false;
   if(InpReentryOn && idea.state == IDEA_SL_WAIT && idea.reCount < InpMaxReentry
      && idea.slBarAge >= InpReentryCool
      && !idea.recovering && !recoverBusy)
     {
      if(idea.dir > 0 && trigB && allowB)
        {
         int rc = idea.reCount + 1;
         ArmIdea(1, bar, true, slLo);
         idea.reCount = rc;
         lastBuyTime = bar.t;
         HollowArrow(bar.t, bar.h, bar.l, 1, InpReBuyColor, true);
         didRe = true;
        }
      else if(idea.dir < 0 && trigS && allowS)
        {
         int rc = idea.reCount + 1;
         ArmIdea(-1, bar, true, slHi);
         idea.reCount = rc;
         lastSellTime = bar.t;
         HollowArrow(bar.t, bar.h, bar.l, -1, InpReSellColor, true);
         didRe = true;
        }
     }

   if(!didRe)
     {
      bool coolB = Cooled(bar.t, lastBuyTime, InpCooldown) && Cooled(bar.t, lastSellTime, 3);
      bool coolS = Cooled(bar.t, lastSellTime, InpCooldown) && Cooled(bar.t, lastBuyTime, 3);
      bool free = (idea.state == IDEA_IDLE);
      if(gAllowTrade)
         free = free && RoomForNewTrade(1);

      if(free && trigB && allowB && coolB)
        {
         lastBuyTime = bar.t;
         ArmIdea(1, bar, false, slLo);
         HollowArrow(bar.t, bar.h, bar.l, 1, InpBuyColor, false);
        }
      else if(free && trigS && allowS && coolS)
        {
         lastSellTime = bar.t;
         ArmIdea(-1, bar, false, slHi);
         HollowArrow(bar.t, bar.h, bar.l, -1, InpSellColor, false);
        }
     }
  }

int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(DevPoints());
   trade.SetTypeFilling(FillType());
   if(gAtr != INVALID_HANDLE) IndicatorRelease(gAtr);
   gAtr = iATR(_Symbol, _Period, InpATRPeriod);
   ResetIdea();
   gAllowTrade = false;
   gWarmed = false;
   gLastClosedBar = 0;
   Print("CinnamonPro EA v1.5 init | fixed lot asked=", DoubleToString(InpFixedLot, 2),
         " norm=", DoubleToString(NormalizeLot(InpFixedLot), 2),
         " min=", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), 2),
         " | grid ", (InpGridOn ? "ON" : "OFF"),
         " | max running ", MaxRunningAllowed());
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(gAtr != INVALID_HANDLE) IndicatorRelease(gAtr);
   gAtr = INVALID_HANDLE;
   ObjectsDeleteAll(0, PREFIX);
   ObjectsDeleteAll(0, ZPRE);
   ObjectsDeleteAll(0, ARPRE);
  }

void OnTick()
  {
   gD  = TFBiasNow(InpTF_D);
   gH4 = TFBiasNow(InpTF_H4);
   gH1 = TFBiasNow(InpTF_H1);
   gM5 = TFBiasNow(InpTF_M5);
   gScoreB = (gD.dir==1) + (gH4.dir==1) + (gH1.dir==1) + (gM5.dir==1);
   gScoreS = (gD.dir==-1) + (gH4.dir==-1) + (gH1.dir==-1) + (gM5.dir==-1);

   if(!gWarmed)
     {
      ReplayHistory();
      gAllowTrade = true;
      gWarmed = true;
      if(idea.state != IDEA_IDLE && idea.dir != 0 && PositionsOurs() == 0 && PendingsOurs() == 0)
        {
         idea.firstSent = false;
         SendReplicaOrders(idea.state == IDEA_LIVE, idea.limitOpen || idea.state == IDEA_PENDING);
        }
     }

   datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 != 0 && t0 != gLastClosedBar)
     {
      gLastClosedBar = t0;
      ProcessClosedBar();
     }

   if((idea.limitOpen || idea.state == IDEA_PENDING) && !idea.recovering && !idea.leg2)
      ApplyStraddle(SymbolInfoDouble(_Symbol, SYMBOL_BID));

   if(idea.state == IDEA_LIVE)
     {
      ManageGrid();
      if(!InpGridOn && idea.sl > 0.0)
         PatchStops(OrderSL(idea.sl), OrderTP(idea.tp1, idea.tp2));
     }

   if(idea.signalTime != 0 && idea.entry > 0.0)
      lastZone = idea;

   DrawPanel();
   DrawLiveZone();
  }
//+------------------------------------------------------------------+
