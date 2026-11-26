# Task: Fix Steadfast Trading – Simple BUY → Automatic Stop Loss / Target → SELL

You are working on the Steadfast trading platform, consisting of four repositories:

1. https://github.com/nagabyteworks/steadfast-monorepo
2. https://github.com/nagabyteworks/steadfast-app
3. https://github.com/nagabyteworks/steadfast-api
4. https://github.com/nagabyteworks/steadfast-websocket

Your primary responsibility is to make the basic trading experience reliable, predictable, and extremely simple.

## 1. Understand the actual product requirement

I want a simple options trading application.

As a user, I want to:

1. Select an instrument.
2. Enter quantity.
3. Enable or disable Stop Loss.
4. Enter Stop Loss points.
5. Enable or disable Target.
6. Enter Target points.
7. Click BUY.
8. Have the application automatically monitor the position.
9. When Stop Loss or Target is reached, automatically SELL the open position.
10. See the actual execution status.

That's it.

I do not want unnecessary configuration screens, technical options, complicated workflows, or multiple ways to manage the same position.

The backend should handle the complexity.

## 2. Mandatory first step: Audit all four repositories

Before modifying anything:

- Inspect the complete architecture.
- Understand the existing application, API, WebSocket and broker integration.
- Trace the complete BUY request lifecycle.
- Trace how entry fills are identified.
- Trace how default SL/target protection is created.
- Trace how market prices reach the risk monitor.
- Trace how SL/target triggers are evaluated.
- Trace how automatic SELL orders are submitted.
- Trace how order status and actual fills are reconciled.
- Inspect existing tests and implementation-status documentation.
- Identify duplicate implementations and conflicting responsibilities.

Pay particular attention to:

- `positionLifecycle.js`
- `riskStore.js`
- `routes/risk.js`
- `routes/flattrade.js`
- `useOrderManagement.js`
- `useRiskManagement.js`
- `useUiRiskTriggers.js`
- `risk_monitor.py`

Do not assume existing functionality works just because functions and tests exist.

Identify the actual root causes of the existing SL/target failures.

Do not replace the entire architecture unnecessarily. Reuse working code and make targeted improvements.

## 3. Simplify the trading UI

The normal trading screen should expose only:

- Instrument
- Quantity
- BUY button
- Stop Loss toggle
- Stop Loss points
- Target toggle
- Target points

Example:

Instrument: NIFTY Option

Quantity: 1 lot

Stop Loss: ON
Stop Loss: 20 points

Target: ON
Target: 30 points

[ BUY ]

The values above are illustrative.

Requirements:

- Both SL and Target can be enabled independently.
- Both can be disabled.
- SL-only must work.
- Target-only must work.
- Both enabled must work.
- Both disabled must not create automatic protection.
- Do not expose internal monitoring architecture to ordinary users.
- Remove unnecessary UI monitoring/server monitoring switches.
- Remove unnecessary manual reconciliation workflows from the normal trading flow.
- Keep advanced trailing functionality separate from the basic trading experience.
- Do not break existing position visibility or manual SELL functionality.

Do not redesign unrelated application screens.

## 4. Make the backend the single execution authority

The backend must own:

- Entry order submission.
- Entry fill reconciliation.
- Position lifecycle.
- Stop Loss and Target creation.
- Risk monitoring coordination.
- Exit order submission.
- Exit fill reconciliation.
- Remaining quantity tracking.
- Duplicate-exit prevention.
- Restart recovery.
- Execution history.

The WebSocket service should primarily provide market data and evaluate risk conditions if that responsibility remains in the existing design.

It must not independently submit broker orders.

The browser must not independently submit automatic exit orders.

All automatic and manual exits must pass through one centralized backend exit service.

There must never be competing execution authorities.

## 5. Implement the correct BUY lifecycle

When the user clicks BUY:

1. Validate instrument, quantity and protection settings.
2. Validate broker session and live trading readiness.
3. Submit the actual LIVE BUY order.
4. Record the broker order ID.
5. Reconcile the order until its actual filled quantity is known.
6. Do not create protection for unfilled quantity.
7. Create protection using the actual average entry fill price.
8. For partial entry fills, protect the confirmed filled quantity.
9. Continue reconciling any outstanding entry quantity.
10. Return accurate position and protection status to the application.

