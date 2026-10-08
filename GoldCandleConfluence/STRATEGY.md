# GoldCandleConfluence: XAUUSD M5 candlestick strategy

A pattern on its own is noise. On gold M5 you will see dozens of "engulfing"
candles a day. A pattern is only worth trading when it forms **in the right
context, at the right location, and many independent factors agree**. This
indicator turns that idea into rules and a score.

```
Context gate  →  Location gate  →  Pattern trigger  →  Confluence score  →  Daily/session cap
(should I       (is this a level   (did buyers/sellers  (how many things     (keep only the best
 trade now?)     that matters?)     visibly take over?)  agree? ≥ MinScore)   few per day)
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

- With the bias: you need **score ≥ MinScore (7)**.
- Against the bias: only allowed when price **swept a major level** (PDH/PDL/Asia), and it needs MinScore + 1.
- If a buy and a sell both qualify on the same bar, the higher score wins. A tie means no trade.

## 5. Selection: quality over quantity
- Max **5 signals per trading day** (the day starts at 22:00 GMT).
- Max **2 per session** (Asia 22–07, London 07–12, Overlap 12–16, New York 16–22 GMT). This spreads signals across all sessions so one session can't use up the whole day's limit.
- **6-bar (30 min) cooldown** between signals.

## 6. Trade plan for each signal
- **Entry**: close of the signal bar (or the next bar's open).
- **SL**: beyond the pattern extreme + 0.2 × ATR. Minimum 0.8 × ATR. If the SL would be more than 2.5 × ATR away, the signal is rejected.
- **TP1 = 1R**: take 50% off and move the SL to breakeven. **TP2 = 2R** for the rest.
- **Time stop**: 4 hours.

## Built-in self-check
The panel replays every historical signal on the chart using the trade plan above.
The rules are conservative:
- If SL and TP are hit in the same bar, it counts as a loss.
- A cost of $0.30 is deducted from every trade.

The panel shows signals/day, TP1 hit rate, win rate, net R and a breakdown by session.
Use it to tune the settings:

- Too many signals, or weak results → raise `MinScore` to 8.
- Too few signals → lower `MinScore` to 6 or `LevelTolATR` to 0.45.
- A session that's consistently negative → note it and trade it with smaller size, or skip it.

**This replay is a sanity check, not proof.** Before going live, validate in the MT4
Strategy Tester (or forward-test on demo for at least 4 weeks) on your broker's data.

## Setup notes
- Set `ServerGMTOffset` to your broker's offset. Most brokers are GMT+2 in winter and GMT+3 in summer. This offset sets the session, Asian range and rollover times.
- Keep H1 and D1 history loaded. The indicator reads the H1 bias and the D1 previous-day levels.
- Buffers for an EA (`iCustom`): 0 = buy arrow, 1 = sell arrow, 2 = SL, 3 = TP1, 4 = TP2,
  5 = score (+ buy / − sell). Read shift 1.
