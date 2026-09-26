//+------------------------------------------------------------------+
//| Lukes Export History                                             |
//| Script: saves the chart symbol's M5 bars (with spread) to        |
//| MQL5/Files/<symbol>_M5_history.csv for an offline backtest.      |
//| Usage: drag onto an XAUUSD chart, set the number of bars, OK.    |
//+------------------------------------------------------------------+
#property copyright "Lukes MTF"
#property version   "1.00"
#property script_show_inputs

input int InpBars = 100000;   // M5 bars to export (100 000 = about 1.5 years)

void OnStart()
  {
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int got = CopyRates(_Symbol, PERIOD_M5, 0, InpBars, r);
   if(got <= 0)
     {
      Alert("Export failed: no M5 history (error ", GetLastError(), "). Open an M5 chart, scroll back to load history, try again.");
      return;
     }

   string fname = _Symbol + "_M5_history.csv";
   int h = FileOpen(fname, FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
   if(h == INVALID_HANDLE)
     {
      Alert("Export failed: cannot create ", fname, " (error ", GetLastError(), ")");
      return;
     }

   // header + symbol facts the backtest needs
   FileWrite(h, "#symbol", _Symbol, "digits", (string)_Digits, "point", DoubleToString(_Point, 8),
             "tick_value", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), 8),
             "tick_size", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE), 8),
             "contract", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE), 2),
             "stops_level", (string)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
             "currency", AccountInfoString(ACCOUNT_CURRENCY));
   FileWrite(h, "time", "open", "high", "low", "close", "tick_volume", "spread_points");
   for(int i = 0; i < got; i++)
      FileWrite(h, TimeToString(r[i].time, TIME_DATE|TIME_MINUTES),
                DoubleToString(r[i].open, _Digits), DoubleToString(r[i].high, _Digits),
                DoubleToString(r[i].low, _Digits), DoubleToString(r[i].close, _Digits),
                (string)r[i].tick_volume, (string)r[i].spread);
   FileClose(h);

   Alert("Exported ", got, " M5 bars of ", _Symbol, " (", TimeToString(r[0].time, TIME_DATE), " to ",
         TimeToString(r[got - 1].time, TIME_DATE), ") to MQL5\\Files\\", fname,
         ". Open it via File > Open Data Folder > MQL5 > Files.");
  }
//+------------------------------------------------------------------+
