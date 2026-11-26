# Stop-loss, target and trailing

This document describes how stop-loss (SL), target, trailing stop-loss (TSL) and trailing target (TT) work in Steadfast, who watches the price, how to deploy it and how to debug it.

**Safety:** These are virtual rules, not exchange-side protection. Feed, monitor,
network or broker failures, and unfilled exit orders, can leave a position open.
Order submission is not confirmation of execution; verify fills with Flattrade.

## 1. Concepts

A **rule** belongs to one open position (keyed by its trading symbol) and holds:

| Field | Meaning |
| --- | --- |
| `instrument` | `EXCH\|token`, for example `NFO\|12345`. Used to subscribe to prices. |
| `side` | `long` (netqty > 0, exit is SELL) or `short` (exit is BUY). |
| `entry` | First opening fill for reconciled manual and default rules. |
| `slPrice` / `targetPrice` | Absolute trigger prices. Either may be empty, not both. |
| `mode` | `static`, `trailing_sl` or `target_trail` (see below). |
| `slPoints` | Distance the stop follows the price in `trailing_sl`. |
| `trailPoints` | Distance the target advances in `target_trail`. |
| `monitor` | Who watches the price: `server` or `ui`. |
| `status` | `armed`, `triggered`, `done`, `failed`, `cancelled`, `reconciliation_required`. |
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
| On | `ui` | The browser (`useUiRiskTriggers.js`, checked every second), exit requested through the API | No |

* New rules take the monitor from the toggle at the time they are created.
* Flipping the toggle re-assigns armed rules (`PATCH` with `monitor`). The API refuses a server trigger when the stored rule is already `ui`; this does not guarantee that simultaneous UI and server exits cannot race.
* In UI mode, trailing changes are saved back to the API, so the SL/target shown stay in sync.
* The price logic in the browser (`evaluateRule`) mirrors `evaluate` in `risk_monitor.py`.

## 3. Predefined protection (the toggles on the trade page)

* **Predefined Stoploss / Target**: when enabled, the API attempts to reconstruct the first fill of the current open position from Flattrade's trade and position books and sets levels from that fill. Defaults: SL 20, target 20.
  If the books cannot be reconciled, no new default rule is created and the app reports that manual reconciliation is needed.
  A same-day restart can recover the lifecycle from complete broker history; an unidentified carry-forward position cannot currently be recovered automatically.
* Manual creation uses the same first-fill reconciliation. An identified
  reconciliation failure persists a warning and suspends an armed rule; verify
  protection with Flattrade. Flagged symbols cannot be rearmed automatically;
  a manual resolution workflow is not yet implemented. Startup and broker
  reconciliation failures suspend existing rules; manual exits remain available.
* **Trailing stoploss**: new SL becomes a TSL. Turning it on also turns on Predefined Stoploss.
* **Target Trailing** (on by default, 10 points): new target becomes a TT. **Enabling it also enables Predefined Stoploss and Predefined Target**, and disabling either of those disables Target Trailing.
* **T** (before the target's X) and **TSL** buttons in a position row switch only that position, and mirror the change in the global toggle.
* SL and target values in a row can be edited by clicking them (Enter saves, Esc cancels, empty removes). `+` / `-` move the level by 1 point.

Browsers that already stored toggle values keep them; the new defaults apply to fresh browsers (or after clearing site data).

## 4. Data flow

```
App --POST /flattrade/risk/rules/:tsym/default (reconciled defaults)--> API
App --POST /flattrade/risk/rules/:tsym/manual (reconciled manual)----> API
App --PATCH/DELETE /flattrade/risk/rules/:tsym----------------------> API (SQLite risk_rule)
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

In UI mode the browser evaluates ticks and requests an exit through the risk API.
The API rechecks the rule and broker lifecycle before submitting an exit.

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
| `[ui-risk] exit for TSYM threw` | Browser trigger request failed; verify the broker position. |
| `[exit] closing TSYM qty=N` | Manual exit started. |

A rule that already fired shows its result under the symbol in the positions table.

## 9. Troubleshooting checklist

1. For manual edits, check the browser console and `Risk rule saved` logs for save errors.
   Default-rule reconciliation uses a separate endpoint; check for `Default protection reconciliation failed`.
2. Saved but no `Watching ...`: the WebSocket service cannot read rules (token mismatch / `API_BASE_URL`), or the rule is `monitor=ui`.
3. `Watching ...` but never `Risk rule hit`: the price feed is not subscribed or the broker stream is not authenticated.
4. `trading disabled or unsupported exchange`: set `TRADING_ENABLED=true`; only NFO/BFO are supported.
5. The restored server monitor does not reject nonpositive or nonfinite LTP, nor
   invalid next trailing targets. Do not rely on these values being filtered.
   The browser monitor alerts if a target cannot advance to a positive price;
   this check is not present in the server monitor.

## 10. Risk tests and coverage

The frontend risk suite includes regression tests for reopening a strike and adding lots:

```sh
npm run test:risk:coverage --prefix steadfast-app
```

The 70% thresholds apply separately to lines, statements, functions and branches in
`useRiskManagement.js` and `useUiRiskTriggers.js`. Manual and default creation
reconcile the current day's fills. Rules are keyed by symbol, and exits are not yet reconciled against
confirmed fills. Verify protection with the broker; do not assume these scenarios
are protected as requested.

API risk store and route coverage can be checked with:

```sh
node --test --experimental-test-coverage --test-coverage-include='**/riskStore.js' --test-coverage-include='**/routes/risk.js' steadfast-api/test/riskStore.test.js steadfast-api/test/riskRoutes.test.js
```

For the WebSocket monitor, install the optional `coverage` package in its virtual
environment, then run:

```sh
cd steadfast-websocket
.venv/bin/python -m coverage run --branch --source=risk_monitor -m unittest test_risk_monitor
.venv/bin/python -m coverage report -m
```
