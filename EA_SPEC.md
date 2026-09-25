# Lukes MTF EA – Specification

Single source of truth for the EA's rules. Read this before every phase or change.
Files: `Lukes MTF EA.mq5` (the EA), `Lukes MTF Ind.mq5` (the indicator it replicates).

Status legend: **Done** = built in code · **To do** = agreed, not built yet · **Changed** = rule was updated (see history).

---

## 0. General

| # | Rule | Status |
|---|------|--------|
| G1 | Symbol: XAUUSD on M5. Must work on 2-digit and 3-digit brokers. | Done |
| G2 | **All distances are in points** (grid distance, trailing, basket distance, plus the signal inputs). 1 point = 0.01 on XAUUSD. On 3-digit brokers the EA scales them x10 automatically (`InpAutoDigits`), so 500 points = $5.00 move on both broker types. | Changed |
| G3 | Signal point inputs (pending pts, SL buffer, min SL gap) are auto-scaled x10 on 3/5-digit brokers (`InpAutoDigits`, default on). Same setting must be used in EA and indicator. | Done |
| G4 | Mode toggle: **Signals only** (default) / **Single trades only** / **Full grid**. | Done |
| G5 | Entry toggle: **Pending order** at the indicator's Entry level (default since v1.05 — trades exactly the indicator's Entry/SL/TP1) / **Market price** at signal. | Changed |
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
| T4 | Trailing stop with toggle (`InpTrailOn`): starts after `InpTrailStartPts` points profit, trails `InpTrailDistPts` points behind price, moves in steps of `InpTrailStepPts` points. | Done |
| T5 | New signal while a trade is open: same direction → ignored. Opposite direction → close and reverse (`InpCloseOnOpposite`, default on). | Done |
| T6 | Pending entry mode: pending order is deleted when the indicator cancels/expires that idea, or after `InpPendingExpire` bars. | Done |

## 3. Grid (mode = Full grid)

| # | Rule | Status |
|---|------|--------|
| R1 | Own starting lot (`InpGridStartLot`), separate from single-trade lot. | Done |
| R2 | First grid trade opens on a signal (market or pending, per G5). | Done |
| R3 | Add a grid trade each time price moves a **fixed distance** (`InpGridDistPts`, points) against the most adverse open grid trade. | Done |
| R3b | **Widening gaps** (toggle `InpGridWidenOn`, default off): gap to trade #2 = `InpGridDistPts`, each next gap × `InpGridGapMult` (e.g. 500, 600, 720, 864…). Optional cap `InpGridMaxGapPts` (0 = none). | Done (v1.03) |
| R4 | Lot of each new grid trade = start lot × `InpGridMultiplier` ^ (trades already open). | Done |
| R5 | `InpGridMaxTrades`: when this many trades are running, stop adding grid trades. | Done |
| R6 | **Basket TP** closes all grid trades. Adjustable: money profit (`InpBasketTPMoney`, $) or points beyond the basket average (`InpBasketTPPts`), selected by `InpBasketTPType`. | Done |
| R7 | Basket TP toggle (`InpBasketTPOn`). When **off**, all grid trades close when price reaches the single-trade **TP1** of the signal that started the basket. | Done |
| R8 | In grid mode the indicator's individual TP and SL are **not** used. Instead (toggle `InpGridBrokerLevels`, default on) every grid trade carries the **same basket TP and basket SL price**, so the whole basket closes together. These real levels show on PC and mobile and work even if MT5 is off. Basket TP price = TP1 (basket TP off) / average ± `InpBasketTPPts` / price where basket profit = `InpBasketTPMoney`. Basket SL price = tighter of the basket break-even/trailing stop and the price where the loss = Equity Protector %. Updated after every grid add and stop move. | Changed (v1.06) |
| R9 | **One direction at a time**: while a basket is running, new signals (either direction) are ignored. | Done |
| R10 | Single-trade trailing stop does not apply in grid mode (the grid has its own basket stop, R11–R12). | Done |
| R11 | **Basket break-even** (toggle `InpBasketBEOn`, default off): when price is `InpBasketBEStartPts` points past the basket average, a basket stop is set at average + `InpBasketBELockPts` points. | Done (Phase 4) |
| R12 | **Basket trailing** (toggle `InpBasketTrailOn`, default off): when price is `InpBasketTrailStartPts` points past the average, the basket stop trails `InpBasketTrailDistPts` points behind price in steps of `InpBasketTrailStepPts`, and only ever moves in profit. | Done (Phase 4) |
| R13 | The basket stop is **virtual**: no SL is placed on the grid orders (keeps R8). The EA closes all grid trades when price hits it. It is shown as an orange dashed line and survives an EA/terminal restart. It only works while MT5 is running and connected. | Done (Phase 4) |

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

