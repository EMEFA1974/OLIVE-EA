# Olive Trade Manager (MT5)

An Expert Advisor that takes **confirmed arrow signals** from a custom indicator,
opens one trade at a time and manages it. It is built for compiled `.ex5`
indicators like **CharisGold FX**, so you don't need the indicator's source code.

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
- **One EA trade at a time.** A signal in the same direction as the open trade is ignored.
  An opposite signal **closes the trade and reverses** by default; you can change this to close only, or ignore.
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
| SL ATR multiplier / SL pips | 1.5 / 30 | |
| Take profit mode | ATR | *ATR × multiplier*, *Fixed pips* or *None*, set separately from the SL |
| TP ATR multiplier / TP pips | 3.0 / 60 | |
| ATR period / timeframe | 14 / current | |

### Trade management and filters
| Input | Default | Meaning |
|---|---|---|
| Opposite signal | Close and reverse | Or *Close only* / *Ignore* |
| Breakeven | off | Trigger at X pips of profit, lock in Y pips |
| Trailing stop | off | ATR × multiplier or fixed pips; starts at X pips of profit |
| Max spread | 0 (off) | Skips entries when the spread is wider |
| Daily loss limit % | 0 (off) | Stops new entries for the day once EA losses reach this % |
| Pip size | 0 (auto) | Auto: gold (XAU/GOLD) = 0.1, 5/3-digit FX = 10 points. Set it to override. |
| Magic number | 20261008 | Identifies the EA's trades. Use a different one on each chart. |
| Popup / Push alerts | on / off | Alerts when the EA opens or closes a trade. Push needs MT5 notifications set up. |

## The panel

- **Header:** symbol, timeframe and state (ACTIVE / PAUSED / BLOCKED / SEARCHING).
- **Signal:** source, indicator, buffers in use, last signal.
- **Position:** the EA trade (side, lots, entry, SL/TP, floating P/L) and your manual trades.
- **Market:** spread, ATR in pips, lot and SL/TP modes.
- **Today:** closed P/L, trades/wins, balance/equity.
- **Buttons:**
  - **BUY / SELL** open an EA-managed trade with the EA's SL/TP; an opposite EA trade is closed first.
  - **CLOSE EA TRADE** closes the EA's trade only.
  - **AUTO** turns signal trading on/off. Management (breakeven, trailing) keeps running either way.

## Troubleshooting

- **Panel stays on SEARCHING / "No arrow buffers found":** run the scanner and look for the lines
  marked `<<< BUY ARROWS` and `<<< SELL ARROWS`, then put those numbers into
  *Buy arrow buffer* / *Sell arrow buffer*. If the scanner finds no arrow buffers but lists arrow
  objects, set *Signal source = Arrow objects drawn on the chart*.
- **BLOCKED:** the message line at the bottom of the panel says why (Algo Trading off, spread, daily limit).
- **Strategy Tester:** the tester has no "indicator on the chart", so fill in *Indicator file name*.
  Chart-arrow mode does not work in the tester.
- **Netting accounts** merge all trades on a symbol into one position, so manual trades and EA trades
  can't be kept separate. Use a **hedging** account.
