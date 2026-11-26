# Architecture

This describes the current working tree, not the desired final architecture.
The [implementation status](IMPLEMENTATION_STATUS.md) identifies gaps.

## Components and trust boundaries

- [Vue app](../steadfast-app/src/) displays positions and rules, submits entry
  and manual-exit requests, and can optionally monitor UI-selected risk rules
  while its page is open. It sends trigger signals to the API; it does not
  submit automatic broker exits itself.
- [Express API](../steadfast-api/server.js) manages Flattrade sessions,
  order routes, risk routes and the application-wide broker reconciliation
  scheduler in server-managed mode. The production API binds to loopback;
  CORS/origin checks and the internal token are not user authentication.
- [Python WebSocket service](../steadfast-websocket/flattrade/flattrade_websocket.py)
  receives broker LTP updates and feeds the [risk monitor](../steadfast-websocket/risk_monitor.py).
  Server-monitored rules are loaded from the API; UI-monitored rules are only
  monitored in the open browser tab. Both paths send progress and trigger
  requests to the API. An authenticated reconnect also signals the API
  scheduler to reconcile immediately.
- Flattrade is the live broker. The API rejects `/virtual`; legacy development
  can still expose Shoonya functionality.

## Application-wide reconciliation

[reconciliationService.js](../steadfast-api/reconciliationService.js) is the
only periodic broker-state reconciler. In server-managed mode it starts with
the API, runs an initial cycle, then schedules cycles every three seconds.
Cycles are single-flight; timer ticks during a slow request are skipped, and
order/session/reconnect events can queue an immediate follow-up. API order
submission, cancellation, session changes and uncertain order outcomes signal
it; no order-modification route currently exists.

Each cycle makes bounded sequential bulk reads of PositionBook, OrderBook for
products M and I, and TradeBook. Requests time out after 10 seconds. Failed
cycles use bounded backoff (honoring a capped broker `Retry-After` when
present) and do not stop later attempts. The SQLite lease prevents overlapping
cycles across API processes that share the same state database. It does not
coordinate instances on hosts with separate databases; deployment currently
uses one API service and one local SQLite state directory. Flattrade's actual
read-endpoint rate limits have not been independently verified.

The scheduler validates order/trade fill consistency, persists broker order
quantities and fill summaries only when changed, computes same-day position
metrics, adopts a matching active exit order instead of duplicating it, and
closes or restores rule state only when broker evidence supports the update.
The health endpoint `/health/reconciliation` reports scheduler/cycle status,
position/order counts, discrepancies, repairs, unresolved symbols and last
success; structured cycle logs include the cycle ID and broker-call results.
The rules endpoint also carries the status used by the app's periodic refresh.

## UI refresh and paired entry

The app refreshes account data every three seconds without reloading the page.
Each refresh validates broker tokens and updates funds, orders, positions and
risk rules; an in-flight guard prevents overlapping refreshes. The Buy Both and
Sell Both controls submit the selected CE then PE using the existing order
handlers. For LMT orders, each leg has its own sequential price dialog; canceling
the second dialog leaves the first submitted order unchanged.

## Rule creation and persistence flow

The app schedules default protection after an entry submission and position
refresh. `POST /flattrade/risk/rules/:tsym/default` requests a position book,
trade book and second position book from Flattrade. It compares the position
snapshots, checks the trade totals and reconstructs the first fill of the
current same-day open lifecycle. Manual creation uses the same reconciliation
via `POST /flattrade/risk/rules/:tsym/manual`. Missing, inconsistent or
ambiguous data is rejected for manual reconciliation; it is not replaced
with LTP or average.

