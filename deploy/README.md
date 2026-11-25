# EC2 deployment preparation

This deployment supports live Flattrade trading when explicitly enabled in the
API service. The Steadfast API and WebSocket services are configured with
separate service users. The scalpX service and files must remain intact;
changing the public Caddy route does not require stopping or deleting them.

## Intended layout

| Component | Address or path |
| --- | --- |
| HTTPS and WebSocket | `trade.nagabyte.com`, Caddy ports 80/443 |
| API | `127.0.0.1:3001` |
| Flattrade WebSocket | `127.0.0.1:8765` |
| WebSocket selector | `127.0.0.1:5000` |
| Source and built frontend | `/opt/steadfast` |
| API and WebSocket environment files | `/etc/steadfast/api.env`, `/etc/steadfast/websocket.env` |

Port 3001 avoids the observed scalpX listener on port 3000. Recheck all ports on
the instance before installation. Only Caddy should be exposed publicly; keep
the API, WebSocket, and selector bound to loopback.

The Caddy configuration has no authentication and does not restrict clients by
IP address, because there is a single user. Anyone who can reach
`trade.nagabyte.com` can use the app and the connected Flattrade session, so
keep the API, WebSocket, and selector bound to loopback and treat the URL as
sensitive. Add Caddy `basic_auth` or an IP allowlist again if that changes.

## Service prerequisites

- The working tree includes three Git submodules. Publish the appropriate
  child repository changes and update the parent submodule references before
  cloning; do not assume local uncommitted changes exist on EC2. To publish
  from a checkout on `main`, `./git-commit-push.sh` asks for one commit
  message, stages all changes (including untracked files), then commits and
  pushes each submodule followed by the parent. Repositories without changes
  are still pushed. It does not show diffs or deploy; inspect changes first if
  needed. A failure can leave earlier repositories committed or pushed.
- Install Node.js 22.13 or newer and a compatible system-wide Python, create the
  `steadfast` service user, install the dependencies, and build the frontend.
  The units use `/usr/bin/env node`; Node must be on systemd's service PATH and
  must not depend on a shell-only `nvm` setup or a protected home directory.
- Ensure the service user can read the application and its environment files.
  The API must also be able to write
  `/opt/steadfast/steadfast-api/symbols`; `ProtectSystem=strict` makes the rest
  of the filesystem read-only to the services.
- Set `FLATTRADE_CLIENT_ID`, `FLATTRADE_API_KEY`, `FLATTRADE_API_SECRET`, and
  `WEBSOCKET_INTERNAL_TOKEN` in the API environment file. Set the same
  `WEBSOCKET_INTERNAL_TOKEN` in the WebSocket environment file; it must be
  random and contain 32–256 URL-safe characters. Give the WebSocket service
  access only to its own file, not to the API's broker secret.
- Keep environment files out of Git and restrict access to the relevant service
  user and administrators. Never paste passwords, broker credentials, or
  session tokens into chat, terminal history, logs, or deployment examples.
- Production uses Flattrade's current `PiConnectAPI` and `PiConnectWSAPI`
  endpoints and a checksum-pinned SDK from Flattrade's official repository.
  Confirm these endpoints, the callback URL
  `https://trade.nagabyte.com/flattrade/redirect`, and the EC2 **outbound** IP
  against the broker's current configuration. An unexpired saved session can
  be restored after an API restart; Flattrade can still invalidate it earlier.
  Login and expiry restart the streaming process, so the WebSocket service must
  run under systemd. Log in again after first deploying session persistence;
  sessions created before deployment were held only in memory.
- The API stores the session in a SQLite database under
  `/var/lib/steadfast-api`, protected by the API unit's private systemd state
  directory. Tokens are not encrypted at rest; restrict host and backup access.
  The saved and in-memory session expire at 6:00 AM Asia/Kolkata.
- The production API systemd unit has `TRADING_ENABLED=true`, which permits
  live Flattrade order placement and cancellation after deployment. Set it to
  `false` and restart `steadfast-api.service` to disable those routes. Production
  orders are limited to NFO derivatives and one contract lot per order; this
  does not cap total exposure or daily loss.
- Stop-loss/target automation is optional and browser-run, not broker-side.
  Keep the trading page open with its market-data connection active. If both
  UI toggles are off, orders have no automatic stop-loss or target; even when
  enabled, a browser or network interruption can stop the monitoring. Verify
  orders and positions directly with Flattrade.
- Automatic exits require Web Locks and persist a per-symbol safety lock after
  an attempted submission. Verify broker orders and positions before resetting
  the lock in the trading page. Locks only coordinate tabs in the same browser;
  other devices and broker-side actions are not coordinated.

The included systemd units force production mode and loopback addresses.
Shoonya and virtual trading are disabled in production. Legacy browser broker
secrets are removed from local storage on first production load; configure the
account on the server first.

## Updating an existing installation

From the `/opt/steadfast` checkout on `main`, run `./deploy.sh`. It fetches and
fast-forwards to `origin/main`, checks out the submodule revisions recorded by
that commit, installs dependencies, builds the frontend, and restarts the API
and WebSocket systemd services. It checks that both services are active and
the API health endpoint responds; it does not verify the broker stream. The checkout and its submodules must be
clean, including generated tracked symbol files; preserve and resolve any local
changes before running it. The deploying user needs write access to the checkout
and virtual environment, network access, and sudo permission to restart the two
services. The existing systemd units and Caddy configuration are not installed
or changed by this script.

Before the first deployment of SQLite session storage, compare the installed
API unit with `deploy/systemd/steadfast-api.service`, preserving any intentional
local overrides. Update the installed unit to include `StateDirectory=steadfast-api`
and `StateDirectoryMode=0700`, then run `sudo -A systemctl daemon-reload`.
The deploy script refuses to restart with the old unit. Only the API service
user should have access to the state directory and its backups.

Deployment modifies files in place and has no automatic rollback: a failure may
leave files or services partially updated. Schedule it when interruptions are
safe, inspect errors and service status if it fails, and verify broker positions
and orders independently. Service activity checks do not prove broker
connectivity or successful trading.

## Validation and eventual cutover

1. Independently test acknowledgements, partial fills, rejections, duplicate
   requests, outages, and manual-intervention states without submitting live
   orders. Browser-based protection is not broker-side risk management.
2. Test the services privately before changing Caddy; verify broker login and
   fresh market data without orders.
3. Check DNS, TLS, the Flattrade portal's approved outbound IP, and the
   WebSocket behavior. Validate Caddy's configuration using its
   installed version and verify the systemd units on Ubuntu. The local Caddy
   syntax check does not establish compatibility with the server or prove
   access control end to end.
4. Back up the current Caddy configuration and record the scalpX service state.
   After positions and orders are reviewed and cutover is explicitly approved,
   switch the site to the new configuration and reload Caddy. Verify TLS,
   access, the callback, and streaming.
5. If verification fails, restore the saved Caddy configuration and prior
   service state. Recheck broker positions and pending orders independently;
   rolling back a service does not cancel or reverse broker orders.
