//+------------------------------------------------------------------+
//| WildOliveEA_Update.mq5                                           |
//| Copyright 2025, Crispin Tibilla                                  |
//| Quality-over-quantity update of Wild Olive EA v1.14              |
//|  - Closed-candle signals, M15 trend veto, EMA21 pullback entry    |
//|  - RSI exhaustion: wait for pullback after RSI 70 / 30            |
//|  - Spread / session / volatility filters                          |
//|  - Breakeven + 2-step trailing (main trade and grid basket)       |
//|  - Capped grid: ATR step, reversal-confirmed adds, basket stop    |
//|  - Circuit breakers: cooldown, 1-hour pause after any loss       |
//|    (losing basket or account drawdown stop)                       |
//| Attach to an M5 chart.                                           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Crispin Tibilla"
#property link      "https://www.mql5.com/en/users/crispintibilla"
#property version   "2.00"

const long allowed_accounts[] = {};   // ADD ACCOUNT NUMBERS HERE

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade         m_trade;
CPositionInfo  m_position;

//--- enums
enum eDrawdownType
  {
   DD_EQUITY = 0,
   DD_PIP    = 1,
   DD_CASH   = 2
  };

//--- === CORE SETTINGS ===
input group "=== Core Trade Settings ==="
input double InpMainTradeLot     = 0.80;
input double InpMainTradeTP      = 500.0;   // Main trade TP (pips)
input double InpGridTradesLot    = 0.80;    // Grid base lot (keep = main lot)
input double InpGridTradesTP     = 200.0;   // Basket TP from average (pips); kept when > grid trail start
input int    InpSlippage         = 3;

//--- === MAIN TRADE PROTECTION ===
input group "=== Main Trade: Breakeven ==="
input bool   InpUseBreakeven     = true;
input double InpBE_TriggerPips   = 250.0;   // Move SL to breakeven at this profit
input double InpBE_LockPips      = 20.0;    // SL = entry + this

input group "=== Main Trade: 2-Step Trailing ==="
input bool   InpTrailMain        = true;
input double InpTrailStartPips   = 300.0;   // Step 1 trigger (profit pips)
input double InpTrailLock1Pips   = 100.0;   // Step 1: SL locks this profit
input double InpTrailStep2Pips   = 400.0;   // Step 2 trigger (profit pips)
input double InpTrailLock2Pips   = 250.0;   // Step 2: SL locks this profit
input double InpTrailAfterPips   = 0.0;     // After step 2: trail at this distance (0 = off)

input group "=== Grid Basket: 2-Step Trailing (from basket average) ==="
input bool   InpTrailGrid          = true;  // Basket TP stays while it is above the trail start
input double InpGridTrailStartPips = 150.0;   // Step 1 trigger (pips above basket average)
input double InpGridTrailLock1Pips = 60.0;    // Step 1: SL locks this profit
input double InpGridTrailStep2Pips = 180.0;   // Step 2 trigger (below basket TP)
input double InpGridTrailLock2Pips = 120.0;   // Step 2: SL locks this profit
input double InpGridTrailAfterPips = 0.0;

//--- === GRID SETTINGS ===
input group "=== Grid Settings ==="
input int             InpMaxConcTrades         = 4;     // Max trades per basket (main + grids)
input double          InpGrid_MartingaleFactor = 1.3;
input bool            InpUseAtrGridStep        = true;  // Grid step = ATR x mult (fixed per basket)
input ENUM_TIMEFRAMES InpGridAtrTF             = PERIOD_M15;
input int             InpGridAtrPeriod         = 14;
input double          InpGridAtrMult           = 2.5;
input int             InpGridStep_Pips         = 800;   // Fixed step (ATR off / ATR unavailable)
input int             InpGridStepMin_Pips      = 400;   // Minimum ATR-based step
input bool            InpGridNeedReversal      = true;  // Add only after a rejection candle at the HILO band
input bool            InpGridNeedKerSlowdown   = true;  // Add only when KER < threshold (move slowing)
input int             InpKerPeriod             = 10;
input double          InpKerThreshold          = 0.35;
input bool            InpGridBlockOnHTFFlip    = true;  // No adds when M15 trend is clearly against basket
input bool            InpEnableGridCooldown    = true;
input int             InpGridCoolDownSeconds   = 200;
input bool            InpCloseMainTrade        = false;

input group "=== Basket Stop ==="
input bool   InpUseBasketStop    = true;
input double InpBasketStopSteps  = 1.0;   // Hard SL = one grid step beyond the deepest allowed grid level
input double InpBasketMaxLossPct = 0.0;   // Also close basket if floating loss >= % of balance (0 = off)

