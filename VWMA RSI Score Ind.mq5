//+------------------------------------------------------------------+
//|                                           VWMA RSI Score Ind.mq5 |
//|                                                                  |
//| 5-point bull/bear score built from four VWMAs (on High, tick     |
//| volume) and three RSIs, plus session / day / week levels.        |
//|                                                                  |
//| Score checks (bull and bear are counted separately):             |
//|   1-3. RSI 14 / 9 / 7:  bull > RsiMid, bear < RsiSellBelow       |
//|        (bear < RsiMid when the neutral zone is off)              |
//|   4.   Red VWMA1 (85): bull = whole bar above (Low > red),       |
//|        bear = whole bar below (High < red); or Close/High vs red |
//|        when UseWholeBarCheck is off                              |
//|   5.   Yellow VWMA3 (18) vs orange VWMA2 (37)                    |
//| Signal = score >= MinScore plus optional gates: green VWMA4 vs   |
//| yellow, red line slope, RSI14 not overbought/oversold. The same  |
//| direction re-arms only after its score fell to ReArmScore.       |
//| The panel scores every past signal (TP/SL in ATR multiples).     |
//+------------------------------------------------------------------+
#property version     "1.20"
#property description "Four VWMAs on High + three RSIs -> 5-point bull/bear score."
#property description "Arrow on the bar where the score first reaches MinScore."
#property indicator_chart_window
#property indicator_buffers 15
#property indicator_plots   6

#property indicator_label1  "VWMA High 1"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrRed
#property indicator_width1  3

#property indicator_label2  "VWMA High 2"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange
#property indicator_width2  3

#property indicator_label3  "VWMA High 3"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrYellow
#property indicator_width3  1

#property indicator_label4  "VWMA High 4"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrLime
#property indicator_width4  1

#property indicator_label5  "Buy signal"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrLime
#property indicator_width5  3

#property indicator_label6  "Sell signal"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrRed
#property indicator_width6  3

enum ENUM_CHECK4_PRICE
  {
   CHECK4_CLOSE = 0, // Close
   CHECK4_HIGH  = 1  // High
  };

input int               MinScore          = 5;     // Score needed for a signal (1-5)
input bool              ShowSignals       = true;  // Draw signal arrows
input bool              AlertPopup        = true;  // Popup alert on signal
input bool              AlertPush         = false; // Push notification on signal
input bool              AlertEmail        = false; // Email on signal
input bool              AutoServerOffset  = true;  // Detect broker server time offset automatically
input int               ServerUtcOffset   = 3;     // broker server time minus UTC, in hours (if not auto)
input int               VWMA1             = 85;    // VWMA1 period (red, scored vs price)
input int               VWMA2             = 37;    // VWMA2 period (orange)
input int               VWMA3             = 18;    // VWMA3 period (yellow)
input int               VWMA4             = 6;     // VWMA4 period (green, display only)
input int               RSI1              = 14;    // RSI1 period
input int               RSI2              = 9;     // RSI2 period
input int               RSI3              = 7;     // RSI3 period
input double            RsiOB             = 70.0;  // RSI14 overbought: no buys above (OB/OS filter)
input double            RsiMid            = 55.0;  // RSI bull threshold (votes bull above)
input double            RsiOS             = 30.0;  // RSI14 oversold: no sells below (OB/OS filter)
input bool              UseRsiNeutralZone = true;  // Bear vote needs RSI < RsiSellBelow (else < RsiMid)
input double            RsiSellBelow      = 45.0;  // RSI bear threshold when neutral zone is on
input int               SydS              = 21;    // Sydney start hour (UTC)
input int               SydE              = 6;     // Sydney end hour (UTC)
input int               AsiS              = 0;     // Asian start hour (UTC)
input int               AsiE              = 9;     // Asian end hour (UTC)
input int               LonS              = 7;     // London start hour (UTC)
input int               LonE              = 16;    // London end hour (UTC)
input int               NyS               = 12;    // New York start hour (UTC)
input int               NyE               = 21;    // New York end hour (UTC)
input bool              UseWholeBarCheck  = true;  // Check 4: whole bar beyond red (Low > red / High < red)
input ENUM_CHECK4_PRICE Check4Price       = CHECK4_CLOSE; // Check 4 price when whole-bar check is off
input bool              UseFastGate       = true;  // Signal also needs green VWMA4 vs yellow VWMA3 to agree
input bool              UseRedSlope       = true;  // Buy only while red VWMA1 rises, sell only while it falls
input int               RedSlopeBars      = 5;     // Bars back for the red slope comparison
input int               ReArmScore        = 2;     // Repeat same-direction signal only after its score fell to this
input bool              UseObOsFilter     = true;  // Block buys if RSI14 > RsiOB, sells if RSI14 < RsiOS
input bool              ShowStats         = true;  // Score past signals on the panel
input int               StatsAtrPeriod    = 14;    // ATR period for stats TP/SL
input double            StatsTpAtr        = 2.0;   // Stats take profit (x ATR)
input double            StatsSlAtr        = 1.0;   // Stats stop loss (x ATR)
input int               StatsMaxBars      = 48;    // Bars to wait for TP/SL before a signal counts as expired
input bool              SignalOnClosedBar = true;  // Arrows/alerts on closed bars only (no repaint)
input bool              ShowPanel         = true;  // Show info panel (click the triangle to hide/show)
input bool              ShowVwmaLines     = false; // Draw the four VWMA lines on the chart
input bool              ShowLevels        = true;  // Draw PDH/PDL and PWH/PWL lines
input int               PanelX            = 10;    // Panel X offset (px)
input int               PanelY            = 25;    // Panel Y offset (px)
input int               PanelFontSize     = 9;     // Panel font size

