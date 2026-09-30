# LukesPro BTC MTF (Indicator + EA)

BTC builds of `LukesPro_MTF_Ind` / `LukesPro_MTF_EA` v1.91. The signal engine, grading, filters,
zones, panel and trade management are unchanged — only the inputs and labels were converted for BTC.

## What changed

- All point-based inputs are now **USD distances of BTC price** (`...Usd` inputs, type `double`).
  On BTCUSD one price unit is $1, so the settings work the same on 0/1/2/3-digit BTC symbols.
  `InpAutoDigits` was removed because digit scaling no longer matters.
- Conversion rule from the XAUUSD defaults: **1 gold point ($0.01) → $0.50 of BTC** (BTC moves roughly 50x more in dollars than gold).
- Slippage is entered in USD and turned into broker points at runtime (`SlipPts()`).
- Panel spread is shown in $ (warning above `InpSpreadWarnUsd`); the session row shows `WEEKEND (BTC 24/7)` instead of `CLOSED`.
- The EA uses its own magic (`26092601`), comment (`LukesBTC`), log file (`LukesBTC_EA_log.csv`) and global-variable keys, so it can run next to the gold EA.
- Both files print a warning if attached to a non-BTC symbol.

## Input conversion table

| Input (gold)             | Gold default | BTC input               | BTC default |
|--------------------------|-------------:|-------------------------|------------:|
| InpPendingPts            | 40 pts       | InpPendingUsd           | $20         |
| InpMinSLGapPts           | 15 pts       | InpMinSLGapUsd          | $8          |
| InpSLBufferPts           | 20 pts       | InpSLBufferUsd          | $10         |
| InpSlippagePts (EA)      | 30 pts       | InpSlippageUsd          | $15         |
| InpTrailStartPts (EA)    | 300 pts      | InpTrailStartUsd        | $150        |
| InpTrailDistPts (EA)     | 200 pts      | InpTrailDistUsd         | $100        |
| InpTrailStepPts (EA)     | 50 pts       | InpTrailStepUsd         | $25         |
| InpBELockPts (EA)        | 0 pts        | InpBELockUsd            | $0          |
| InpGridDistPts (EA)      | 500 pts      | InpGridDistUsd          | $250        |
| InpGridMaxGapPts (EA)    | 0 (no cap)   | InpGridMaxGapUsd        | 0 (no cap)  |
| InpBasketTPPts (EA)      | 200 pts      | InpBasketTPUsd          | $100        |
| InpBasketTPMoney (EA)    | 5.00         | InpBasketTPMoney        | 2.50 (0.01 BTC × $250) |
| InpBasketBEStartPts (EA) | 150 pts      | InpBasketBEStartUsd     | $75         |
| InpBasketBELockPts (EA)  | 20 pts       | InpBasketBELockUsd      | $10         |
| InpBasketTrailStartPts   | 200 pts      | InpBasketTrailStartUsd  | $100        |
| InpBasketTrailDistPts    | 150 pts      | InpBasketTrailDistUsd   | $75         |
| InpBasketTrailStepPts    | 20 pts       | InpBasketTrailStepUsd   | $10         |
| Spread warning (panel)   | 50 pts       | InpSpreadWarnUsd        | $25         |

Ratio/ATR/percentage inputs (body ratios, ATR multiples, R-multiples, EMA periods, equity %),
timeframes and bar counts are unchanged because they don't depend on price scale.

EA defaults: Mode = Full grid, basket TP = price distance ($100 beyond the basket average),
signal trade lot = 1.0 (Single Lot, also the first trade of a grid), grid adds start at 2.0
(Grid Lot) x1.5 per level, max 5 trades: 1.0 → 2.0 → 3.0 → 4.5 → 6.75.

Check your broker's BTC contract size: `InpBasketTPMoney` assumes 1 lot = 1 BTC.

## Hybrid entry (default, v1.98)

`InpEntryType = HYBRID` always opens **ONE trade per signal**:

- **Single trades:** if the indicator Entry is `InpHybridMinGapUsd` (default $50) or more away from the
  current price (big candle, a pullback that deep is unlikely), the trade opens **at market** so the move
  is not missed (TP1/TP2 measured from the fill, same R). Closer than that, it is a **pending order** at the
  indicator Entry (better price, likely to fill).
- **Full grid:** one market trade; the grid adds trades on a pullback.
- `PENDING` / `MARKET` still behave exactly as before.

Related tuning (set the same in the indicator and the EA): a smaller `InpPendingRetrace`
(e.g. 0.20 instead of 0.40) places the limit closer to the signal close, so it fills more often.

## Full grid TP / SL rules (v1.97)

- **No grid trade ever has an SL.**
- **First (signal) trade alone:** TP only = the signal's TP1.
- **From the 2nd grid trade on, basket TP ON** (`InpBasketTPOn = true`): every trade gets the same basket TP
  (`InpBasketTPType` / `InpBasketTPUsd`, default avg ± $100) and they all close together there.
- **Basket TP OFF:** every grid trade gets the first trade's TP1 and they all close there.
- The TP is written on each trade (broker side) and moves as new grid trades change the average.
  It is shown as a green dashed line and on the panel.
- The equity protector (and the optional basket BE/trailing stop) are not SLs on the trades;
  the EA closes the whole basket itself when they are hit, so MT5 must be running for those.

## Fixes in Ind v1.92 / EA v1.99

- **Spread-aware signal logic (both files, `InpSpreadAware = true`).** Sells close at the ask and buys fill
  at the ask, so the bar's historical spread is added to those checks. A sell stopped out a spread above the
  candle high is now registered as stopped (so its re-entry can come).
- **Re-entry for MARKET / HYBRID trades (EA).** When one of the EA's single trades closes at its SL with a loss
  and the signal logic had already forgotten the signal (pending expired) or never saw it fill, the EA starts the
  re-entry wait for that signal (`REENTRY_SYNC` in the log). Break-even stops after TP1 don't count.
  The indicator can't see real trades, so here the EA may take a re-entry the indicator doesn't show.
- **Grid trades (EA).** Free margin is checked before each grid trade; if it's not enough, you get one
  `GRID_NO_MARGIN` alert per grid level and it re-checks every 30 s. Other refusals (requote etc.) retry after 3 s.
- **`InpReNeedA = false` (both files).** Re-entries accept the same grades as normal signals.
  Unchanged: `InpMaxReentry = 1`, 24-bar window, 3-bar wait. In Full grid mode, new signals and re-entries are not
  traded while a basket is open.

## Wider SL (Ind v1.93 / EA v2.00)

`InpSLExpandPct` (default 50, set the same in both files) moves the SL further from the entry by that % of
the Entry–SL distance. TP1 and TP2 stay where they were (R-multiples of the original candle stop), and the
EA's partial close at TP1 still happens at that same TP1. 0 = original SL. Example: entry 100 000, candle SL
99 900 ($100) → with 50% the SL is 99 850 ($150); TP1 (1R) stays 100 100, TP2 (2R) stays 100 200.
Full grid trades have no SL, so there it only changes the indicator's zone and signal bookkeeping.