//--- === ENTRY ===
input group "=== Entry: M5 Trend + EMA Pullback ==="
input int             InpMA_Period        = 50;
input ENUM_MA_METHOD  InpMA_Method        = MODE_EMA;
input int             InpPullbackEMA      = 21;
input double          InpPullbackAtrMult  = 0.3;   // Low/high must reach EMA21 +/- this x ATR
input int             InpAtrPeriod        = 14;
input int             InpHILO_Period      = 3;     // HILO band (used for grid reversal check)
input ENUM_MA_METHOD  InpHILO_Method      = MODE_EMA;

input group "=== Entry: M15 Trend Veto ==="
input bool            InpUseHTFVeto       = true;  // Block only trades against a clear M15 trend
input ENUM_TIMEFRAMES InpHTF              = PERIOD_M15;
input int             InpHTFFastEMA       = 50;
input int             InpHTFSlowEMA       = 200;

input group "=== Entry: RSI Exhaustion (wait for pullback) ==="
input bool   InpUseRsiExhaustion = true;
input int    InpRsiPeriod        = 14;
input double InpRsiOverbought    = 70;   // RSI >= this: no BUY until pullback
input double InpRsiBuyReset      = 55;   // BUY allowed again once RSI has dropped to this
input double InpRsiOversold      = 30;   // RSI <= this: no SELL until pullback
input double InpRsiSellReset     = 45;   // SELL allowed again once RSI has risen to this
input int    InpRsiLookbackBars  = 50;

input group "=== Entry: ADX (optional) ==="
input bool   InpEnableAdxFilter  = false;
input int    InpAdxPeriod        = 14;
input double InpMinAdx           = 18;   // ADX >= this AND rising

input group "=== Entry: Spread / Session / Volatility ==="
input int    InpMaxSpreadPoints  = 30;   // Max spread in points (0 = off)
input bool   InpUseSession       = true;
input int    InpSessionStartHour = 7;    // Server time
input int    InpSessionEndHour   = 20;   // Server time
input bool   InpUseVolFilter     = true;
input int    InpVolAvgBars       = 50;
input double InpVolMinRatio      = 0.7;  // ATR / avg ATR lower bound
input double InpVolMaxRatio      = 2.0;  // ATR / avg ATR upper bound

input group "=== Circuit Breakers ==="
input int    InpCooldownBars             = 2;     // Bars to wait after any basket close
input int    InpLossPauseMinutes         = 60;    // Pause new trades after a loss, then resume (0 = off)
input double InpDailyProfitLockPct       = 0.0;   // Close all + stop for the day (0 = off)

input group "=== Account Drawdown (last resort) ==="
input bool          InpEnableDD          = true;
input eDrawdownType InpDrawdownType      = DD_EQUITY;
input double        InpEquityDDPercent   = 25.0;
input double        InpPipDD             = 100.0;
input double        InpCashDD            = 1000.0;

//--- constants
const string MAIN_TRADE_COMMENT = "Wild Olive";
const string GRID_TRADE_COMMENT = "Wild Olive+";
const long   MAGIC_MAIN_TRADE   = 20260603;
const long   MAGIC_GRID_TRADE   = 202606032;
#define NO_LOCK -1.0e9

//--- basket snapshot
struct BasketInfo
  {
   int      count;
   int      mainCount;
   int      gridCount;
   int      dir;         // 1 buy, -1 sell, 0 none
   double   sumLots;
   double   avgPrice;
   double   firstPrice;
   datetime firstTime;
   double   lastPrice;
   datetime lastTime;
   double   bestSL;      // tightest existing SL (0 = none)
   double   floating;
  };

//--- globals
double   pointValue;
datetime GRID_COOLDOWN_UNTIL = 0;
datetime g_blockUntil        = 0;
datetime g_lastCloseTime     = 0;
bool     g_inBasket          = false;
datetime g_basketStart       = 0;
double   g_basketStep        = 0;   // grid step (pips) frozen for the current basket
datetime g_dayStart          = 0;
double   g_dayStartBalance   = 0;
bool     g_newBar            = false;

int handle_ma = INVALID_HANDLE, handle_pb = INVALID_HANDLE, handle_atr = INVALID_HANDLE;
int handle_hiloLow = INVALID_HANDLE, handle_hiloHigh = INVALID_HANDLE;
int handle_gridAtr = INVALID_HANDLE, handle_htfFast = INVALID_HANDLE, handle_htfSlow = INVALID_HANDLE;
int handle_rsi = INVALID_HANDLE, handle_adx = INVALID_HANDLE;

//+------------------------------------------------------------------+
bool IsMyMagic(long magic)
  {
   return magic == MAGIC_MAIN_TRADE || magic == MAGIC_GRID_TRADE;
  }

datetime DayStart(datetime t)
  {
   return t - (t % 86400);
  }

