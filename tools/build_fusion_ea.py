"""Build the stand-alone FusionOliveEA: FusionOliveInd engine + EA trade layer.

Usage: python3 tools/build_fusion_ea.py FusionOliveInd.mq5 <EA 1.00 trade layer: git show e760592:FusionOliveEA.mq5> FusionOliveEA.mq5
"""
import re, sys
ind_path, ea_old_path, out_path = sys.argv[1:4]
ind = open(ind_path, encoding="utf-8").read()
ea  = open(ea_old_path, encoding="utf-8").read()

def cut(s, a, b):
    i = s.index(a); j = s.index(b, i)
    return s[i:j]

# ---------------------------------------------------------------- engine
eng = ind
# drop the indicator header (comment block + #property lines) up to the first enum/define
first = eng.index("enum ")
eng = eng[first:]
eng = re.sub(r'^#property[^\n]*\n', '', eng, flags=re.M)
eng = eng.replace("""// first input on purpose: FusionOliveEA loads the indicator with iCustom(..., true)
input bool InpHeadless = false;   // EA use only: no panel, zones, levels, grade tags or alerts""",
"""bool InpHeadless = true;          // engine runs inside the EA: no panel, zones, tags or alerts""")
assert "bool InpHeadless = true;" in eng
# visual / alert inputs of the indicator are not EA settings: keep them as plain globals
hide = False
lines = []
for ln in eng.split("\n"):
    m = re.match(r'input group "(.*)"', ln)
    if m:
        title = m.group(1)
        hide = any(k in title for k in ("Alerts", "Visuals", "Zones", "Levels / Sessions"))
        if hide:
            continue
        if "Trade Management" in title:
            ln = 'input group "=== Engine trade simulation (signal flow / stats, not the EA orders) ==="'
    elif hide and ln.startswith("input "):
        ln = ln[len("input "):]
    lines.append(ln)
eng = "\n".join(lines)
eng = eng.replace('input group "=== ', 'input group "=== Signal: ')
eng = eng.replace('input group "=== Signal: Engine trade', 'input group "=== Engine trade')
# OnInit -> EngineInit without buffer / plot setup
a = eng.index("int OnInit()")
b = eng.index("void OnDeinit(const int reason)")
init = eng[a:b].replace("int OnInit()", "int EngineInit()")
keep = []
for ln in init.split("\n"):
    s = ln.strip()
    if s.startswith(("SetIndexBuffer(", "PlotIndexSet", "IndicatorSet", "for(int p = ", "int aw =", "// hollow outline", "PlotIndexSetDouble")):
        continue
    keep.append(ln)
init = "\n".join(keep)
eng = eng[:a] + init + eng[b:]
eng = eng.replace("void OnDeinit(const int reason)", "void EngineDeinit(const int reason)")
eng = eng.replace("int OnCalculate(const int rates_total,", "int EngineCalc(const int rates_total,")
eng = eng.replace("void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)",
                  "void EngineChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)")
eng = eng.replace('Print("FusionOliveInd: ', 'Print("FusionOliveEA engine: ')
for bad in ("SetIndexBuffer", "PlotIndexSet", "IndicatorSet", "#property indicator", "OnCalculate(", "int OnInit(", "void OnDeinit("):
    assert bad not in eng, bad

# ---------------------------------------------------------------- trade layer (from EA 1.00)
inputs = cut(ea, 'input group "=== Signal Source ==="', "// indicator buffer numbers")
inputs = inputs.replace('input string          InpIndName      = "FusionOliveInd"; // indicator file name in MQL5\\Indicators\n', "")
inputs = inputs.replace('input group "=== Signal Source ==="', 'input group "=== EA: Signals traded ==="')
inputs = inputs.replace('input group "=== Entry ==="', 'input group "=== EA: Entry ==="')
inputs = inputs.replace('input group "=== Lots ==="', 'input group "=== EA: Lots ==="')
inputs = inputs.replace('input group "=== Stop Loss / Take Profit', 'input group "=== EA: Stop Loss / Take Profit')
inputs = inputs.replace('input group "=== Break-even / Trailing ==="', 'input group "=== EA: Break-even / Trailing ==="')
inputs = inputs.replace('input group "=== Risk / Management ==="', 'input group "=== EA: Risk / Management ==="')
inputs = inputs.replace('input group "=== Visuals / Notifications ==="', 'input group "=== EA: Visuals / Notifications ==="')
inputs = inputs.replace("InpShowPanel", "InpEAPanel")
assert "InpIndName" not in inputs

