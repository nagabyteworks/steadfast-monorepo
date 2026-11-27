# Critical Production Fix: Steadfast Backend Startup Failure

The latest deployment successfully built the frontend, but Steadfast services failed to become ready.

The API systemd logs identify this exact error:

File: `steadfast-api/routes/flattrade.js`

Line: 361

Error:

`ReferenceError: Cannot access 'requireServerManagedTrading' before initialization`

Failing route:

`router.post("/lots/:lotId/exit", requireTradingEnabled, requireServerManagedTrading, ...)`

## 1. Fix the root cause

Inspect `steadfast-api/routes/flattrade.js`.

Find the declaration of `requireServerManagedTrading`.

The middleware is being referenced by a route before its initialization.

Fix the declaration order so that all middleware variables are initialized before their first use.

Prefer moving the existing middleware declaration above the route registration.

Alternatively, use a function declaration if appropriate.

Preserve the existing middleware implementation and behaviour.

## 2. Audit the complete route file

Inspect all route registrations in `flattrade.js`.

Identify other middleware or constants referenced before initialization.

Check for similar Temporal Dead Zone errors involving `const` and `let`.

Fix all confirmed initialization-order issues.

Do not blindly convert every variable to `var` or change unrelated code.

## 3. WebSocket service investigation

The actual WebSocket systemd service is:

`steadfast-websocket.service`

Inspect its unit file and logs.

Find the actual startup failure.

Do not assume it is the same issue as the API failure.

Fix any confirmed startup problem without changing unrelated WebSocket behaviour.

## 4. Production safety

Steadfast is configured for LIVE Flattrade trading.

Preserve:

- Existing Flattrade authentication.
- Existing broker session restoration.
- Existing SQLite database.
- Existing lot-position ledger.
- Existing SL/Target monitoring.
- Existing lot-level execution functionality.
- Existing WebSocket event contracts.
- Existing environment configuration.

Do not reset databases.

Do not delete trading records.

Do not change trading behaviour.

Do not place test orders or unintended live trades.

Do not introduce paper trading.

## 5. Validation

Before restarting production services:

1. Run JavaScript syntax checks on modified files.
2. Run relevant API tests.
3. Run TypeScript checks if applicable.
4. Verify route registration.
5. Verify middleware initialization order.
6. Inspect WebSocket startup dependencies.
7. Run the production build if frontend or shared code was changed.

Then perform a controlled service restart.

Verify:

- `steadfast-api.service` is active.
- `steadfast-websocket.service` is active.
- API health endpoint responds successfully.
- WebSocket process is listening on its configured port.
- Flattrade session restoration succeeds.
- Existing trading state is preserved.

Do not report success based only on systemd showing active.

## 6. Final report

Provide:

- Root cause.
- Modified files.
- Exact code changes.
- WebSocket failure root cause.
- Test results.
- API health result.
- WebSocket health result.
- Any remaining production risks.

Do not declare deployment successful until both services are healthy.