bool CopyVal(int handle, int bufferNum, int shift, double &val)
  {
   double tmp[];
   if(handle == INVALID_HANDLE) return false;
   if(CopyBuffer(handle, bufferNum, shift, 1, tmp) != 1) return false;
   val = tmp[0];
   return true;
  }

//+------------------------------------------------------------------+
bool CheckTrailInputs(string name, double start, double lock1, double step2, double lock2)
  {
   if(lock1 >= start || lock2 >= step2 || step2 < start || lock2 < lock1)
     {
      Alert(name, ": need Lock1 < Start <= Step2, Lock1 <= Lock2 < Step2");
      return false;
     }
   return true;
  }

bool f_inputValidation()
  {
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(InpMainTradeLot < minVol || InpGridTradesLot < minVol)
     {
      Alert("Lot size below minimum volume: ", minVol);
      return false;
     }
   if(InpMainTradeLot > maxVol || InpGridTradesLot > maxVol)
     {
      Alert("Lot size above maximum volume: ", maxVol);
      return false;
     }
   if(InpMaxConcTrades < 1)
     {
      Alert("Max trades must be >= 1");
      return false;
     }

   if(_Digits == 3 || _Digits == 5)
      pointValue = _Point * 10;
   else
      pointValue = _Point;

   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(InpMainTradeTP > 0 && InpMainTradeTP * pointValue < stopsLevel * _Point)
     {
      Alert("Main TP too close to stops level");
      return false;
     }
   if(InpGridStep_Pips * pointValue < stopsLevel * _Point)
     {
      Alert("Grid step too close to stops level");
      return false;
     }
   if(InpTrailMain && !CheckTrailInputs("Main trailing", InpTrailStartPips, InpTrailLock1Pips, InpTrailStep2Pips, InpTrailLock2Pips))
      return false;
   if(InpTrailGrid && !CheckTrailInputs("Grid trailing", InpGridTrailStartPips, InpGridTrailLock1Pips, InpGridTrailStep2Pips, InpGridTrailLock2Pips))
      return false;
   if(InpUseBreakeven && InpBE_LockPips >= InpBE_TriggerPips)
     {
      Alert("Breakeven lock must be below breakeven trigger");
      return false;
     }
   if(InpRsiBuyReset >= InpRsiOverbought || InpRsiSellReset <= InpRsiOversold)
     {
      Alert("RSI reset levels must be inside the 30/70 zone");
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(!hf_verifyEA())
      return INIT_FAILED;

   if(!f_inputValidation())
     {
      Print("Input validation failed");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(Period() != PERIOD_M5)
      Print("Note: WildOliveEA_Update is designed for M5, chart is ", EnumToString((ENUM_TIMEFRAMES)Period()));

   handle_ma       = iMA(_Symbol, PERIOD_CURRENT, InpMA_Period, 0, InpMA_Method, PRICE_CLOSE);
   handle_pb       = iMA(_Symbol, PERIOD_CURRENT, InpPullbackEMA, 0, MODE_EMA, PRICE_CLOSE);
   handle_atr      = iATR(_Symbol, PERIOD_CURRENT, InpAtrPeriod);
   handle_hiloLow  = iMA(_Symbol, PERIOD_CURRENT, InpHILO_Period, 0, InpHILO_Method, PRICE_LOW);
   handle_hiloHigh = iMA(_Symbol, PERIOD_CURRENT, InpHILO_Period, 0, InpHILO_Method, PRICE_HIGH);
   handle_gridAtr  = iATR(_Symbol, InpGridAtrTF, InpGridAtrPeriod);
   handle_htfFast  = iMA(_Symbol, InpHTF, InpHTFFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   handle_htfSlow  = iMA(_Symbol, InpHTF, InpHTFSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   handle_rsi      = iRSI(_Symbol, PERIOD_CURRENT, InpRsiPeriod, PRICE_CLOSE);

   if(handle_ma == INVALID_HANDLE || handle_pb == INVALID_HANDLE || handle_atr == INVALID_HANDLE ||
      handle_hiloLow == INVALID_HANDLE || handle_hiloHigh == INVALID_HANDLE || handle_gridAtr == INVALID_HANDLE ||
      handle_htfFast == INVALID_HANDLE || handle_htfSlow == INVALID_HANDLE || handle_rsi == INVALID_HANDLE)
     {
      Print("Failed to create indicator handles");
      return INIT_FAILED;
     }

   if(InpEnableAdxFilter)
     {
      handle_adx = iADX(_Symbol, PERIOD_CURRENT, InpAdxPeriod);
      if(handle_adx == INVALID_HANDLE)
        {
         Print("Failed to create ADX handle");
         return INIT_FAILED;
        }
     }

   if(InpTrailGrid && InpGridTradesTP <= InpGridTrailStartPips)
      Print("Grid trailing is on and Grid TP (", InpGridTradesTP, ") <= trail start (", InpGridTrailStartPips,
            "): baskets have no fixed TP and exit by the trailing stop / basket stop");

   m_trade.SetDeviationInPoints(InpSlippage);
   m_trade.SetExpertMagicNumber(MAGIC_MAIN_TRADE);

   g_dayStart        = DayStart(TimeCurrent());
   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   BasketInfo b;
   GetBasket(b);
   if(b.count > 0)
     {
      g_inBasket    = true;
      g_basketStart = b.firstTime;
      g_basketStep  = GetGridStepPips();
     }

   EventSetTimer(1);
   Print("WildOliveEA_Update v2.00 initialized successfully");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(handle_ma);
   IndicatorRelease(handle_pb);
   IndicatorRelease(handle_atr);
   IndicatorRelease(handle_hiloHigh);
   IndicatorRelease(handle_hiloLow);
   IndicatorRelease(handle_gridAtr);
   IndicatorRelease(handle_htfFast);
   IndicatorRelease(handle_htfSlow);
   IndicatorRelease(handle_rsi);
   if(handle_adx != INVALID_HANDLE)
      IndicatorRelease(handle_adx);
   EventKillTimer();
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   UpdateDay();
   hf_equityProtection();
   CheckDailyLimits();
   CheckBasketCashStop();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   g_newBar = IsNewBar();
   UpdateDay();

   BasketInfo b;
   GetBasket(b);
   TrackBasket(b);

   if(b.count > 0)
     {
      ManageStops(b);
      ManageGrid(b);
      return;
     }

   // Entries: closed candles only, one evaluation per bar
   if(!g_newBar) return;
   if(!CanOpenNewBasket()) return;

   int signal = GetTradeSignal();
   if(signal != 0)
      OpenInitialTrade(signal);
  }

//+------------------------------------------------------------------+
bool IsNewBar()
  {
   static datetime lastBar = 0;
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t == 0) return false;
   if(t != lastBar)
     {
      lastBar = t;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
void GetBasket(BasketInfo &b)
  {
   b.count = 0; b.mainCount = 0; b.gridCount = 0; b.dir = 0;
   b.sumLots = 0; b.avgPrice = 0; b.firstPrice = 0; b.firstTime = 0;
   b.lastPrice = 0; b.lastTime = 0; b.bestSL = 0; b.floating = 0;

   double sumPriceLot = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Symbol() != _Symbol || !IsMyMagic(m_position.Magic())) continue;

      int      dir   = (m_position.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;
      double   price = m_position.PriceOpen();
      double   vol   = m_position.Volume();
      datetime t     = m_position.Time();
      double   sl    = m_position.StopLoss();

      b.count++;
      if(m_position.Magic() == MAGIC_MAIN_TRADE) b.mainCount++;
      else                                        b.gridCount++;
      b.dir        = dir;
      b.sumLots   += vol;
      sumPriceLot += price * vol;
      b.floating  += m_position.Profit() + m_position.Swap();

      if(b.firstTime == 0 || t < b.firstTime) { b.firstTime = t; b.firstPrice = price; }
      if(t >= b.lastTime)                     { b.lastTime  = t; b.lastPrice  = price; }

      if(sl > 0)
        {
         if(b.bestSL == 0)                  b.bestSL = sl;
         else if(dir == 1 && sl > b.bestSL)  b.bestSL = sl;
         else if(dir == -1 && sl < b.bestSL) b.bestSL = sl;
        }
     }
   if(b.sumLots > 0)
      b.avgPrice = sumPriceLot / b.sumLots;
  }

//+------------------------------------------------------------------+
//| Detect basket open/close; apply cooldown and losing-basket stop  |
//+------------------------------------------------------------------+
void TrackBasket(const BasketInfo &b)
  {
   if(b.count > 0 && !g_inBasket)
     {
      g_inBasket    = true;
      g_basketStart = b.firstTime;
      if(g_basketStep <= 0)
         g_basketStep = GetGridStepPips();
     }
   else if(b.count == 0 && g_inBasket)
     {
      g_inBasket     = false;
      g_lastCloseTime = TimeCurrent();
      double pl = BasketRealizedPL(g_basketStart);
      PrintFormat("Basket closed | P/L = %.2f", pl);
      if(pl < 0 && InpLossPauseMinutes > 0)
         BlockUntil(TimeCurrent() + InpLossPauseMinutes * 60, "losing basket");
      g_basketStep  = 0;
      g_basketStart = 0;
     }
  }

double BasketRealizedPL(datetime from)
  {
   if(from <= 0) return 0;
   if(!HistorySelect(from - 1, TimeCurrent() + 86400)) return 0;

   double pl = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0) continue;
      if(HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol) continue;
      if(!IsMyMagic(HistoryDealGetInteger(tk, DEAL_MAGIC))) continue;
      pl += HistoryDealGetDouble(tk, DEAL_PROFIT) +
            HistoryDealGetDouble(tk, DEAL_SWAP) +
            HistoryDealGetDouble(tk, DEAL_COMMISSION);
     }
   return pl;
  }

//+------------------------------------------------------------------+
void BlockUntil(datetime until, string reason)
  {
   if(until > g_blockUntil)
     {
      g_blockUntil = until;
      Print("New trades blocked until ", TimeToString(until), " (", reason, ")");
     }
  }

void BlockUntilNextDay(string reason)
  {
   BlockUntil(DayStart(TimeCurrent()) + 86400, reason);
  }

void UpdateDay()
  {
   datetime d = DayStart(TimeCurrent());
   if(d != g_dayStart)
     {
      g_dayStart        = d;
      g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
     }
  }

void CheckDailyLimits()
  {
   if(InpDailyProfitLockPct <= 0 || g_dayStartBalance <= 0) return;
   BasketInfo b;
   GetBasket(b);
   if(b.count == 0 && TimeCurrent() < g_blockUntil) return;   // already handled
   double change = AccountInfoDouble(ACCOUNT_EQUITY) - g_dayStartBalance;

   if(InpDailyProfitLockPct > 0 && change >= g_dayStartBalance * InpDailyProfitLockPct / 100.0)
     {
      Print("DAILY PROFIT TARGET HIT – closing all positions");
      hf_closeAll();
      BlockUntilNextDay("daily profit lock");
     }
  }

void CheckBasketCashStop()
  {
   if(InpBasketMaxLossPct <= 0) return;
   BasketInfo b;
   GetBasket(b);
   if(b.count == 0) return;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(b.floating <= -bal * InpBasketMaxLossPct / 100.0)
     {
      PrintFormat("BASKET LOSS CAP HIT (%.2f) – closing basket", b.floating);
      hf_closeAll();
     }
  }

//+------------------------------------------------------------------+
bool CanOpenNewBasket()
  {
   if(TimeCurrent() < g_blockUntil) return false;

   if(InpCooldownBars > 0 && g_lastCloseTime > 0 &&
      TimeCurrent() - g_lastCloseTime < InpCooldownBars * PeriodSeconds(PERIOD_CURRENT))
      return false;

   if(!SpreadOK()) return false;
   if(!SessionOK()) return false;
   return true;
  }

bool SpreadOK()
  {
   if(InpMaxSpreadPoints <= 0) return true;
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpreadPoints)
     {
      Print("Spread filter blocked | spread=", spread);
      return false;
     }
   return true;
  }

bool SessionOK()
  {
   if(!InpUseSession) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   if(InpSessionStartHour <= InpSessionEndHour)
      return h >= InpSessionStartHour && h < InpSessionEndHour;
   return h >= InpSessionStartHour || h < InpSessionEndHour;
  }

//+------------------------------------------------------------------+
void hf_equityProtection()
  {
   if(!InpEnableDD) return;

   BasketInfo b;
   GetBasket(b);
   if(b.count == 0) return;

   bool breached = false;

   if(InpDrawdownType == DD_EQUITY)
     {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq <= bal * (100.0 - InpEquityDDPercent) / 100.0)
         breached = true;
     }
   else if(InpDrawdownType == DD_CASH)
     {
      if(b.floating < -InpCashDD) breached = true;
     }
   else if(InpDrawdownType == DD_PIP)
     {
      if(b.count > 0)
        {
         double pips = (b.dir == 1) ?
                       (SymbolInfoDouble(_Symbol, SYMBOL_BID) - b.firstPrice) / pointValue :
                       (b.firstPrice - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / pointValue;
         if(pips <= -InpPipDD) breached = true;
        }
     }

   if(breached)
     {
      Print("DRAWDOWN LIMIT HIT – closing all positions");
      hf_closeAll();
      if(InpLossPauseMinutes > 0)
         BlockUntil(TimeCurrent() + InpLossPauseMinutes * 60, "account drawdown limit");
     }
  }

//+------------------------------------------------------------------+
//| M15 bias: 1 clearly bullish, -1 clearly bearish, 0 neutral       |
//+------------------------------------------------------------------+
int HTFBias()
  {
   double fast, slow;
   if(!CopyVal(handle_htfFast, 0, 1, fast) || !CopyVal(handle_htfSlow, 0, 1, slow))
      return 0;
   double c = iClose(_Symbol, InpHTF, 1);
   if(c > fast && fast > slow) return 1;
   if(c < fast && fast < slow) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
int GetTradeSignal()
  {
   double ma1, ma2, pb1, atr1;
   if(!CopyVal(handle_ma, 0, 1, ma1) || !CopyVal(handle_ma, 0, 2, ma2)) return 0;
   if(!CopyVal(handle_pb, 0, 1, pb1) || !CopyVal(handle_atr, 0, 1, atr1)) return 0;

   double o1 = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double h1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double l1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double zone = InpPullbackAtrMult * atr1;

   int signal = 0;
   // BUY: M5 uptrend, pullback into EMA21, bullish close back above it
   if(c1 > ma1 && ma1 > ma2 && pb1 > ma1 &&
      l1 <= pb1 + zone && c1 > pb1 && c1 > o1)
      signal = 1;
   // SELL: M5 downtrend, pullback into EMA21, bearish close back below it
   else if(c1 < ma1 && ma1 < ma2 && pb1 < ma1 &&
           h1 >= pb1 - zone && c1 < pb1 && c1 < o1)
      signal = -1;

   if(signal == 0) return 0;

   if(InpUseHTFVeto && HTFBias() == -signal)
     {
      Print("M15 veto blocked ", signal == 1 ? "BUY" : "SELL");
      return 0;
     }
   if(!RsiAllows(signal)) return 0;
   if(!AdxAllows())       return 0;
   if(!VolatilityOK(atr1)) return 0;

   return signal;
  }

//+------------------------------------------------------------------+
//| After RSI >= 70, no BUY until RSI has pulled back to reset level  |
//| After RSI <= 30, no SELL until RSI has pulled back to reset level |
//+------------------------------------------------------------------+
bool RsiAllows(int side)
  {
   if(!InpUseRsiExhaustion) return true;

   double r[];
   ArraySetAsSeries(r, true);
   int n = MathMax(InpRsiLookbackBars, 1);
   if(CopyBuffer(handle_rsi, 0, 1, n, r) != n) return false;

   for(int i = 0; i < n; i++)
     {
      if(side == 1)
        {
         if(r[i] <= InpRsiBuyReset) return true;
         if(r[i] >= InpRsiOverbought)
           {
            Print("RSI: waiting for pullback before BUY | RSI=", r[0]);
            return false;
           }
        }
      else
        {
         if(r[i] >= InpRsiSellReset) return true;
         if(r[i] <= InpRsiOversold)
           {
            Print("RSI: waiting for pullback before SELL | RSI=", r[0]);
            return false;
           }
        }
     }
   return true;
  }

bool AdxAllows()
  {
   if(!InpEnableAdxFilter) return true;
   double adx1, adx3;
   if(!CopyVal(handle_adx, 0, 1, adx1) || !CopyVal(handle_adx, 0, 3, adx3)) return false;
   if(adx1 >= InpMinAdx && adx1 > adx3) return true;
   Print("ADX blocked | ADX=", adx1);
   return false;
  }

bool VolatilityOK(double atr1)
  {
   if(!InpUseVolFilter) return true;
   double a[];
   int n = MathMax(InpVolAvgBars, 1);
   if(CopyBuffer(handle_atr, 0, 1, n, a) != n) return false;
   double sum = 0;
   for(int i = 0; i < n; i++) sum += a[i];
   double avg = sum / n;
   if(avg <= 0) return false;
   double ratio = atr1 / avg;
   if(ratio < InpVolMinRatio || ratio > InpVolMaxRatio)
     {
      PrintFormat("Volatility filter blocked | ATR ratio=%.2f", ratio);
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
double GetGridStepPips()
  {
   if(!InpUseAtrGridStep) return InpGridStep_Pips;
   double atr;
   if(!CopyVal(handle_gridAtr, 0, 1, atr) || atr <= 0) return InpGridStep_Pips;
   return MathMax(atr * InpGridAtrMult / pointValue, (double)InpGridStepMin_Pips);
  }

double BasketStepPips()
  {
   return (g_basketStep > 0) ? g_basketStep : GetGridStepPips();
  }

// Hard basket SL: one stop-step beyond the deepest allowed grid level, measured from the first entry
double HardStopPrice(int dir, double firstPrice)
  {
   double dist = ((InpMaxConcTrades - 1) + InpBasketStopSteps) * BasketStepPips() * pointValue;
   return NormalizeDouble(firstPrice - dir * dist, _Digits);
  }

//+------------------------------------------------------------------+
void OpenInitialTrade(int signal)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double lot = InpMainTradeLot;

   g_basketStep = GetGridStepPips();
   m_trade.SetExpertMagicNumber(MAGIC_MAIN_TRADE);

   if(signal == 1)
     {
      double tp = (InpMainTradeTP > 0) ? NormalizeDouble(ask + InpMainTradeTP * pointValue, _Digits) : 0;
      double sl = InpUseBasketStop ? HardStopPrice(1, ask) : 0;
      if(m_trade.Buy(lot, _Symbol, 0, sl, tp, MAIN_TRADE_COMMENT))
         PrintFormat("Main BUY opened | SL=%s TP=%s step=%.0f pips", DoubleToString(sl, _Digits), DoubleToString(tp, _Digits), g_basketStep);
     }
   else if(signal == -1)
     {
      double tp = (InpMainTradeTP > 0) ? NormalizeDouble(bid - InpMainTradeTP * pointValue, _Digits) : 0;
      double sl = InpUseBasketStop ? HardStopPrice(-1, bid) : 0;
      if(m_trade.Sell(lot, _Symbol, 0, sl, tp, MAIN_TRADE_COMMENT))
         PrintFormat("Main SELL opened | SL=%s TP=%s step=%.0f pips", DoubleToString(sl, _Digits), DoubleToString(tp, _Digits), g_basketStep);
     }
  }

//+------------------------------------------------------------------+
//| Breakeven, 2-step trailing and hard basket stop                  |
//+------------------------------------------------------------------+
double TrailLockPips(double profit, double start, double lock1, double step2, double lock2, double after)
  {
   double lock = NO_LOCK;
   if(profit >= start) lock = lock1;
   if(profit >= step2) lock = MathMax(lock, lock2);
   if(after > 0 && profit >= step2) lock = MathMax(lock, profit - after);
   return lock;
  }

// Returns the tighter of two stop prices for the given direction (0 = none)
double TighterSL(int dir, double a, double b)
  {
   if(a <= 0) return b;
   if(b <= 0) return a;
   return (dir == 1) ? MathMax(a, b) : MathMin(a, b);
  }

void ManageStops(const BasketInfo &b)
  {
   if(b.count == 0 || b.dir == 0) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool   isBasket = (b.gridCount > 0);
   double ref = isBasket ? b.avgPrice : b.firstPrice;
   double profitPips = (b.dir == 1) ? (bid - ref) / pointValue : (ref - ask) / pointValue;

   double lock = NO_LOCK;
   if(!isBasket)
     {
      if(InpUseBreakeven && profitPips >= InpBE_TriggerPips)
         lock = InpBE_LockPips;
      if(InpTrailMain)
         lock = MathMax(lock, TrailLockPips(profitPips, InpTrailStartPips, InpTrailLock1Pips,
                                            InpTrailStep2Pips, InpTrailLock2Pips, InpTrailAfterPips));
     }
   else if(InpTrailGrid)
     {
      lock = TrailLockPips(profitPips, InpGridTrailStartPips, InpGridTrailLock1Pips,
                           InpGridTrailStep2Pips, InpGridTrailLock2Pips, InpGridTrailAfterPips);
     }

   double desired = 0;
   if(lock > NO_LOCK / 2)
      desired = NormalizeDouble(ref + b.dir * lock * pointValue, _Digits);
   if(InpUseBasketStop)
      desired = TighterSL(b.dir, desired, HardStopPrice(b.dir, b.firstPrice));
   desired = TighterSL(b.dir, desired, b.bestSL);   // keep all basket SLs aligned
   if(desired <= 0) return;

   // Respect stops / freeze level
   long   lvl     = MathMax(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
                            SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL));
   double minDist = lvl * _Point;
   if(b.dir == 1 && desired >= bid - minDist) return;
   if(b.dir == -1 && desired <= ask + minDist) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Symbol() != _Symbol || !IsMyMagic(m_position.Magic())) continue;

      double curSL = m_position.StopLoss();
      bool improve = (curSL == 0) ||
                     (b.dir == 1  && desired > curSL + _Point / 2) ||
                     (b.dir == -1 && desired < curSL - _Point / 2);
      if(improve)
         m_trade.PositionModify(m_position.Ticket(), desired, m_position.TakeProfit());
     }
  }

