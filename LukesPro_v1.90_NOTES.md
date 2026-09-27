# LukesPro MTF Ind / EA — v1.90 / v1.91

v1.91: `InpMinGrade` default changed from A to C (grades A, B and C all accepted). Re-entries still need a fresh A-grade signal (`InpReNeedA`).

Files: `LukesPro MTF Ind.mq5` (indicator, was Lukes MTF Ind v1.82) and
`LukesPro MTF EA.mq5` (EA, was Lukes MTF EA v1.09). Both run the same signal
engine: **give the indicator and the EA the same inputs** or their signals will differ.

## What changed

| # | Change | Inputs | Off = old behaviour |
|---|--------|--------|---------------------|
| 1 | EMA trend replaces the one-candle bias vote. Trade only when EMA 50/200 on H1 **and** H4 agree (fast > slow and close > slow for up). D1 close must not be on the wrong side of D1 EMA 50. Pending ideas are cancelled when the EMA trend turns against them. | `InpFiltOn`, `InpFiltTF1/2`, `InpFiltFast/Slow`, `InpD1FilterOn`, `InpD1EmaP` | `InpFiltOn=false`, `InpD1FilterOn=false` |
| 2 | ATR filters: signal candle range must be 0.6–2.5 × ATR(14); close must be within 1.5 × ATR of EMA 21 (no chasing). SL buffer = max(`InpSLBufferPts`, 0.3 × ATR, 2 × spread). | `InpATROn`, `InpMinRangeATR`, `InpMaxRangeATR`, `InpLocationOn`, `InpLocEmaP`, `InpMaxExtATR`, `InpATRStopOn`, `InpSLBufATR`, `InpSLBufSpread` | set the `...On` inputs to false |
| 3 | Strict trigger: body ≥ 50 %, close in the top/bottom 30 %, and the candle is the first close through a real swing (fractal) in the last 15 bars — or a real pin bar (wick ≥ 2 × body and ≥ 55 % of range, sweeping the last 3 bars' low/high). | `InpStrictOn`, `InpStrictBody`, `InpStrictClose`, `InpSwingBars`, `InpFractalSide`, `InpPinWick*`, `InpPinSweep` | `InpStrictOn=false` |
| 4 | Re-entry: one re-entry at most, only on a fresh A-grade trigger. (Sessions are not filtered: all sessions trade.) | `InpMaxReentry=1`, `InpReNeedA` | `InpMaxReentry=2`, `InpReNeedA=false` |
| 5 | Signal grade. Every base signal is graded against the filters in 1–3: **A** = passes all enabled filters, **B** = fails one, **C** = fails two or more. Only grades at or better than `InpMinGrade` become signals (zone, alert, EA trade). **Since v1.91 the default is C: A, B and C signals are all accepted.** The grade letter is still shown on the zone, alerts, panel and EA log. With a stricter setting, lower grades appear as a small grey letter; hover over it to see which filters failed. | `InpMinGrade` (default C), `InpShowFiltered`, `InpFiltColor` | `InpMinGrade = C` with every filter off gives the v1.82 signals |
| 6 | **Toggle** trade management (EA single-trade mode): close `InpPartialPct` % at TP1, move SL to entry (+ `InpBELockPts`), let the rest run to TP2, optionally trail it by ATR. The broker TP on the order is TP2. With 0.01 lots nothing can be split: the whole trade runs to TP2 with the break-even stop (use ≥ 0.02 lots for a 50 % partial). | `InpManageOn` (default on), `InpPartialPct`, `InpMoveBE`, `InpBELockPts`, `InpRunnerTrailOn`, `InpRunnerTrailATR` | `InpManageOn=false` → whole trade closes at TP1 as before |

The indicator also has `InpManageOn` / `InpMoveBE`. They only change its chart zone and
stats (after TP1 the SL moves to entry, a stop there ends the idea as `[BE]` without
a re-entry). Set them the same as the EA. Grid mode doesn't use trade management, so for
grid set `InpManageOn=false` on both.

### Bug fixes
* The engine now checks SL/TP on the bar that fills the pending entry. Before, a fill
  bar that also hit the SL could be missed, so the win rate looked too high and the EA's engine
  could stay "LIVE" after the broker had closed the trade, blocking new signals.
  Where the order inside that bar is unknown, the loss is assumed.
* The SL buffer now scales with ATR and spread (the fixed $0.20 on XAUUSD was about one
  spread, so sells had no real buffer).

## How to test (Strategy Tester, "Every tick based on real ticks", ≥ 2 years)
1. Baseline: `InpFiltOn=false`, `InpD1FilterOn=false`, `InpATROn=false`,
   `InpLocationOn=false`, `InpATRStopOn=false`, `InpStrictOn=false`, `InpMinGrade=C`,
   `InpMaxReentry=2`, `InpReNeedA=false`, `InpManageOn=false`. This matches v1.82 / v1.09,
   apart from the fill-bar fix.
2. Turn the filters on one at a time and record profit factor, expectancy (R per trade),
   max drawdown and number of trades. Keep a filter only if it improves expectancy.
3. Compare `InpMinGrade` A vs B, then `InpManageOn` on vs off.
4. Confirm the chosen settings on a later period that wasn't used for tuning.

## EA v1.92 — HYBRID entry type

* **`InpEntryType`**: MARKET / PENDING / HYBRID, default **HYBRID**. MARKET and PENDING work exactly as before.
* **`InpHybridMktPct`** (default 50): the % of the lot opened at market.
* On each HYBRID signal:
  * the market part opens immediately with the signal's SL. Its TP1/TP2 are measured from
    its own fill price with the same R multiples (`InpRR1` / `InpRR2`);
  * the rest goes in as the normal pending order at the signal's Entry, with the signal's
    SL/TP;
  * if the lot is too small to split (either part below the minimum lot), the whole lot goes
    in as the pending order.
* Grid mode: the market part is grid trade #1, and the pending part joins the same
  basket when it fills. When the basket closes, a pending part that hasn't filled is deleted
  so it can't start a basket of its own.
* Panel: the Entry row shows `Hybrid 50% mkt`. Both parts of one signal count as one entry,
  and as one closed trade in the TODAY stats.
* The signal engine and the indicator are unchanged.

## EA v1.93 — HYBRID fix in Full grid mode

* Bug: in Full grid mode, HYBRID opened a market part plus a pending part. When the pending
  part filled, the grid counted it as its next trade. It used up one of the `InpGridMaxTrades`
  slots, pushed the next grid lot one multiplier step too far, and got the same basket TP/SL
  as trade #1. So two trades were placed close together with the same TP and SL.
* Fix: in Full grid mode, HYBRID no longer splits. Each signal opens **one market trade with the
  full `InpGridStartLot`**, and the grid adds trades as before when price moves against the basket.
  The panel shows `Hybrid: grid = market`.
* Single trades mode is unchanged: HYBRID still splits into a market part and a pending part.
  They share the signal's SL, but their TPs are measured from their own entry prices, so they
  differ. MARKET and PENDING are unchanged in both modes.

## EA v1.94 — lot sizes in Full grid mode

* Bug: in Full grid mode the signal trade (grid #1) opened with the Grid Lot (`InpGridStartLot`)
  instead of the Single Lot (`InpSingleLot`).
* Fix: the signal trade always uses the **Single Lot**, in both modes (in HYBRID single mode, the
  Single Lot is what gets split). The grid's extra trades start at the **Grid Lot**:
  #2 = Grid Lot, #3 = Grid Lot x `InpGridMultiplier`, #4 = Grid Lot x multiplier², and so on.
  Example with Single 1.0, Grid 2.0, multiplier 1.5: 1.0 → 2.0 → 3.0 → 4.5 → 6.75.
* `InpGridMaxTrades` still counts the signal trade, so the default of 5 is the signal trade plus 4 extra trades.

## EA v1.95 — Full grid: TP only, never an SL; Equity Protector 25%

* **No SL on any grid trade.** Before, `InpGridBrokerLevels` wrote an SL (the Equity Protector
  price, or the basket break-even/trailing stop) onto every grid trade. Now grid trades are sent
  without an SL, and any SL found on one is removed. The Equity Protector and the optional basket
  break-even/trailing stop still work, but the EA checks them itself and closes the trades, so
  they are never placed on the trades.
* **Signal trade alone: TP1 only.** Measured from its own fill price for a market entry.
* **Two or more trades: one basket TP on all of them.** Once the distance threshold is reached and
  a grid trade is added, every trade gets the same basket TP (money or distance), and they all
  close together there.
* **Basket TP off (`InpBasketTPOn = false`):** every grid trade gets TP1 and they all close there.
* **Equity Protector default: 25%** of the balance (was 10%).
