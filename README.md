# Olive Trade Manager (MT5)

An Expert Advisor that takes **confirmed arrow signals** from a custom indicator,
opens one trade at a time and manages it. It is built for compiled `.ex5`
indicators like **CharisGold FX**, so you don't need the indicator's source code.

The defaults are set for **XAUUSD on M5 with Exness (3-digit prices)**:
- **All distances are in pips.** On XAUUSD, 1 pip = 0.1, so 10 pips = a $1.00 move. Symbol suffixes such as `XAUUSDm` are recognised.
- **Signal candles are marked with dots:** aqua under buy candles, magenta above sell candles, and yellow for signals the EA skipped.
- **One trade at a time.** All signals are ignored until the running trade closes (manually, by TP or by SL).
- **Push notifications are on.**

| File | What it is |
|---|---|
| `MQL5/Experts/OliveTradeManager.mq5` | The trade manager EA |
| `MQL5/Scripts/OliveBufferScanner.mq5` | Helper script that finds which indicator buffers hold the buy/sell arrows |

## Install

1. In MT5: **File → Open Data Folder**.
2. Copy `OliveTradeManager.mq5` to `MQL5\Experts\` and `OliveBufferScanner.mq5` to `MQL5\Scripts\`.
3. Your indicator `.ex5` should already be in `MQL5\Indicators\`.
4. Open both `.mq5` files in **MetaEditor** and press **F7 (Compile)**.
5. Restart MT5 or right-click **Navigator → Refresh**.

## Quick start

1. Open the chart you trade (for example XAUUSD) and attach **CharisGold FX** with your usual
   settings (Push Alert on, etc.).
2. *(Optional check)* Drag **OliveBufferScanner** onto the chart. It prints which buffers hold the
   buy and sell arrows. You only need it if the EA can't find the signals by itself.
3. Drag **OliveTradeManager** onto the same chart. On the **Common** tab tick **Allow Algo Trading**,
   and make sure the **Algo Trading** button in the toolbar is green.
4. The panel shows **ACTIVE** once the EA has found the signals. The *Buffers* line shows which buffers it uses.

With the default settings, the EA reads the copy of the indicator that is already on the chart.
Your own indicator settings (Push Alert) are kept, and you don't get duplicate alerts.

## How a trade happens

- The EA only reacts to an arrow on a **closed candle** (`Signal candle = 1`), so arrows that appear
  and then vanish while a candle is forming are ignored.
- A signal that is already on the chart when the EA starts is **not** traded. The EA waits for the
  next new arrow.
- **One EA trade at a time.** While an EA trade is running, **every new signal is ignored**, in either
  direction, until that trade closes (manually, by TP or by SL). Signals that came while the trade
  was open are never traded later; the EA waits for the next fresh arrow. You can switch
  *Opposite signal* to *Close and reverse* or *Close only* if you ever want that.
- **Manual trades are allowed alongside the EA.** The EA never touches them and they don't block its
  entries. The panel shows how many there are and their P/L.

## Settings

### Signal indicator
| Input | Default | Meaning |
|---|---|---|
| Indicator file name | *(empty)* | Empty = use the indicator already on the chart. Fill it in only for the Strategy Tester (e.g. `CharisGoldFX.TradingView_Indicator`). |
| Chart indicator name contains | *(empty)* | If the chart has several indicators, part of the signal indicator's name (e.g. `CharisGold`). |
| Signal source | Auto | Auto tries indicator buffers first, then arrow objects drawn on the chart. |
| Buy / Sell arrow buffer | -1 | -1 = auto-detect. Set both (from the scanner) to force them. |
| Signal candle | 1 | 1 = last closed candle (recommended). 0 = live candle (arrows can repaint). |

### Lot size, SL, TP
| Input | Default | Meaning |
|---|---|---|
| Lot mode | Fixed lot | *Fixed lot*, or *% of balance* risked at the stop loss |
| Fixed lot / Risk % / Max lot | 0.01 / 1.0 / 5.0 | |
| Stop loss mode | ATR | *ATR × multiplier*, *Fixed pips* or *None* |
| SL ATR multiplier / SL pips | 1.5 / 30 ($3.00) | |
| Take profit mode | ATR | *ATR × multiplier*, *Fixed pips* or *None*, set separately from the SL |
| TP ATR multiplier / TP pips | 3.0 / 60 ($6.00) | |
| ATR period / timeframe | 14 / current | |

### Trade management and filters
| Input | Default | Meaning |
|---|---|---|
| Opposite signal | Ignore (wait until the trade closes) | Or *Close and reverse* / *Close only* |
| Breakeven | off | Trigger at 20 pips ($2.00) of profit, lock in 2 pips ($0.20) |
| Trailing stop | off | ATR × multiplier or fixed pips (20); starts at 30 pips of profit, moves in steps of 1 pip |
| Max spread | 0 (off) | Skips entries when the spread is wider |
| Daily loss limit % | 0 (off) | Stops new entries for the day once EA losses reach this % |
| Magic number | 20261008 | Identifies the EA's trades. Use a different one on each chart. |
| Popup / Push alerts | on / on | Alerts when the EA opens or closes a trade. Push needs your MetaQuotes ID in MT5 (see below). |
| Max slippage | 3 pips | $0.30 on XAUUSD. Exness gold uses market execution, so this is usually ignored. |
| Pip size | 0 (auto) | Auto: gold (XAU/GOLD) = 0.1, 5/3-digit FX = 10 points. Set it to override. |

## XAUUSD M5 on Exness

- Fixed SL 30 pips = $3.00 price move, TP 60 pips = $6.00. With 0.01 lot, a $1.00 price move is about $1.00 of P/L.
- The ATR modes adapt to volatility automatically. On M5 gold, ATR(14) is often 15-40 pips ($1.50-$4.00), so SL = 1.5 x ATR and TP = 3 x ATR.
- Gold spreads widen sharply around news and the daily rollover. Consider setting *Max spread* (e.g. 4-5 pips = $0.40-$0.50) to skip entries then.
- **Push notifications:** in the MT5 mobile app, open *Settings → Messages* and copy your **MetaQuotes ID**.
  In desktop MT5, go to *Tools → Options → Notifications*, tick *Enable Push Notifications* and paste the ID.

## Signal dots

| Input | Default | Meaning |
|---|---|---|
| Mark signal candles with dots | on | |
| Buy dot colour | Aqua | Drawn under the low of each buy signal candle |
| Sell dot colour | Magenta | Drawn above the high of each sell signal candle |
| Skipped signal dot colour | Yellow | Signals where no trade was opened (trade still running, auto off, spread or daily limit, or the order failed) |
| Dot size | 1 | 1-5 |
| Gap between candle and dot | 3 pips ($0.30) | |
| Past candles to mark at start | 500 | |

Every confirmed signal gets a dot. While the EA is running, a signal that opened a trade is aqua or
magenta, and a skipped one is **yellow** (still drawn under the candle for a buy, above it for a sell).
Dots for past candles marked at start-up are aqua or magenta only, because the EA wasn't running
then to know whether they would have been traded. Past signals are re-checked on every new candle,
so their dots also appear if the indicator finishes loading after the EA starts.

Dots stay on the chart when the EA restarts (timeframe change, new settings, recompile), so yellow
dots keep their colour. They are removed only when you remove the EA from the chart.

## The panel

- **Header:** symbol, timeframe and state (ACTIVE / PAUSED / BLOCKED / SEARCHING).
- **Signal:** source, indicator, buffers in use, last signal.
- **Position:** the EA trade (side, lots, entry, SL/TP, floating P/L) and your manual trades.
- **Market:** spread and ATR in pips, lot and SL/TP modes.
- **Today:** closed P/L, trades/wins, balance/equity.
- **Buttons:**
  - **BUY / SELL** open an EA-managed trade with the EA's SL/TP. They are blocked while an EA trade is running.
  - **CLOSE** closes the EA's trade only (your manual trades are not touched).
  - **AUTO** turns signal trading on/off. Management (breakeven, trailing) keeps running either way.

## Troubleshooting

- **No trades at all:** check the **Experts** tab. With *Log what the EA sees on every candle* on
  (the default), the EA writes one `[diag]` line per candle showing what it read from the indicator
  buffers, whether that was a signal, and whether something blocked the trade. Press the panel's
  **BUY** once on a demo account to check that orders go through; if they don't, the panel's message
  line shows the broker's error.

- **Panel stays on SEARCHING / "No arrow buffers found":** run the scanner and look for the lines
  marked `<<< BUY ARROWS` and `<<< SELL ARROWS`, then put those numbers into
  *Buy arrow buffer* / *Sell arrow buffer*. If the scanner finds no arrow buffers but lists arrow
  objects, set *Signal source = Arrow objects drawn on the chart*.
- **BLOCKED:** the message line at the bottom of the panel says why (Algo Trading off, spread, daily limit).
- **Strategy Tester:** the tester has no "indicator on the chart", so fill in *Indicator file name*.
  Chart-arrow mode does not work in the tester.
- **Netting accounts** merge all trades on a symbol into one position, so manual trades and EA trades
  can't be kept separate. Use a **hedging** account.
