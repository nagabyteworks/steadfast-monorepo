# Steadfast – Production Deployment Audit and Required Code Fixes

Act as a senior backend engineer, DevOps engineer, and application security reviewer.

I am preparing to deploy Steadfast on an Ubuntu AWS EC2 instance. Review the entire monorepo, including all three submodules:

- `steadfast-api`
- `steadfast-app`
- `steadfast-websocket`

My objective is to replace my existing scalpX deployment with Steadfast.

## 1. Existing EC2 deployment architecture

The application is deployed on:

- Domain: `https://trade.nagabyte.com`
- Ubuntu EC2 instance
- Node.js API
- Python WebSocket service
- Vue frontend
- Caddy reverse proxy
- systemd services

Current service configuration:

| Component | Address |
|---|---|
| Steadfast API | `127.0.0.1:3001` |
| WebSocket internal API | `127.0.0.1:5000` |
| Broker market-data WebSocket | `127.0.0.1:8765` (expected after successful connection) |
| Existing scalpX | `127.0.0.1:3000` |
| Public domain | `https://trade.nagabyte.com` |

The frontend has already been built using:

`VITE_BASE_URL=https://trade.nagabyte.com npm run build`

Build output:

`steadfast-app/dist`

The API and WebSocket services are running under separate Linux service users:

- `steadfast-api`
- `steadfast-ws`

Both users belong to the shared `steadfast` group.

## 2. Environment and security constraints

The following environment variables are configured outside the repository in protected systemd environment files:

API:
- `NODE_ENV`
- `API_HOST`
- `PORT`
- `CORS_ORIGIN`
- `FLATTRADE_CLIENT_ID`
- `FLATTRADE_API_KEY`
- `FLATTRADE_API_SECRET`
- `WEBSOCKET_INTERNAL_TOKEN`
- `TRADING_ENABLED`

WebSocket:
- `ENV`
- `API_BASE_URL`
- `WS_HOST`
- `WS_ALLOWED_ORIGIN`
- `WEBSOCKET_INTERNAL_TOKEN`
- `PYTHONUNBUFFERED`

Important requirements:

1. Never hardcode credentials, API keys, API secrets, TOTP secrets, session tokens, or internal authentication tokens.
2. Do not move credentials into frontend code or localStorage.
3. Keep the API and internal WebSocket services bound to localhost.
4. Do not expose ports 3001, 5000, or 8765 directly to the public internet.
5. Do not weaken authentication or internal token validation.
6. Preserve separate Linux service users and their security isolation.
7. Do not introduce unnecessary dependencies.
8. Do not modify production environment files.
9. Do not modify systemd files or the EC2 Caddy configuration as part of application-code changes.

## 3. Trading safety requirements

This deployment is currently READ-ONLY.

Keep:

`TRADING_ENABLED=false`

Production must not allow:
- Placing orders
- Modifying orders
- Cancelling orders
- Browser-based automated trading
- Any accidental live-trading execution

Do not enable paper trading as an alternative.

Do not implement live trading functionality as part of this task.

Review the existing trading safety gates and ensure they cannot be bypassed through alternative routes, WebSocket messages, or frontend interactions.

## 4. Required audit areas

### A. Frontend production deployment

Inspect:

- Vue Router configuration
- Vite configuration
- API base URL handling
- WebSocket URL handling
- Asset paths
- SPA routing and browser refresh behavior
- Production/development conditional logic

Determine whether the frontend can be served correctly from:

`https://trade.nagabyte.com`

Determine whether it should be served by the API or directly by Caddy.

Do not assume either architecture. Explain the recommended approach based on the actual source code.

Check for:
- Hardcoded localhost URLs
- Incorrect production API URLs
- Incorrect WebSocket URLs
- Missing production environment handling
- Browser console errors
- Incorrect callback routing
- Broken static asset paths

### B. Node.js API

Inspect:

- `server.js`
- Configuration loading
- Route registration
- CORS configuration
- Flattrade authentication
- Session storage
- Internal WebSocket communication
- Error handling
- Health checks

Verify that:

