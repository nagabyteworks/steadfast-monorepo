# Test status

This is the latest **observed** test evidence for the current uncommitted
working tree, not a production or end-to-end safety certification.

## API startup middleware ordering

| Suite / command | Result | Scope |
| --- | --- | --- |
| `node --check steadfast-api/routes/flattrade.js` and `node --check steadfast-api/test/tradingGateRoutes.test.js` | Passed | JavaScript syntax for both modified API files. |
| `TRADING_ENABLED=false npm test --prefix steadfast-api` | 72 passed | Full API suite; the new regression constructs the router with real temporary SQLite stores and verifies lot exit/trigger gates. It reproduced the reported initialization error before the fix. |
| `cd steadfast-websocket && PROFILE=dev API_BASE_URL=http://127.0.0.1:3001 .venv/bin/python -m unittest test_startup test_flattrade_lifecycle` | 23 passed | Mocked WebSocket startup and reconnection behavior, not the production service. |

No deployment or production restart was performed; production logs, API health,
WebSocket listener and broker session restoration were not accessible or
verified. These tests do not establish live trading safety. In particular,
the existing lot trigger callback references an undeclared `sign` when
evaluating a supplied trigger price.

## Lot-level positions snapshot: 2026-11-27

| Suite / command | Result | Scope |
| --- | --- | --- |
| `npm run test --prefix steadfast-api` | 70 passed | Full API suite plus lot reservation and partial-fill reconciliation test. |
| `npm run test:unit --prefix steadfast-app -- --run src/components/PositionsTableComponent.test.js` | 2 passed | Positions table reconciliation UX and three-lot expandable rendering. |
| Accordion regression | 2 passed | Desktop expand/collapse and lot-row rendering. |
| `npm run test:unit --prefix steadfast-app -- --run src/composables/useRiskManagement.test.js src/components/PositionsTableComponent.test.js` | 24 passed | Protection remove/re-add regression and three-lot Positions table rendering. |
| `node --test steadfast-api/test/riskRoutes.test.js steadfast-api/test/riskStore.test.js` | 37 passed | Re-adding protection, legacy average/LTP fallback, stale-history rejection and lot partial-fill reservation. |
| `npm run build --prefix steadfast-app` | Passed | Production frontend build; Vite reports the existing large-chunk warning. |

Lot allocation is derived from available broker TradeBook fills and is not a
broker-confirmed per-lot position identity. No live broker requests or orders
were made in these runs.

## P&L charge breakdown: 2026-11-26

| Suite / command | Result | Scope |
| --- | --- | --- |
| `TRADING_ENABLED=false npm run test:unit --prefix steadfast-app -- --run src/composables/usePnlCalculations.test.js` | 3 passed | Charge separation, Flattrade BSE options estimates, Shoonya per-order brokerage across partial fills, and net P&L arithmetic. |
| `TRADING_ENABLED=false npm run build --prefix steadfast-app` | Passed | Production frontend build. Vite reports the existing large-chunk warning. |

Displayed fees are estimates from turnover and TradeBook data, not broker
contract-note values. No live broker requests, orders or deployment occurred.

## Three-second UI refresh and paired orders: 2026-11-26

| Suite / command | Result | Scope |
| --- | --- | --- |
| `TRADING_ENABLED=false npm run test:unit --prefix steadfast-app -- --run` | 81 passed | Full frontend suite, including sequential CE/PE limit-order progression and cancellation handling. |
| `TRADING_ENABLED=false npm run build --prefix steadfast-app` | Passed | Production frontend build. Vite reports the existing large-chunk warning. |

The app refreshes funds, orders, positions and risk rules every three seconds
without reloading the page. Paired orders use the existing per-leg handlers;
LMT orders prompt separately for CE and PE and stop after cancellation. Tests
use mocks; no live broker requests, orders or deployment occurred.

## Central reconciliation and status UX: 2026-11-26

| Suite / command | Result | Scope |
| --- | --- | --- |
| `TRADING_ENABLED=false npm test --prefix steadfast-api` | 68 passed | Full API suite, including 3-second scheduling, single-flight behavior, bulk multi-position reads, verified recovery, partial/uncertain exits, SQLite lease, status endpoints and mocked order handling. |
| `TRADING_ENABLED=false npm run test:unit --prefix steadfast-app -- --run` | 79 passed | Full frontend suite, including concise recovery notices, no reconciliation details in position rows, stale-cycle status handling, monitor selection, protection modes and automatic-sync messaging. |
| `TRADING_ENABLED=false npm run build --prefix steadfast-app` | Passed | Production frontend build. Vite reports the existing large-chunk warning. |
| `cd steadfast-websocket && TRADING_ENABLED=false PROFILE=dev .venv/bin/python -m unittest test_flattrade_lifecycle` | 12 passed | Mocked WebSocket lifecycle/reconnect tests, including the authenticated API reconciliation signal. |
| Pylance file syntax check for `flattrade_websocket.py` | Passed | No Python syntax errors reported. |

