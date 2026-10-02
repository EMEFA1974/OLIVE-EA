//+------------------------------------------------------------------+
//|                                                 Mt.Zion Ind.mq5 |
//|        Clean candlestick + market-structure indicator for MT5    |
//|                                                                  |
//|  What it shows                                                   |
//|   - Confirmed swing highs / lows (fractal-style, no repaint once |
//|     confirmed)                                                   |
//|   - Break of Structure (BOS) and Change of Character (CHoCH)     |
//|     on candle CLOSE beyond the last swing                        |
//|   - Buy / Sell arrows from engulfing and pin-bar candles, only   |
//|     when they agree with structure (trend) and form in the       |
//|     discount (buys) / premium (sells) half of the dealing range  |
//|   - Entry / TP / SL zone box for the latest signal, drawn at the |
//|     right edge of the chart                                      |
//|                                                                  |
//|  Tuned for XAUUSD M5. All size filters are ATR based, so it      |
//|  adapts to gold's volatility and broker digit differences.       |
//|  Signals are evaluated on CLOSED candles only.                   |
//+------------------------------------------------------------------+
#property copyright   "OLIVE-EA"
#property version     "1.00"
#property description "Mt.Zion Ind - candlestick structure indicator for XAUUSD M5: swings, BOS/CHoCH and filtered engulfing / pin-bar signals."
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   4

#property indicator_label1  "Buy Signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrAqua
#property indicator_width1  2

#property indicator_label2  "Sell Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrMagenta
#property indicator_width2  2

#property indicator_label3  "Swing High"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrSilver
#property indicator_width3  1

#property indicator_label4  "Swing Low"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrSilver
#property indicator_width4  1

//--- inputs
input group "Structure"
input int    InpSwingLeft       = 3;      // Swing: bars to the left
input int    InpSwingRight      = 3;      // Swing: bars to the right (confirmation lag)
input int    InpMaxBars         = 3000;   // Bars to calculate

input group "Candle patterns"
input bool   InpUseEngulfing    = true;   // Use engulfing candles
input bool   InpUsePinBar       = true;   // Use pin bars (hammer / shooting star)
input int    InpATRPeriod       = 14;     // ATR period
input double InpMinBodyATR      = 0.35;   // Engulfing: min body size (x ATR)
input double InpMinRangeATR     = 0.60;   // Pin bar: min candle range (x ATR)
input double InpPinWickRatio    = 2.0;    // Pin bar: rejection wick >= ratio x body
input double InpPinWickShare    = 0.60;   // Pin bar: rejection wick >= share of range

input group "Signal filters"
input bool   InpTrendFilter     = true;   // Only trade with structure trend
input bool   InpPDFilter        = true;   // Buys in discount / sells in premium
input int    InpCooldownBars    = 6;      // Min bars between same-side signals
input bool   InpUseSession      = false;  // Restrict signals to a session
input int    InpSessionStart    = 8;      // Session start hour (server time)
input int    InpSessionEnd      = 20;     // Session end hour (server time)

input group "Display"
input bool   InpShowBreaks      = true;   // Show BOS / CHoCH lines
input bool   InpShowPanel       = true;   // Show structure panel
input color  InpBuyArrowColor   = clrAqua;       // Buy arrow colour
input color  InpSellArrowColor  = clrMagenta;    // Sell arrow colour
input color  InpBullColor       = clrDodgerBlue; // Bullish structure colour
input color  InpBearColor       = clrTomato;     // Bearish structure colour
input color  InpLabelColor      = clrSilver;     // Swing label colour
input int    InpFontSize        = 7;      // Label font size
input double InpArrowOffsetATR  = 0.30;   // Arrow distance from candle (x ATR)

input group "Trade zone box"
input bool   InpShowZone        = true;   // Show Entry / TP / SL box at right edge
input double InpSLBufferATR     = 0.20;   // SL beyond signal candle (x ATR)
input double InpRiskReward      = 2.0;    // TP distance = risk x this ratio
input int    InpZoneBars        = 12;     // Box width in bars
input bool   InpChartShift      = true;   // Enable chart shift to make room on the right
input color  InpTPZoneColor     = C'0,95,80';    // TP zone fill
input color  InpSLZoneColor     = C'115,25,60';  // SL zone fill
input color  InpEntryColor      = clrWhite;      // Entry line / text colour

input group "Alerts"
input bool   InpAlertPopup      = true;   // Popup alert
input bool   InpAlertPush       = false;  // Push notification
input bool   InpAlertSound      = false;  // Sound only

