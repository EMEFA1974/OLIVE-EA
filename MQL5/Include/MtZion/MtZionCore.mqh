//+------------------------------------------------------------------+
//|                                                    MtZionCore.mqh |
//|  Shared signal engine for the Mt.Zion Ind indicator     |
//|  and the Mt.Zion EA. Both programs use this exact code, so what    |
//|  the indicator shows is what the EA trades.                      |
//|                                                                  |
//|  Strategy (all evaluated on CLOSED bars only - no repainting):   |
//|   1. Bias   : higher-timeframe close vs. EMA, with EMA slope.    |
//|   2. Trend  : chart fast EMA above/below slow EMA.               |
//|   3. Pullbk : price touched the fast EMA within the last N bars  |
//|               without closing beyond the slow EMA.               |
//|   4. Trigger: bar closes back in trend direction beyond the      |
//|               previous bar's high/low, RSI in momentum zone,     |
//|               optional ADX strength filter.                      |
//|   5. Risk   : SL beyond pullback swing + ATR buffer, bounded by  |
//|               min/max ATR multiples; TP at fixed reward:risk.    |
//+------------------------------------------------------------------+
#ifndef MTZION_CORE_MQH
#define MTZION_CORE_MQH

enum ENUM_MTZION_SL_MODE
  {
   MTZION_SL_ATR=0,     // ATR-based (beyond pullback swing)
   MTZION_SL_FIXED=1    // Fixed distance in points
  };

struct MtZionSettings
  {
   ENUM_TIMEFRAMES   htf;            // higher timeframe for bias
   int               htfEmaPeriod;   // HTF EMA period
   int               htfSlopeBars;   // HTF EMA slope lookback (bars)
   int               fastEma;        // chart fast EMA
   int               slowEma;        // chart slow EMA
   int               rsiPeriod;
   double            rsiMin;         // buy RSI zone lower bound (sell = 100 - rsiMax)
   double            rsiMax;         // buy RSI zone upper bound (sell = 100 - rsiMin)
   int               adxPeriod;
   double            adxMin;         // 0 disables the ADX filter
   int               atrPeriod;
   int               pullbackBars;   // pullback lookback window
   double            slAtrBuffer;    // ATR buffer beyond swing
   double            minSlAtr;       // minimum SL distance in ATR
   double            maxSlAtr;       // skip trade if SL wider than this (ATR)
   double            rewardRisk;     // TP = SL distance * rewardRisk
   ENUM_MTZION_SL_MODE slMode;        // ATR or fixed-points stop
   int               fixedSlPoints;  // stop distance when slMode = fixed
  };

struct MtZionSignal
  {
   int               direction;      // 1 buy, -1 sell, 0 none
   datetime          barTime;        // signal bar open time
   double            entry;          // signal bar close
   double            sl;
   double            tp;
   double            atr;
  };

//+------------------------------------------------------------------+
//| Signal engine                                                    |
//+------------------------------------------------------------------+
class CMtZionEngine
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   MtZionSettings     m_s;
   int               h_htfEma;
   int               h_fast;
   int               h_slow;
   int               h_rsi;
   int               h_adx;
   int               h_atr;

   bool              Value(const int handle,const int shift,double &v)
     {
      double tmp[];
      if(CopyBuffer(handle,0,shift,1,tmp)!=1)
         return false;
      v=tmp[0];
      return (v!=EMPTY_VALUE);
     }

   //--- final stop distance; false = setup too wide to trade (ATR mode)
   bool              StopDistance(const double swingDist,const double atr,double &dist)
     {
      if(m_s.slMode==MTZION_SL_FIXED)
        {
         dist=m_s.fixedSlPoints*SymbolInfoDouble(m_symbol,SYMBOL_POINT);
         return (dist>0);
        }
      dist=MathMax(swingDist,atr*m_s.minSlAtr);
      return (dist<=atr*m_s.maxSlAtr);
     }

