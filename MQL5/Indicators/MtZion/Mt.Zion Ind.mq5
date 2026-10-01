//+------------------------------------------------------------------+
//|                                           Mt.Zion Ind.mq5 |
//|  Trend-pullback signal indicator. Non-repainting: signals are    |
//|  only printed on closed bars. Uses the same engine as Mt.Zion EA.  |
//+------------------------------------------------------------------+
#property copyright "Mt.Zion"
#property version   "1.00"
#property description "Higher-timeframe trend + pullback entries with SL / TP1 / TP2 zones and risk-based lot size."
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   4

#property indicator_label1  "Fast EMA (bias colored)"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrSilver,clrAqua,clrMagenta
#property indicator_width1  2

#property indicator_label2  "Slow EMA"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrSteelBlue
#property indicator_width2  1

#property indicator_label3  "Buy signal"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrAqua
#property indicator_width3  1

#property indicator_label4  "Sell signal"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrMagenta
#property indicator_width4  1

//+------------------------------------------------------------------+
//| Mt.Zion signal engine (embedded - no external include needed).   |
//| Keep this block identical in Mt.Zion Ind and Mt.Zion EA.         |
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

//+------------------------------------------------------------------+
//| Chart drawing shared by the indicator and the EA                 |
//+------------------------------------------------------------------+
#define MTZION_BUY_CLR    clrAqua
#define MTZION_SELL_CLR   clrMagenta
#define MTZION_SL_BOX     C'150,30,30'
#define MTZION_TP1_BOX    C'20,120,40'
#define MTZION_TP2_BOX    C'20,40,170'

void MtZionRect(const string name,const datetime t1,const double p1,
                const datetime t2,const double p2,const color clr)
  {
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,p1,t2,p2);
   ObjectSetInteger(0,name,OBJPROP_TIME,0,t1);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,p1);
   ObjectSetInteger(0,name,OBJPROP_TIME,1,t2);
   ObjectSetDouble(0,name,OBJPROP_PRICE,1,p2);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FILL,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

void MtZionLevel(const string name,const datetime t1,const datetime t2,const double price,
                 const color clr,const ENUM_LINE_STYLE style,const string text,const datetime tText)
  {
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_TREND,0,t1,price,t2,price);
   ObjectSetInteger(0,name,OBJPROP_TIME,0,t1);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,price);
   ObjectSetInteger(0,name,OBJPROP_TIME,1,t2);
   ObjectSetDouble(0,name,OBJPROP_PRICE,1,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,text);

   string lbl=name+"_lbl";
   if(ObjectFind(0,lbl)<0)
      ObjectCreate(0,lbl,OBJ_TEXT,0,tText,price);
   ObjectSetInteger(0,lbl,OBJPROP_TIME,0,tText);
   ObjectSetDouble(0,lbl,OBJPROP_PRICE,0,price);
   ObjectSetString(0,lbl,OBJPROP_TEXT,text);
   ObjectSetString(0,lbl,OBJPROP_FONT,"Arial Bold");
   ObjectSetInteger(0,lbl,OBJPROP_FONTSIZE,9);
   ObjectSetInteger(0,lbl,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,lbl,OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0,lbl,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,lbl,OBJPROP_HIDDEN,true);
  }

//--- SL zone (red), entry->TP1 zone (green), TP1->TP2 zone (blue),
//--- dotted level lines with price labels, as one trade "card".
void MtZionDrawZones(const string prefix,const int dir,const datetime t1,
                     const double entry,const double sl,const double tp1,const double tp2,
                     const int boxBars)
  {
   int    digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   int    ps=PeriodSeconds();
   datetime tBox =t1+(datetime)(MathMax(boxBars,1)*ps);
   datetime tLine=tBox+(datetime)(MathMax(boxBars/2,6)*ps);
   string side=(dir>0) ? "BUY" : "SELL";

   MtZionRect(prefix+"box_sl", t1,entry,tBox,sl, MTZION_SL_BOX);
   MtZionRect(prefix+"box_tp1",t1,entry,tBox,tp1,MTZION_TP1_BOX);
   MtZionRect(prefix+"box_tp2",t1,tp1,  tBox,tp2,MTZION_TP2_BOX);

   MtZionLevel(prefix+"lvl_tp2",t1,tLine,tp2,clrDeepSkyBlue,STYLE_DOT,
               "TP2  "+DoubleToString(tp2,digits),tBox);
   MtZionLevel(prefix+"lvl_tp1",t1,tLine,tp1,clrAquamarine,STYLE_DOT,
               "TP1  "+DoubleToString(tp1,digits),tBox);
   MtZionLevel(prefix+"lvl_entry",t1,tLine,entry,clrGold,STYLE_DASH,
               "Entry  "+DoubleToString(entry,digits)+"  "+side,tBox);
   MtZionLevel(prefix+"lvl_sl",t1,tLine,sl,clrTomato,STYLE_DOT,
               "SL  "+DoubleToString(sl,digits),tBox);
  }

