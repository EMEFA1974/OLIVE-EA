//+------------------------------------------------------------------+
//|                                           Mt.Zion Ind.mq5 |
//|  Trend-pullback signal indicator. Non-repainting: signals are    |
//|  only printed on closed bars. Uses the same engine as Mt.Zion EA.  |
//+------------------------------------------------------------------+
#property copyright "Mt.Zion"
#property version   "1.00"
#property description "Higher-timeframe trend + pullback entries with ATR stop, target and risk-based lot size."
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   4

#property indicator_label1  "Fast EMA (bias colored)"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrSilver,clrLimeGreen,clrTomato
#property indicator_width1  2

#property indicator_label2  "Slow EMA"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrSteelBlue
#property indicator_width2  1

#property indicator_label3  "Buy signal"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrLimeGreen
#property indicator_width3  2

#property indicator_label4  "Sell signal"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrTomato
#property indicator_width4  2

#include <MtZion/MtZionCore.mqh>

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
input double          InpRewardRisk   = 1.5;       // Reward : Risk

input group "Display & alerts"
input int             InpHistoryBars  = 3000;      // Bars to calculate (0 = all)
input bool            InpShowLevels   = true;      // Draw entry / SL / TP of last signal
input int             InpLevelsLookback = 30;      // Show levels if signal within N bars
input double          InpRiskPercent  = 0.5;       // Risk % for lot-size display
input bool            InpShowPanel    = true;      // Show info panel
input bool            InpAlertPopup   = true;      // Popup alert on new signal
input bool            InpAlertPush    = false;     // Push notification on new signal

double g_fast[],g_fastClr[],g_slow[],g_buy[],g_sell[],g_raw[];
CMtZionEngine g_engine;
datetime     g_lastAlert=0;
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
   PlotIndexSetInteger(2,PLOT_ARROW,233);
   PlotIndexSetInteger(3,PLOT_ARROW,234);

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
void DrawLevel(const string name,const datetime t1,const datetime t2,const double price,
               const color clr,const ENUM_LINE_STYLE style,const string text)
  {
   string obj=OBJ_PREFIX+name;
   if(ObjectFind(0,obj)<0)
      ObjectCreate(0,obj,OBJ_TREND,0,t1,price,t2,price);
   ObjectSetInteger(0,obj,OBJPROP_TIME,0,t1);
   ObjectSetDouble(0,obj,OBJPROP_PRICE,0,price);
   ObjectSetInteger(0,obj,OBJPROP_TIME,1,t2);
   ObjectSetDouble(0,obj,OBJPROP_PRICE,1,price);
   ObjectSetInteger(0,obj,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,obj,OBJPROP_STYLE,style);
   ObjectSetInteger(0,obj,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,obj,OBJPROP_SELECTABLE,false);
   ObjectSetString(0,obj,OBJPROP_TOOLTIP,text);

   string lbl=obj+"_lbl";
   if(ObjectFind(0,lbl)<0)
      ObjectCreate(0,lbl,OBJ_TEXT,0,t2,price);
   ObjectSetInteger(0,lbl,OBJPROP_TIME,0,t2);
   ObjectSetDouble(0,lbl,OBJPROP_PRICE,0,price);
   ObjectSetString(0,lbl,OBJPROP_TEXT," "+text);
   ObjectSetInteger(0,lbl,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,lbl,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,lbl,OBJPROP_ANCHOR,ANCHOR_LEFT);
   ObjectSetInteger(0,lbl,OBJPROP_SELECTABLE,false);
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

   if(InpShowLevels && have)
     {
      datetime t1=time[lastShift];
      datetime t2=time[0]+PeriodSeconds()*5;
      DrawLevel("entry",t1,t2,sig.entry,clrSilver,STYLE_DOT,StringFormat("Entry %s",DoubleToString(sig.entry,_Digits)));
      DrawLevel("sl",t1,t2,sig.sl,clrTomato,STYLE_DASH,StringFormat("SL %s",DoubleToString(sig.sl,_Digits)));
      DrawLevel("tp",t1,t2,sig.tp,clrLimeGreen,STYLE_DASH,StringFormat("TP %s (%.1fR)",DoubleToString(sig.tp,_Digits),InpRewardRisk));
     }
   else
      ObjectsDeleteAll(0,OBJ_PREFIX);

   if(!InpShowPanel)
      return;
   int bias=0;
   g_engine.Bias(0,bias);
   string txt="Mt.Zion Ind\n";
   txt+=StringFormat("Bias (%s): %s\n",EnumToString(InpHTF),bias>0 ? "BULLISH - buys only" : (bias<0 ? "BEARISH - sells only" : "NEUTRAL - stand aside"));
   if(have)
     {
      txt+=StringFormat("Last signal: %s %d bar(s) ago\n",sig.direction>0 ? "BUY" : "SELL",lastShift);
      txt+=StringFormat("Entry %s | SL %s | TP %s\n",DoubleToString(sig.entry,_Digits),
                        DoubleToString(sig.sl,_Digits),DoubleToString(sig.tp,_Digits));
      txt+=(lots>0) ? StringFormat("Lot size @ %.2f%% risk: %.2f\n",InpRiskPercent,lots)
                    : StringFormat("Min lot exceeds %.2f%% risk - skip\n",InpRiskPercent);
     }
   else
      txt+="No recent signal\n";
   Comment(txt);
  }
//+------------------------------------------------------------------+
