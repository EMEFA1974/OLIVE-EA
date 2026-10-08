# GoldCandleConfluence: XAUUSD M5 candlestick strategy

A pattern on its own is noise. On gold M5 you will see dozens of "engulfing"
candles a day. A pattern is only worth trading when it forms **in the right
context, at the right location, and many independent factors agree**. This
indicator turns that idea into rules and a score.

```
Context gate  →  Location gate  →  Pattern trigger  →  Confluence score  →  Daily/session cap
(should I       (is this a level   (did buyers/sellers  (how many things     (keep only the best
 trade now?)     that matters?)     visibly take over?)  graded A/B/C)       few per day)
```

## 1. Context gate (hard filters)
| Filter | Rule | Why |
|---|---|---|
| Volatility regime | ATR(14) / 100-bar ATR average between 0.6 and 2.5 | Dead markets give fake patterns. In chaotic markets stops get run. |
| News shock | Skip if any of the last 4 bars > 3.5 × ATR | Patterns that form during a news spike don't mean anything |
| Rollover | Skip 21:00–23:00 GMT | Spreads on gold widen a lot at rollover |
| Closed bar only | Signals come only from bar 1 (the bar that just closed) | Signals don't repaint |

## 2. Location gate (required)
The pattern's extreme (low for a buy, high for a sell) must **touch**
(within 0.35 × ATR) or **sweep** (wick through, close back) at least one level:

| Level | Weight |
|---|---|
| Previous day high / low | 2 (major) |
| Asian session high / low (00:00–07:00 GMT) | 2 (major) |
| Confirmed M5 swing highs/lows (last 12 h) | 1 |
| $10 round numbers | 1 |
| M5 EMA50, **only in the H1 bias direction** | 1 |

## 3. Pattern triggers (on the closed bar)
All sizes are measured against ATR, so they adapt to gold's volatility.
- **Engulfing**: the body engulfs the prior opposite body. Body ≥ 55% of range, small wick against the trade.
- **Pin bar (hammer / shooting star)**: rejection wick ≥ 60% of range and ≥ 2 × body. The wick pokes past the last 3 bars.
- **Morning / evening star**: a strong bar, then a small indecision bar, then a strong reversal that closes past the midpoint of the first bar.
- **Key reversal**: takes out the last 5 lows/highs, then closes beyond the prior bar's high/low in the top/bottom 30% of its range.

## 4. Confluence score (0–12)
| Component | Points |
|---|---|
| Valid pattern | 2 |
| Pattern is "strong" (e.g. engulfs and closes past prior high) | +1 |
| Two or more patterns on the same bar | +1 |
| Location (sum of level weights, capped) | +1 to +3 |
| Liquidity sweep of a major or swing level | +1 |
| H1 bias agrees (close vs EMA50 + EMA slope, last **closed** H1 bar) | +2 |
| RSI exhaustion (≤ 35 for buys / ≥ 65 for sells in last 4 bars) | +1 |
| Momentum close beyond prior bar's high/low | +1 |
| Major level less than 0.7R in front of entry ("tight") | −1 |

- Against the bias: only allowed when price **swept a major level** (PDH/PDL/Asia). Its score is lowered by 1 before grading.

### Signal grades (MT5)
| Grade | Score | Default |
|---|---|---|
| **A** | 9 or more | On |
| **B** | 7–8 | On |
| **C** | 5–6 | **Off** |

- Each grade has its own on/off switch, and you can change the score thresholds in the inputs.
- A grade that is switched off is completely ignored: it doesn't use up the daily/session limit or trigger the cooldown.
- With C switched on you get more signals. But C signals can use up the per-session limit before a later A/B appears in that session.
- The grade letter is printed in faint grey **under each buy** signal and **above each sell** signal.
- Re-entries inherit the grade of the original signal.
- The panel shows count, win % and average R for each grade, so you can check whether C is worth turning on.
- If a buy and a sell both qualify on the same bar, the higher score wins. A tie means no trade.

