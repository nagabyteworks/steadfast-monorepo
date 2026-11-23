# EC2 deployment preparation

**Do not cut over yet.** The configuration in this directory is a draft for a
read-only Flattrade deployment, not a live-trading release. HTTP/WebSocket
integration, broker authentication, streaming, and this systemd configuration
have not been verified on the EC2 host. Broker-side protective SL-limit orders
and backend target progression are not implemented. Production placements,
modifications, cancellations, and browser-managed risk automation must remain
unavailable until those requirements are implemented and tested.

The existing scalpX service and Caddy configuration have not been changed.
Before stopping scalpX, inspect positions and pending orders at the broker.
Stopping scalpX can interrupt any protection or targets it manages in memory;
broker-side orders can remain open.

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

The Caddy configuration permits only the CIDR supplied in
`STEADFAST_ALLOWED_CIDR`, then requires HTTP Basic authentication on every
route, including the WebSocket and callback. It defaults to `127.0.0.1/32` if
the CIDR is not configured. Set it to the **client's** trusted public IP/CIDR,
not the EC2 outbound IP; do not use a public-wide CIDR. A changing client IP
will require an update. This configuration assumes Caddy sees the actual
client IP directly, without a load balancer or other proxy in front.

`STEADFAST_AUTH_FILE` defaults to `/etc/caddy/steadfast-auth`. That file must
contain a Caddy Basic Auth username and a bcrypt password hash, not a plaintext
password. Generate the hash with Caddy's `hash-password` command on the host;
use a unique strong password, and restrict file access to Caddy and
administrators. Supply the CIDR through Caddy's systemd environment, validate
the configuration under the same environment, and verify that both HTTP and
WebSocket requests are authenticated before any public exposure.

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

The included systemd units force production mode and loopback addresses.
Shoonya and virtual trading are disabled in production. Legacy browser broker
secrets are removed from local storage on first production load; configure the
account on the server first.

## Validation and eventual cutover

1. Complete broker-side risk management and restart/reconciliation behavior;
   independently test acknowledgements, partial fills, rejections, duplicate
   requests, outages, and manual-intervention states without submitting live
   orders. Do not remove the production trading gate before explicit approval.
2. Resolve the local sandbox's denied listener permission and run actual
   HTTP/WebSocket integration tests. On EC2, test the services privately before
   changing Caddy; verify broker login and fresh market data without orders.
3. Check DNS, TLS, the instance's actual outbound IP, the Flattrade portal's
   approved IP, the client allowlist, and the Basic Auth and WebSocket behavior.
   Validate Caddy's configuration using its installed version and verify the
   systemd units on Ubuntu. The local Caddy syntax check does not establish
   compatibility with the server or prove access control end to end.
4. Back up the current Caddy configuration and record the scalpX service state.
   After positions and orders are reviewed and cutover is explicitly approved,
   switch the site to the new configuration and reload Caddy. Verify TLS,
   unauthorized rejection, authorized access, the callback, and streaming.
5. If verification fails, restore the saved Caddy configuration and prior
   service state. Recheck broker positions and pending orders independently;
   rolling back a service does not cancel or reverse broker orders.
