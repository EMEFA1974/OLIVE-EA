//+------------------------------------------------------------------+
//|                                                      OliveEA.mq5 |
//|  Trend-pullback EA, tuned for XAUUSD M5 (H1 bias). One position  |
//|  per symbol, stop loss on every trade, fixed-lot or risk-% size. |
//|  No martingale, no grid, no averaging down.                      |
//+------------------------------------------------------------------+
#property copyright "Olive"
#property version   "1.00"
#property description "Trend-pullback EA: HTF bias, EMA pullback entries, ATR or fixed stops, fixed or risk-% lots,"
#property description "daily-loss and max-drawdown guards, session, weekend and news filters."

#include <Trade/Trade.mqh>
#include <Olive/OliveCore.mqh>

enum ENUM_OLIVE_LOT_MODE
  {
   OLIVE_LOT_FIXED=0,  // Fixed lot
   OLIVE_LOT_RISK=1    // Risk % of balance (lot from stop distance)
  };

input group "Strategy (keep identical to the indicator)"
input ENUM_TIMEFRAMES InpHTF          = PERIOD_H1; // Bias timeframe
input int             InpHtfEma       = 50;        // Bias EMA period
input int             InpHtfSlopeBars = 3;         // Bias EMA slope lookback (bars)
input int             InpFastEma      = 20;        // Fast EMA
input int             InpSlowEma      = 50;        // Slow EMA
input int             InpRsiPeriod    = 14;        // RSI period
input double          InpRsiMin       = 50;        // Buy RSI min (sell uses 100-max)
input double          InpRsiMax       = 70;        // Buy RSI max (sell uses 100-min)
input int             InpAdxPeriod    = 14;        // ADX period
input double          InpAdxMin       = 18;        // ADX minimum (0 = off)
input int             InpAtrPeriod    = 14;        // ATR period
input int             InpPullbackBars = 5;         // Pullback lookback (bars)
input double          InpSlAtrBuffer  = 0.3;       // SL buffer beyond swing (ATR)
input double          InpMinSlAtr     = 1.0;       // Min SL distance (ATR)
input double          InpMaxSlAtr     = 3.0;       // Max SL distance (ATR) - wider = skip
input ENUM_OLIVE_SL_MODE InpSlMode   = OLIVE_SL_ATR; // Stop-loss mode
input int             InpFixedSlPoints = 500;      // Fixed SL in points (500 = $5.00 on 2-digit gold)
input double          InpRewardRisk   = 1.5;       // Reward : Risk

input group "Position size"
input ENUM_OLIVE_LOT_MODE InpLotMode     = OLIVE_LOT_RISK; // Lot mode
input double          InpFixedLot        = 0.01;   // Fixed lot (Lot mode = fixed)
input double          InpRiskPercent     = 0.5;    // Risk per trade % (Lot mode = risk)

input group "Risk"
input double          InpMaxDailyLossPct = 4.0;    // Max daily loss % - close & stop for the day (0 = off)
input double          InpMaxDrawdownPct  = 15.0;    // Max drawdown % from equity peak - halt EA (0 = off)
input int             InpMaxTradesPerDay = 0;      // Max new trades per day per symbol (0 = no limit)
input int             InpMaxSpreadPoints = 60;     // Max spread in points (0 = off)
input double          InpMaxSpreadSlPct  = 10.0;   // Max spread as % of SL distance (0 = off)
input bool            InpResetGuards     = false;  // Reset drawdown halt / equity peak on start

input group "Trade management"
input double          InpBreakEvenR      = 1.0;    // Move SL to break-even at +R (0 = off)
input double          InpBreakEvenLockR  = 0.1;    // Profit locked at break-even (R)
input double          InpPartialR        = 0.0;    // Partial close at +R (0 = off)
input double          InpPartialPct      = 50.0;   // Partial close volume %
input double          InpTrailStartR     = 1.0;    // Start ATR trailing at +R (0 = off)
input double          InpTrailAtrMult    = 1.5;    // Trailing distance (ATR)
input int             InpMaxBarsInTrade  = 0;      // Close trade after N bars (0 = off)

