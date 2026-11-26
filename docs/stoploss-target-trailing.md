# Stop-loss, target and trailing

This document describes how stop-loss (SL), target, trailing stop-loss (TSL) and trailing target (TT) work in Steadfast, who watches the price, how to deploy it and how to debug it.

## 1. Concepts

A **rule** belongs to one open position (keyed by its trading symbol) and holds:

| Field | Meaning |
| --- | --- |
| `instrument` | `EXCH\|token`, for example `NFO\|12345`. Used to subscribe to prices. |
| `side` | `long` (netqty > 0, exit is SELL) or `short` (exit is BUY). |
| `entry` | Average price of the position when the rule was created. |
| `slPrice` / `targetPrice` | Absolute trigger prices. Either may be empty, not both. |
| `mode` | `static`, `trailing_sl` or `target_trail` (see below). |
| `slPoints` | Distance the stop follows the price in `trailing_sl`. |
| `trailPoints` | Distance the target advances in `target_trail`. |
| `monitor` | Who watches the price: `server` or `ui`. |
| `status` | `armed`, `triggered`, `done`, `failed`, `cancelled`. |
| `rev` | Incremented on every save; lets the server detect user edits. |

### Modes

* **static**: fixed SL, optional fixed target. Hitting either exits the position.
* **trailing_sl (TSL)**: the SL follows the price at `slPoints` distance and only ever moves in the profit direction. A target, if present, still exits.
* **target_trail (TT)**: the target never exits. Each time the price reaches the target, the SL moves up to that target and the target advances by `trailPoints`. The position exits only when the SL is hit.

TSL and TT are mutually exclusive. Turning one on turns the other off, in the global toggles and in each position row.

### Exit order

The exit is a marketable **limit** order priced 2% through the last price (rounded to 0.05). Flattrade rejects API market orders (`ALGO_CHK`), so this is how a market-like exit is sent. Server exits are never retried automatically, because an order may have reached the broker even if the response was lost. Verify with Flattrade when a rule reports `failed`.

## 2. Who watches the price: the "Trigger from app (UI)" toggle

| Toggle | `monitor` | Watched by | Works when the page is closed |
| --- | --- | --- | --- |
| Off (default) | `server` | `steadfast-websocket` (`risk_monitor.py`), exit placed by the API | Yes |
| On | `ui` | The browser (`useUiRiskTriggers.js`, checked every second), exit placed by the app | No |

* New rules take the monitor from the toggle at the time they are created.
* Flipping the toggle re-assigns every armed rule immediately (`PATCH` with `monitor`). The API refuses a server trigger for a rule that is now `ui`, so a rule is never fired twice.
* In UI mode, trailing changes are saved back to the API, so the SL/target shown stay in sync.
* The price logic in the browser (`evaluateRule`) mirrors `evaluate` in `risk_monitor.py`.

## 3. Predefined protection (the toggles on the trade page)

