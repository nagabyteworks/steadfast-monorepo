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
| Virtual fixed SL and target | IN PROGRESS | [WebSocket monitor](../steadfast-websocket/risk_monitor.py) evaluates price conditions; a browser monitor also exists. Both request backend-checked exits. | A WebSocket reconnect does not itself persist a reconciliation flag; verification occurs at the next trigger. Confirmed execution and complete recovery remain incomplete. |
| Trailing SL and target trailing | IN PROGRESS | Both monitor paths implement directional arithmetic; target trailing does not exit at a milestone. Selected arithmetic tests pass. | Tick-size validation, ordering/freshness, reliable progress recovery and concurrency are incomplete. The restored server monitor does not reject nonpositive next targets or guard against non-advancing trailing increments; the browser path does. |
| Centralized exit service | IN PROGRESS | Browser and server automatic triggers share the risk endpoint handler; manual exits remain separate. | Implement one durable, serialized service for all exits before relying on duplicate-prevention guarantees. |
| Percentage partial exits | NOT STARTED | No 25/50/75/100% workflow or confirmed remaining-quantity tracking. | Requires centralized exits, lot rounding/validation, and broker reconciliation. |
| Broker order and fill reconciliation | IN PROGRESS | Manual and default creation reconcile position quantities with same-day trade history. Automated exit submission records `done` on broker acknowledgement rather than confirmed execution. | Reconcile historical order and trade data, actual orders, fills, cancellations, rejection, timeouts and remaining quantities; recover pending exits after restart. |
| Marketable-LMT exit repricing | NOT STARTED | Existing exit paths use a 2% LTP buffer and a fixed 0.05 tick; no bounded cancellation/replacement lifecycle. | Obtain fresh depth, instrument tick size and price bands; implement the agreed three-attempt policy and confirm cancellation and remaining quantity before replacement. |
| Per-position state and audit history | IN PROGRESS | SQLite persists symbol-keyed rules and opening-fill identity; rule revisions guard trailing progress. | Stable account/exchange/product/lifecycle identity, execution and edit history, timestamp ordering, and safe concurrent updates remain incomplete. |
| UI controls and status | IN PROGRESS | Position rows show protected, unprotected, in-progress or reconciliation-required state; flagged positions show a warning and checklist. Browser triggers use the backend risk endpoint. | Status is based on the last synchronized snapshot and may lag; the displayed timestamp records a status update, not a full attempt history. Verified evidence intake, review, confirmation and audit workflow remain unimplemented. |

Virtual rules are not exchange-side protection. Feed, backend, network or broker
failure, or an unfilled order, can leave a position open. Do not treat this
snapshot as evidence that live exits or recovery are safe.