//+------------------------------------------------------------------+
//| Grid adds: closed candle, step reached, move slowing, reversal   |
//+------------------------------------------------------------------+
double CalcKER(int period, int shift)
  {
   double c[];
   ArraySetAsSeries(c, true);
   if(CopyClose(_Symbol, PERIOD_CURRENT, shift, period + 1, c) != period + 1) return -1;
   double change = MathAbs(c[0] - c[period]);
   double noise  = 0;
   for(int i = 0; i < period; i++)
      noise += MathAbs(c[i] - c[i + 1]);
   if(noise <= 0) return 0;
   return change / noise;
  }

bool ReversalCandle(int dir)
  {
   double hl, hh;
   if(!CopyVal(handle_hiloLow, 0, 1, hl) || !CopyVal(handle_hiloHigh, 0, 1, hh)) return false;
   double o1 = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double h1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double l1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);

   if(dir == 1)  return c1 > o1 && l1 < hl && c1 > hl;   // wick below HILO low, bullish close back above
   return c1 < o1 && h1 > hh && c1 < hh;                  // wick above HILO high, bearish close back below
  }

void ManageGrid(const BasketInfo &b)
  {
   if(!g_newBar) return;
   if(InpEnableGridCooldown && TimeCurrent() < GRID_COOLDOWN_UNTIL) return;
   if(b.count >= InpMaxConcTrades) return;

   double step  = BasketStepPips();
   double c1    = iClose(_Symbol, PERIOD_CURRENT, 1);
   double dist  = (b.dir == 1) ? (b.lastPrice - c1) : (c1 - b.lastPrice);
   if(dist < step * pointValue) return;

   // Never add within one step of the hard basket stop
   if(InpUseBasketStop)
     {
      double hard = HardStopPrice(b.dir, b.firstPrice);
      double room = (b.dir == 1) ? (c1 - hard) : (hard - c1);
      if(room < step * pointValue) return;
     }

   if(!SpreadOK()) return;

   if(InpGridBlockOnHTFFlip && HTFBias() == -b.dir)
     {
      Print("Grid add blocked: M15 trend against basket");
      return;
     }
   if(InpGridNeedKerSlowdown)
     {
      double ker = CalcKER(InpKerPeriod, 1);
      if(ker < 0 || ker >= InpKerThreshold)
        {
         Print("Grid add blocked: move not slowing | KER=", ker);
         return;
        }
     }
   if(InpGridNeedReversal && !ReversalCandle(b.dir))
      return;

   OpenGridTrade(b.dir, b.count);
  }

