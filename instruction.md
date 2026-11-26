# Steadfast – Implement Application-Wide Automatic Reconciliation Every 3 Seconds

## Objective

Implement a centralized, application-wide automatic reconciliation mechanism that synchronizes the entire Steadfast trading application's internal state with LIVE Flattrade broker state every 3 seconds.

I do not want manual reconciliation, manual protection verification or manual reactivation of suspended protection rules.

The backend must continuously maintain accurate broker and application state.

## 1. Central reconciliation scheduler

Implement one centralized reconciliation scheduler in the backend.

Requirements:

- Run reconciliation every 3 seconds during active trading.
- Cover all active positions and relevant pending orders, not just the position currently visible in the UI.
- Start an initial reconciliation when the backend starts.
- Continue reconciling after WebSocket reconnects and broker API failures.
- Reconcile immediately after important events such as BUY submission, SELL submission, order modification and cancellation, without waiting for the next scheduled cycle.
- Do not create separate competing schedulers in the frontend, WebSocket service and API.
- Ensure only one reconciliation cycle runs at a time.
- Prevent overlapping executions when a previous cycle takes longer than 3 seconds.
- Use a single-flight lock and appropriate distributed locking if multiple backend instances are possible.
- Make the scheduler lifecycle safe during application shutdown and restart.

## 2. Reconcile the entire application

Every reconciliation cycle must compare internal application state with Flattrade's actual state.

Reconcile:

1. Broker positions.
2. Open and pending orders.
3. Completed orders.
4. Trade book and execution fills.
5. BUY order execution status.
6. SELL order execution status.
7. Partially filled orders.
8. Remaining open quantities.
9. Average entry and exit prices.
10. SL and target rules.
11. Suspended protection rules.
12. Pending exit requests.
13. Uncertain or timed-out broker requests.
14. Internal position lifecycle state.
15. Duplicate or conflicting orders.

Use broker endpoints efficiently. Prefer bulk retrieval and batch reconciliation instead of issuing unnecessary requests for each individual position.

## 3. Automatic protection recovery

If an open position exists but its protection is missing, suspended or inconsistent:

- Automatically identify the actual open quantity.
- Reconstruct the position's correct lifecycle.
- Restore its valid SL and target rules.
- Resume monitoring when the required state has been established.
- Never require manual verification or manual reactivation during recoverable failures.
- Never silently mark an unverified position as protected.

For positions where protection parameters cannot be safely reconstructed, preserve the last valid protection configuration and raise an actionable internal recovery condition. Do not invent SL or target values.

## 4. Automatic exit execution

When SL or target triggers:

- Automatically submit a LIVE SELL order.
- Use the actual remaining broker position quantity.
- Ensure only one active exit operation exists for a position.
- Handle partial fills.
- Reconcile uncertain requests before retrying.
- Never create duplicate SELL orders.
- Mark CLOSED only after broker reconciliation confirms the position is flat.

The reconciliation scheduler must also discover positions whose exit should have occurred but whose exit request failed or was left unresolved.

## 5. Real-time risk monitoring must remain independent

Do not replace real-time LTP monitoring with 3-second reconciliation.

- WebSocket market data remains responsible for real-time price updates.
- The risk engine evaluates SL and target triggers using live market data.
- The centralized backend execution service remains the sole authority for broker order submission.
- Reconciliation independently verifies that the resulting broker state matches the expected state.

There must be no competing exit execution authorities.

## 6. Failure handling

Handle:

- Flattrade API timeouts.
- Network disconnections.
- Authentication/session expiry.
- Rate limits.
- Broker errors.
- Partial execution.
- Missing or stale market data.
- Backend restarts.
- WebSocket reconnects.
- Conflicting broker and application state.

Use bounded retries, backoff where appropriate, request timeouts and circuit-breaker protection.

The scheduler must continue attempting reconciliation every 3 seconds without allowing overlapping requests or violating broker API limits. If the broker imposes rate limits, batch requests and coordinate API calls centrally.

A failed cycle must not permanently stop future reconciliation cycles.

## 7. Monitoring and observability

Record:

- Reconciliation cycle ID.
- Start and completion timestamps.
- Duration.
- Broker API calls and response status.
- Number of positions checked.
- Number of orders checked.
- Number of discrepancies found.
- Number of discrepancies automatically repaired.
- Number of positions requiring further recovery.
- Last successful reconciliation timestamp.

Expose a backend health/status endpoint showing:

- Scheduler running status.
- Last successful reconciliation.
- Last attempted reconciliation.
- Current reconciliation status.
- Active position count.
- Unresolved reconciliation count.

The UI should show simple statuses, not technical reconciliation logs.

## 8. Performance and reliability

- Do not allow a slow reconciliation cycle to block order placement or real-time risk monitoring.
- Avoid unnecessary database writes when nothing has changed.
- Use atomic updates and idempotency.
- Protect against concurrent modifications by order-management and risk-management services.
- Support application restarts and multiple backend instances safely.
- Ensure one authoritative state per position.

## 9. User experience

Remove routine manual reconciliation workflows.

Users should not need to:
- Click Verify with Flattrade.
- Manually reactivate protection.
- Manually reconcile positions.
- Refresh the app to synchronize broker state.

Show only:
- OPEN – PROTECTED
- OPEN – RECOVERING
- EXITING
- EXIT PARTIALLY FILLED
- CLOSED
- ACTION REQUIRED

Only show ACTION REQUIRED when automatic recovery genuinely cannot safely resolve the state.

## 10. Testing and acceptance criteria

Use mocked Flattrade responses for all automated tests. Never submit real-money orders during development or testing.

Verify:

- Scheduler executes at the configured 3-second interval.
- No overlapping cycles occur.
- Multiple open positions are reconciled.
- Pending orders and partial fills are reconciled.
- Missing protection is automatically recovered.
- A failed cycle does not stop future cycles.
- Backend restart restores reconciliation.
- WebSocket reconnect triggers immediate reconciliation.
- Duplicate SELL orders are prevented.
- An uncertain SELL request is resolved before another SELL is submitted.
- SL and target continue triggering through real-time market data.
- No simulated or paper trading mode is introduced.

## Implementation instructions

First inspect the existing architecture across all four repositories:

- steadfast-monorepo
- steadfast-api
- steadfast-websocket
- steadfast-app

Identify existing reconciliation logic and reuse or refactor it instead of creating duplicate mechanisms.

Implement this as a centralized backend service with clear ownership, tests, structured logging and documentation.

Do not simply add a setInterval() call that repeatedly invokes existing reconciliation endpoints.

Do not hide errors or falsely report successful reconciliation.

Do not change the LIVE trading configuration, and never place actual broker orders during development or testing.

Deliver a summary of changed files, architecture, tests, remaining limitations and deployment requirements.