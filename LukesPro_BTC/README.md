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
single-trade lot = 1.0, grid start lot = 2.0 (x1.5 per level, max 5 trades).

Check your broker's BTC contract size: `InpBasketTPMoney` assumes 1 lot = 1 BTC.