input group "Sessions, weekend & news (server time)"
input int             InpStartHour       = 0;      // Trading window start hour (start = end -> 24h)
input int             InpEndHour         = 0;      // Trading window end hour
input bool            InpWeekendProtect  = true;   // Weekend protection
input int             InpFridayNoEntryHour = 18;   // Friday: no new trades from this hour
input int             InpFridayCloseHour = 21;     // Friday: close open trades at this hour
input bool            InpNewsFilter      = true;   // Block entries around high-impact news (live only)
input int             InpNewsMinsBefore  = 30;     // Minutes before news
input int             InpNewsMinsAfter   = 30;     // Minutes after news

input group "General"
input long            InpMagic           = 20261001; // Magic number
input string          InpComment         = "OliveEA";// Order comment
input int             InpSlippagePoints  = 20;     // Max slippage (points)
input bool            InpShowPanel       = true;   // Show status panel

CTrade       g_trade;
COliveEngine g_engine;
datetime     g_lastBar=0;
double       g_dailyLossPct=0;
double       g_ddPct=0;
int          g_tradesToday=0;
string       g_status="";

//+------------------------------------------------------------------+
//| Global-variable helpers (state survives restarts)                |
//+------------------------------------------------------------------+
string AcctKey(const string name)
  {
   return "OliveEA_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+name;
  }
string TicketKey(const string kind,const ulong ticket)
  {
   return "OliveEA_"+kind+"_"+IntegerToString((long)ticket);
  }
double GVGet(const string key,const double def)
  {
   return GlobalVariableCheck(key) ? GlobalVariableGet(key) : def;
  }

double NormalizeLots(const double lots)
  {
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double vmin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double vmax=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(step<=0)
      step=0.01;
   double v=MathFloor(lots/step+1e-9)*step;
   v=MathMax(vmin,MathMin(vmax,v));
   int digits=(int)MathMax(0,MathCeil(-MathLog10(step)-1e-9));
   return NormalizeDouble(v,digits);
  }

double NormPrice(const double price)
  {
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick>0)
      return NormalizeDouble(MathRound(price/tick)*tick,_Digits);
   return NormalizeDouble(price,_Digits);
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpLotMode==OLIVE_LOT_RISK && (InpRiskPercent<=0 || InpRiskPercent>5))
     {
      Print("OliveEA: risk per trade must be between 0 and 5%");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLotMode==OLIVE_LOT_FIXED && InpFixedLot<=0)
     {
      Print("OliveEA: fixed lot must be greater than 0");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpPartialPct<=0 || InpPartialPct>=100 || InpTrailAtrMult<=0)
     {
      Print("OliveEA: invalid trade management settings");
      return INIT_PARAMETERS_INCORRECT;
     }

   OliveSettings s;
   s.htf=InpHTF;
   s.htfEmaPeriod=InpHtfEma;
   s.htfSlopeBars=InpHtfSlopeBars;
   s.fastEma=InpFastEma;
   s.slowEma=InpSlowEma;
   s.rsiPeriod=InpRsiPeriod;
   s.rsiMin=InpRsiMin;
   s.rsiMax=InpRsiMax;
   s.adxPeriod=InpAdxPeriod;
   s.adxMin=InpAdxMin;
   s.atrPeriod=InpAtrPeriod;
   s.pullbackBars=InpPullbackBars;
   s.slAtrBuffer=InpSlAtrBuffer;
   s.minSlAtr=InpMinSlAtr;
   s.maxSlAtr=InpMaxSlAtr;
   s.rewardRisk=InpRewardRisk;
   s.slMode=InpSlMode;
   s.fixedSlPoints=InpFixedSlPoints;
   if(!g_engine.Init(_Symbol,_Period,s))
      return INIT_PARAMETERS_INCORRECT;

   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetDeviationInPoints((ulong)InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetMarginMode();

   if(InpResetGuards)
     {
      GlobalVariableDel(AcctKey("peak"));
      GlobalVariableDel(AcctKey("halted"));
      Print("OliveEA: drawdown guard reset");
     }
   PruneTicketVariables();
   g_lastBar=iTime(_Symbol,_Period,0);   // wait for the next fresh bar
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(InpShowPanel)
      Comment("");
   g_engine.Release();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateGuards();
   ManagePositions();

   datetime bar=iTime(_Symbol,_Period,0);
   if(bar!=0 && bar!=g_lastBar && g_engine.Ready())
     {
      g_lastBar=bar;
      TryEntry();
     }
   if(InpShowPanel && !MQLInfoInteger(MQL_OPTIMIZATION))
      ShowPanel();
  }