//--- confirmation dot: under the candle for buys, above it for sells
void MtZionDot(const string name,const int dir,const datetime t,const double price)
  {
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_ARROW,0,t,price);
   ObjectSetInteger(0,name,OBJPROP_TIME,0,t);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,price);
   ObjectSetInteger(0,name,OBJPROP_ARROWCODE,108);
   ObjectSetInteger(0,name,OBJPROP_COLOR,dir>0 ? MTZION_BUY_CLR : MTZION_SELL_CLR);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,dir>0 ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,dir>0 ? "Buy confirmation" : "Sell confirmation");
  }

#endif // MTZION_CORE_MQH
//+------------------------------------------------------------------+

input group "Strategy (keep identical to the EA)"
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
input ENUM_MTZION_SL_MODE InpSlMode   = MTZION_SL_ATR; // Stop-loss mode
input int             InpFixedSlPoints = 500;      // Fixed SL in points (500 = $5.00 on 2-digit gold)
input double          InpTp1R         = 1.0;       // TP1 (R multiple)
input double          InpRewardRisk   = 2.0;       // TP2 / final target (R multiple)

input group "Display & alerts"
input int             InpHistoryBars  = 3000;      // Bars to calculate (0 = all)
input bool            InpShowLevels   = true;      // Draw zone boxes & levels of last signal
input int             InpLevelsLookback = 30;      // Show zones if signal within N bars
input int             InpZoneBars     = 20;        // Zone box width (bars)
input double          InpRiskPercent  = 0.5;       // Risk % for lot-size display
input bool            InpShowPanel    = true;      // Show info panel
input bool            InpAlertPopup   = true;      // Popup alert on new signal
input bool            InpAlertPush    = false;     // Push notification on new signal

double g_fast[],g_fastClr[],g_slow[],g_buy[],g_sell[],g_raw[];
CMtZionEngine g_engine;
datetime     g_lastAlert=0;
datetime     g_zoneTime=0;
const string OBJ_PREFIX="MtZionInd_";

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0,g_fast,INDICATOR_DATA);
   SetIndexBuffer(1,g_fastClr,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,g_slow,INDICATOR_DATA);
   SetIndexBuffer(3,g_buy,INDICATOR_DATA);
   SetIndexBuffer(4,g_sell,INDICATOR_DATA);
   SetIndexBuffer(5,g_raw,INDICATOR_CALCULATIONS);
   ArraySetAsSeries(g_fast,true);
   ArraySetAsSeries(g_fastClr,true);
   ArraySetAsSeries(g_slow,true);
   ArraySetAsSeries(g_buy,true);
   ArraySetAsSeries(g_sell,true);
   ArraySetAsSeries(g_raw,true);
   for(int p=0; p<4; p++)
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(2,PLOT_ARROW,241);   // hollow up arrow
   PlotIndexSetInteger(3,PLOT_ARROW,242);   // hollow down arrow

   MtZionSettings s;
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
   if(InpTp1R<=0 || InpTp1R>=InpRewardRisk)
     {
      Print("Mt.Zion: TP1 must be greater than 0 and smaller than TP2");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(!g_engine.Init(_Symbol,_Period,s))
      return INIT_PARAMETERS_INCORRECT;

   IndicatorSetString(INDICATOR_SHORTNAME,"Mt.Zion Ind");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0,OBJ_PREFIX);
   if(InpShowPanel)
      Comment("");
   g_engine.Release();
  }