An initial API run exposed a null-prototype SQLite-row assertion mismatch; the
test now compares its data fields. Intermediate frontend expectations still
referenced the previous technical/manual-warning text and were updated to
assert concise statuses. A stale-cycle test also verifies that old protection
state is not presented as protected. Subsequent full runs passed. All broker responses were mocked;
`TRADING_ENABLED=false` was used, and no live broker requests, orders or
deployment occurred.

These tests do not verify Flattrade rate limits or history retention, recovery
on a separate host with an independent SQLite database, real-world order/fill
semantics, missed LTP-trigger handling, bounded exit repricing or live trading
safety. A position without verifiable lifecycle evidence remains
`ACTION REQUIRED`; recovery evidence intake is not implemented.

## Restored UI risk controls: 2026-11-26

| Suite / command | Result | Scope |
| --- | --- | --- |
| `TRADING_ENABLED=false npm test --prefix steadfast-api` | 58 passed | Full API suite, including UI-monitor persistence, API-owned UI trigger execution and stale progress-revision rejection with mocked broker calls. |
| `TRADING_ENABLED=false npm run test:unit --prefix steadfast-app -- --run` | 77 passed | Full frontend suite, including UI trigger freshness, SL/target/trailing behavior, monitor selection, warning placement and BUY/SELL Side colors. |
| `TRADING_ENABLED=false npm run build --prefix steadfast-app` | Passed | Production frontend build; Vite reports the existing large-chunk warning. |

Targeted ESLint using the repository's legacy configuration still reports
errors in changed files, mainly existing unused imports/variables and undefined
symbols in `useTradeView.js` and older tests. No live broker requests, orders or
deployment occurred. These checks do not establish live fills, API quote-age
validation, startup reconciliation or safe exit recovery.

## Earlier server-only risk and pending-exit safeguards: 2026-11-26

| Suite / command | Result | Scope |
| --- | --- | --- |
| `TRADING_ENABLED=false npm test --prefix steadfast-api` | 57 passed | API unit/integration suite, including trigger validation, browser-trigger rejection, legacy monitor migration, pending-exit startup flagging, lifecycle-race handling and missing order-ID handling. |
| `TRADING_ENABLED=false npm run test:unit --prefix steadfast-app -- --run` | 61 passed | Full frontend unit suite; covers fixed SL-only, target-only, both and neither, server-only protection, and preserving advanced settings on existing positions. |
| `cd steadfast-websocket && TRADING_ENABLED=false PROFILE=dev python3 -m unittest test_risk_monitor` | 18 passed | WebSocket monitor tests for invalid prices and non-advancing target-trail increments. |
| `TRADING_ENABLED=false npm run build --prefix steadfast-app` | Passed | Production frontend build; Vite reports an existing large-chunk warning. |
| Pylance file syntax checks | Passed | `risk_monitor.py` and `flattrade_websocket.py`. |

An intermediate frontend run failed because the new disabled-protection test
was placed inside another test; it was moved and the complete suite passed.
The first Python test invocation used the wrong working directory; the
documented targeted command above ran successfully. Full Python test discovery
was attempted but 20 tests could not import because `python-dotenv` is absent
from the available interpreter. Targeted ESLint with the repository's legacy
configuration reported 11 unused/undefined-symbol errors across affected
files; lint is not clean, and no broad lint cleanup was attempted. All tests used fixtures/mocks,
trading was disabled, and no real broker requests or orders were made. These
results do not verify actual fills, order reconciliation, stale-market-data
handling, shared manual/automatic exits or restart recovery.

## Stale-protection safety changes: 2026-11-26

| Suite / command | Result | Scope |
| --- | --- | --- |
| `TRADING_ENABLED=false npm test --prefix steadfast-api` | 53 passed | Mocked API suite, including startup suspension, timeouts, missing sessions, duplicate positions, reopen, partial exit, trigger races, UI trigger validation and refresh failures. Earlier runs passed 51/51 twice and 52/52. |
| `TRADING_ENABLED=false npm run test:unit --prefix steadfast-app -- --run` | 82 passed | Full frontend suite, including flagged SL/target triggers. Run twice successfully. |
| `TRADING_ENABLED=false npm run test:risk:coverage --prefix steadfast-app` | 53 passed | Frontend risk modules: 95.29% statements/lines, 87.7% branches, 100% functions; each exceeds 70%. |
| `TRADING_ENABLED=false node --test --experimental-test-coverage --test-coverage-include='**/riskStore.js' --test-coverage-include='**/routes/risk.js' --test-coverage-include='**/positionLifecycle.js' steadfast-api/test/riskStore.test.js steadfast-api/test/riskRoutes.test.js steadfast-api/test/positionLifecycle.test.js` | 31 passed | Final aggregate 90.14% lines, 87.73% branches, 96.61% functions; each file exceeds 70%. Previous runs passed 30 tests with 90.53%/87.94%/96.61% and 91.16%/87.77%/96.55%. |
| `cd steadfast-websocket && TRADING_ENABLED=false PROFILE=dev .venv/bin/python -m unittest test_risk_monitor test_startup` | 27 passed | Selected mocked Python tests, including revision in trigger request. An earlier intermediate run passed 26 tests. |
| Frontend production build | Passed twice | Isolated output, invalid example URL and trading disabled; Vite reported a chunk-size warning. |