enums = cut(ea, "enum ENUM_ENTRY_MODE", 'input group "=== Signal Source ==="')
body = ea[ea.index("#define DOTPRE"):]
# drop the iCustom-specific parts; they are re-written below
def drop_func(s, sig):
    i = s.index(sig)
    j = s.index("\n  }\n", i) + len("\n  }\n")
    return s[:i] + s[j:]
for sig in ("double Pt()", "int OnInit()", "void OnDeinit(const int reason)", "double Buf(const int b, const int sh)",
            "bool ReadSignal(const int sh, EaSignal &s)", "bool IndicatorReady()", "void DrawHistoryDots()", "void OnTick()"):
    body = drop_func(body, sig)
body = body.replace("""CTrade   trade;
int      gH = INVALID_HANDLE;
datetime gLastBar   = 0;      // last closed bar whose signal was handled""",
"""CTrade   trade;
datetime gEaLastBar = 0;      // last closed bar whose signal was handled""")
body = body.replace("InpShowPanel", "InpEAPanel")
assert "gH" not in re.findall(r'\bgH\b', body) and "iCustom" not in body and "gLastBar " not in body

trade_core = r'''
//+------------------------------------------------------------------+
//| Engine driver: feeds the embedded FusionOliveInd engine with the  |
//| chart's bars, exactly as the terminal feeds the indicator.       |
//| The window is fixed (InpHistoryBars + 600 bars); on every new    |
//| bar the engine arrays shift by one and only that bar is run.     |
//+------------------------------------------------------------------+
datetime gEngT0    = 0;       // open time of bar 0 at the last engine run
int      gEngTotal = 0;       // bars in the engine window (0 = full run needed)
datetime gTime[];
double   gOpen[], gHigh[], gLow[], gClose[];
long     gTickVol[], gVolume[];
int      gSpread[];

void SeriesShift(double &a[], const int k, const double fill)
  {
   int n = ArraySize(a);
   for(int j = n - 1; j >= k; j--) a[j] = a[j - k];
   for(int j = 0; j < k && j < n; j++) a[j] = fill;
  }

void SeriesReset(double &a[], const int n, const double fill)
  {
   ArraySetAsSeries(a, false);
   ArrayResize(a, n);
   ArraySetAsSeries(a, true);
   ArrayInitialize(a, fill);
  }

void EngineArrays(const int n, const int k, const bool reset)
  {
   if(reset)
     {
      SeriesReset(BuyBuf, n, EMPTY_VALUE);  SeriesReset(SellBuf, n, EMPTY_VALUE);
      SeriesReset(ReBuyBuf, n, EMPTY_VALUE); SeriesReset(ReSellBuf, n, EMPTY_VALUE);
      SeriesReset(V1, n, EMPTY_VALUE); SeriesReset(V2, n, EMPTY_VALUE);
      SeriesReset(V3, n, EMPTY_VALUE); SeriesReset(V4, n, EMPTY_VALUE);
      SeriesReset(VL1, n, EMPTY_VALUE); SeriesReset(VL4, n, EMPTY_VALUE);
      SeriesReset(EaSig, n, 0.0);  SeriesReset(EaSigT, n, 0.0); SeriesReset(EaEntry, n, 0.0);
      SeriesReset(EaBrk, n, 0.0);  SeriesReset(EaSL, n, 0.0);   SeriesReset(EaTP1, n, 0.0);
      SeriesReset(EaTP2, n, 0.0);  SeriesReset(EaBSL, n, 0.0);  SeriesReset(EaBTP1, n, 0.0);
      SeriesReset(EaBTP2, n, 0.0);
      return;
     }
   SeriesShift(BuyBuf, k, EMPTY_VALUE);  SeriesShift(SellBuf, k, EMPTY_VALUE);
   SeriesShift(ReBuyBuf, k, EMPTY_VALUE); SeriesShift(ReSellBuf, k, EMPTY_VALUE);
   SeriesShift(V1, k, EMPTY_VALUE); SeriesShift(V2, k, EMPTY_VALUE);
   SeriesShift(V3, k, EMPTY_VALUE); SeriesShift(V4, k, EMPTY_VALUE);
   SeriesShift(VL1, k, EMPTY_VALUE); SeriesShift(VL4, k, EMPTY_VALUE);
   SeriesShift(EaSig, k, 0.0);  SeriesShift(EaSigT, k, 0.0); SeriesShift(EaEntry, k, 0.0);
   SeriesShift(EaBrk, k, 0.0);  SeriesShift(EaSL, k, 0.0);   SeriesShift(EaTP1, k, 0.0);
   SeriesShift(EaTP2, k, 0.0);  SeriesShift(EaBSL, k, 0.0);  SeriesShift(EaBTP1, k, 0.0);
   SeriesShift(EaBTP2, k, 0.0);
  }

bool LoadBars(const int n)
  {
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, _Period, 0, n, r) != n) return false;
   ArrayResize(gTime, n); ArrayResize(gOpen, n); ArrayResize(gHigh, n); ArrayResize(gLow, n);
   ArrayResize(gClose, n); ArrayResize(gTickVol, n); ArrayResize(gVolume, n); ArrayResize(gSpread, n);
   ArraySetAsSeries(gTime, true); ArraySetAsSeries(gOpen, true); ArraySetAsSeries(gHigh, true);
   ArraySetAsSeries(gLow, true); ArraySetAsSeries(gClose, true); ArraySetAsSeries(gTickVol, true);
   ArraySetAsSeries(gVolume, true); ArraySetAsSeries(gSpread, true);
   for(int j = 0; j < n; j++)
     {
      gTime[j] = r[j].time; gOpen[j] = r[j].open; gHigh[j] = r[j].high; gLow[j] = r[j].low;
      gClose[j] = r[j].close; gTickVol[j] = r[j].tick_volume; gVolume[j] = r[j].real_volume;
      gSpread[j] = r[j].spread;
     }
   return true;
  }

// run the engine when a new bar has opened; true when the engine is up to date
bool EngineRun(bool &fullRun)
  {
   fullRun = false;
   datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 == 0) return false;
   if(gEngTotal > 0 && t0 == gEngT0) return true;

   int k = (gEngTotal > 0 ? iBarShift(_Symbol, _Period, gEngT0, true) : -1);
   bool reset = (gEngTotal <= 0 || k <= 0 || k >= gEngTotal - 10);
   int n = (reset ? (int)MathMin(Bars(_Symbol, _Period), MathMax(100, InpHistoryBars) + 600) : gEngTotal);
   if(n < 200) return false;
   if(!LoadBars(n)) return false;
   EngineArrays(n, k, reset);
   int prev = (reset ? 0 : n - k);
   int ret = EngineCalc(n, prev, gTime, gOpen, gHigh, gLow, gClose, gTickVol, gVolume, gSpread);
   if(ret <= 0) { gEngTotal = 0; return false; }   // filter indicators still loading: full run next tick
   gEngTotal = n;
   gEngT0 = t0;
   fullRun = reset;
   return true;
  }

bool ReadSignal(const int sh, EaSignal &s)
  {
   if(sh < 0 || sh >= ArraySize(EaSig)) return false;
   s.code = (int)MathRound(EaSig[sh]);
   if(s.code == 0) return false;
   int a   = MathAbs(s.code);
   s.dir   = (s.code > 0 ? 1 : -1);
   s.re    = (a >= 10);
   s.kind  = a % 10;
   s.sigTime = (datetime)(long)EaSigT[sh];
   s.entry = EaEntry[sh];
   s.brk   = EaBrk[sh];
   s.sl    = EaSL[sh];
   s.tp1   = EaTP1[sh];
   s.tp2   = EaTP2[sh];
   s.bsl   = EaBSL[sh];
   s.btp1  = EaBTP1[sh];
   s.btp2  = EaBTP2[sh];
   return (s.kind >= 1 && s.kind <= 4);
  }

// confirmed signals already in the engine window (history), drawn once
void DrawHistoryDots()
  {
   if(!InpShowDots) return;
   int n = (int)MathMin(MathMax(0, InpDotHistoryBars), ArraySize(EaSig) - 1);
   for(int k = 1; k <= n; k++)
     {
      int c = (int)MathRound(EaSig[k]);
      int kind = MathAbs(c) % 10;
      if(c != 0 && (kind == 1 || kind == 2 || kind == 4))
         DrawDot((datetime)(long)EaSigT[k], (c > 0 ? 1 : -1));
     }
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpLots <= 0.0 || InpSLPts <= 0 || InpTPPts <= 0 || InpTPRR <= 0.0)
     {
      Print("FusionOliveEA: lots, SL/TP points and TP RR must be positive");
      return(INIT_PARAMETERS_INCORRECT);
     }
   int r = EngineInit();
   if(r != INIT_SUCCEEDED) return(r);
   trade.SetExpertMagicNumber((ulong)InpMagic);
   trade.SetDeviationInPoints((ulong)MathMax(0, InpSlippagePts));
   trade.SetTypeFillingBySymbol(_Symbol);
   gEngTotal  = 0;
   gEngT0     = 0;
   gEaLastBar = 0;
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EngineDeinit(reason);
   if(reason == REASON_REMOVE) ObjectsDeleteAll(0, DOTPRE);
   Comment("");
  }

void OnTick()
  {
   ManagePosition();
   ManagePendings();

   bool fullRun = false;
   if(EngineRun(fullRun))
     {
      datetime t1 = iTime(_Symbol, _Period, 1);
      if(fullRun)
        {
         DrawHistoryDots();
         if(gEaLastBar == 0) gEaLastBar = t1;   // never trade a signal that closed before the EA started
        }
      // one decision per closed bar
      if(t1 != 0 && t1 != gEaLastBar)
        {
         gEaLastBar = t1;
         EaSignal s;
         if(ReadSignal(1, s)) HandleSignal(s);
        }
     }
   ShowPanel();
  }
'''