[riskStore.js](../steadfast-api/riskStore.js) saves rules in SQLite keyed by
symbol and stores opening order/fill identity in `risk_lifecycle` keyed by
account and symbol. A matching lifecycle preserves an existing armed rule;
the save checks the rule revision inside a transaction. Rules expire at the
daily session cutoff. Reconciliation failures with an identifiable account
and invalid or incomplete broker data persist a `RECONCILIATION_REQUIRED`
record and suspend an armed rule.
Once flagged, ordinary automatic/manual rule creation remains blocked. The
scheduler attempts recovery on startup and later cycles, restoring a suspended
rule only when current broker positions/trades reconstruct its saved lifecycle
and any associated exit order is resolved. Backend startup suspends persisted
armed/in-flight rules before the initial broker reconciliation; session expiry
also suspends active rules. Missing, ambiguous or mismatched evidence remains
`ACTION REQUIRED`; no SL/target values are invented. Lifecycle identity alone
cannot establish continuity of a carry-forward position, and historical
order/trade recovery is not implemented.

### Flattrade history evidence

The [Flattrade API documentation](https://pi.flattrade.in/docs) describes
`POST /TradeBook` with fill identifiers, times, quantities and prices;
`POST /OrderBook`; and `POST /SingleOrdHist` for a specified order number.
The reviewed documentation does not establish a retention or completeness
guarantee for the entire offline period, nor a historical date-range query for
the trade book. An individual order's history does not prove that no other
orders closed and reopened the position.

An actual post-reconnect trade-book response has **not** been verified: no
local API health response was available on the checked ports. No service was
restarted and no broker request or order was made for this check. Observing
one response would not by itself establish the broker's retention guarantee.

The UI shows concise recovery statuses and does not display technical
reconciliation details in position rows. It reports `OPEN – PROTECTED` only
when the backend has a recent successful reconciliation; stale or failed cycles
show `OPEN – RECOVERING`. It does not accept documents or offer an override. A
document or user confirmation alone is not independently verified execution
evidence. A safe workflow for evidence unavailable from Flattrade, and any
trusted independent verification source, remain unimplemented.

## Monitoring and exits

The WebSocket risk monitor evaluates server-selected fixed SL/target and
trailing modes from LTP. The optional UI monitor evaluates UI-selected rules
using fresh per-position quotes while the page is open. Both paths send
revision-checked progress and trigger requests to the API; the browser never
submits an automatic broker exit. Before an automatic exit submission the API checks the stored monitor,
revision and reconciliation flag, fetches position and trade snapshots,
verifies the opening fill against the stored account, instrument and product
identity, and checks the flag again. A successful PlaceOrder acknowledgement
is recorded as `exit_pending` with the broker order ID, not as a completed fill.
The scheduler reconciles known order states and partial fills, adopts a single
matching active exit, and closes the rule only after a flat broker position is
observed with consistent order/trade evidence. On restart, pending exits are
checked against broker state; unresolved or unmatchable requests remain
`ACTION REQUIRED` instead of being retried or silently re-armed. Manual exits
still use the browser order path; automatic and manual exits are not serialized
through a shared position-level exit service.

The server monitor and API reject nonpositive/non-finite prices; the API also
checks that the trigger reason matches a crossed fixed rule. The UI monitor
ignores missing, invalid or older-than-30-second per-position quotes. The API
does not independently verify quote age, so server-side stale-price rejection
is not established. A target-trailing increment that cannot advance after
rounding is logged and left unchanged.

Both current exit paths use a 2% LTP-based marketable-limit buffer with a
fixed 0.05 tick. They do not implement the agreed fresh-depth, price-band and
three-attempt cancellation/replacement policy. Monitoring, network and broker
outages or unfilled orders can leave positions open; no broker-side protective
SL or target is maintained by this risk flow.

## Security and recovery boundaries

The API persists broker sessions and rules in separate SQLite databases.
Session tokens are not encrypted at rest; protect the state directory and
backups. `TRADING_ENABLED` gates order placement/cancellation and server risk
exits, but does not close positions or cancel existing broker orders. There is
no automatic exit submission from reconciliation when LTP monitoring misses a
trigger; the scheduler uses broker evidence for state recovery and does not
infer triggers from stale prices. There is no bounded exit cancel/replace
service. Rule storage is still symbol-keyed, and concurrent external trading
or changes after the last broker snapshot can invalidate it. Flags do not
revoke an order already sent. Polling can temporarily display outdated UI
state. These remain safety risks, and no live broker behavior or rate-limit
behavior has been verified.
