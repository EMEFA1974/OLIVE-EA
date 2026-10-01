# Mt.Zion Ind + Mt.Zion EA (MT5)

A rule-based trend-pullback system for MetaTrader 5, tuned by default for **XAUUSD on M5** with an **H1 trend filter**.
The indicator and the EA contain the same embedded signal engine, so the arrows on the chart are exactly the trades the EA takes. Each `.mq5` is self-contained: there is no separate include file to install.

**No martingale, no grid, no averaging down.** Every trade has a stop loss from the moment it opens.

## Files

| File | Copy to (MT5 → File → Open Data Folder) |
|---|---|
| `MQL5/Indicators/MtZion/Mt.Zion Ind.mq5` | `MQL5/Indicators/` |
| `MQL5/Experts/MtZion/Mt.Zion EA.mq5` | `MQL5/Experts/` |

Open each `.mq5` in MetaEditor and press **F7 (Compile)**.

## Strategy logic (closed bars only, no repainting)

1. **Bias (H1):** the last closed H1 candle is above a rising EMA 50 (buys only) or below a falling EMA 50 (sells only). Otherwise it stands aside.
2. **Trend (M5):** EMA 20 above EMA 50 for buys, below for sells.
3. **Pullback:** within the last 5 bars, price touched EMA 20 without closing beyond EMA 50.
4. **Trigger:** the signal candle closes in the trend direction, beyond the previous candle's high (buys) or low (sells). RSI must be in the momentum zone (50–70 for buys, 30–50 for sells) and ADX ≥ 18.
5. **Stop:** either ATR mode (beyond the pullback swing plus a 0.3 ATR buffer, minimum 1 ATR, and the trade is skipped if the stop would be wider than 3 ATR) or fixed-points mode (default 500 points = $5.00 on 2-digit gold).
6. **Targets:** TP1 at 1R and TP2 (final target) at 2R. At TP1 the EA closes 50% of the trade and moves the stop to break-even (+0.1R locked). From +1.5R an ATR trailing stop follows price.

## Chart display

- **Mt.Zion Ind:** hollow arrows on signal candles (**Aqua = buy**, **Magenta = sell**). The fast EMA is coloured by trend: Aqua for bullish, Magenta for bearish, grey for neutral. The latest signal gets zone boxes and labelled levels.
- **Mt.Zion EA:** dots on confirmation candles instead of arrows (Aqua dot under the candle = buy, Magenta dot above the candle = sell). Each trade it opens gets zone boxes and labelled levels.
- **Zone boxes:** red = Entry → SL, green = Entry → TP1, blue = TP1 → TP2, with dotted level lines and labels (`TP2`, `TP1`, `Entry … BUY/SELL`, `SL`).

## Key settings

| Setting | Default | Notes |
|---|---|---|
| Lot mode | Risk % | Switch to **Fixed lot** and set `Fixed lot`. |
| Risk per trade | 0.5% | Used only in Risk % mode. |
| Stop-loss mode | ATR | Switch to **Fixed points** and set `Fixed SL in points`. |
| Trading window | 0 → 0 | Start = end means trade 24 hours. |
| Max daily loss | 4% | Closes the EA's trades and stops entries for the rest of the day. |
| Max drawdown | 15% | From the equity peak. Halts the EA until you restart it with `Reset drawdown halt = true`. |
| Max trades per day | 0 | 0 means no limit. |
| Max spread | 60 pts, and 10% of SL | Skips entries during spread spikes. |
| News filter | On | Skips entries 30 min before and after high-impact USD news, using MT5's built-in calendar. Live trading only; the Strategy Tester has no calendar. |
| Weekend protection | On | No new trades after 18:00 server time on Friday; open trades close at 21:00. |

Keep the **Strategy** inputs identical in the indicator and the EA.

## About "10 trades a day"

The EA does **not** force a number of trades. It takes every setup that passes the filters and nothing else. On XAUUSD M5, trading all sessions, the number of trades varies with the market: busy trending days give more setups, choppy or ranging days give few or none.

If you want more trades, the levers are below. Each one adds trades at the cost of quality, so test before you change them:

- Lower `ADX minimum` (e.g., 15) or set it to 0.
- Widen the RSI zone (e.g., 45–75).
- Use M15 instead of H1 as the bias timeframe.
- Increase `Pullback lookback` (e.g., 8).

## Testing before real money

1. In the Strategy Tester, choose XAUUSD M5, **"Every tick based on real ticks"**, at least 12 months of history, and your broker's real spread and commission.
2. Look at maximum drawdown, profit factor (above 1.3 is decent), number of trades, and the longest losing streak, not just net profit.
3. Run a forward test on a demo account for at least 4 weeks (the news filter only works live).
4. Go live small: use Fixed lot 0.01 or 0.25–0.5% risk.

Past performance, backtested or live, does not guarantee future results.