Never treat an order acknowledgement as proof of a fill.

Never calculate SL/target from an assumed entry price when actual execution data is available.

## 6. Implement reliable fixed Stop Loss and Target

For a LONG options position:

- SL price = actual average entry price - SL points.
- Target price = actual average entry price + Target points.

For a SHORT position, reverse the calculations appropriately.

Requirements:

- Validate positive prices.
- Validate instrument tick sizes.
- Validate price precision.
- Handle market-price updates correctly.
- Handle missing, zero, invalid and stale LTP.
- Handle WebSocket disconnections.
- Avoid duplicate triggers.
- Trigger SL and Target independently.
- Ensure a crossed threshold cannot be silently ignored.
- Persist the protection configuration and its lifecycle state.

The trigger must use the correct position direction and actual instrument.

Do not accidentally apply equity-style assumptions to options positions.

## 7. Implement reliable automatic SELL

When SL or Target triggers:

1. Atomically claim the position's exit lifecycle.
2. Prevent other automatic or manual exit workflows from submitting duplicate orders.
3. Fetch the latest broker position.
4. Verify the actual remaining open quantity.
5. Submit a LIVE SELL order for that quantity.
6. Record the broker order ID.
7. Reconcile the actual order status and fills.
8. Handle partial fills.
9. If quantity remains open, continue the controlled exit process.
10. Mark the position CLOSED only after the broker confirms that the position is flat.

Never mark an exit as successful merely because Flattrade returned `stat: "Ok"`.

An accepted order is not necessarily an executed order.

Implement appropriate handling for:

- Order rejection.
- Broker timeout.
- Unknown execution status.
- Partial fills.
- Cancellation.
- Replacement orders.
- Network failure.
- Duplicate requests.
- Manual SELL during automatic exit.

Do not blindly retry an order after a timeout. First reconcile the original order to determine whether it was accepted or executed.

Respect Flattrade API restrictions and supported order types. Use valid tick sizes, price bands and fresh market depth when calculating marketable limit prices.

## 8. Centralize position lifecycle and concurrency

Implement a durable position-level state machine.

Suggested states:

- ENTRY_PENDING
- ENTRY_PARTIALLY_FILLED
- OPEN
- EXIT_PENDING
- EXIT_PARTIALLY_FILLED
- EXIT_UNCERTAIN
- CLOSED
- ENTRY_FAILED
- RECONCILIATION_REQUIRED

Requirements:

- Use stable position/lifecycle identifiers.
- Do not rely exclusively on trading symbols as unique position identities.
- Use atomic state transitions.
- Implement database-backed duplicate-exit protection.
- Make exit requests idempotent.
- Maintain actual remaining quantities.
- Preserve execution and state-transition history.
- Handle concurrent WebSocket events and manual actions safely.

## 9. Restart and recovery

This is mandatory.

If the API or WebSocket service restarts:

- Reconnect to the broker.
- Retrieve actual open positions.
- Retrieve outstanding orders.
- Retrieve relevant order history and trade history.
- Reconcile pending entries and exits.
- Restore valid SL/target rules.
- Resume monitoring only after successful reconciliation.
- Detect positions without protection.
- Detect outstanding exits that may already have filled.
- Never submit a duplicate exit during recovery.

Do not silently suspend protection and leave the user with no practical recovery path.

If recovery cannot establish a safe state, clearly report RECONCILIATION_REQUIRED and do not pretend the position is protected.

## 10. Simplify position status

The application should show only meaningful user-facing states:

- ENTRY PENDING
- OPEN – PROTECTED
- OPEN – UNPROTECTED
- EXITING
- EXIT PARTIALLY FILLED
- CLOSED
- ACTION REQUIRED

Show:

- Entry price
- Current LTP
- Quantity
- Remaining quantity
- Stop Loss price
- Target price
- Exit reason
- Actual exit price
- Actual realized P&L

Show accurate broker-confirmed execution status.

Do not show misleading success notifications.

## 11. LIVE TRADING ONLY

I explicitly do not want paper trading or simulated production orders.

Requirements:

- Use the actual Flattrade LIVE integration.
- Do not silently fall back to PAPER or SIMULATION mode.
- Do not create fake broker responses.
- Do not simulate successful BUY or SELL executions.
- Fail closed when live broker readiness cannot be established.
- Validate broker session and trading permissions before submitting orders.
- Do not change existing production trading configuration without understanding and preserving the agreed live-trading setup.

