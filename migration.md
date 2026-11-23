# Project Infrastructure & Technical Handover – Nagabyte Trading Application

## 1. Project Overview

I am developing a LIVE options trading application integrated primarily with Flattrade.

My previous implementation was split across:
- `scalpX-backend`
- `scalpX-android`

I have now selected the following repository as my primary project:

**Main repository:** https://github.com/nagabyteworks/steadfast-monorepo

The monorepo contains:
- `steadfast-app` – frontend
- `steadfast-api` – Node.js backend
- `steadfast-websocket` – Python WebSocket service

The objective is to adapt and improve this codebase to support my trading requirements.

Do not assume that the old scalpX implementation and Steadfast have identical functionality.

## 2. AWS EC2 – Previously Configured Infrastructure

I previously configured an AWS EC2 instance to host my trading backend.

### Known configuration

| Property | Previously known value |
|---|---|
| Cloud provider | AWS |
| Compute service | EC2 |
| Operating system | Ubuntu |
| Deployment architecture | Node.js backend + reverse proxy |
| Backend application port | 3000 |
| Reverse proxy | Caddy |
| Backend process manager | systemd |
| systemd service name | `scalpx.service` |
| Production domain | `trade.nagabyte.com` |
| Backend public IP | `18.61.185.225` |
| Broker | Flattrade |

**Important:** These are details from my previous scalpX deployment. The current EC2 instance status, instance ID, instance type, region, storage, security groups, and whether the same configuration is being used for Steadfast have not been verified.

### Previous deployment architecture

```text
                 Internet
                    |
                    |
          trade.nagabyte.com
                    |
                    |
              Caddy Proxy
                    |
                    |
             127.0.0.1:3000
                    |
                    |
          Node.js Backend
                    |
                    |
             Flattrade API
```

Caddy was configured as the reverse proxy, forwarding requests to the Node.js backend running on port 3000.

The backend was managed through systemd using:

`scalpx.service`

### Previously used commands

Check the service:

```bash
sudo systemctl status scalpx.service
```

Restart:

```bash
sudo systemctl restart scalpx.service
```

Stop:

```bash
sudo systemctl stop scalpx.service
```

Start:

```bash
sudo systemctl start scalpx.service
```

View logs:

```bash
sudo journalctl -u scalpx.service -f
```

These commands apply to the previous deployment. Do not assume the Steadfast services already have the same systemd configuration.

## 3. Flattrade Broker – Network Configuration

My primary broker is Flattrade.

Previously, I verified that the EC2 server's outbound public IP was:

`18.61.185.225`

This IP matched the public IP configured in the Flattrade portal's approved IP configuration.

This is important because broker API connectivity may depend on the approved outbound IP.

When changing EC2 instances, NAT gateways, Elastic IPs, or network routing, verify the actual outbound public IP before changing the broker configuration.

Do not assume the EC2 public IP and outbound IP are always identical.

## 4. Production Domain

My previously configured production domain is:

`https://trade.nagabyte.com`

Expected production endpoints:

- REST API: `https://trade.nagabyte.com`
- WebSocket: `wss://trade.nagabyte.com` or the separately configured production WebSocket endpoint.

The actual WebSocket routing and current Caddy configuration need to be inspected before implementation.

Security requirements:
- HTTPS for REST.
- WSS for production WebSocket connections.
- Never expose broker API credentials in frontend code.
- Never disable TLS certificate validation.
- Never log broker session tokens or secrets.

## 5. Trading Application Requirements

My primary objective is LIVE options trading.

I do not want paper trading as a feature in the finished application.

### Trading functionality

- Flattrade authentication.
- Live index prices.
- Live option-chain data.
- CE/PE selection.
- Live LTP.
- Place orders.
- Modify orders.
- Retrieve positions.
- Close positions.
- Automated protective stop-loss management.
- Backend-managed target progression.

### Stop-loss and target logic

Example:

Entry price: ₹100  
Initial SL: 5 points  
Target: 5 points

| Market price | Broker SL | Next target |
|---|---:|---:|
| ₹100 | ₹95 | ₹105 |
| ₹105 | ₹105 | ₹110 |
| ₹110 | ₹110 | ₹115 |
| ₹115 | ₹115 | ₹120 |

Important design:
- Actual protective SL-LIMIT order is placed with Flattrade.
- Target progression is maintained in backend RAM.
- When a target is reached, the backend modifies the broker SL.
- The next target is advanced by the configured target increment.
- Average executed entry price must be used.
- SL trigger price and SL limit price must be handled separately.
- A modification request must not be considered successful until broker acknowledgement is received.

The target state is not durably persisted in this design. If the backend restarts, the target progression is lost. The application must flag this and require manual intervention instead of guessing the previous state.

## 6. Trading Safety

The last known configuration in the previous scalpX backend was:

`TRADING_ENABLED=false`

This is a historical configuration, not a verified current value.

