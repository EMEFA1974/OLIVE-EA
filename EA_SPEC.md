# Lukes MTF EA – Specification

Single source of truth for the EA's rules. Read this before every phase or change.
Files: `Lukes MTF EA.mq5` (the EA), `Lukes MTF Ind.mq5` (the indicator it replicates).

Status legend: **Done** = built in code · **To do** = agreed, not built yet · **Changed** = rule was updated (see history).

---

## 0. General

| # | Rule | Status |
|---|------|--------|
| G1 | Symbol: XAUUSD on M5. Must work on 2-digit and 3-digit brokers. | Done |
| G2 | EA-only distances (grid distance, trailing, basket distance) are entered in **price $** (e.g. 5.00 = $5 move in gold), so they are identical on 2- and 3-digit brokers. | Done |
| G3 | Indicator/EA point inputs (pending pts, SL buffer, min SL gap) are auto-scaled x10 on 3/5-digit brokers (`InpAutoDigits`, default on). Same setting must be used in EA and indicator. | Done |
| G4 | Mode toggle: **Signals only** (default) / **Single trades only** / **Full grid**. | Done |
| G5 | Entry toggle: **Market price** at signal (default) / **Pending order** at the indicator's Entry level. | Done |
| G6 | Trades identified by magic number + symbol. State is rebuilt from open positions/orders after a restart. | Done |
| G7 | Every signal, order, close and protection event is written to the Experts log and to `MQL5/Files/LukesEA_log.csv`. | Done |
| G8 | Signals-only mode draws a small dot on each EA signal candle (history + live) so it can be compared with the indicator's arrows on the same chart. | Done |

## 1. Signals (replicate the indicator exactly)

| # | Rule | Status |
|---|------|--------|
| S1 | EA contains the same signal engine as the indicator (same inputs, same defaults): candle quality, D1/H4/H1/M5 bias, cooldown, pending levels, SL/TP1/TP2, re-entry after SL. | Done |
| S2 | Each closed bar is processed exactly once. (Indicator bug fixed in v1.70: it used to re-process the last 2 bars on every tick.) | Done |
| S3 | On start the EA replays the last 800 bars (same as the indicator) to rebuild the engine state. No trades are taken from replayed signals. | Done |
| S4 | Trades are only taken on a signal from the bar that just closed. | Done |

## 2. Single trades (mode = Single trades only)

| # | Rule | Status |
|---|------|--------|
| T1 | Own lot size (`InpSingleLot`), separate from grid lot. | Done |
| T2 | **No partial profit.** Trade closes in full at **TP1**. | Done |
| T3 | SL = indicator SL. TP = indicator TP1. Market entries: if TP1 is no longer valid (price already past it) or `InpTPFromFill` = true, TP is recalculated from the fill price with the same R-multiple (`InpRR1`). | Done |
| T4 | Trailing stop with toggle (`InpTrailOn`): starts after `InpTrailStart` $ profit, trails `InpTrailDist` $ behind price, moves in steps of `InpTrailStep` $. | Done |
| T5 | New signal while a trade is open: same direction → ignored. Opposite direction → close and reverse (`InpCloseOnOpposite`, default on). | Done |
| T6 | Pending entry mode: pending order is deleted when the indicator cancels/expires that idea, or after `InpPendingExpire` bars. | Done |

## 3. Grid (mode = Full grid)

| # | Rule | Status |
|---|------|--------|
| R1 | Own starting lot (`InpGridStartLot`), separate from single-trade lot. | Done |
| R2 | First grid trade opens on a signal (market or pending, per G5). | Done |
| R3 | Add a grid trade each time price moves a **fixed distance** (`InpGridDistance`, $) against the most adverse open grid trade. | Done |
| R4 | Lot of each new grid trade = start lot × `InpGridMultiplier` ^ (trades already open). | Done |
| R5 | `InpGridMaxTrades`: when this many trades are running, stop adding grid trades. | Done |
| R6 | **Basket TP** closes all grid trades. Adjustable: money profit (`InpBasketTPMoney`, $) or price distance beyond the basket average (`InpBasketTPDist`, $), selected by `InpBasketTPType`. | Done |
| R7 | Basket TP toggle (`InpBasketTPOn`). When **off**, all grid trades close when price reaches the single-trade **TP1** of the signal that started the basket. | Done |
| R8 | In grid mode individual TP and SL are **not** used (orders are sent without SL/TP). | Done |
| R9 | **One direction at a time**: while a basket is running, new signals (either direction) are ignored. | Done |
| R10 | Trailing stop does not apply in grid mode. | Done |

## 4. Protection

| # | Rule | Status |
|---|------|--------|
| P1 | **Equity Protector** (toggle): when the EA's floating loss reaches `InpEquityProtPct` % of the **current balance**, close all EA trades and pending orders. | Done |
| P2 | After the Equity Protector fires, the EA waits for the **next signal** and continues normally. | Done |

## 5. Alerts

| # | Rule | Status |
|---|------|--------|
| A1 | Trade events (open, close, basket TP, equity stop) → popup/sound/push (push on by default). | Done |
| A2 | Signal alerts from the EA are off by default (the indicator already alerts). | Done |

---

## Verification plan (no Strategy Tester)

1. Demo account, XAUUSD M5, indicator + EA on the same chart, EA in **Signals only**. Check every EA dot sits on a candle with an indicator arrow (history is drawn immediately on load).
2. Switch to **Single trades only** (min lot). Check entries, SL/TP1, trailing, logs.
3. Switch to **Full grid** (min lot, low max trades, Equity Protector on). Check grid spacing, lots, basket close.
4. Only then consider a live account.

## Change history

- 2026-09-25 – Spec created. Single-trade and grid rules confirmed by user. Indicator v1.70: once-per-bar processing fix + auto-digits.
