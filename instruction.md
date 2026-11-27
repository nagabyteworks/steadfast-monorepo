# Feature: Lot-Level Expandable Positions with Independent SL and Target Management

Implement a lot-level expandable/collapsible Positions table in scalpX.

## 1. Objective

Currently, the Positions table displays aggregated positions grouped by trading symbol.

I want each symbol to have an expandable accordion/subtable that displays its individual lots separately.

For example:

NIFTY 26DEC01 CALL 26200 — 3 Lots

When expanded, display:

- Lot 1
- Lot 2
- Lot 3

Each lot must have independent Stop Loss, Target, Trailing Stop Loss, P&L tracking, and Exit functionality.

This is a functional trading feature, not just a UI change.

## 2. UI Requirements

### A. Parent Symbol Row

Preserve the existing Positions table and its current columns, styling, colors, spacing, and dark theme.

Do not redesign the entire trading dashboard.

Add an expand/collapse control beside each symbol.

The parent row must continue displaying aggregated symbol-level information:

- Select
- Symbol
- Qty
- Side
- TSL / SL
- LTP
- Target
- Type
- B.Avg
- S.Avg
- Realized
- Unrealized
- Exit

The parent row should display aggregated values across all its lots.

For SL and Target, display an appropriate indicator such as "Mixed" when individual lots have different values. Allow users to expand the row to inspect individual configurations.

### B. Expanded Lot Rows

When the user expands a symbol, render its individual lots underneath the parent row.

Each child row must use the same columns as the existing Positions table.

Example:

Parent:
NIFTY 26DEC01 CALL 26200 | Qty: 3

Children:

Lot 1 | Qty: 1
Lot 2 | Qty: 1
Lot 3 | Qty: 1

Each lot must display:

- Lot identifier
- Individual quantity
- Individual side
- Individual SL
- Current LTP
- Individual target
- Position type
- Individual buy average
- Individual sell average
- Individual realized P&L
- Individual unrealized P&L
- Individual exit action

Use visually distinguishable nested rows with appropriate indentation or a subtle background difference.

Support multiple expanded symbols simultaneously.

Preserve expansion state when positions are refreshed or WebSocket updates arrive.

### C. Individual Lot Controls

Every lot must independently support:

1. Set SL.
2. Modify SL.
3. Enable/disable SL.
4. Set Target.
5. Modify Target.
6. Enable/disable Target.
7. Configure Trailing Stop Loss.
8. Exit individual lot.

Provide an intuitive interaction for editing SL and Target, preferably inline editing or a compact dialog.

Changes to one lot must not modify another lot's configuration.

### D. Independent Execution Behaviour

This is a critical requirement.

Example:

Symbol: NIFTY 26DEC01 CALL 26200

- Lot 1: SL = 45, Target = 60
- Lot 2: SL = 42, Target = 65
- Lot 3: SL = 40, Target = 70

Expected behaviour:

- If Lot 1 hits SL, execute the exit for Lot 1 only.
- If Lot 2 hits Target, execute the exit for Lot 2 only.
- Lot 3 must continue trading with its existing SL and Target.
- Exiting Lot 1 must not affect Lot 2 or Lot 3.
- Closing the entire symbol must remain available through the parent-level Exit action.

Do not trigger a full-symbol exit when an individual lot reaches its SL or Target.

### E. Buy Price, Sell Price and P&L

Track individual lot-level execution details.

For every lot, maintain:

- Entry order ID.
- Entry execution details.
- Actual average buy price.
- Exit order ID.
- Actual average sell price.
- Executed quantity.
- Remaining quantity.
- Realized P&L.
- Unrealized P&L.
- Entry timestamp.
- Exit timestamp.
- Lot status.

Calculate P&L using actual execution prices and quantities, not LTP approximations.

For a BUY position:

Unrealized P&L = (Current LTP - Entry Average Price) × Remaining Quantity

Realized P&L = (Exit Average Price - Entry Average Price) × Exited Quantity

Handle partial fills and partial exits correctly.

Display appropriate values for closed lots.

### F. Parent-Level Aggregation

The parent symbol row must calculate its values from the underlying lot records.

- Total quantity = Sum of remaining lot quantities.
- Buy average = Quantity-weighted entry average.
- Sell average = Quantity-weighted exit average.
- Realized P&L = Sum of realized P&L across lots.
- Unrealized P&L = Sum of unrealized P&L across lots.
- Total P&L = Realized + Unrealized.