Do not enable live trading, place actual orders, or change trading flags without my explicit authorization.

During development:
- Use read-only broker API operations wherever possible.
- Test order-management logic with mocks or controlled test fixtures.
- Do not accidentally place real orders.
- Preserve kill switches and execution safeguards.
- Verify partial fills, duplicate requests, broker rejections, and network failures.

## 7. Local Development Environment

My primary development machine is:

**MacBook Air M5**

I use:
- VS Code
- Antigravity IDE
- Git
- Node.js
- npm
- Python
- Android development tools where required

My intended local environment should support the full Steadfast monorepo.

Previously documented local service ports:

| Service | Port |
|---|---:|
| Steadfast frontend | 5173 |
| Steadfast API | 3000 |
| Flattrade WebSocket | 8765 |
| Shoonya WebSocket | 8766 |

These are the ports documented in the monorepo README and must be verified against the actual startup scripts and service configurations.

## 8. Environment Configuration

I want a clean separation between development and production.

Previously intended configuration:

| Environment | API URL |
|---|---|
| Android emulator | `http://10.0.2.2:3000` |
| Physical device | Configurable Mac LAN IP |
| Production | `https://trade.nagabyte.com` |

WebSocket URLs must follow the same environment selection.

Requirements:
- Do not hardcode URLs in multiple files.
- Use environment-based configuration.
- No silent development/production fallback.
- Allow HTTP only where necessary in development.
- Production must use HTTPS/WSS.

The exact environment variable names and frontend configuration must be determined from the current Steadfast source code.

## 9. Previous Debugging Findings

Some issues encountered in scalpX should be considered when reviewing Steadfast.

### Index instrument lookup

The previous backend encountered errors while resolving the BSE SENSEX instrument through Flattrade's GetIndexList API.

Observed details:
- Exchange: BSE.
- Instrument ID was null.
- API returned HTTP 502 through the backend.
- Broker's actual error message was not adequately preserved in the logs.

Potential improvement:
- Preserve sanitized broker error messages.
- Validate instrument lookup results.
- Handle session expiration explicitly.
- Do not convert every broker failure into a generic error.

### WebSocket first-tick race

A previous option-chain implementation subscribed to the index and immediately checked the cached latest tick.

A subscription does not guarantee that a tick has already arrived.

The implementation should wait for the first valid tick or use a controlled timeout/retry mechanism.

### OAuth callback

A previous OAuth integration had a response-field mismatch involving `status` and `stat`.

The adapter was subsequently updated to support:

`data.status ?? data.stat`

Inspect the current implementation before assuming this issue still exists.

## 10. Other Infrastructure – Home Server

Separately from AWS EC2, I have also configured a home server.

Previously discussed details:
- Ubuntu Server installed after replacing Windows.
- Docker Compose installed.
- Docker installation verified using `hello-world`.
- Tailscale configured for remote SSH access.
- Immich planned for self-hosted photo storage.
- Intended photo domain: `photos.nagabyte.com`.

Immich is a separate project and should not be mixed with the trading application's EC2 deployment.

## 11. What Needs Verification Before Making Infrastructure Changes

The following details are currently unknown or potentially outdated:

- EC2 instance ID.
- AWS region.
- EC2 instance type.
- Current instance state.
- Current Elastic IP.
- Current public and outbound IP.
- EBS volume size and type.
- Security group inbound rules.
- IAM role and permissions.
- Current Caddy configuration.
- Current systemd services.
- Current Node.js version on EC2.
- Python version.
- Current deployed Git commit.
- Whether `trade.nagabyte.com` still points to the same instance.
- Whether the old scalpX backend is still running.
- Whether Steadfast has been deployed to EC2 yet.

Never invent these details. Ask me to provide the relevant AWS configuration or inspect the server when required.

## 12. Instructions for the AI Assisting This Project

1. Treat `nagabyteworks/steadfast-monorepo` as my primary codebase.
2. Inspect the actual source code before recommending changes.
3. Distinguish existing functionality from new requirements.
4. Prefer Node.js and JavaScript/TypeScript for backend work where compatible with the existing architecture.
5. Preserve the existing Python WebSocket service unless there is a concrete reason to change it.
6. Keep broker secrets and authentication details on the backend.
7. Do not enable live trading without explicit permission.
8. Do not introduce paper trading into the finished product.
9. Avoid reintroducing device UUID pre-authorization.
10. Maintain one-click execution as the preferred trading workflow.
11. Handle broker API failures explicitly instead of hiding them.
12. Consider real-world trading risks, partial fills, network interruptions and backend crashes.
13. Do not assume old scalpX configuration is already present in Steadfast.
14. Provide exact commands and file paths when explaining deployment or debugging.
15. Prioritize security, reliability and execution correctness over quick implementation.

**Primary objective:** Build a reliable, backend-controlled LIVE options trading application using Steadfast, Flattrade, AWS EC2 and the existing `trade.nagabyte.com` production infrastructure where appropriate.