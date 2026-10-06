//+------------------------------------------------------------------+
//|                                               VWMA RSI Score.mq5 |
//|                                                                  |
//| 5-point bull/bear score built from four VWMAs (on High, tick     |
//| volume) and three RSIs, plus session / day / week levels.        |
//|                                                                  |
//| Score checks (BUY votes; SELL is the mirror, bear = 5 - bull):   |
//|   1. RSI1 (14) > RsiMid                                          |
//|   2. RSI2 (9)  > RsiMid                                          |
//|   3. RSI3 (7)  > RsiMid                                          |
//|   4. Close (or High) > VWMA1 (85, red)                           |
//|   5. VWMA3 (18, yellow) > VWMA2 (37, orange)                     |
//| VWMA4 (6, green) is not scored, but by default it gates signals: |
//| a BUY also needs green > yellow, a SELL green < yellow.          |
//| An arrow prints on the first bar where score >= MinScore and the |
//| gate agrees. The same direction cannot fire again until its      |
//| score has dropped to ReArmScore or lower.                        |
//+------------------------------------------------------------------+
#property version     "1.00"
#property description "Four VWMAs on High + three RSIs -> 5-point bull/bear score."
#property description "Arrow on the bar where the score first reaches MinScore."
#property indicator_chart_window
#property indicator_buffers 13
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
input double            RsiOB             = 80.0;  // RSI overbought (used by OB/OS filter)
input double            RsiMid            = 55.0;  // RSI bull/bear threshold
input double            RsiOS             = 20.0;  // RSI oversold (used by OB/OS filter)
input int               SydS              = 21;    // Sydney start hour (UTC)
input int               SydE              = 6;     // Sydney end hour (UTC)
input int               AsiS              = 0;     // Asian start hour (UTC)
input int               AsiE              = 9;     // Asian end hour (UTC)
input int               LonS              = 7;     // London start hour (UTC)
input int               LonE              = 16;    // London end hour (UTC)
input int               NyS               = 12;    // New York start hour (UTC)
input int               NyE               = 21;    // New York end hour (UTC)
input ENUM_CHECK4_PRICE Check4Price       = CHECK4_CLOSE; // Price compared with VWMA1 (check 4)
input bool              UseFastGate       = true;  // Signal also needs green VWMA4 vs yellow VWMA3 to agree
input int               ReArmScore        = 3;     // Repeat same-direction signal only after its score fell to this
input bool              UseObOsFilter     = false; // Block buys if any RSI > RsiOB, sells if any RSI < RsiOS
input bool              SignalOnClosedBar = true;  // Arrows/alerts on closed bars only (no repaint)
input bool              ShowPanel         = true;  // Show info panel
input bool              ShowLevels        = true;  // Draw PDH/PDL and PWH/PWL lines
input int               PanelX            = 10;    // Panel X offset (px)
input int               PanelY            = 25;    // Panel Y offset (px)
input int               PanelFontSize     = 9;     // Panel font size

double V1[], V2[], V3[], V4[];
double BuyArr[], SellArr[];
double R1[], R2[], R3[];
double BullScore[];
double Sig[], ArmBuy[], ArmSell[];

int      hR1 = INVALID_HANDLE, hR2 = INVALID_HANDLE, hR3 = INVALID_HANDLE;
int      gMaxPeriod = 0;
int      gReArm     = 3;
datetime gLastAlertBar = 0;

const string PFX = "VRS_";

//+------------------------------------------------------------------+
int OnInit()
  {
   if(VWMA1 < 1 || VWMA2 < 1 || VWMA3 < 1 || VWMA4 < 1 || RSI1 < 1 || RSI2 < 1 || RSI3 < 1)
     {
      Print("All periods must be >= 1");
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

   for(int p = 0; p < 6; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, VWMA1 - 1);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, VWMA2 - 1);
   PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, VWMA3 - 1);
   PlotIndexSetInteger(3, PLOT_DRAW_BEGIN, VWMA4 - 1);
   PlotIndexSetInteger(4, PLOT_ARROW, 233);
   PlotIndexSetInteger(5, PLOT_ARROW, 234);
   PlotIndexSetInteger(4, PLOT_ARROW_SHIFT, 15);
   PlotIndexSetInteger(5, PLOT_ARROW_SHIFT, -15);

   IndicatorSetString(INDICATOR_SHORTNAME, "VWMA RSI Score");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   hR1 = iRSI(_Symbol, _Period, RSI1, PRICE_CLOSE);
   hR2 = iRSI(_Symbol, _Period, RSI2, PRICE_CLOSE);
   hR3 = iRSI(_Symbol, _Period, RSI3, PRICE_CLOSE);
   if(hR1 == INVALID_HANDLE || hR2 == INVALID_HANDLE || hR3 == INVALID_HANDLE)
     {
      Print("Failed to create RSI handles");
      return INIT_FAILED;
     }

   gMaxPeriod = MathMax(MathMax(VWMA1, VWMA2), MathMax(VWMA3, VWMA4));
   gMaxPeriod = MathMax(gMaxPeriod, MathMax(RSI1, MathMax(RSI2, RSI3)));
   gReArm     = MathMax(0, MathMin(ReArmScore, MinScore - 1));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PFX);
   if(hR1 != INVALID_HANDLE) IndicatorRelease(hR1);
   if(hR2 != INVALID_HANDLE) IndicatorRelease(hR2);
   if(hR3 != INVALID_HANDLE) IndicatorRelease(hR3);
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
int BullCount(const int i, const double &high[], const double &close[])
  {
   int bull = 0;
   if(R1[i] > RsiMid) bull++;
   if(R2[i] > RsiMid) bull++;
   if(R3[i] > RsiMid) bull++;
   double price = (Check4Price == CHECK4_HIGH) ? high[i] : close[i];
   if(price > V1[i]) bull++;
   if(V3[i] > V2[i]) bull++;
   return bull;
  }