//+------------------------------------------------------------------+
//| Daily-loss and max-drawdown protection                           |
//+------------------------------------------------------------------+
void UpdateGuards()
  {
   datetime now=TimeCurrent();
   datetime today=now-(now%86400);
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);

   if((datetime)GVGet(AcctKey("day"),0)!=today)
     {
      GlobalVariableSet(AcctKey("day"),(double)today);
      GlobalVariableSet(AcctKey("dayStartEq"),MathMax(bal,eq));
      GlobalVariableSet(AcctKey("dayBlocked"),0);
     }
   double dayStart=GVGet(AcctKey("dayStartEq"),MathMax(bal,eq));
   g_dailyLossPct=(dayStart>0) ? (dayStart-eq)/dayStart*100.0 : 0;
   if(InpMaxDailyLossPct>0 && g_dailyLossPct>=InpMaxDailyLossPct && GVGet(AcctKey("dayBlocked"),0)==0)
     {
      GlobalVariableSet(AcctKey("dayBlocked"),1);
      PrintFormat("OliveEA: daily loss limit hit (%.2f%%) - closing trades, no new entries today",g_dailyLossPct);
     }

   double peak=MathMax(GVGet(AcctKey("peak"),eq),eq);
   GlobalVariableSet(AcctKey("peak"),peak);
   g_ddPct=(peak>0) ? (peak-eq)/peak*100.0 : 0;
   if(InpMaxDrawdownPct>0 && g_ddPct>=InpMaxDrawdownPct && GVGet(AcctKey("halted"),0)==0)
     {
      GlobalVariableSet(AcctKey("halted"),1);
      PrintFormat("OliveEA: max drawdown hit (%.2f%%) - EA HALTED. Review, then restart with 'Reset drawdown halt' = true",g_ddPct);
     }

   if(DailyBlocked() || Halted())
      CloseAll(Halted() ? "max drawdown" : "daily loss");
  }

bool DailyBlocked() { return InpMaxDailyLossPct>0 && GVGet(AcctKey("dayBlocked"),0)!=0; }
bool Halted()       { return InpMaxDrawdownPct>0 && GVGet(AcctKey("halted"),0)!=0; }

//+------------------------------------------------------------------+
bool IsOurs(const ulong ticket)
  {
   return PositionSelectByTicket(ticket) &&
          PositionGetString(POSITION_SYMBOL)==_Symbol &&
          PositionGetInteger(POSITION_MAGIC)==InpMagic;
  }

void CloseAll(const string reason)
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !IsOurs(ticket))
         continue;
      if(g_trade.PositionClose(ticket))
         PrintFormat("OliveEA: closed #%I64u (%s)",ticket,reason);
      else
         PrintFormat("OliveEA: close #%I64u failed: %d %s",ticket,g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
     }
  }

//--- any exposure on this symbol that should block a new entry
bool HasExposure()
  {
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      return PositionSelect(_Symbol);   // netting: never merge into another position
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket!=0 && IsOurs(ticket))
         return true;
     }
   return false;
  }

int TradesToday()
  {
   datetime now=TimeCurrent();
   if(!HistorySelect(now-(now%86400),now+60))
      return 0;
   int count=0;
   for(int i=HistoryDealsTotal()-1; i>=0; i--)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0)
         continue;
      if(HistoryDealGetString(deal,DEAL_SYMBOL)==_Symbol &&
         HistoryDealGetInteger(deal,DEAL_MAGIC)==InpMagic &&
         HistoryDealGetInteger(deal,DEAL_ENTRY)==DEAL_ENTRY_IN)
         count++;
     }
   return count;
  }