## Phase status

| Phase | Content | Status |
|---|---|---|
| 1–3 | Signals, single trades, grid | Built (v1.00–1.01), awaiting demo verification |
| 4 | Grid risk controls: basket break-even / trailing (user chose this only) | Built (v1.02) |
| 4b | Widening grid gaps (R3b) | Built (v1.03) |
| 5 | Protections (hours filter, Friday close, spread filter, dashboard) | Not requested for now |

## 6. Dashboard panel

| # | Rule | Status |
|---|------|--------|
| D1 | Styled panel (dark background, blue section headers, coloured values), replaces the plain text panel. Header shows status: SIGNALS ONLY / WAITING / IN TRADE / NOT TRADING. | Done (v1.07) |
| D2 | MARKET: session (GMT: Asia, London, London + NY, New York, Sydney, Closed), EMA trend (`InpTrendTF`, EMA `InpTrendFast`/`InpTrendSlow`), D1/H4/H1/M5 bias, align B/S, spread. | Done (v1.07) |
| D3 | TODAY: signals, trades closed, TP (wins), SL (losses), win rate, P/L. A grid basket closing together counts as one trade. Win = closed at profit >= 0. | Done (v1.07) |
| D3b | TODAY also shows: signals traded / pending order / not traded (signals-only mode, pending never filled, cancelled, skipped), grid trades added (levels after the first trade), grid baskets closed. CURRENT shows grid trades open (n / max). | Done (v1.09) |
| D4 | EA: mode, entry type, trading enabled, equity protector. CURRENT: signal state + levels, last signal, position/basket, floating P/L, grid level, basket stop. | Done (v1.07) |

| D5 | **Indicator** (v1.80) uses the same panel style: MARKET (session, trend, bias, align, spread), TODAY (signals, TP1/TP2/SL hits, running, win rate = TP1 / (TP1 + SL before TP1)), RUNNING TOTAL over chart history, CURRENT SIGNAL. Indicator panel at X 10, EA panel next to it at X 280. | Done |

| D6 | Panels fixed (v1.08 EA / v1.81 indicator): background is drawn before the text (it used to hide it). Both panels on the **left edge**: indicator top-left, EA bottom-left. **Drag** a panel by its title area; **click** the title to collapse/expand. Position and collapsed state are remembered per chart. Default size: width 250, font 8, row 15. | Done |

## Verification plan (no Strategy Tester)

1. Demo account, XAUUSD M5, indicator + EA on the same chart, EA in **Signals only**. Check every EA dot sits on a candle with an indicator arrow (history is drawn immediately on load).
2. Switch to **Single trades only** (min lot). Check entries, SL/TP1, trailing, logs.
3. Switch to **Full grid** (min lot, low max trades, Equity Protector on). Check grid spacing, lots, basket close.
4. Only then consider a live account.

## Change history

- 2026-09-25 – Spec created. Single-trade and grid rules confirmed by user. Indicator v1.70: once-per-bar processing fix + auto-digits.
- 2026-09-25 – G2 changed: all EA distances now in points instead of $ (user request).
- 2026-09-25 – Phase 4: basket break-even + trailing stop added (R11–R13). Other Phase 4/5 options offered, not chosen.
- 2026-09-25 – Widening grid gaps added (R3b).
- 2026-09-25 – G5 changed: default entry is now Pending (user wants the EA to take exactly the indicator's signal; market entries shortened the TP distance).
- 2026-09-25 – R8 changed: grid trades now carry a shared basket TP/SL (visible on PC + mobile). Single trades already had real SL/TP.
- 2026-09-25 – New dashboard panel (D1–D4).
- 2026-09-25 – Indicator v1.80: same styled panel (D5). EA panel moved beside it (X 280, Y 20).
- 2026-09-25 – Panel fix: text was hidden behind the background. Panels moved to the left edge, draggable and collapsible (D6).
- 2026-09-25 – Panels: thin fonts (Segoe UI Light / Semilight, inputs `InpPanelFontName`, `InpPanelFontHead`), width 270, shorter values to stop overlapping text.
- 2026-09-25 – Brighter panel colours and zone label colours (SL 255,75,75 / TP1 0,255,170 / TP2 70,170,255); fonts Segoe UI Semilight (was Light, too dim).
- 2026-09-25 – Panels are solid: chart-on-foreground turned off, and the panel is rebuilt on top when other objects appear. Colours brightened again (headings/info light blue, TP2 line).
- 2026-09-25 – EA v1.09: panel explains signals vs trades and counts grid trades (D3b).
