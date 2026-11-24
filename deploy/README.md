# EC2 deployment preparation

This deployment supports live Flattrade trading when explicitly enabled in the
API service. The Steadfast API and WebSocket services are configured with
separate service users. The scalpX service and files must remain intact;
changing the public Caddy route does not require stopping or deleting them.

## Intended layout

| Component | Address or path |
| --- | --- |
| HTTPS and authenticated WebSocket | `trade.nagabyte.com`, Caddy ports 80/443 |
| API | `127.0.0.1:3001` |
| Flattrade WebSocket | `127.0.0.1:8765` |
| WebSocket selector | `127.0.0.1:5000` |
| Source and built frontend | `/opt/steadfast` |
| API and WebSocket environment files | `/etc/steadfast/api.env`, `/etc/steadfast/websocket.env` |
| Caddy Basic Auth account file | `/etc/caddy/steadfast-auth` |

Port 3001 avoids the observed scalpX listener on port 3000. Recheck all ports on
the instance before installation. Only Caddy should be exposed publicly; keep
the API, WebSocket, and selector bound to loopback.

The Caddy configuration requires HTTP Basic authentication on every route,
including the WebSocket and callback, and does not restrict clients by IP
address. This allows access from different networks while keeping the API and
broker listeners private on loopback.

`STEADFAST_AUTH_FILE` defaults to `/etc/caddy/steadfast-auth`. That file must
contain a Caddy Basic Auth username and a bcrypt password hash, not a plaintext
password. Generate the hash with Caddy's `hash-password` command on the host;
use a unique strong password, and restrict file access to Caddy and
administrators. Validate the configuration using the same environment as the
Caddy service, and verify that HTTP, WebSocket, and callback requests are
authenticated before any public exposure.

## Service prerequisites

- The working tree includes three Git submodules. Publish the appropriate
  child repository changes and update the parent submodule references before
  cloning; do not assume local uncommitted changes exist on EC2.
- Install a compatible system-wide Node.js and Python, create the
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
  against the broker's current configuration. Session login must be repeated
  after an API restart. Reauthentication requests a supervised restart of the
  streaming process, so the WebSocket service must run under systemd.
- The production API systemd unit has `TRADING_ENABLED=true`, which permits
  live Flattrade order placement and cancellation after deployment. Set it to
  `false` and restart `steadfast-api.service` to disable those routes. Production
  orders are limited to NFO and BFO derivatives and ten contract lots per order; this
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
that commit, installs dependencies, builds the frontend, and restarts and checks
the API and WebSocket systemd services. The checkout and its submodules must be
clean, including generated tracked symbol files; preserve and resolve any local
changes before running it. The deploying user needs write access to the checkout
and virtual environment, network access, and sudo permission to restart the two
services. The existing systemd units and Caddy configuration are not installed
or changed by this script.

Deployment modifies files in place and has no automatic rollback: a failure may
leave files or services partially updated. Schedule it when interruptions are
safe, inspect errors and service status if it fails, and verify broker positions
and orders independently. API restart requires logging in again; service
activity checks do not prove broker connectivity or successful trading.

## Validation and eventual cutover

1. Independently test acknowledgements, partial fills, rejections, duplicate
   requests, outages, and manual-intervention states without submitting live
   orders. Browser-based protection is not broker-side risk management.
2. Test the services privately before changing Caddy; verify broker login and
   fresh market data without orders.
3. Check DNS, TLS, the Flattrade portal's approved outbound IP, and the Basic
   Auth and WebSocket behavior. Validate Caddy's configuration using its
   installed version and verify the systemd units on Ubuntu. The local Caddy
   syntax check does not establish compatibility with the server or prove
   access control end to end.
4. Back up the current Caddy configuration and record the scalpX service state.
   After positions and orders are reviewed and cutover is explicitly approved,
   switch the site to the new configuration and reload Caddy. Verify TLS,
   unauthorized rejection, authorized access, the callback, and streaming.
5. If verification fails, restore the saved Caddy configuration and prior
   service state. Recheck broker positions and pending orders independently;
   rolling back a service does not cancel or reverse broker orders.