bool InSession()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   if(InpWeekendProtect && dt.day_of_week==5 && dt.hour>=InpFridayNoEntryHour)
      return false;
   if(dt.day_of_week==0 || dt.day_of_week==6)
      return false;
   if(InpStartHour==InpEndHour)
      return true;
   if(InpStartHour<InpEndHour)
      return dt.hour>=InpStartHour && dt.hour<InpEndHour;
   return dt.hour>=InpStartHour || dt.hour<InpEndHour;   // window crosses midnight
  }

//+------------------------------------------------------------------+
//| High-impact news check via the built-in MT5 economic calendar.   |
//| The calendar is not available in the Strategy Tester.            |
//+------------------------------------------------------------------+
bool NewsBlocked(string &eventName)
  {
   eventName="";
   if(!InpNewsFilter || MQLInfoInteger(MQL_TESTER))
      return false;
   datetime now=TimeTradeServer();
   string ccy[2];
   ccy[0]=SymbolInfoString(_Symbol,SYMBOL_CURRENCY_BASE);
   ccy[1]=SymbolInfoString(_Symbol,SYMBOL_CURRENCY_PROFIT);
   for(int c=0; c<2; c++)
     {
      if(ccy[c]=="" || (c==1 && ccy[1]==ccy[0]))
         continue;
      MqlCalendarValue values[];
      int n=CalendarValueHistory(values,now-InpNewsMinsAfter*60,now+InpNewsMinsBefore*60,NULL,ccy[c]);
      for(int i=0; i<n; i++)
        {
         MqlCalendarEvent ev;
         if(CalendarEventById(values[i].event_id,ev) && ev.importance==CALENDAR_IMPORTANCE_HIGH)
           {
            eventName=ccy[c]+" "+ev.name;
            return true;
           }
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Entry on the close of the signal bar                             |
//+------------------------------------------------------------------+
void TryEntry()
  {
   g_tradesToday=TradesToday();
   if(Halted())        { g_status="Halted: max drawdown reached"; return; }
   if(DailyBlocked())  { g_status="Stopped for today: daily loss limit"; return; }
   if(HasExposure())   { g_status="In trade"; return; }
   if(!InSession())    { g_status="Outside trading window"; return; }
   if(InpMaxTradesPerDay>0 && g_tradesToday>=InpMaxTradesPerDay)
     { g_status="Daily trade limit reached"; return; }

   OliveSignal sig;
   if(!g_engine.EvaluateFresh(1,sig))
     {
      g_lastBar=0;                       // data not ready - retry on next tick
      return;
     }
   if(sig.direction==0)
     { g_status="Waiting for setup"; return; }

   string news;
   if(NewsBlocked(news))
     {
      g_status="Signal skipped - news: "+news;
      Print("OliveEA: ",g_status);
      return;
     }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;
   bool buy=(sig.direction>0);
   double entry=buy ? tick.ask : tick.bid;
   double sl=NormPrice(sig.sl);
   double risk=buy ? entry-sl : sl-entry;
   if(risk<=0)
     {
      Print("OliveEA: price already beyond stop level - signal skipped");
      return;
     }
   double tp=NormPrice(buy ? entry+risk*InpRewardRisk : entry-risk*InpRewardRisk);

   //--- spread filters
   double spread=tick.ask-tick.bid;
   if(InpMaxSpreadPoints>0 && spread>InpMaxSpreadPoints*_Point)
     {
      PrintFormat("OliveEA: spread %.0f pts too high - signal skipped",spread/_Point);
      return;
     }
   if(InpMaxSpreadSlPct>0 && spread>risk*InpMaxSpreadSlPct/100.0)
     {
      Print("OliveEA: spread too large relative to stop - signal skipped");
      return;
     }

   //--- broker stop distance
   long lvl=MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL));
   double minDist=lvl*_Point;
   if(risk<=minDist || MathAbs(tp-entry)<=minDist)
     {
      Print("OliveEA: stop/target inside broker minimum distance - signal skipped");
      return;
     }

   //--- position size
   double riskMoney=MathMin(AccountInfoDouble(ACCOUNT_BALANCE),AccountInfoDouble(ACCOUNT_EQUITY))*InpRiskPercent/100.0;
   ENUM_ORDER_TYPE type=buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double lots;
   if(InpLotMode==OLIVE_LOT_FIXED)
      lots=NormalizeLots(InpFixedLot);
   else
     {
      lots=OliveLotsForRisk(_Symbol,type,entry,sl,riskMoney);
      if(lots<=0)
        {
         PrintFormat("OliveEA: minimum lot would risk more than %.2f%% - signal skipped",InpRiskPercent);
         return;
        }
     }
   double lossMoney=0;
   if(OrderCalcProfit(type,_Symbol,lots,entry,sl,lossMoney))
      riskMoney=MathAbs(lossMoney);
   double margin=0;
   if(!OrderCalcMargin(type,_Symbol,lots,entry,margin) || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)*0.9)
     {
      Print("OliveEA: insufficient free margin - signal skipped");
      return;
     }

   bool ok=buy ? g_trade.Buy(lots,_Symbol,0,sl,tp,InpComment)
                : g_trade.Sell(lots,_Symbol,0,sl,tp,InpComment);
   if(ok && (g_trade.ResultRetcode()==TRADE_RETCODE_DONE || g_trade.ResultRetcode()==TRADE_RETCODE_PLACED))
     {
      g_status=StringFormat("Opened %s %.2f lots",buy ? "BUY" : "SELL",lots);
      PrintFormat("OliveEA: %s %.2f @ %s SL %s TP %s (risk %.2f %s)",buy ? "BUY" : "SELL",lots,
                  DoubleToString(entry,_Digits),DoubleToString(sl,_Digits),DoubleToString(tp,_Digits),
                  riskMoney,AccountInfoString(ACCOUNT_CURRENCY));
     }
   else
      PrintFormat("OliveEA: order failed: %d %s",g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Break-even, partial close, ATR trailing, time exit, weekend exit |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   if(InpWeekendProtect && dt.day_of_week==5 && dt.hour>=InpFridayCloseHour)
     {
      CloseAll("weekend protection");
      return;
     }

   double point=_Point;
   long lvl=MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL));
   double minDist=(lvl+1)*point;

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !IsOurs(ticket))
         continue;

      bool   buy  =(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double open =PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   =PositionGetDouble(POSITION_SL);
      double tp   =PositionGetDouble(POSITION_TP);
      double vol  =PositionGetDouble(POSITION_VOLUME);
      double price=buy ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      //--- initial risk (R), remembered from the original stop
      string rKey=TicketKey("R",ticket);
      double R=GVGet(rKey,0);
      if(R<=0)
        {
         if(sl>0 && ((buy && sl<open) || (!buy && sl>open)))
           {
            R=MathAbs(open-sl);
            GlobalVariableSet(rKey,R);
           }
         else
            continue;
        }
      double profitR=(buy ? price-open : open-price)/R;

      //--- time exit
      if(InpMaxBarsInTrade>0)
        {
         int bars=iBarShift(_Symbol,_Period,(datetime)PositionGetInteger(POSITION_TIME),false);
         if(bars>=InpMaxBarsInTrade)
           {
            if(g_trade.PositionClose(ticket))
               PrintFormat("OliveEA: closed #%I64u after %d bars",ticket,bars);
            continue;
           }
        }

      //--- partial close
      string pKey=TicketKey("P",ticket);
      if(InpPartialR>0 && profitR>=InpPartialR && !GlobalVariableCheck(pKey))
        {
         double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
         double vmin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
         double part=MathFloor(vol*InpPartialPct/100.0/step+1e-9)*step;
         if(part>=vmin && vol-part>=vmin-1e-9)
           {
            if(g_trade.PositionClosePartial(ticket,part))
              {
               GlobalVariableSet(pKey,1);
               PrintFormat("OliveEA: partial close %.2f of #%I64u at +%.2fR",part,ticket,profitR);
              }
           }
         else
            GlobalVariableSet(pKey,1);   // too small to split - don't retry
         if(!PositionSelectByTicket(ticket))
            continue;
         sl=PositionGetDouble(POSITION_SL);
         tp=PositionGetDouble(POSITION_TP);
        }

      double newSL=sl;

      //--- break-even
      if(InpBreakEvenR>0 && profitR>=InpBreakEvenR)
        {
         double be=buy ? open+InpBreakEvenLockR*R : open-InpBreakEvenLockR*R;
         if(buy ? (newSL<be) : (newSL>be || newSL==0))
            newSL=be;
        }

      //--- ATR trailing
      if(InpTrailStartR>0 && profitR>=InpTrailStartR)
        {
         double atr;
         if(g_engine.Atr(1,atr) && atr>0)
           {
            double trail=buy ? price-atr*InpTrailAtrMult : price+atr*InpTrailAtrMult;
            if(buy ? (trail>newSL) : (trail<newSL || newSL==0))
               newSL=trail;
           }
        }

      newSL=NormPrice(newSL);
      bool improves=buy ? (newSL>sl+point/2) : (sl==0 || newSL<sl-point/2);
      bool legal   =buy ? (price-newSL>=minDist) : (newSL-price>=minDist);
      if(newSL>0 && improves && legal)
        {
         if(!g_trade.PositionModify(ticket,newSL,tp))
            PrintFormat("OliveEA: modify #%I64u failed: %d %s",ticket,g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
        }
     }
  }