//--- buffers
double BuyBuf[];
double SellBuf[];
double SwingHighBuf[];
double SwingLowBuf[];
double AtrBuf[];

//--- state
const string PREFIX = "CSX_";
datetime     g_lastAlertTime = 0;
int          g_trend         = 0;      // 1 bullish, -1 bearish, 0 undefined
string       g_lastBreak     = "-";

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpSwingLeft < 1 || InpSwingRight < 1 || InpATRPeriod < 1)
     {
      Print("Mt.Zion Ind: swing and ATR periods must be >= 1");
      return(INIT_PARAMETERS_INCORRECT);
     }

   SetIndexBuffer(0, BuyBuf,       INDICATOR_DATA);
   SetIndexBuffer(1, SellBuf,      INDICATOR_DATA);
   SetIndexBuffer(2, SwingHighBuf, INDICATOR_DATA);
   SetIndexBuffer(3, SwingLowBuf,  INDICATOR_DATA);
   SetIndexBuffer(4, AtrBuf,       INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(0, PLOT_ARROW, 241);   // hollow up arrow
   PlotIndexSetInteger(1, PLOT_ARROW, 242);   // hollow down arrow
   PlotIndexSetInteger(2, PLOT_ARROW, 159);
   PlotIndexSetInteger(3, PLOT_ARROW, 159);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpBuyArrowColor);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpSellArrowColor);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, InpLabelColor);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, InpLabelColor);
   for(int p = 0; p < 4; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME, "Mt.Zion Ind");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
      Print("Mt.Zion Ind: tuned for XAUUSD, current symbol is ", _Symbol);
   if(_Period != PERIOD_M5)
      Print("Mt.Zion Ind: tuned for M5, current timeframe is ", EnumToString(_Period));

   if(InpShowZone && InpChartShift)
      ChartSetInteger(0, CHART_SHIFT, true);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PREFIX);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
double TrueRange(const int i, const double &h[], const double &l[], const double &c[])
  {
   return(MathMax(h[i], c[i - 1]) - MathMin(l[i], c[i - 1]));
  }

bool IsSwingHigh(const int p, const double &h[])
  {
   for(int k = 1; k <= InpSwingLeft; k++)
      if(h[p - k] >= h[p])
         return(false);
   for(int k = 1; k <= InpSwingRight; k++)
      if(h[p + k] > h[p])
         return(false);
   return(true);
  }

bool IsSwingLow(const int p, const double &l[])
  {
   for(int k = 1; k <= InpSwingLeft; k++)
      if(l[p - k] <= l[p])
         return(false);
   for(int k = 1; k <= InpSwingRight; k++)
      if(l[p + k] < l[p])
         return(false);
   return(true);
  }

bool BullEngulfing(const int i, const double &o[], const double &c[], const double atr)
  {
   double body = c[i] - o[i];
   double prevBody = o[i - 1] - c[i - 1];
   return(prevBody > 0.0 && body > 0.0 &&
          c[i] >= o[i - 1] && o[i] <= c[i - 1] &&
          body >= prevBody && body >= InpMinBodyATR * atr);
  }

bool BearEngulfing(const int i, const double &o[], const double &c[], const double atr)
  {
   double body = o[i] - c[i];
   double prevBody = c[i - 1] - o[i - 1];
   return(prevBody > 0.0 && body > 0.0 &&
          c[i] <= o[i - 1] && o[i] >= c[i - 1] &&
          body >= prevBody && body >= InpMinBodyATR * atr);
  }

bool BullPinBar(const int i, const double &o[], const double &h[], const double &l[], const double &c[], const double atr)
  {
   double range = h[i] - l[i];
   if(range <= 0.0 || range < InpMinRangeATR * atr)
      return(false);
   double body  = MathAbs(c[i] - o[i]);
   double lower = MathMin(o[i], c[i]) - l[i];
   double upper = h[i] - MathMax(o[i], c[i]);
   return(lower >= InpPinWickRatio * body &&
          lower >= InpPinWickShare * range &&
          upper <= 0.25 * range);
  }

bool BearPinBar(const int i, const double &o[], const double &h[], const double &l[], const double &c[], const double atr)
  {
   double range = h[i] - l[i];
   if(range <= 0.0 || range < InpMinRangeATR * atr)
      return(false);
   double body  = MathAbs(c[i] - o[i]);
   double upper = h[i] - MathMax(o[i], c[i]);
   double lower = MathMin(o[i], c[i]) - l[i];
   return(upper >= InpPinWickRatio * body &&
          upper >= InpPinWickShare * range &&
          lower <= 0.25 * range);
  }

