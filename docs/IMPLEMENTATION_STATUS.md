# Implementation status

Snapshot: 2026-11-26, current working tree, including uncommitted changes. This
is not a release or deployment approval. See [test status](TEST_STATUS.md) for
the scope and date of the latest runs.

Statuses: **NOT STARTED**, **IN PROGRESS**, **IMPLEMENTED**, **TESTED**, and
**BLOCKED**. An IN PROGRESS item may have passing tests for a subset of its
behavior; that does not make the entire requirement TESTED.

| Requirement | Status | Evidence and limitations | Remaining work / dependencies |
| --- | --- | --- | --- |
| Live Flattrade and trading gate | IN PROGRESS | [Flattrade routes](../steadfast-api/routes/flattrade.js) enforce a trading gate, session and 1–10 whole lots per server-managed order; API tests pass. The checked-in production unit explicitly enables trading. A successful response is not a confirmed fill. | Keep the agreed configuration unchanged unless explicitly authorized; add broker readiness and reconciliation before new trades. Verify the unit's live-enabled default against the agreed startup safeguard. |
| No simulated production orders | IN PROGRESS | [/virtual](../steadfast-api/routes/virtual.js) returns 403 in every profile and has a gate test. Production blocks Shoonya; legacy development still supports it. | Explicit PAPER/SIMULATION mode rejection and complete runtime enforcement are not verified. |
| First-fill manual and default protection | IN PROGRESS | [Lifecycle reconstruction](../steadfast-api/positionLifecycle.js) and [risk routes](../steadfast-api/routes/risk.js) reconcile same-day position and trade books for manual/default creation and before automated exit. Backend startup, session expiry and reconciliation failure suspend rules persistently; flagged symbols cannot be automatically rearmed. | Manual resolution and multi-day historical continuity are not implemented. Startup suspends even previously valid rules, leaving them unprotected with no in-app resolution. Rule storage remains symbol-keyed; broker positions may change after the final snapshot. |
| Virtual fixed SL and target | IN PROGRESS | [WebSocket monitor](../steadfast-websocket/risk_monitor.py) evaluates server-selected rules; optional UI monitoring checks fresh per-position quotes and sends trigger signals to the API. The API validates monitor, trigger price, reason, revision and opening fill before placing exits. | API-side quote age is not checked, WebSocket reconnect does not persist a reconciliation flag, and confirmed execution/recovery remain incomplete. |
| Trailing SL and target trailing | IN PROGRESS | Default entry settings now pass selected trailing-stop or target-trailing mode and points to the API; both monitor paths preserve directional arithmetic and avoid non-advancing target-trail increments. | Tick-size validation, quote ordering/freshness, durable error reporting and reliable progress recovery remain incomplete. |
| Centralized exit service | IN PROGRESS | Both server and UI monitors submit trigger signals to the API; neither browser monitor places broker orders directly. Flattrade PlaceOrder acknowledgement now leaves the rule `exit_pending` with the broker order ID in its message. Pending exits are flagged for reconciliation on API restart. | Manual exits still use a separate browser order path; no durable shared exit service or fill reconciler exists. |
| Percentage partial exits | NOT STARTED | No 25/50/75/100% workflow or confirmed remaining-quantity tracking. | Requires centralized exits, lot rounding/validation, and broker reconciliation. |
| Broker order and fill reconciliation | IN PROGRESS | Manual and default protection creation reconcile position quantities with same-day trade history. Automatic exit acknowledgement is now represented as `exit_pending`, not a confirmed fill. | Persist/reconcile exit orders and actual fills, cancellations, rejection, timeouts and remaining quantities; recover pending exits after restart. |
| Marketable-LMT exit repricing | NOT STARTED | Existing exit paths use a 2% LTP buffer and a fixed 0.05 tick; no bounded cancellation/replacement lifecycle. | Obtain fresh depth, instrument tick size and price bands; implement the agreed three-attempt policy and confirm cancellation and remaining quantity before replacement. |
| Per-position state and audit history | IN PROGRESS | SQLite persists symbol-keyed rules and opening-fill identity; rule revisions guard trailing progress. | Stable account/exchange/product/lifecycle identity, execution and edit history, timestamp ordering, and safe concurrent updates remain incomplete. |
| UI controls and status | IN PROGRESS | Entry screen exposes fixed SL/target, trailing SL, target trailing, and a server/UI monitor toggle. Position rows omit warning details; open-position reconciliation and exit outcomes remain available in the global notification panel. UI monitoring requires this tab and fresh quotes. | Actual exit fills and realized P&L are not yet reconciled or displayed. Verified evidence intake and recovery remain unimplemented. |

Virtual rules are not exchange-side protection. Feed, backend, network or broker
failure, or an unfilled order, can leave a position open. Do not treat this
snapshot as evidence that live exits or recovery are safe.