//--- remove remembered R / partial flags of positions that no longer exist
void PruneTicketVariables()
  {
   for(int i=GlobalVariablesTotal()-1; i>=0; i--)
     {
      string name=GlobalVariableName(i);
      if(StringFind(name,"OliveEA_R_")!=0 && StringFind(name,"OliveEA_P_")!=0)
         continue;
      ulong ticket=(ulong)StringToInteger(StringSubstr(name,10));
      if(ticket>0 && !PositionSelectByTicket(ticket))
         GlobalVariableDel(name);
     }
  }

//+------------------------------------------------------------------+
void ShowPanel()
  {
   static datetime lastDraw=0;
   datetime now=TimeLocal();
   if(now==lastDraw && !MQLInfoInteger(MQL_TESTER))
      return;
   lastDraw=now;

   int bias=0;
   g_engine.Bias(0,bias);
   string txt="Olive EA  |  "+_Symbol+" "+EnumToString((ENUM_TIMEFRAMES)_Period)+"\n";
   txt+=StringFormat("Bias: %s\n",bias>0 ? "BULLISH" : (bias<0 ? "BEARISH" : "NEUTRAL"));
   txt+=(InpLotMode==OLIVE_LOT_FIXED) ? StringFormat("Lot: fixed %.2f   RR: 1:%.1f\n",InpFixedLot,InpRewardRisk)
                                      : StringFormat("Risk/trade: %.2f%%   RR: 1:%.1f\n",InpRiskPercent,InpRewardRisk);
   txt+=StringFormat("Stop: %s   Trades today: %d\n",InpSlMode==OLIVE_SL_ATR ? "ATR" : StringFormat("fixed %d pts",InpFixedSlPoints),g_tradesToday);
   txt+=StringFormat("Today P/L vs start: %.2f%%  (limit -%.1f%%)\n",-g_dailyLossPct,InpMaxDailyLossPct);
   txt+=StringFormat("Drawdown from peak: %.2f%%  (limit %.1f%%)\n",g_ddPct,InpMaxDrawdownPct);
   txt+="Status: "+(Halted() ? "HALTED - max drawdown" : (DailyBlocked() ? "Stopped for today" : g_status))+"\n";
   Comment(txt);
  }
//+------------------------------------------------------------------+