bool InSession(const datetime t)
  {
   if(!InpUseSession)
      return(true);
   MqlDateTime dt;
   TimeToStruct(t, dt);
   if(InpSessionStart <= InpSessionEnd)
      return(dt.hour >= InpSessionStart && dt.hour < InpSessionEnd);
   return(dt.hour >= InpSessionStart || dt.hour < InpSessionEnd);   // wraps midnight
  }

void DrawText(const string name, const datetime t, const double price, const string txt,
              const color clr, const ENUM_ANCHOR_POINT anchor, const int size = 0)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   else
      ObjectMove(0, name, 0, t, price);
   ObjectSetString(0, name, OBJPROP_TEXT, txt);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size > 0 ? size : InpFontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

void DrawLevel(const string name, const datetime t1, const datetime t2, const double price,
               const color clr, const ENUM_LINE_STYLE style)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   else
     {
      ObjectMove(0, name, 0, t1, price);
      ObjectMove(0, name, 1, t2, price);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
  }

void DrawRect(const string name, const datetime t1, const double p1, const datetime t2, const double p2,
              const color clr)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   else
     {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

//--- Entry / TP / SL box for the latest signal, drawn just right of the current candle
void DrawZone(const datetime lastBarTime, const int dir, const double entry, const double sl,
              const double tp, const string status)
  {
   if(!InpShowZone || dir == 0)
      return;
   int      sec = PeriodSeconds();
   datetime t1  = lastBarTime + sec;
   datetime t2  = t1 + sec * MathMax(InpZoneBars, 2);

   DrawRect(PREFIX + "Z_TP", t1, entry, t2, tp, InpTPZoneColor);
   DrawRect(PREFIX + "Z_SL", t1, entry, t2, sl, InpSLZoneColor);
   DrawLevel(PREFIX + "Z_EN", t1, t2, entry, InpEntryColor, STYLE_SOLID);
   ObjectSetInteger(0, PREFIX + "Z_EN", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, PREFIX + "Z_EN", OBJPROP_BACK, false);

   bool   up  = (tp > entry);
   string tpT = "TP  " + DoubleToString(tp, _Digits);
   string slT = "SL  " + DoubleToString(sl, _Digits);
   string enT = "ENTRY  " + DoubleToString(entry, _Digits);
   DrawText(PREFIX + "Z_TPT", t2, tp, tpT, InpEntryColor, up ? ANCHOR_RIGHT_UPPER : ANCHOR_RIGHT_LOWER, 8);
   DrawText(PREFIX + "Z_SLT", t2, sl, slT, InpEntryColor, up ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER, 8);
   DrawText(PREFIX + "Z_ENT", t2, entry, enT, InpEntryColor, up ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER, 8);

   string head = StringFormat("%s  |  %s  |  RR 1:%s", dir == 1 ? "BUY" : "SELL", status,
                              DoubleToString(InpRiskReward, 1));
   DrawText(PREFIX + "Z_HD", t1, MathMax(tp, sl), head, dir == 1 ? InpBuyArrowColor : InpSellArrowColor,
            ANCHOR_LEFT_LOWER, 8);
  }

void DrawPanel()
  {
   string name = PREFIX + "Panel";
   if(!InpShowPanel)
      return;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   string trendTxt = (g_trend == 1) ? "Bullish" : (g_trend == -1) ? "Bearish" : "Ranging";
   color  clr      = (g_trend == 1) ? InpBullColor : (g_trend == -1) ? InpBearColor : InpLabelColor;
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 20);
   ObjectSetString(0, name, OBJPROP_TEXT, "Structure: " + trendTxt + "  |  Last: " + g_lastBreak);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

void SendSignalAlert(const string side, const string pattern, const double price, const double sl,
                     const double tp, const datetime t)
  {
   string msg = StringFormat("%s %s: %s %s @ %s  SL %s  TP %s (%s)", _Symbol, EnumToString(_Period), side, pattern,
                             DoubleToString(price, _Digits), DoubleToString(sl, _Digits),
                             DoubleToString(tp, _Digits), TimeToString(t, TIME_DATE | TIME_MINUTES));
   if(InpAlertPopup)
      Alert(msg);
   if(InpAlertPush)
      SendNotification(msg);
   if(InpAlertSound && !InpAlertPopup)
      PlaySound("alert.wav");
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
   int minBars = InpATRPeriod + InpSwingLeft + InpSwingRight + 5;
   if(rates_total < minBars)
      return(0);

   //--- everything is evaluated on closed candles: only work when a new bar appears
   if(prev_calculated == rates_total)
      return(rates_total);

   ArrayInitialize(BuyBuf, EMPTY_VALUE);
   ArrayInitialize(SellBuf, EMPTY_VALUE);
   ArrayInitialize(SwingHighBuf, EMPTY_VALUE);
   ArrayInitialize(SwingLowBuf, EMPTY_VALUE);
   ArrayInitialize(AtrBuf, 0.0);
   ObjectsDeleteAll(0, PREFIX);

   //--- ATR (simple average of true range)
   int a0 = MathMax(1, rates_total - InpMaxBars - InpATRPeriod - 1);
   double sum = 0.0;
   for(int i = a0; i < rates_total; i++)
     {
      sum += TrueRange(i, high, low, close);
      if(i - a0 >= InpATRPeriod)
         sum -= TrueRange(i - InpATRPeriod, high, low, close);
      if(i - a0 + 1 >= InpATRPeriod)
         AtrBuf[i] = sum / InpATRPeriod;
     }

   //--- structure state
   int    begin       = MathMax(a0 + InpATRPeriod, InpSwingLeft + InpSwingRight + 1);
   int    lastClosed  = rates_total - 2;
   int    trend       = 0;
   double lastHigh    = 0.0, lastLow = 0.0;
   int    lastHighBar = -1,  lastLowBar = -1;
   bool   highBroken  = true, lowBroken = true;
   double hiSinceLow  = 0.0, loSinceHigh = 0.0;     // dealing-range extremes
   int    lastBuyBar  = -1000000, lastSellBar = -1000000;
   string lastBreak   = "-";
   string buyPattern  = "", sellPattern = "";
   double buySL = 0.0, buyTP = 0.0, sellSL = 0.0, sellTP = 0.0;
   int    tDir        = 0;                          // latest signal: 1 buy, -1 sell
   int    tBar        = -1;
   double tEntry      = 0.0, tSL = 0.0, tTP = 0.0;
   string tStatus     = "";

   for(int i = begin; i <= lastClosed; i++)
     {
      double atr = AtrBuf[i];
      if(atr <= 0.0)
         continue;

      //--- 0) follow the latest signal until TP or SL is touched (SL checked first)
      if(tDir != 0 && i > tBar && tStatus == "Active")
        {
         if(tDir == 1)
            tStatus = (low[i] <= tSL) ? "SL hit" : (high[i] >= tTP) ? "TP hit" : "Active";
         else
            tStatus = (high[i] >= tSL) ? "SL hit" : (low[i] <= tTP) ? "TP hit" : "Active";
        }

      //--- 1) confirm the swing that is now InpSwingRight bars old
      int p = i - InpSwingRight;
      if(p - InpSwingLeft >= 0)
        {
         if(IsSwingHigh(p, high))
           {
            lastHigh    = high[p];
            lastHighBar = p;
            highBroken  = false;
            loSinceHigh = low[p];
            for(int k = p + 1; k <= i; k++)
               loSinceHigh = MathMin(loSinceHigh, low[k]);
            SwingHighBuf[p] = high[p] + 0.15 * atr;
           }
         if(IsSwingLow(p, low))
           {
            lastLow    = low[p];
            lastLowBar = p;
            lowBroken  = false;
            hiSinceLow = high[p];
            for(int k = p + 1; k <= i; k++)
               hiSinceLow = MathMax(hiSinceLow, high[k]);
            SwingLowBuf[p] = low[p] - 0.15 * atr;
           }
        }

      //--- keep dealing-range extremes current
      if(lastLowBar >= 0)
         hiSinceLow = MathMax(hiSinceLow, high[i]);
      if(lastHighBar >= 0)
         loSinceHigh = MathMin(loSinceHigh, low[i]);

      //--- 2) structure breaks on candle close
      if(!highBroken && lastHighBar >= 0 && close[i] > lastHigh)
        {
         string tag = (trend == -1) ? "CHoCH" : "BOS";
         if(InpShowBreaks)
           {
            string id = (string)(long)time[lastHighBar];
            DrawLevel(PREFIX + "BU_" + id, time[lastHighBar], time[i], lastHigh, InpBullColor,
                      tag == "BOS" ? STYLE_SOLID : STYLE_DASH);
            DrawText(PREFIX + "BUT_" + id, time[(lastHighBar + i) / 2], lastHigh, tag, InpBullColor, ANCHOR_LOWER);
           }
         trend      = 1;
         highBroken = true;
         lastBreak  = "Bullish " + tag;
        }
      if(!lowBroken && lastLowBar >= 0 && close[i] < lastLow)
        {
         string tag = (trend == 1) ? "CHoCH" : "BOS";
         if(InpShowBreaks)
           {
            string id = (string)(long)time[lastLowBar];
            DrawLevel(PREFIX + "BD_" + id, time[lastLowBar], time[i], lastLow, InpBearColor,
                      tag == "BOS" ? STYLE_SOLID : STYLE_DASH);
            DrawText(PREFIX + "BDT_" + id, time[(lastLowBar + i) / 2], lastLow, tag, InpBearColor, ANCHOR_UPPER);
           }
         trend     = -1;
         lowBroken = true;
         lastBreak = "Bearish " + tag;
        }

      //--- 3) candle patterns in structural context
      if(!InSession(time[i]))
         continue;

      string bull = "";
      if(InpUseEngulfing && BullEngulfing(i, open, close, atr))
         bull = "Bullish Engulfing";
      else if(InpUsePinBar && BullPinBar(i, open, high, low, close, atr))
         bull = "Bullish Pin Bar";

      if(bull != "")
        {
         bool ok = true;
         if(InpTrendFilter && trend != 1)
            ok = false;
         if(ok && InpPDFilter)
           {
            if(lastLowBar < 0)
               ok = false;
            else if(low[i] > (lastLow + hiSinceLow) * 0.5)
               ok = false;                                  // not in discount
           }
         if(ok && i - lastBuyBar < InpCooldownBars)
            ok = false;
         if(ok)
           {
            BuyBuf[i]  = low[i] - InpArrowOffsetATR * atr;
            lastBuyBar = i;
            tDir    = 1;
            tBar    = i;
            tEntry  = close[i];
            tSL     = low[i] - InpSLBufferATR * atr;
            tTP     = tEntry + (tEntry - tSL) * InpRiskReward;
            tStatus = "Active";
            if(i == lastClosed)
              {
               buyPattern = bull;
               buySL      = tSL;
               buyTP      = tTP;
              }
           }
        }

      string bear = "";
      if(InpUseEngulfing && BearEngulfing(i, open, close, atr))
         bear = "Bearish Engulfing";
      else if(InpUsePinBar && BearPinBar(i, open, high, low, close, atr))
         bear = "Bearish Pin Bar";

      if(bear != "")
        {
         bool ok = true;
         if(InpTrendFilter && trend != -1)
            ok = false;
         if(ok && InpPDFilter)
           {
            if(lastHighBar < 0)
               ok = false;
            else if(high[i] < (lastHigh + loSinceHigh) * 0.5)
               ok = false;                                  // not in premium
           }
         if(ok && i - lastSellBar < InpCooldownBars)
            ok = false;
         if(ok)
           {
            SellBuf[i]  = high[i] + InpArrowOffsetATR * atr;
            lastSellBar = i;
            tDir    = -1;
            tBar    = i;
            tEntry  = close[i];
            tSL     = high[i] + InpSLBufferATR * atr;
            tTP     = tEntry - (tSL - tEntry) * InpRiskReward;
            tStatus = "Active";
            if(i == lastClosed)
              {
               sellPattern = bear;
               sellSL      = tSL;
               sellTP      = tTP;
              }
           }
        }
     }

   g_trend     = trend;
   g_lastBreak = lastBreak;
   DrawPanel();
   DrawZone(time[rates_total - 1], tDir, tEntry, tSL, tTP, tStatus);

   //--- alerts for the candle that just closed (skip the initial history load)
   datetime closedTime = time[lastClosed];
   if(prev_calculated == 0)
      g_lastAlertTime = closedTime;
   else if(closedTime != g_lastAlertTime)
     {
      g_lastAlertTime = closedTime;
      if(buyPattern != "")
         SendSignalAlert("BUY", buyPattern, close[lastClosed], buySL, buyTP, closedTime);
      if(sellPattern != "")
         SendSignalAlert("SELL", sellPattern, close[lastClosed], sellSL, sellTP, closedTime);
     }

   ChartRedraw();
   return(rates_total);
  }
//+------------------------------------------------------------------+