//+------------------------------------------------------------------+
//| Score for a direction: +1 buy, -1 sell                           |
//+------------------------------------------------------------------+
int DirScore(const int i, const int dir)
  {
   if(i < 0 || BullScore[i] == EMPTY_VALUE)
      return 0;
   int bull = (int)BullScore[i];
   return (dir > 0) ? bull : 5 - bull;
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
   if(UseObOsFilter)
     {
      if(dir > 0 && (R1[i] > RsiOB || R2[i] > RsiOB || R3[i] > RsiOB))
         return false;
      if(dir < 0 && (R1[i] < RsiOS || R2[i] < RsiOS || R3[i] < RsiOS))
         return false;
     }
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
      BarsCalculated(hR3) < rates_total)
      return prev_calculated;

   bool full = (prev_calculated <= 0 || prev_calculated > rates_total);
   int to_copy = full ? rates_total : rates_total - prev_calculated + 1;
   if(CopyBuffer(hR1, 0, 0, to_copy, R1) <= 0) return 0;
   if(CopyBuffer(hR2, 0, 0, to_copy, R2) <= 0) return 0;
   if(CopyBuffer(hR3, 0, 0, to_copy, R3) <= 0) return 0;

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
         ArmBuy[i]    = 1;
         ArmSell[i]   = 1;
         continue;
        }
      BullScore[i] = BullCount(i, high, close);

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
         SendAlerts(sig, (int)BullScore[ab]);
        }
     }

   if(ShowLevels)
      DrawLevels();
   if(ShowPanel)
      DrawPanel(rates_total, time, high, low);
   return rates_total;
  }

//+------------------------------------------------------------------+
void SendAlerts(const int sig, const int bull)
  {
   int score = (sig > 0) ? bull : 5 - bull;
   string msg = StringFormat("%s %s: %s signal (score %d/5)",
                             _Symbol, StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7),
                             (sig > 0) ? "BUY" : "SELL", score);
   if(AlertPopup) Alert(msg);
   if(AlertPush)  SendNotification(msg);
   if(AlertEmail) SendMail("VWMA RSI Score", msg);
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
void DrawPanel(const int total, const datetime &time[], const double &high[], const double &low[])
  {
   int rowH = PanelFontSize * 2;
   int colW = PanelFontSize * 14;
   int rows = 15;
   string bg = PFX + "BG";
   if(ObjectFind(0, bg) < 0)
     {
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
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, rows * rowH + PanelFontSize);

   string names[16];
   string vals[16];
   color  cols[16];
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

   int last = total - 1;
   double rsis[3];
   int    pers[3];
   rsis[0] = R1[last]; rsis[1] = R2[last]; rsis[2] = R3[last];
   pers[0] = RSI1;     pers[1] = RSI2;     pers[2] = RSI3;
   string mid = DoubleToString(RsiMid, 0);
   for(int k = 0; k < 3; k++)
     {
      bool above = rsis[k] > RsiMid;
      names[r] = "RSI " + IntegerToString(pers[k]);
      vals[r]  = DoubleToString(rsis[k], 1) + (above ? " >" : " <") + mid;
      cols[r++] = above ? clrLime : clrOrange;
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
   int bull = (BullScore[last] == EMPTY_VALUE) ? 0 : (int)BullScore[last];
   int bear = 5 - bull;
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

   for(int k = 0; k < r; k++)
     {
      int y = PanelY + PanelFontSize / 2 + k * rowH;
      Lbl("N" + IntegerToString(k), PanelX + 8, y, names[k], clrSilver);
      Lbl("V" + IntegerToString(k), PanelX + 8 + colW, y, vals[k], cols[k]);
     }
  }
//+------------------------------------------------------------------+
