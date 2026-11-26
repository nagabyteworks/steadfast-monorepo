# Architecture

This describes the current working tree, not the desired final architecture.
The [implementation status](IMPLEMENTATION_STATUS.md) identifies gaps.

## Components and trust boundaries

- [Vue app](../steadfast-app/src/) displays positions and rules, submits entry
  and manual-exit requests, and exposes no browser-side automatic monitor.
- [Express API](../steadfast-api/server.js) manages Flattrade sessions,
  order routes and, in server-managed mode, risk routes. The production API
  binds to loopback; CORS/origin checks and the internal token are not user
  authentication.
- [Python WebSocket service](../steadfast-websocket/flattrade/flattrade_websocket.py)
  receives broker LTP updates and feeds the [risk monitor](../steadfast-websocket/risk_monitor.py).
  Server-monitored rules are loaded from the API; progress and trigger requests
  use internal endpoints.
- Flattrade is the live broker. The API rejects `/virtual`; legacy development
  can still expose Shoonya functionality.

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
Once flagged, automatic and manual creation remain blocked pending manual
reconciliation; a resolution workflow is not implemented. Backend startup
suspends all persisted armed/in-flight rules before restoring sessions.
Creation pauses an armed rule before requesting broker data; failures record
the reason and timestamp. Session expiry suspends active rules.
Lifecycle identity alone cannot establish continuity of a carry-forward
position; historical order/trade recovery is not implemented.

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

The position view displays an evidence checklist for flagged symbols, but does
not accept documents or offer an override. A document or user confirmation
alone is not independently verified execution evidence. A future resolution
workflow must validate a complete lifecycle, present it for confirmation and
audit the evidence and user action before clearing the flag; this workflow and
any trusted verification source remain unimplemented.

## Monitoring and exits

The WebSocket risk monitor evaluates fixed SL/target and trailing modes from
LTP; trailing progress and triggers are sent to the API with a revision.
Browser-triggered automatic exits are disabled, and legacy UI-monitor rules
are migrated to the server monitor. Before an automatic exit submission the API
checks the stored revision and reconciliation flag, fetches position and trade
snapshots, verifies the opening fill against the stored account, instrument
and product identity, and checks the flag again. A successful PlaceOrder
acknowledgement is now recorded as `exit_pending` with the broker order ID, not
as a completed fill. Actual order/fill reconciliation is not yet implemented.
On restart, pending exits are flagged for reconciliation rather than silently
re-armed; no automatic recovery of their broker status is available yet.
Manual exits still use the browser order path; automatic and manual exits are
not serialized through a shared position-level exit service.

The server monitor and API reject nonpositive/non-finite prices; the API also
checks that the trigger reason matches a crossed fixed rule. A target-trailing
increment that cannot advance after rounding is logged and left unchanged.
Market-data age is not currently propagated into triggers, so stale-price
rejection is not established.

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
no complete exit-reconciliation or pending-exit recovery service. Rule storage
is still symbol-keyed, and concurrent external trading or changes after the
last broker snapshot can invalidate it. Flags do not revoke an order already
sent. Polling can temporarily display outdated UI state. These remain safety
risks, and no live broker behavior has been verified.