void OpenGridTrade(int dir, int count)
  {
   m_trade.SetExpertMagicNumber(MAGIC_GRID_TRADE);
   double lot = CalculateLotSize(count);

   bool ok = (dir == 1) ? m_trade.Buy(lot, _Symbol, 0, 0, 0, GRID_TRADE_COMMENT)
                        : m_trade.Sell(lot, _Symbol, 0, 0, 0, GRID_TRADE_COMMENT);
   if(!ok) return;

   PrintFormat("Grid %s opened | lot=%.2f trade #%d", dir == 1 ? "BUY" : "SELL", lot, count + 1);
   if(InpEnableGridCooldown)
      GRID_COOLDOWN_UNTIL = TimeCurrent() + InpGridCoolDownSeconds;
   if(InpCloseMainTrade)
      hf_closePositions(dir == 1 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, MAGIC_MAIN_TRADE);

   BasketInfo nb;
   GetBasket(nb);
   ManageBasketTP(nb);
   ManageStops(nb);
  }

//+------------------------------------------------------------------+
void ManageBasketTP(const BasketInfo &b)
  {
   if(b.count == 0 || b.sumLots <= 0) return;

   double newTP = 0;
   bool useFixedTP = !InpTrailGrid || InpGridTradesTP > InpGridTrailStartPips;
   if(useFixedTP && InpGridTradesTP > 0)
      newTP = NormalizeDouble(b.avgPrice + b.dir * InpGridTradesTP * pointValue, _Digits);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Symbol() != _Symbol || !IsMyMagic(m_position.Magic())) continue;
      m_trade.PositionModify(m_position.Ticket(), m_position.StopLoss(), newTP);
     }
  }