## 5. Selection: quality over quantity
- **No daily limit** by default (`MaxSignalsPerDay = 0`). Set it to a number to cap signals per trading day (the day starts at 22:00 GMT).
- Max **2 per session** (Asia 22–07, London 07–12, Overlap 12–16, New York 16–22 GMT). This spreads signals across all sessions so one session can't use up the whole day's limit.
- **6-bar (30 min) cooldown** between signals.

## 6. Trade plan for each signal
- **Entry**: close of the signal bar (or the next bar's open).
- **SL**: beyond the pattern extreme + 0.2 × ATR. Minimum 0.8 × ATR. If the SL would be more than 2.5 × ATR away, the signal is rejected.
- **TP1 = 1R**: take 50% off and move the SL to breakeven. **TP2 = 2R** for the rest.
- **Time stop**: 4 hours.

## 7. Re-entry after a stop-out (MT5)
If a signal hits its SL **before TP1**, it gets a re-entry window of 12 bars (1 hour).
One re-entry is signalled if, on a closed bar inside that window, all of these hold:
- Price **reclaims the zone**: the bar closes back beyond the original pattern's low (buys) or high (sells). This means the stop-out was a liquidity sweep, not a breakdown.
- The bar is a reversal pattern (engulfing, pin, star or key reversal) or a strong reclaim candle (body ≥ 55% of its range, closing beyond the prior bar).
- The H1 bias has not turned against the trade. This is not required if the original trade was already counter-trend.
- The context gate still passes (volatility, no news shock, no rollover).
- The new SL, placed beyond the sweep extreme, is within the 2.5 × ATR risk limit.

The re-entry is cancelled if:
- price runs more than 1.5 × ATR beyond the old SL,
- TP1 was hit first,
- or the window expires.

There is at most one re-entry per signal. Re-entries don't count toward the daily or session caps, and the panel tracks them separately.

## Chart display (MT5)
- Hollow arrows: **Aqua** = Buy, **Magenta** = Sell, **Orange** = Re-entry Buy, **Yellow** = Re-entry Sell.
- Zone boxes from the signal bar to the trade's exit:
  - red = risk zone (Entry → SL)
  - green = Entry → TP1
  - blue = TP1 → TP2
- Each box has Entry, SL, TP1 and TP2 lines, with prices printed at the right edge.

## Built-in self-check
The panel replays every historical signal on the chart using the trade plan above.
The rules are conservative:
- If SL and TP are hit in the same bar, it counts as a loss.
- A cost of $0.30 is deducted from every trade.

The panel shows signals/day, TP1 hit rate, win rate, net R and a breakdown by session.
Use it to tune the settings:

- Too many signals, or weak results → turn grade B off (A only), or raise `GradeB_MinScore` to 8.
- Too few signals → turn grade C on, or lower `LevelTolATR` to 0.45.
- A session that's consistently negative → note it and trade it with smaller size, or skip it.

**This replay is a sanity check, not proof.** Before going live, validate in the MT4
Strategy Tester (or forward-test on demo for at least 4 weeks) on your broker's data.

## Setup notes
- **MT5**: `GoldCandleConfluence.mq5` goes in `MQL5/Indicators/`. **MT4**: `GoldCandleConfluence.mq4` goes in `MQL4/Indicators/`. Same logic in both.
- Set `ServerGMTOffset` to your broker's offset. Most brokers are GMT+2 in winter and GMT+3 in summer. This offset sets the session, Asian range and rollover times.
- Keep H1 and D1 history loaded. The indicator reads the H1 bias and the D1 previous-day levels.
- Buffers for an EA (`iCustom` + `CopyBuffer` on MT5), read at shift 1:
  - 0 = buy
  - 1 = sell
  - 2 = re-entry buy
  - 3 = re-entry sell
  - 4 = SL
  - 5 = TP1
  - 6 = TP2
  - 7 = score (+ buy / − sell)
  - 8 = grade (1 = A, 2 = B, 3 = C)

  The MT4 file still uses the older 6-buffer layout and has no re-entries.