header = '''//+------------------------------------------------------------------+
//|                                               FusionOliveEA.mq5  |
//|                                                                  |
//| Stand-alone EA: the complete FusionOliveInd signal engine is     |
//| built in (no indicator file needed). It trades the CONFIRMED     |
//| signals, one trade at a time, every order with SL and TP.        |
//|                                                                  |
//| "Signal:" inputs = the indicator's settings (same defaults);     |
//| "EA:" inputs = lots, entry, SL/TP, trailing, risk, visuals.      |
//|                                                                  |
//| Generated from FusionOliveInd + the EA trade layer; keep the     |
//| engine part in sync when the indicator logic changes.            |
//+------------------------------------------------------------------+
#property copyright "FusionOliveEA"
#property link      ""
#property version   "2.00"
#property description "Stand-alone FusionOliveEA: built-in FusionOliveInd engine, confirmed signals only, one trade at a time, SL/TP, break-even, trailing."

#include <Trade/Trade.mqh>

'''

out = (header + enums + inputs +
       "\n//+------------------------------------------------------------------+\n"
       "//| Embedded FusionOliveInd signal engine                            |\n"
       "//+------------------------------------------------------------------+\n" +
       eng + "\n" + body.rstrip() + "\n" + trade_core)
# the EA's body must not end with the original closing comment line twice
open(out_path, "w", encoding="utf-8").write(out)
print("written", out_path, len(out.splitlines()), "lines")
