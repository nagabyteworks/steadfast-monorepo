# Agreed trading rules

These are requirements, **not claims that the current implementation meets
them**. For deviations and blockers see [implementation status](IMPLEMENTATION_STATUS.md).

## Runtime and entry

- Production execution is live through Flattrade only. No paper or simulated
  production execution, fake broker acknowledgements or fallback to simulation.
- Preserve the explicit live-trading gate, session/authentication checks,
  validation and existing safety restrictions. Do not start trading merely
  because the application starts; do not introduce a daily-loss limit.
- Entry orders must be 1–10 whole contract lots per order. Additional orders
  may add lots; this is not a limit on total position size.
- Do not place real broker orders during automated tests or development
  verification. Tests use mocked broker responses.

## Virtual protection and first fill

- SL and targets are internal virtual rules, not broker-side protective SL,
  SL-LMT, SL-M or target orders. Clearly warn that monitoring and execution
  depend on the application, feed, network and broker.
- The reference for the initial SL/target is the **first executed fill of the
  current open-position lifecycle**, not LTP, broker average, an order price or
  a later added fill. Keep weighted average separately for P&L.
- Additional entries must preserve the first-fill reference and existing
  levels. A fully closed position ends its lifecycle; reopening the same
  symbol starts a new one. Recover using broker history and durable state;
  if the reference cannot be established, flag it for reconciliation/manual
  confirmation rather than guessing.
- Current behavior: startup suspends existing armed rules and reconciliation is
  checked before automatic exit submission. Multi-day continuity and safe
  recovery of carried positions are not implemented. A flagged symbol remains
  blocked until manual reconciliation, but the resolution workflow is not yet
  implemented; existing positions may be left without virtual protection.
- Rules and controls must be independent per position. SL, target and target
  trailing points are editable; confirmed state must be shown accurately.

## Trailing and triggers

- With target trailing enabled, an SL is enabled and independent SL trailing is
  disabled. Crossing a target moves the SL to the previous target and advances
  the target by the latest configured trail points; the milestone itself does
  not exit. Process all crossed milestones. For shorts use the opposite
  direction. Prices must remain positive and align with the instrument tick.
- With target trailing disabled, crossing the fixed target initiates an exit;
  a crossed SL also initiates an exit. Do not move an automatic SL backwards.
  Handle duplicate, stale and out-of-order prices and concurrent edits safely.

## Exits and recovery

- Centralize manual, automatic and 25%, 50%, 75% and 100% exits, with
  per-position serialization, whole-lot validation, confirmed remaining
  quantity and protection of any remainder.
- Use aggressive marketable **LMT** exits, not API MKT exits. Use fresh best
  bid for sells and best ask for buys, actual instrument tick size and exchange
  price bands. Never use LTP as a fallback for missing or stale depth.
- At most three total attempts: initial order plus two replacements, with two
  seconds between reconciliation/repricing. Initial aggression is one tick
  beyond the applicable best quote, increasing by one tick per attempt, and
  never beyond three ticks adverse from the **initial** bid/ask reference.
- Confirm prior order status and cancellation, and reconcile actual filled and
  remaining quantities, before sending a replacement; never overlap exits.
  If depth is missing or stale, retain any active order, track its status,
  retry fresh depth and alert. After three unsuccessful attempts, stop automatic
  repricing, alert and retain the position as open until reconciled.
- Reconcile pending, partial, filled, cancelled, rejected and uncertain orders
  against Flattrade, including after disconnect/restart. Never treat a broker
  acknowledgement as a confirmed execution or blindly retry a timeout.