double V1[], V2[], V3[], V4[];
double BuyArr[], SellArr[];
double R1[], R2[], R3[];
double BullScore[], BearScore[];
double Sig[], ArmBuy[], ArmSell[];
double Atr[];

int      hR1 = INVALID_HANDLE, hR2 = INVALID_HANDLE, hR3 = INVALID_HANDLE;
int      hAtr = INVALID_HANDLE;
int      gMaxPeriod = 0;
int      gReArm     = 3;
datetime gLastAlertBar = 0;
datetime gLastStatsBar = 0;
bool     gPanelOn = true;
string   gPanelGv = "";
int      gStatWins = 0, gStatLosses = 0, gStatExpired = 0;

const string PFX = "VRS_";

//+------------------------------------------------------------------+
int OnInit()
  {
   if(VWMA1 < 1 || VWMA2 < 1 || VWMA3 < 1 || VWMA4 < 1 || RSI1 < 1 || RSI2 < 1 || RSI3 < 1)
     {
      Print("All periods must be >= 1");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(StatsAtrPeriod < 1 || RedSlopeBars < 1 || StatsMaxBars < 1 || StatsTpAtr <= 0 || StatsSlAtr <= 0)
     {
      Print("Stats/slope settings must be positive");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(UseRsiNeutralZone && RsiSellBelow > RsiMid)
     {
      Print("RsiSellBelow must not be above RsiMid");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(MinScore < 1 || MinScore > 5)
     {
      Print("MinScore must be between 1 and 5");
      return INIT_PARAMETERS_INCORRECT;
     }

   SetIndexBuffer(0, V1,        INDICATOR_DATA);
   SetIndexBuffer(1, V2,        INDICATOR_DATA);
   SetIndexBuffer(2, V3,        INDICATOR_DATA);
   SetIndexBuffer(3, V4,        INDICATOR_DATA);
   SetIndexBuffer(4, BuyArr,    INDICATOR_DATA);
   SetIndexBuffer(5, SellArr,   INDICATOR_DATA);
   SetIndexBuffer(6, R1,        INDICATOR_CALCULATIONS);
   SetIndexBuffer(7, R2,        INDICATOR_CALCULATIONS);
   SetIndexBuffer(8, R3,        INDICATOR_CALCULATIONS);
   SetIndexBuffer(9, BullScore, INDICATOR_CALCULATIONS);
   SetIndexBuffer(10, Sig,      INDICATOR_CALCULATIONS);
   SetIndexBuffer(11, ArmBuy,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(12, ArmSell,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(13, BearScore, INDICATOR_CALCULATIONS);
   SetIndexBuffer(14, Atr,      INDICATOR_CALCULATIONS);

   for(int p = 0; p < 6; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   for(int p = 0; p < 4; p++)
      PlotIndexSetInteger(p, PLOT_DRAW_TYPE, ShowVwmaLines ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, VWMA1 - 1);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, VWMA2 - 1);
   PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, VWMA3 - 1);
   PlotIndexSetInteger(3, PLOT_DRAW_BEGIN, VWMA4 - 1);
   PlotIndexSetInteger(4, PLOT_ARROW, 233);
   PlotIndexSetInteger(5, PLOT_ARROW, 234);
   PlotIndexSetInteger(4, PLOT_ARROW_SHIFT, 15);
   PlotIndexSetInteger(5, PLOT_ARROW_SHIFT, -15);

   IndicatorSetString(INDICATOR_SHORTNAME, "VWMA RSI Score Ind");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   hR1 = iRSI(_Symbol, _Period, RSI1, PRICE_CLOSE);
   hR2 = iRSI(_Symbol, _Period, RSI2, PRICE_CLOSE);
   hR3 = iRSI(_Symbol, _Period, RSI3, PRICE_CLOSE);
   hAtr = iATR(_Symbol, _Period, StatsAtrPeriod);
   if(hR1 == INVALID_HANDLE || hR2 == INVALID_HANDLE || hR3 == INVALID_HANDLE || hAtr == INVALID_HANDLE)
     {
      Print("Failed to create RSI/ATR handles");
      return INIT_FAILED;
     }

   gMaxPeriod = MathMax(MathMax(VWMA1, VWMA2), MathMax(VWMA3, VWMA4));
   gMaxPeriod = MathMax(gMaxPeriod, MathMax(RSI1, MathMax(RSI2, RSI3)));
   gMaxPeriod = MathMax(gMaxPeriod, MathMax(StatsAtrPeriod, VWMA1 - 1 + RedSlopeBars));
   gReArm     = MathMax(0, MathMin(ReArmScore, MinScore - 1));
   //--- panel open/closed state survives timeframe changes and restarts
   gPanelGv = "VRS_Panel_" + IntegerToString(ChartID());
   gPanelOn = !GlobalVariableCheck(gPanelGv) || GlobalVariableGet(gPanelGv) > 0.5;
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PFX);
   if(reason == REASON_REMOVE)
      GlobalVariableDel(gPanelGv);
   if(hR1 != INVALID_HANDLE) IndicatorRelease(hR1);
   if(hR2 != INVALID_HANDLE) IndicatorRelease(hR2);
   if(hR3 != INVALID_HANDLE) IndicatorRelease(hR3);
   if(hAtr != INVALID_HANDLE) IndicatorRelease(hAtr);
  }

//+------------------------------------------------------------------+
//| Volume-weighted MA of High over `period` bars ending at i        |
//+------------------------------------------------------------------+
double Vwma(const int i, const int period, const double &high[], const long &vol[])
  {
   if(i < period - 1)
      return EMPTY_VALUE;
   double pv = 0.0, v = 0.0, h = 0.0;
   for(int k = i - period + 1; k <= i; k++)
     {
      pv += high[k] * (double)vol[k];
      v  += (double)vol[k];
      h  += high[k];
     }
   return (v > 0.0) ? pv / v : h / period;
  }

//+------------------------------------------------------------------+
//| Count bull and bear votes for bar i. With the neutral RSI zone   |
//| or the whole-bar check a check can vote for neither side.        |
//+------------------------------------------------------------------+
void CountVotes(const int i, const double &high[], const double &low[], const double &close[],
                int &bull, int &bear)
  {
   double sellLvl = UseRsiNeutralZone ? RsiSellBelow : RsiMid;
   double rsi[3];
   rsi[0] = R1[i]; rsi[1] = R2[i]; rsi[2] = R3[i];
   bull = 0;
   bear = 0;
   for(int k = 0; k < 3; k++)
     {
      if(rsi[k] > RsiMid)       bull++;
      else if(rsi[k] < sellLvl) bear++;
     }
   if(UseWholeBarCheck)
     {
      if(low[i] > V1[i])       bull++;
      else if(high[i] < V1[i]) bear++;
     }
   else
     {
      double price = (Check4Price == CHECK4_HIGH) ? high[i] : close[i];
      if(price > V1[i])      bull++;
      else if(price < V1[i]) bear++;
     }
   if(V3[i] > V2[i])      bull++;
   else if(V3[i] < V2[i]) bear++;
  }

//+------------------------------------------------------------------+
//| Score for a direction: +1 buy, -1 sell                           |
//+------------------------------------------------------------------+
int DirScore(const int i, const int dir)
  {
   if(i < 0)
      return 0;
   double v = (dir > 0) ? BullScore[i] : BearScore[i];
   return (v == EMPTY_VALUE) ? 0 : (int)v;
  }

//+------------------------------------------------------------------+
//| Score reached, fast gate agrees and OB/OS filter passes          |
//+------------------------------------------------------------------+
bool Aligned(const int i, const int dir)
  {
   if(DirScore(i, dir) < MinScore)
      return false;
   if(UseFastGate && (dir > 0 ? V4[i] <= V3[i] : V4[i] >= V3[i]))
      return false;
   if(UseRedSlope)
     {
      int j = i - RedSlopeBars;
      if(j < VWMA1 - 1 || (dir > 0 ? V1[i] <= V1[j] : V1[i] >= V1[j]))
         return false;
     }
   if(UseObOsFilter && (dir > 0 ? R1[i] > RsiOB : R1[i] < RsiOS))
      return false;
   return true;
  }

//+------------------------------------------------------------------+
//| Broker server time minus UTC, in seconds                         |
//+------------------------------------------------------------------+
long ServerOffsetSec()
  {
   if(!AutoServerOffset)
      return (long)ServerUtcOffset * 3600;
   long d = (long)TimeTradeServer() - (long)TimeGMT();
   return (long)MathRound(d / 1800.0) * 1800;
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
   if(rates_total < gMaxPeriod + 2)
      return 0;
   if(BarsCalculated(hR1) < rates_total || BarsCalculated(hR2) < rates_total ||
      BarsCalculated(hR3) < rates_total || BarsCalculated(hAtr) < rates_total)
      return prev_calculated;

   bool full = (prev_calculated <= 0 || prev_calculated > rates_total);
   int to_copy = full ? rates_total : rates_total - prev_calculated + 1;
   if(CopyBuffer(hR1, 0, 0, to_copy, R1) <= 0) return 0;
   if(CopyBuffer(hR2, 0, 0, to_copy, R2) <= 0) return 0;
   if(CopyBuffer(hR3, 0, 0, to_copy, R3) <= 0) return 0;
   if(CopyBuffer(hAtr, 0, 0, to_copy, Atr) <= 0) return 0;

   int start = full ? 0 : prev_calculated - 1;
   for(int i = start; i < rates_total; i++)
     {
      V1[i] = Vwma(i, VWMA1, high, tick_volume);
      V2[i] = Vwma(i, VWMA2, high, tick_volume);
      V3[i] = Vwma(i, VWMA3, high, tick_volume);
      V4[i] = Vwma(i, VWMA4, high, tick_volume);
      BuyArr[i]  = EMPTY_VALUE;
      SellArr[i] = EMPTY_VALUE;

      Sig[i] = 0;
      if(i < gMaxPeriod)
        {
         BullScore[i] = EMPTY_VALUE;
         BearScore[i] = EMPTY_VALUE;
         ArmBuy[i]    = 1;
         ArmSell[i]   = 1;
         continue;
        }
      int bull, bear;
      CountVotes(i, high, low, close, bull, bear);
      BullScore[i] = bull;
      BearScore[i] = bear;

      //--- one signal per move: fire when armed and aligned, re-arm once the score has faded
      bool armB = (ArmBuy[i - 1] > 0.5);
      bool armS = (ArmSell[i - 1] > 0.5);
      if(armB && Aligned(i, 1))
        { Sig[i] = 1; armB = false; }
      else if(armS && Aligned(i, -1))
        { Sig[i] = -1; armS = false; }
      if(DirScore(i, 1) <= gReArm)
         armB = true;
      if(DirScore(i, -1) <= gReArm)
         armS = true;
      ArmBuy[i]  = armB ? 1 : 0;
      ArmSell[i] = armS ? 1 : 0;

      if(!ShowSignals || (SignalOnClosedBar && i == rates_total - 1))
         continue;
      if(Sig[i] > 0)
         BuyArr[i] = low[i];
      else if(Sig[i] < 0)
         SellArr[i] = high[i];
     }

   //--- alerts, once per bar
   int ab = SignalOnClosedBar ? rates_total - 2 : rates_total - 1;
   if(full)
      gLastAlertBar = time[ab];
   else if(time[ab] != gLastAlertBar)
     {
      int sig = (int)Sig[ab];
      if(sig != 0)
        {
         gLastAlertBar = time[ab];
         SendAlerts(sig, DirScore(ab, sig));
        }
     }

   if(ShowStats && (full || time[rates_total - 1] != gLastStatsBar))
     {
      gLastStatsBar = time[rates_total - 1];
      ComputeStats(rates_total, high, low, close);
     }

   if(ShowLevels)
      DrawLevels();
   if(ShowPanel)
      DrawPanel();
   return rates_total;
  }

//+------------------------------------------------------------------+
void SendAlerts(const int sig, const int score)
  {
   string msg = StringFormat("%s %s: %s signal (score %d/5)",
                             _Symbol, StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7),
                             (sig > 0) ? "BUY" : "SELL", score);
   if(AlertPopup) Alert(msg);
   if(AlertPush)  SendNotification(msg);
   if(AlertEmail) SendMail("VWMA RSI Score Ind", msg);
  }

//+------------------------------------------------------------------+
//| Replay every closed-bar signal: entry at the signal bar's close, |
//| TP/SL in ATR multiples. If both are hit in one bar, count a loss.|
//| Spread and commission are ignored.                               |
//+------------------------------------------------------------------+
void ComputeStats(const int total, const double &high[], const double &low[], const double &close[])
  {
   gStatWins = 0;
   gStatLosses = 0;
   gStatExpired = 0;
   for(int i = gMaxPeriod; i < total - 1; i++)
     {
      int dir = (int)Sig[i];
      if(dir == 0 || Atr[i] <= 0.0 || Atr[i] == EMPTY_VALUE)
         continue;
      double entry = close[i];
      double tp = entry + dir * StatsTpAtr * Atr[i];
      double sl = entry - dir * StatsSlAtr * Atr[i];
      int outcome = 0;
      int last = MathMin(total - 1, i + StatsMaxBars);
      for(int j = i + 1; j <= last && outcome == 0; j++)
        {
         bool hitSl = (dir > 0) ? low[j] <= sl : high[j] >= sl;
         bool hitTp = (dir > 0) ? high[j] >= tp : low[j] <= tp;
         if(hitSl)
            outcome = -1;
         else if(hitTp)
            outcome = 1;
        }
      if(outcome > 0)
         gStatWins++;
      else if(outcome < 0)
         gStatLosses++;
      else if(i + StatsMaxBars <= total - 1)
         gStatExpired++;
     }
  }

//+------------------------------------------------------------------+
//| High/low of the most recent session (current or last completed). |
//| Session hours are UTC; bar times are server time.                |
//+------------------------------------------------------------------+
bool SessionHL(const int total, const datetime &time[], const double &high[], const double &low[],
               const int sH, const int eH, double &hi, double &lo)
  {
   long off    = ServerOffsetSec();
   long nowUtc = (long)time[total - 1] - off;
   long st     = nowUtc - nowUtc % 86400 + (long)sH * 3600;
   if(st > nowUtc)
      st -= 86400;
   int len = ((eH - sH) % 24 + 24) % 24;
   if(len == 0)
      len = 24;
   long en = st + (long)len * 3600;

   hi = -DBL_MAX;
   lo = DBL_MAX;
   for(int i = total - 1; i >= 0; i--)
     {
      long u = (long)time[i] - off;
      if(u < st)
         break;
      if(u >= en)
         continue;
      hi = MathMax(hi, high[i]);
      lo = MathMin(lo, low[i]);
     }
   return hi > -DBL_MAX;
  }

//+------------------------------------------------------------------+
void HLine(const string name, const double price, const color clr, const ENUM_LINE_STYLE style)
  {
   string n = PFX + name;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, n, OBJPROP_BACK, true);
     }
   ObjectSetDouble(0, n, OBJPROP_PRICE, price);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, n, OBJPROP_STYLE, style);
  }