* **Predefined Stoploss / Target**: when enabled, a new position automatically gets an SL / target at the configured points from its price. Defaults: SL 20, target 20.
* **Trailing stoploss**: new SL becomes a TSL. Turning it on also turns on Predefined Stoploss.
* **Target Trailing** (on by default, 10 points): new target becomes a TT. **Enabling it also enables Predefined Stoploss and Predefined Target**, and disabling either of those disables Target Trailing.
* **T** (before the target's X) and **TSL** buttons in a position row switch only that position, and mirror the change in the global toggle.
* SL and target values in a row can be edited by clicking them (Enter saves, Esc cancels, empty removes). `+` / `-` move the level by 1 point.

Browsers that already stored toggle values keep them; the new defaults apply to fresh browsers (or after clearing site data).

## 4. Data flow

```
App --PUT/PATCH/DELETE /flattrade/risk/rules/:tsym--> API (SQLite risk_rule)
                                                       | GET /internal/rules (monitor = server only, every 2 s)
                                                       v
                                  WebSocket service: subscribes to the tokens,
                                  evaluates each tick, moves trailing levels
                                       | POST /internal/progress   (trailing moved)
                                       | POST /internal/trigger    (SL/target hit)
                                       v
                                  API: claims the rule once, finds the open position,
                                  places the exit order, records status + message
App <--GET /flattrade/risk/rules (every 5 s with account refresh)-- shows levels and the outcome
```

In UI mode the browser evaluates ticks itself, places the exit through the normal order path and deletes the rule.

## 5. Live exits

Exits are always live. Server exits need `TRADING_ENABLED=true` and only NFO/BFO positions are exited.

## 6. Exit buttons

The Exit button in each position row closes that position immediately, **without a confirmation prompt**. Close All behaves as before.

## 7. Deploy

1. Copy `deploy/systemd/steadfast-api.service` to `/etc/systemd/system/`, then `sudo systemctl daemon-reload`.
2. `sudo systemctl restart steadfast-api steadfast-websocket`.
3. Build and publish the app (`npm run build` in `steadfast-app`).
4. The API and WebSocket service must share `WEBSOCKET_INTERNAL_TOKEN`; the WebSocket service reaches the API through `API_BASE_URL` (loopback).
5. Existing databases are upgraded automatically (a `monitor` column, default `server`, is added).

## 8. Logs and debugging

Server (`journalctl -u steadfast-api -u steadfast-websocket -f`):

| Message | Meaning |
| --- | --- |
| `Risk rule saved: TSYM monitor=... mode=... sl=... target=... rev=...` | API stored a create/edit. |
| `Risk rule removed: TSYM` | Rule deleted. |
| `Watching N risk rule(s): [...]` | WebSocket service loaded rules (printed whenever the set or levels change). |
| `Risk monitor subscribed to NFO\|token` | Price feed requested for a rule. |
| `Risk rules are waiting for the broker stream` | Rules exist but the broker stream is not authenticated yet. |
| `Risk rule hit for TSYM: Stop-loss at 101.5` | A tick crossed a level. |
| `Risk trigger received for TSYM: ... ` | API got the trigger. |
| `Risk exit submitted for TSYM` | Exit order accepted by Flattrade. |
| `Risk exit failed` | Order failed or is uncertain; check Flattrade. |
| `Risk trailing progress for TSYM: sl=... target=... applied=...` | Trailing level persisted. |
| `Risk progress pushed for TSYM` | WebSocket service sent a trailing update. |
| `Risk trigger for TSYM ignored: ...` | Rule already handled, removed, or owned by the app. |
| `Risk rule sync failed (type=...)` | WebSocket service could not reach the API (check token and `API_BASE_URL`). |

Browser console (prefixes `[risk]`, `[ui-risk]`, `[exit]`):

| Message | Meaning |
| --- | --- |
| `[risk] create/update TSYM {fields, deltas, monitor}` | A rule edit was sent. |
| `[risk] removing rule TSYM` | A rule was deleted. |
| `[risk] trigger source switched to ...` | The toggle changed. |
| `[ui-risk] trailing TSYM at LTP: sl a -> b, target c -> d` | UI trailing moved a level. |
| `[ui-risk] Stop-loss/Target hit for TSYM at LTP; sending exit` | UI trigger fired. |
| `[ui-risk] exit order accepted / not acknowledged` | Result of the UI exit. |
| `[exit] closing TSYM qty=N` | Manual or UI exit started. |

A rule that already fired shows its result under the symbol in the positions table.

## 9. Troubleshooting checklist

1. No `Risk rule saved` log: the app is not saving; check the browser console for the save error.
2. Saved but no `Watching ...`: the WebSocket service cannot read rules (token mismatch / `API_BASE_URL`), or the rule is `monitor=ui`.
3. `Watching ...` but never `Risk rule hit`: the price feed is not subscribed or the broker stream is not authenticated.
4. `trading disabled or unsupported exchange`: set `TRADING_ENABLED=true`; only NFO/BFO are supported.