public:
                     CMtZionEngine(void) : h_htfEma(INVALID_HANDLE),h_fast(INVALID_HANDLE),
                     h_slow(INVALID_HANDLE),h_rsi(INVALID_HANDLE),
                     h_adx(INVALID_HANDLE),h_atr(INVALID_HANDLE) {}
                    ~CMtZionEngine(void) { Release(); }

   //--- create indicator handles; returns false on bad settings or handle failure
   bool              Init(const string symbol,const ENUM_TIMEFRAMES tf,const MtZionSettings &s)
     {
      m_symbol=symbol;
      m_tf=(tf==PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)Period() : tf;
      m_s=s;
      if(m_s.htf==PERIOD_CURRENT || PeriodSeconds(m_s.htf)<PeriodSeconds(m_tf))
        {
         if(m_s.htf!=PERIOD_CURRENT)
            PrintFormat("Mt.Zion: bias timeframe is lower than chart timeframe - using %s instead",EnumToString(m_tf));
         m_s.htf=m_tf;
        }
      if(m_s.htfSlopeBars<1)
         m_s.htfSlopeBars=1;
      if(m_s.pullbackBars<1)
         m_s.pullbackBars=1;
      if(m_s.fastEma<1 || m_s.slowEma<=m_s.fastEma || m_s.htfEmaPeriod<1 ||
         m_s.rsiPeriod<1 || m_s.atrPeriod<1 || m_s.adxPeriod<1 ||
         m_s.rewardRisk<=0 || m_s.minSlAtr<=0 || m_s.maxSlAtr<m_s.minSlAtr ||
         m_s.rsiMin>=m_s.rsiMax || (m_s.slMode==MTZION_SL_FIXED && m_s.fixedSlPoints<=0))
        {
         Print("Mt.Zion: invalid strategy settings");
         return false;
        }

      h_htfEma=iMA(m_symbol,m_s.htf,m_s.htfEmaPeriod,0,MODE_EMA,PRICE_CLOSE);
      h_fast  =iMA(m_symbol,m_tf,m_s.fastEma,0,MODE_EMA,PRICE_CLOSE);
      h_slow  =iMA(m_symbol,m_tf,m_s.slowEma,0,MODE_EMA,PRICE_CLOSE);
      h_rsi   =iRSI(m_symbol,m_tf,m_s.rsiPeriod,PRICE_CLOSE);
      h_adx   =iADX(m_symbol,m_tf,m_s.adxPeriod);
      h_atr   =iATR(m_symbol,m_tf,m_s.atrPeriod);
      if(h_htfEma==INVALID_HANDLE || h_fast==INVALID_HANDLE || h_slow==INVALID_HANDLE ||
         h_rsi==INVALID_HANDLE || h_adx==INVALID_HANDLE || h_atr==INVALID_HANDLE)
        {
         PrintFormat("Mt.Zion: failed to create indicator handles (error %d)",GetLastError());
         return false;
        }
      return true;
     }

   void              Release(void)
     {
      if(h_htfEma!=INVALID_HANDLE) { IndicatorRelease(h_htfEma); h_htfEma=INVALID_HANDLE; }
      if(h_fast!=INVALID_HANDLE)   { IndicatorRelease(h_fast);   h_fast=INVALID_HANDLE; }
      if(h_slow!=INVALID_HANDLE)   { IndicatorRelease(h_slow);   h_slow=INVALID_HANDLE; }
      if(h_rsi!=INVALID_HANDLE)    { IndicatorRelease(h_rsi);    h_rsi=INVALID_HANDLE; }
      if(h_adx!=INVALID_HANDLE)    { IndicatorRelease(h_adx);    h_adx=INVALID_HANDLE; }
      if(h_atr!=INVALID_HANDLE)    { IndicatorRelease(h_atr);    h_atr=INVALID_HANDLE; }
     }

   //--- all underlying indicators have data
   bool              Ready(void)
     {
      return (BarsCalculated(h_htfEma)>0 && BarsCalculated(h_fast)>0 && BarsCalculated(h_slow)>0 &&
              BarsCalculated(h_rsi)>0 && BarsCalculated(h_adx)>0 && BarsCalculated(h_atr)>0);
     }

   int               MinBars(void) const
     {
      return MathMax(m_s.slowEma,MathMax(m_s.adxPeriod*2,m_s.atrPeriod))+m_s.pullbackBars+5;
     }

   bool              Lines(const int shift,double &fast,double &slow)
     {
      return (Value(h_fast,shift,fast) && Value(h_slow,shift,slow));
     }

   bool              Atr(const int shift,double &atr)
     {
      return Value(h_atr,shift,atr);
     }

   //--- higher-timeframe bias for the chart bar at 'shift', using the last
   //--- fully CLOSED HTF bar before it (never the forming one)
   bool              Bias(const int shift,int &bias)
     {
      bias=0;
      datetime t=iTime(m_symbol,m_tf,shift);
      if(t==0)
         return false;
      int hs=iBarShift(m_symbol,m_s.htf,t,false);
      if(hs<0)
         return false;
      hs+=1;
      double e0,e1;
      if(!Value(h_htfEma,hs,e0) || !Value(h_htfEma,hs+m_s.htfSlopeBars,e1))
         return false;
      double c=iClose(m_symbol,m_s.htf,hs);
      if(c<=0)
         return false;
      if(c>e0 && e0>e1)
         bias=1;
      else
         if(c<e0 && e0<e1)
            bias=-1;
      return true;
     }

   //--- evaluate the closed bar at 'shift' (>=1). Returns false only when
   //--- data is unavailable; sig.direction holds the result.
   bool              Evaluate(const int shift,MtZionSignal &sig)
     {
      ZeroMemory(sig);
      sig.barTime=iTime(m_symbol,m_tf,shift);

      int bias;
      if(!Bias(shift,bias))
         return false;

      int n=m_s.pullbackBars;
      double fast[],slow[];
      MqlRates r[];
      ArraySetAsSeries(fast,true);
      ArraySetAsSeries(slow,true);
      ArraySetAsSeries(r,true);
      if(CopyBuffer(h_fast,0,shift,n,fast)!=n)
         return false;
      if(CopyBuffer(h_slow,0,shift,n,slow)!=n)
         return false;
      if(CopyRates(m_symbol,m_tf,shift,n+1,r)!=n+1)
         return false;

      double atr,rsi,adx=0;
      if(!Value(h_atr,shift,atr) || !Value(h_rsi,shift,rsi))
         return false;
      if(m_s.adxMin>0 && !Value(h_adx,shift,adx))
         return false;
      sig.atr=atr;

      if(bias==0 || atr<=0)
         return true;
      if(m_s.adxMin>0 && adx<m_s.adxMin)
         return true;

      double c=r[0].close;
      double o=r[0].open;

      if(bias>0)
        {
         if(fast[0]<=slow[0])
            return true;
         bool touched=false;
         double swing=DBL_MAX;
         for(int k=0; k<n; k++)
           {
            if(r[k].close<=slow[k])
               return true;              // pullback too deep - structure broken
            if(r[k].low<=fast[k])
               touched=true;
            swing=MathMin(swing,r[k].low);
           }
         if(!touched)
            return true;
         if(!(c>o && c>fast[0] && c>r[1].high))
            return true;
         if(rsi<m_s.rsiMin || rsi>m_s.rsiMax)
            return true;

         double dist;
         if(!StopDistance(c-(swing-atr*m_s.slAtrBuffer),atr,dist))
            return true;
         double sl=c-dist;
         sig.direction=1;
         sig.entry=c;
         sig.sl=sl;
         sig.tp=c+dist*m_s.rewardRisk;
        }
      else
        {
         if(fast[0]>=slow[0])
            return true;
         bool touched=false;
         double swing=-DBL_MAX;
         for(int k=0; k<n; k++)
           {
            if(r[k].close>=slow[k])
               return true;
            if(r[k].high>=fast[k])
               touched=true;
            swing=MathMax(swing,r[k].high);
           }
         if(!touched)
            return true;
         if(!(c<o && c<fast[0] && c<r[1].low))
            return true;
         if(rsi>100.0-m_s.rsiMin || rsi<100.0-m_s.rsiMax)
            return true;

         double dist;
         if(!StopDistance((swing+atr*m_s.slAtrBuffer)-c,atr,dist))
            return true;
         double sl=c+dist;
         sig.direction=-1;
         sig.entry=c;
         sig.sl=sl;
         sig.tp=c-dist*m_s.rewardRisk;
        }
      return true;
     }

   //--- like Evaluate, but suppresses a signal that merely repeats the
   //--- previous bar's signal in the same direction
   bool              EvaluateFresh(const int shift,MtZionSignal &sig)
     {
      if(!Evaluate(shift,sig))
         return false;
      if(sig.direction!=0)
        {
         MtZionSignal prev;
         if(Evaluate(shift+1,prev) && prev.direction==sig.direction)
            sig.direction=0;
        }
      return true;
     }
  };

//+------------------------------------------------------------------+
//| Position size so that a stop-out loses at most riskMoney.        |
//| Returns 0 when even the minimum lot would exceed the risk.       |
//+------------------------------------------------------------------+
double MtZionLotsForRisk(const string symbol,const ENUM_ORDER_TYPE type,
                        const double entry,const double sl,const double riskMoney)
  {
   if(riskMoney<=0 || entry<=0 || sl<=0 || entry==sl)
      return 0.0;
   double pl=0.0;
   if(!OrderCalcProfit(type,symbol,1.0,entry,sl,pl))
      return 0.0;
   double lossPerLot=MathAbs(pl);
   if(lossPerLot<=0)
      return 0.0;

   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   double vmin=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double vmax=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   if(step<=0)
      step=0.01;

   double lots=MathFloor(riskMoney/lossPerLot/step+1e-9)*step;
   if(lots<vmin)
      return 0.0;
   lots=MathMin(lots,vmax);
   int digits=(int)MathMax(0,MathCeil(-MathLog10(step)-1e-9));
   return NormalizeDouble(lots,digits);
  }

#endif // MTZION_CORE_MQH
//+------------------------------------------------------------------+