Intermediate targeted runs included API failures (18/22 and 25/26) and frontend
failures (47/51) during the changes; those regressions were addressed in the
passing full runs. A subsequent targeted run passed 25/25 API and 51/51
frontend tests before further changes. Pylance syntax checks passed for the two
changed Python files. No live broker responses or orders were used.

These tests do not establish atomicity against external broker actions after
the last snapshot, multi-process order submission, independently verified
historical continuity, or a full WebSocket reconnect/recovery lifecycle.

## Latest runs: 2026-11-26

| Suite / command | Total | Passed | Failed | Skipped | Result and scope |
| --- | ---: | ---: | ---: | ---: | --- |
| `TRADING_ENABLED=false npm run test:unit --prefix steadfast-app -- --run src/composables/useRiskManagement.test.js src/composables/useDefaultProtectionLifecycle.test.js` | 33 | 32 | 1 | 0 | Intermediate failure: a new test was accidentally nested inside another test; fixed before the full run below. |
| `TRADING_ENABLED=false node --test steadfast-api/test/positionLifecycle.test.js steadfast-api/test/riskRoutes.test.js` | 17 | 17 | 0 | 0 | Targeted mocked API reconstruction and manual-protection tests. |
| `TRADING_ENABLED=false npm run test:unit --prefix steadfast-app -- --run` | 80 | 80 | 0 | 0 | Latest Vitest frontend suite; includes the 12 first-fill lifecycle scenarios and the reconciliation notice. Earlier run: 79/79. |
| `TRADING_ENABLED=false npm test --prefix steadfast-api` | 43 | 43 | 0 | 0 | Node API suite, including mocked broker lifecycle and risk routes. |
| `cd steadfast-websocket && TRADING_ENABLED=false PROFILE=dev .venv/bin/python -m unittest test_risk_monitor test_startup` | 26 | 26 | 0 | 0 | Selected WebSocket risk-monitor and startup tests after the user's restoration; not a claim about all Python tests. |
| `TRADING_ENABLED=false npm run test:risk:coverage --prefix steadfast-app` | 51 | 51 | 0 | 0 | Frontend risk tests; aggregate statements 95.29%, branches 87.5%, functions 100%, lines 95.29%. Each configured file exceeded 70%. |
| `TRADING_ENABLED=false node --test --experimental-test-coverage --test-coverage-include='**/riskStore.js' --test-coverage-include='**/routes/risk.js' --test-coverage-include='**/positionLifecycle.js' steadfast-api/test/riskStore.test.js steadfast-api/test/riskRoutes.test.js steadfast-api/test/positionLifecycle.test.js` | 22 | 22 | 0 | 0 | API risk files: each exceeds 70% lines, branches and functions; latest aggregate 90.82%, 85.38%, 94.34%, respectively. The earlier run was 90.52%, 85.24%, 94.34%. |

Frontend production build passed using `TRADING_ENABLED=false`, an invalid
example API URL and an isolated session output directory. Vite reported a
large-chunk warning; the generated output was removed after verification. The earlier targeted test failure was fixed and is covered
by the passing full and coverage runs.

Broker calls exercised by these tests were mocked; no real broker orders were
placed. These runs do not establish end-to-end safety for live execution,
partial fills, bounded repricing, historical carry-forward recovery or concurrency.
The carry-forward test verifies persistence, idempotent rejection of missing
history and continued blocking of rearming, not successful multi-day recovery.
The API suite and coverage run were repeated after adding the rearming block.
The frontend suite and build were repeated after adding the notice. Tests for
verified evidence intake, contradictory documents and successful manual
reconciliation are not implemented because no independent verification source
or resolution workflow is implemented. Earlier
reopen regressions failed because defaults used LTP/average and could reuse an
old rule; those eight cases passed in the latest frontend run.

## Earlier WebSocket run

An earlier run on 2026-11-26 passed 36 selected WebSocket tests against a
different working-tree version. The user subsequently restored the WebSocket
files; that earlier result does not verify the restored code.

## Documentation update

On 2026-11-26 the documentation snapshot was added and contradictory guidance
corrected. Following the restoration, the selected WebSocket suite was rerun
with broker interactions mocked. No real broker interaction or order occurred
during this documentation task.