//+------------------------------------------------------------------+
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
   int minBars=g_engine.MinBars();
   if(rates_total<minBars+2 || !g_engine.Ready())
      return 0;

   ArraySetAsSeries(time,true);
   ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true);

   int limit;
   if(prev_calculated<=0 || prev_calculated>rates_total)
     {
      ArrayInitialize(g_fast,EMPTY_VALUE);
      ArrayInitialize(g_fastClr,0);
      ArrayInitialize(g_slow,EMPTY_VALUE);
      ArrayInitialize(g_buy,EMPTY_VALUE);
      ArrayInitialize(g_sell,EMPTY_VALUE);
      ArrayInitialize(g_raw,0);
      limit=rates_total-minBars;
      if(InpHistoryBars>0)
         limit=MathMin(limit,InpHistoryBars);
     }
   else
      limit=MathMin(rates_total-prev_calculated+1,rates_total-minBars);

   for(int s=limit; s>=0; s--)
     {
      double f,sl;
      if(g_engine.Lines(s,f,sl))
        {
         g_fast[s]=f;
         g_slow[s]=sl;
        }
      int bias=0;
      g_engine.Bias(s,bias);
      g_fastClr[s]=(bias>0) ? 1 : (bias<0 ? 2 : 0);

      g_buy[s]=EMPTY_VALUE;
      g_sell[s]=EMPTY_VALUE;
      g_raw[s]=0;
      if(s==0)
         continue;                       // never signal on the forming bar

      MtZionSignal sig;
      if(!g_engine.Evaluate(s,sig))
        {
         if(s<=2)
            return prev_calculated;      // recent data not ready - retry next tick
         continue;
        }
      g_raw[s]=sig.direction;
      if(sig.direction==0 || (s+1<rates_total && g_raw[s+1]==sig.direction))
         continue;
      if(sig.direction>0)
         g_buy[s]=low[s]-sig.atr*0.3;
      else
         g_sell[s]=high[s]+sig.atr*0.3;
     }

   //--- alerts on a freshly closed signal bar
   if(prev_calculated>0 && time[1]!=g_lastAlert &&
      (g_buy[1]!=EMPTY_VALUE || g_sell[1]!=EMPTY_VALUE))
     {
      g_lastAlert=time[1];
      string msg=StringFormat("Mt.Zion: %s signal on %s %s",
                              g_buy[1]!=EMPTY_VALUE ? "BUY" : "SELL",
                              _Symbol,EnumToString((ENUM_TIMEFRAMES)_Period));
      if(InpAlertPopup)
         Alert(msg);
      if(InpAlertPush)
         SendNotification(msg);
     }

   UpdateLevelsAndPanel(time);
   return rates_total;
  }

//+------------------------------------------------------------------+
void UpdateLevelsAndPanel(const datetime &time[])
  {
   int lastShift=-1;
   int maxLook=MathMin(InpLevelsLookback,ArraySize(time)-2);
   for(int s=1; s<=maxLook; s++)
      if(g_buy[s]!=EMPTY_VALUE || g_sell[s]!=EMPTY_VALUE)
        {
         lastShift=s;
         break;
        }

   MtZionSignal sig;
   ZeroMemory(sig);
   bool have=(lastShift>0 && g_engine.Evaluate(lastShift,sig) && sig.direction!=0);
   double lots=0;
   if(have)
     {
      double riskMoney=MathMin(AccountInfoDouble(ACCOUNT_BALANCE),AccountInfoDouble(ACCOUNT_EQUITY))*InpRiskPercent/100.0;
      lots=MtZionLotsForRisk(_Symbol,sig.direction>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,sig.entry,sig.sl,riskMoney);
     }

   double tp1=sig.entry+(sig.entry-sig.sl)*InpTp1R;   // works for both directions
   if(InpShowLevels && have)
     {
      if(time[lastShift]!=g_zoneTime)
        {
         ObjectsDeleteAll(0,OBJ_PREFIX);
         g_zoneTime=time[lastShift];
        }
      MtZionDrawZones(OBJ_PREFIX,sig.direction,time[lastShift],sig.entry,sig.sl,tp1,sig.tp,InpZoneBars);
     }
   else
     {
      ObjectsDeleteAll(0,OBJ_PREFIX);
      g_zoneTime=0;
     }

   if(!InpShowPanel)
      return;
   int bias=0;
   g_engine.Bias(0,bias);
   string txt="Mt.Zion Ind\n";
   txt+=StringFormat("Bias (%s): %s\n",EnumToString(InpHTF),bias>0 ? "BULLISH - buys only" : (bias<0 ? "BEARISH - sells only" : "NEUTRAL - stand aside"));
   if(have)
     {
      txt+=StringFormat("Last signal: %s %d bar(s) ago\n",sig.direction>0 ? "BUY" : "SELL",lastShift);
      txt+=StringFormat("Entry %s | SL %s | TP1 %s | TP2 %s\n",DoubleToString(sig.entry,_Digits),
                        DoubleToString(sig.sl,_Digits),DoubleToString(tp1,_Digits),DoubleToString(sig.tp,_Digits));
      if(lots>0)
         txt+=StringFormat("Lot size @ %.2f%% risk: %.2f\n",InpRiskPercent,lots);
      else
         txt+=StringFormat("Min lot exceeds %.2f%% risk - skip\n",InpRiskPercent);
     }
   else
      txt+="No recent signal\n";
   Comment(txt);
  }
//+------------------------------------------------------------------+
