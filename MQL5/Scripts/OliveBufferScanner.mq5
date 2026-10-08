//+------------------------------------------------------------------+
//|                                           OliveBufferScanner.mq5 |
//|  Lists every buffer of a compiled indicator and shows which ones |
//|  hold buy / sell arrows. Results go to the Experts tab and chart.|
//+------------------------------------------------------------------+
#property copyright   "Olive EA"
#property version     "1.00"
#property description "Finds the buy/sell arrow buffers of an indicator (works with .ex5 files)."
#property script_show_inputs

input string InpIndicatorName = "";   // Indicator file name (empty = indicators on this chart)
input int    InpBars          = 2000; // Bars to scan
input int    InpShowLast      = 5;    // Recent signals listed per buffer

string g_summary = "";

void Out(const string s)
  {
   Print(s);
   g_summary += s + "\n";
  }

bool IsSignalValue(double v)
  {
   return (MathIsValidNumber(v) && v != EMPTY_VALUE && v != 0.0 && MathAbs(v) < 1e100);
  }

void ScanIndicator(int h, const string name)
  {
   Out("=== " + name + " ===");
   for(int k = 0; k < 50 && BarsCalculated(h) <= 0; k++)
      Sleep(200);
   int calc = BarsCalculated(h);
   if(calc <= 0)
     {
      Out("  indicator did not finish calculating - run the script again");
      return;
     }
   int n = MathMin(InpBars, calc - 1);
   double hi[], lo[];
   datetime tm[];
   ArraySetAsSeries(hi, true);
   ArraySetAsSeries(lo, true);
   ArraySetAsSeries(tm, true);
   if(CopyHigh(_Symbol, _Period, 1, n, hi) != n || CopyLow(_Symbol, _Period, 1, n, lo) != n ||
      CopyTime(_Symbol, _Period, 1, n, tm) != n)
     {
      Out("  price history not ready - run the script again");
      return;
     }
   double avgRange = 0;
   for(int i = 0; i < n; i++)
      avgRange += hi[i] - lo[i];
   avgRange = MathMax(avgRange / n, _Point);

   int buyBuf = -1, sellBuf = -1;
   for(int b = 0; b < 64; b++)
     {
      double v[];
      ArraySetAsSeries(v, true);
      int got = CopyBuffer(h, b, 1, n, v);
      if(got <= 0)
        {
         Out(StringFormat("  %d buffer(s) in total", b));
         break;
        }
      int cnt = 0, below = 0, above = 0, other = 0;
      string recent = "";
      int shown = 0;
      for(int i = 0; i < got && i < n; i++)
        {
         if(!IsSignalValue(v[i]))
            continue;
         cnt++;
         double mid = (hi[i] + lo[i]) / 2.0;
         string side;
         if(MathAbs(v[i] - mid) <= 20.0 * avgRange)
           {
            if(v[i] < mid) { below++; side = "below"; }
            else           { above++; side = "above"; }
           }
         else
           {
            other++;
            side = "value";
           }
         if(shown < InpShowLast)
           {
            recent += StringFormat("\n      %s  %s  %s", TimeToString(tm[i], TIME_DATE | TIME_MINUTES),
                                   DoubleToString(v[i], _Digits), side);
            shown++;
           }
        }
      string verdict;
      if(cnt == 0)
         verdict = "empty";
      else
         if(cnt > got * 0.3)
            verdict = "line (not arrows)";
         else
            if(other > cnt / 2)
               verdict = "non-price values";
            else
               if(below >= cnt * 0.8)
                 {
                  verdict = "<<< BUY ARROWS";
                  if(buyBuf < 0)
                     buyBuf = b;
                 }
               else
                  if(above >= cnt * 0.8)
                    {
                     verdict = "<<< SELL ARROWS";
                     if(sellBuf < 0)
                        sellBuf = b;
                    }
                  else
                     verdict = "<<< BUY+SELL in one buffer";
      Out(StringFormat("  buffer %d: %d values (below candle %d, above %d, other %d)  %s",
                       b, cnt, below, above, other, verdict));
      if(cnt > 0 && cnt <= got * 0.3 && recent != "")
         Out("    latest:" + recent);
     }
   if(buyBuf >= 0 && sellBuf >= 0)
      Out(StringFormat("  RESULT: Buy buffer = %d, Sell buffer = %d", buyBuf, sellBuf));
   else
      Out("  RESULT: no separate buy/sell arrow buffers found");
  }

void ScanObjects()
  {
   int total = ObjectsTotal(0, -1, -1);
   int arrows = 0;
   string list = "";
   for(int i = 0; i < total; i++)
     {
      string name = ObjectName(0, i, -1, -1);
      if(StringSubstr(name, 0, 1) == "#")
         continue;
      ENUM_OBJECT type = (ENUM_OBJECT)ObjectGetInteger(0, name, OBJPROP_TYPE);
      if(type != OBJ_ARROW && type != OBJ_ARROW_UP && type != OBJ_ARROW_DOWN && type != OBJ_ARROW_BUY &&
         type != OBJ_ARROW_SELL && type != OBJ_ARROW_THUMB_UP && type != OBJ_ARROW_THUMB_DOWN)
         continue;
      arrows++;
      if(arrows <= 10)
         list += StringFormat("\n    %s  type %s  code %d  %s", name, EnumToString(type),
                              ObjectGetInteger(0, name, OBJPROP_ARROWCODE),
                              TimeToString((datetime)ObjectGetInteger(0, name, OBJPROP_TIME), TIME_DATE | TIME_MINUTES));
     }
   Out(StringFormat("=== Arrow objects on chart: %d ===", arrows) + list);
  }

void OnStart()
  {
   Out(StringFormat("Olive Buffer Scanner - %s %s, last %d bars", _Symbol,
                    StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7), InpBars));
   if(InpIndicatorName != "")
     {
      int h = iCustom(_Symbol, _Period, InpIndicatorName);
      if(h == INVALID_HANDLE)
         Out("Cannot load '" + InpIndicatorName + "' (error " + IntegerToString(GetLastError()) + ")");
      else
        {
         ScanIndicator(h, InpIndicatorName);
         IndicatorRelease(h);
        }
     }
   else
     {
      int found = 0;
      int wins = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
      for(int w = 0; w < wins; w++)
         for(int i = 0; i < ChartIndicatorsTotal(0, w); i++)
           {
            string nm = ChartIndicatorName(0, w, i);
            int h = ChartIndicatorGet(0, w, nm);
            if(h == INVALID_HANDLE)
               continue;
            found++;
            ScanIndicator(h, nm);
            IndicatorRelease(h);
           }
      if(found == 0)
         Out("No indicators on this chart - attach the signal indicator first");
     }
   ScanObjects();
   Comment(StringSubstr(g_summary, 0, 2000));
   Alert("Olive Buffer Scanner finished - see the chart or the Experts tab");
  }
//+------------------------------------------------------------------+