For automated tests, use mocked broker responses and test fixtures. These must never be connected to real order submission.

Never place real orders during development or testing.

## 12. Mandatory automated test cases

Implement integration and unit tests for all of the following:

1. BUY completely filled → SL triggered → SELL completely filled → CLOSED.
2. BUY completely filled → Target triggered → SELL completely filled → CLOSED.
3. SL enabled, Target disabled → SL works.
4. Target enabled, SL disabled → Target works.
5. Both enabled → whichever triggers first initiates the exit.
6. Both disabled → no automatic exit.
7. BUY partially filled → protection applies only to filled quantity.
8. Additional BUY fills → protection quantity is updated safely.
9. SELL partially filled → remaining quantity is tracked.
10. SELL rejected → position remains open.
11. SELL times out → original order reconciled before another submission.
12. Duplicate SL events → only one exit workflow.
13. Duplicate Target events → only one exit workflow.
14. Manual SELL and automatic SL occur simultaneously → no duplicate orders.
15. API restarts with an open position → protection is restored.
16. API restarts with an outstanding SELL → original order is reconciled.
17. WebSocket disconnects and reconnects → monitoring recovers safely.
18. Invalid LTP → no invalid exit order.
19. Stale market data → unsafe automatic execution is prevented and reported.
20. Broker session expires → position is reported as requiring attention.

Add regression tests for every root cause identified during the audit.

## 13. Performance, security and reliability

- Use bounded broker API requests and timeouts.
- Implement controlled retry and backoff policies.
- Avoid unnecessary position-book polling.
- Avoid duplicate WebSocket subscriptions.
- Use atomic database operations.
- Protect internal API endpoints with authentication.
- Validate all incoming market data and order requests.
- Keep broker credentials and tokens out of logs.
- Maintain structured execution logs.
- Record every order attempt, broker response and fill.
- Make monitoring health visible to the backend.

Do not introduce unnecessary infrastructure or dependencies.

## 14. Execution strategy

Work in this order:

PHASE 1: Audit and document actual root causes.

PHASE 2: Fix the backend order lifecycle and broker reconciliation.

PHASE 3: Implement centralized automatic and manual exit execution.

PHASE 4: Fix fixed SL and Target monitoring.

PHASE 5: Implement restart recovery and duplicate-exit protection.

PHASE 6: Simplify the trading UI.

PHASE 7: Add and execute comprehensive automated tests.

PHASE 8: Update architecture documentation and implementation status.

After each phase:

- Run relevant tests.
- Run linting and type checks where available.
- Build the affected applications.
- Fix regressions before proceeding.
- Document modified files and remaining risks.

Do not mark an incomplete feature as implemented or tested.

## 15. Important restrictions

- Do not rewrite everything without justification.
- Do not add new trading features before fixing the basic workflow.
- Do not introduce more user-facing configuration.
- Do not use the browser as the authority for automated trading.
- Do not mark broker-acknowledged orders as filled.
- Do not silently ignore failed protection creation.
- Do not mark positions closed without broker confirmation.
- Do not remove safety mechanisms to make the UI appear simpler.
- Do not deploy or enable real-money trading automatically.
- Do not place real orders.

If repository access is read-only, complete the audit and provide exact proposed changes rather than claiming that files were modified.

## 16. Final deliverables

When finished, provide:

1. Root causes identified.
2. Root causes fixed.
3. Files changed in each repository.
4. Updated architecture.
5. BUY-to-SELL lifecycle explanation.
6. Test cases implemented.
7. Test execution results.
8. Build and type-check results.
9. Remaining limitations.
10. Deployment instructions.
11. Explicit confirmation that no real orders were placed.

## FINAL SUCCESS CRITERION

I should be able to open the application, select an option, enter quantity, optionally enable SL and Target, and click BUY.

After the actual BUY fill, the backend should automatically protect the position.

When SL or Target is hit, the backend should automatically execute SELL and reconcile the actual broker fills.

I should not need to open another screen, manually activate protection, choose a monitoring mode, or manually trigger an exit.

**The primary objective is not to build a more complicated trading platform. It is to make this simple trading workflow work correctly and reliably.**