//+------------------------------------------------------------------+
double CalculateLotSize(int count)
  {
   double lot = InpGridTradesLot * MathPow(InpGrid_MartingaleFactor, count);

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(step > 0)
      lot = MathCeil(lot / step - 1e-9) * step;

   lot = MathMax(minL, MathMin(maxL, lot));
   return NormalizeDouble(lot, 2);
  }

//+------------------------------------------------------------------+
void hf_closePositions(ENUM_POSITION_TYPE type, long magic)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Symbol() != _Symbol) continue;
      if(m_position.Magic() != magic) continue;
      if(m_position.PositionType() != type) continue;
      m_trade.PositionClose(m_position.Ticket());
     }
  }

void hf_closeAll()
  {
   hf_closePositions(POSITION_TYPE_BUY,  MAGIC_MAIN_TRADE);
   hf_closePositions(POSITION_TYPE_BUY,  MAGIC_GRID_TRADE);
   hf_closePositions(POSITION_TYPE_SELL, MAGIC_MAIN_TRADE);
   hf_closePositions(POSITION_TYPE_SELL, MAGIC_GRID_TRADE);
  }

//+------------------------------------------------------------------+
bool hf_verifyEA()
  {
   if(ArraySize(allowed_accounts) < 1) return true;
   long acc = AccountInfoInteger(ACCOUNT_LOGIN);
   for(int i = 0; i < ArraySize(allowed_accounts); i++)
      if(acc == allowed_accounts[i]) return true;
   Alert("EA not allowed on this account");
   return false;
  }
//+------------------------------------------------------------------+