- Production binds to `127.0.0.1`.
- Flattrade authentication uses backend-configured credentials.
- API secrets never reach the frontend.
- Internal WebSocket communication uses the internal token.
- Sessions are not exposed through public endpoints.
- Sensitive responses use appropriate cache-control headers.
- API startup fails safely when required configuration is missing.

Determine whether a health-check endpoint is needed. If implementing one, expose only non-sensitive operational status.

### C. Flattrade authentication callback

Review the complete authentication flow:

1. Frontend initiates Flattrade authentication.
2. Backend generates the authorization URL.
3. Flattrade redirects to `/flattrade/redirect`.
4. Frontend extracts the request code.
5. Frontend sends the request code to the backend.
6. Backend exchanges it for the session token.
7. Backend stores the session.
8. Python WebSocket service retrieves the session through the protected internal endpoint.
9. Python connects to Flattrade's market-data WebSocket.

Check:
- Popup communication
- `window.postMessage` origin validation
- Callback URL handling
- Duplicate callback submissions
- Expired or invalid request codes
- Failed token exchanges
- Missing broker credentials
- Session expiration
- Browser refresh behavior
- Error reporting

Do not expose the session token in logs, URLs, browser storage, or frontend responses.

### D. Python WebSocket service

Inspect:

- `main.py`
- Broker connection lifecycle
- Session polling
- Reconnection logic
- Authentication acknowledgement
- Heartbeats
- Subscription management
- Error handling
- Internal communication with the API

Verify that:
- It waits safely when no valid session exists.
- It connects only after receiving valid session data.
- It handles expired sessions.
- It reconnects after network failures.
- It does not continuously create duplicate connections.
- It does not leak credentials or session tokens through logs.
- It binds only to localhost.
- It correctly reports its connection state.

### E. Frontend/backend integration

Verify all production API and WebSocket communication paths.

Ensure that:
- The frontend does not connect directly to broker credentials or broker APIs.
- The backend remains the single source of truth for broker sessions.
- API and WebSocket authentication work with the intended production architecture.
- The frontend handles disconnected and reconnecting states.
- Failed broker authentication is clearly reported.
- No development-only configuration is accidentally used in production.

## 5. Testing requirements

Run the existing test suites.

Add or update tests only where necessary.

At minimum, verify:

- Production configuration validation
- API startup
- Health endpoint behavior, if applicable
- Flattrade callback validation
- Invalid request-code handling
- Internal token authentication
- Trading-disabled enforcement
- Frontend production build
- WebSocket session polling
- WebSocket reconnection behavior

Do not use real broker credentials or execute live orders during testing.

Use mocks and test fixtures.

## 6. Implementation rules

Do not immediately rewrite the application.

First inspect the existing code and produce a list of findings classified as:

- Critical
- High
- Medium
- Low
- No change required

For every finding, explain:
- File and exact location
- Existing behavior
- Problem
- Recommended correction
- Whether an application-code change is necessary

Then implement only fixes that are genuinely required for this production deployment.

Preserve existing functionality.

Do not:
- Reset Git repositories.
- Discard uncommitted changes.
- Modify submodule references unnecessarily.
- Change broker integration behavior without justification.
- Enable trading.
- Change secrets or production environment files.
- Modify EC2 infrastructure configuration.

After implementation:

1. Run all relevant tests.
2. Run the frontend production build.
3. Run API tests.
4. Run Python tests, if present.
5. Check for linting and type errors.
6. Report every modified file.
7. Explain every change.
8. Provide exact commands needed to deploy the code changes on EC2.
9. Clearly identify anything that still requires manual EC2 configuration.

## 7. Final expected report

Provide:

1. Production readiness assessment.
2. Critical and high-risk findings.
3. Files modified.
4. Explanation of each code change.
5. Test results.
6. Remaining infrastructure configuration.
7. Remaining Flattrade authentication requirements.
8. Deployment commands.
9. Explicit confirmation that trading remains disabled.

Do not claim that Steadfast is production-ready for live trading. This deployment is currently intended for read-only operation.