Do not simply add individual average prices.

Ensure the parent-level values reconcile with the broker's actual net position and executions.

## 3. Backend Architecture

Implement lot-level position management in the backend.

Do not implement SL and Target execution logic exclusively in the frontend.

Each lot must have a stable unique identifier independent of its trading symbol.

Introduce or extend a lot-level position model containing:

- lotId
- positionId
- symbol
- exchange
- productType
- side
- quantity
- remainingQuantity
- entryOrderId
- entryAveragePrice
- exitOrderIds
- exitAveragePrice
- stopLoss
- target
- trailingStopLoss
- realizedPnl
- unrealizedPnl
- status
- createdAt
- updatedAt

Adapt the model to the existing scalpX architecture rather than introducing duplicate position-management systems.

## 4. Broker Reconciliation

Flattrade may expose positions at an aggregated symbol/product level rather than providing independent broker positions for every application lot.

Account for this explicitly.

Maintain an internal lot allocation ledger in the backend.

Associate broker executions and order IDs with their corresponding internal lot allocations.

Never fabricate individual broker execution prices by dividing an aggregated position.

Reconcile:

- Broker net quantity.
- Internal lot allocations.
- Entry executions.
- Exit executions.
- Pending orders.
- Partially filled orders.
- Cancelled orders.
- Rejected orders.

Prevent duplicate exits and accidental over-selling.

If the broker cannot independently distinguish individual lots, use the backend's execution allocation model to maintain lot-level accounting while ensuring actual exchange orders close only the intended quantity.

## 5. SL and Target Execution Engine

Integrate lot-level SL and Target into the existing trading engine.

Every active lot must have its own protection rules.

The execution engine must:

1. Monitor active lot-level rules.
2. Evaluate SL and Target independently.
3. Execute the corresponding exit quantity.
4. Track order acknowledgement and execution.
5. Handle partial fills.
6. Update the lot's remaining quantity.
7. Reconcile broker positions.
8. Update the UI through the existing real-time communication mechanism.

Ensure multiple lots of the same symbol can have different protection prices.

Do not create conflicting exit orders that can oversell the broker position.

Preserve the existing live Flattrade execution architecture. Do not introduce paper trading as a fallback.

## 6. Real-Time UI Updates

Update the expanded lot rows through the existing WebSocket infrastructure.

Refresh:

- LTP.
- Individual unrealized P&L.
- Individual SL/Target status.
- Remaining quantity.
- Realized P&L.
- Order execution status.

Do not reload the entire page for every market tick.

Avoid unnecessary React re-renders.

## 7. Backward Compatibility

Existing positions created before this feature must continue to work.

For existing aggregated positions:

- Do not arbitrarily split historical positions into fabricated lots.
- Create lot allocations from actual available entry execution records.
- If individual execution history is unavailable, retain an explicitly marked legacy aggregated position until it can be reconciled.

Existing Buy CE, Buy PE, Sell CE, Sell PE, Buy Both, Sell Both, Close All, and Cancel Orders functionality must continue working.

## 8. Testing Requirements

Add tests covering:

1. One symbol with one lot.
2. One symbol with three lots.
3. Different SL values across lots.
4. Different Target values across lots.
5. One lot hitting SL while other lots remain open.
6. One lot hitting Target while other lots remain open.
7. Individual lot exit.
8. Parent-level Exit All.
9. Partial entry fills.
10. Partial exit fills.
11. Multiple lots with different entry prices.
12. Broker reconciliation.
13. Duplicate exit prevention.
14. WebSocket updates.
15. Application restart and restoration of lot-level state.

## 9. Implementation Instructions

Before making changes:

- Inspect the existing frontend Positions table.
- Inspect backend position models and services.
- Inspect order execution and SL/Target monitoring.
- Inspect Flattrade order and position reconciliation.
- Identify how existing positions are grouped by symbol.
- Identify how executions are currently associated with positions.

Reuse existing architecture wherever possible.

Do not introduce a separate trading engine.

Do not break existing working functionality.

Do not use mock data or simulated executions.

Implement the complete feature across frontend, backend, persistence, WebSocket events, and broker integration.

Run relevant tests, type checking, and production builds.

Provide a summary of changed files, architecture decisions, test results, and any limitations in broker-level lot identification.