//+------------------------------------------------------------------+
void DrawLevels()
  {
   double pdh = iHigh(_Symbol, PERIOD_D1, 1), pdl = iLow(_Symbol, PERIOD_D1, 1);
   double pwh = iHigh(_Symbol, PERIOD_W1, 1), pwl = iLow(_Symbol, PERIOD_W1, 1);
   if(pdh > 0) HLine("PDH", pdh, clrAqua, STYLE_DOT);
   if(pdl > 0) HLine("PDL", pdl, clrAqua, STYLE_DOT);
   if(pwh > 0) HLine("PWH", pwh, clrMagenta, STYLE_DASH);
   if(pwl > 0) HLine("PWL", pwl, clrMagenta, STYLE_DASH);
  }

//+------------------------------------------------------------------+
void Lbl(const string name, const int x, const int y, const string text, const color clr)
  {
   string n = PFX + name;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetString(0, n, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, PanelFontSize);
     }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, n, OBJPROP_TEXT, text);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
  }

//+------------------------------------------------------------------+
string HL(const double hi, const double lo)
  {
   return DoubleToString(hi, _Digits) + " / " + DoubleToString(lo, _Digits);
  }

//+------------------------------------------------------------------+
//| Triangle that collapses / expands the panel                      |
//+------------------------------------------------------------------+
void DrawToggle()
  {
   string n = PFX + "TOGGLE";
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, n, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, PanelFontSize + 2);
      ObjectSetInteger(0, n, OBJPROP_COLOR, clrGold);
      ObjectSetInteger(0, n, OBJPROP_ZORDER, 10);
      ObjectSetString(0, n, OBJPROP_TOOLTIP, "Show / hide panel");
     }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, PanelX + 4);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, PanelY + 1);
   ObjectSetString(0, n, OBJPROP_TEXT, ShortToString((ushort)(gPanelOn ? 0x25BC : 0x25BA)));
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK || sparam != PFX + "TOGGLE" || !ShowPanel)
      return;
   gPanelOn = !gPanelOn;
   GlobalVariableSet(gPanelGv, gPanelOn ? 1.0 : 0.0);
   DrawPanel();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
void DrawPanel()
  {
   if(!gPanelOn)
     {
      ObjectsDeleteAll(0, PFX + "P_");
      DrawToggle();
      return;
     }

   int last = ArraySize(BullScore) - 1;
   if(last < gMaxPeriod)
      return;
   datetime time[];
   double   high[], low[];
   int total = MathMin(Bars(_Symbol, _Period), 3000);
   if(CopyTime(_Symbol, _Period, 0, total, time) < total ||
      CopyHigh(_Symbol, _Period, 0, total, high) < total ||
      CopyLow(_Symbol, _Period, 0, total, low) < total)
      return;

   int rowH = PanelFontSize * 2;
   int colW = PanelFontSize * 14;
   string bg = PFX + "P_BG";
   if(ObjectFind(0, bg) < 0)
     {
      //--- objects draw in creation order: recreate the triangle above the background
      ObjectDelete(0, PFX + "TOGGLE");
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, clrBlack);
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_COLOR, clrDimGray);
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, PanelX);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, PanelY);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, colW + PanelFontSize * 24);
   DrawToggle();
   Lbl("P_TITLE", PanelX + 8 + PanelFontSize * 2, PanelY + PanelFontSize / 2, "VWMA RSI Score Ind", clrGold);

   string names[20];
   string vals[20];
   color  cols[20];
   int r = 0;
   double hi, lo;

   names[r] = "Sydney H/L";
   vals[r]  = SessionHL(total, time, high, low, SydS, SydE, hi, lo) ? HL(hi, lo) : "-";
   cols[r++] = clrWhite;
   names[r] = "Asian H/L";
   vals[r]  = SessionHL(total, time, high, low, AsiS, AsiE, hi, lo) ? HL(hi, lo) : "-";
   cols[r++] = clrWhite;
   names[r] = "London H/L";
   vals[r]  = SessionHL(total, time, high, low, LonS, LonE, hi, lo) ? HL(hi, lo) : "-";
   cols[r++] = clrWhite;
   names[r] = "NY H/L";
   vals[r]  = SessionHL(total, time, high, low, NyS, NyE, hi, lo) ? HL(hi, lo) : "-";
   cols[r++] = clrWhite;

   names[r] = "PDH / PDL";
   vals[r]  = HL(iHigh(_Symbol, PERIOD_D1, 1), iLow(_Symbol, PERIOD_D1, 1));
   cols[r++] = clrAqua;
   names[r] = "PWH / PWL";
   vals[r]  = HL(iHigh(_Symbol, PERIOD_W1, 1), iLow(_Symbol, PERIOD_W1, 1));
   cols[r++] = clrMagenta;

   double rsis[3];
   int    pers[3];
   rsis[0] = R1[last]; rsis[1] = R2[last]; rsis[2] = R3[last];
   pers[0] = RSI1;     pers[1] = RSI2;     pers[2] = RSI3;
   double sellLvl = UseRsiNeutralZone ? RsiSellBelow : RsiMid;
   for(int k = 0; k < 3; k++)
     {
      names[r] = "RSI " + IntegerToString(pers[k]);
      vals[r]  = DoubleToString(rsis[k], 1);
      if(rsis[k] > RsiMid)
        { vals[r] += " >" + DoubleToString(RsiMid, 0); cols[r] = clrLime; }
      else if(rsis[k] < sellLvl)
        { vals[r] += " <" + DoubleToString(sellLvl, 0); cols[r] = clrOrange; }
      else
        { vals[r] += " neutral"; cols[r] = clrGray; }
      r++;
     }

   //--- basket of open positions on this symbol
   int    nb = 0, ns = 0;
   double vb = 0, vs = 0, pb = 0, ps = 0, pl = 0;
   for(int k = PositionsTotal() - 1; k >= 0; k--)
     {
      if(PositionGetTicket(k) == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      double v  = PositionGetDouble(POSITION_VOLUME);
      double op = PositionGetDouble(POSITION_PRICE_OPEN);
      pl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        { nb++; vb += v; pb += v * op; }
      else
        { ns++; vs += v; ps += v * op; }
     }
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string basket = "none", dist = "-";
   if(nb > 0 && ns == 0)
     {
      basket = StringFormat("%d buys, %.2f lots @ %s", nb, vb, DoubleToString(pb / vb, _Digits));
      dist   = DoubleToString(bid - pb / vb, _Digits) + " pts";
     }
   else if(ns > 0 && nb == 0)
     {
      basket = StringFormat("%d sells, %.2f lots @ %s", ns, vs, DoubleToString(ps / vs, _Digits));
      dist   = DoubleToString(ps / vs - bid, _Digits) + " pts";
     }
   else if(nb > 0 && ns > 0)
      basket = StringFormat("%d buys %.2f / %d sells %.2f", nb, vb, ns, vs);
   names[r] = "Basket";
   vals[r]  = basket;
   cols[r++] = clrWhite;
   names[r] = "Basket P/L";
   vals[r]  = (nb + ns > 0) ? "$" + DoubleToString(pl, 2) : "-";
   cols[r++] = (pl >= 0) ? clrLime : clrRed;
   names[r] = "Distance to entry";
   vals[r]  = dist;
   cols[r++] = clrWhite;

   //--- score and bias
   int bull = DirScore(last, 1);
   int bear = DirScore(last, -1);
   string bias = "NEUTRAL";
   color  bc   = clrGray;
   if(bull >= MinScore)
     { bias = "STRONG BULLISH"; bc = clrLime; }
   else if(bear >= MinScore)
     { bias = "STRONG BEARISH"; bc = clrRed; }
   names[r] = "Bias";
   vals[r]  = bias;
   cols[r++] = bc;
   names[r] = "Bull Score";
   vals[r]  = IntegerToString(bull) + " / 5";
   cols[r++] = (bull >= MinScore) ? clrLime : clrGray;
   names[r] = "Bear Score";
   vals[r]  = IntegerToString(bear) + " / 5";
   cols[r++] = (bear >= MinScore) ? clrRed : clrGray;

   if(ShowStats)
     {
      int done = gStatWins + gStatLosses;
      double rr = StatsTpAtr / StatsSlAtr;
      names[r] = "Signals W/L/exp";
      vals[r]  = StringFormat("%d / %d / %d", gStatWins, gStatLosses, gStatExpired);
      cols[r++] = clrWhite;
      names[r] = "Win rate";
      vals[r]  = (done > 0) ? DoubleToString(100.0 * gStatWins / done, 1) + "%  (TP " +
                 DoubleToString(StatsTpAtr, 1) + " / SL " + DoubleToString(StatsSlAtr, 1) + " ATR)" : "-";
      cols[r++] = clrWhite;
      double avgR = (done > 0) ? (gStatWins * rr - gStatLosses) / done : 0.0;
      names[r] = "Avg R per trade";
      vals[r]  = (done > 0) ? StringFormat("%+.2f R", avgR) : "-";
      cols[r++] = (avgR > 0) ? clrLime : (avgR < 0 ? clrRed : clrGray);
     }
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, (r + 1) * rowH + PanelFontSize);

   for(int k = 0; k < r; k++)
     {
      int y = PanelY + PanelFontSize / 2 + (k + 1) * rowH;
      Lbl("P_N" + IntegerToString(k), PanelX + 8, y, names[k], clrSilver);
      Lbl("P_V" + IntegerToString(k), PanelX + 8 + colW, y, vals[k], cols[k]);
     }
  }
//+------------------------------------------------------------------+
