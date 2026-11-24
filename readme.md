# Steadfast

Steadfast is an open-source trading application organized as a monorepo. It combines a browser-based user interface, a Node.js API, and Python WebSocket clients for supported brokers.

> **Open-source version notice:** This repository contains experimental, AI-generated code intended primarily for learning and personal use. It may contain bugs, security vulnerabilities, and implementation issues and is not optimized for production. Test and understand the code thoroughly. Use real funds only at your own risk.
>
> Looking for the hosted service with the latest updates? Visit the [Steadfast website](https://www.steadfastapp.in) for information about the premium version.

Stay updated by joining the [Steadfast Telegram channel](https://t.me/steadfastapp).

## What is in this repository?

| Project | Purpose | Main technology |
| --- | --- | --- |
| [`steadfast-app`](https://github.com/narenkram/steadfast-app) | Browser UI for broker setup and management, trading, settings, and parallel copy trading | Vue 3, Vue Router, Vite |
| [`steadfast-api`](https://github.com/narenkram/steadfast-api) | HTTP API that connects the UI to broker APIs, handles order-related requests, provides symbol data, and offers virtual orders | Node.js, Express |
| [`steadfast-websocket`](https://github.com/narenkram/steadfast-websocket) | Broker-specific Python clients that connect to Flattrade or Shoonya and stream live data | Python, `websockets` |

The root `package.json` includes commands to install and run the services together. Each service also has its own package/dependency files.

## How the services work together

1. The Vue application is served locally by Vite at **http://localhost:5173**.
2. The Express API listens on **http://localhost:3000** by default. It exposes `/flattrade`, `/shoonya`, and `/virtual` route groups.
3. When a broker is selected, the API notifies the Python service over local TCP port **5000**.
4. The Python service fetches the selected broker session details through the API and starts that broker's WebSocket client. Flattrade uses port **8765**; Shoonya uses **8766**. The service waits for a broker selection, so it does not necessarily start both broker streams at once.
5. The frontend uses the API for broker and order operations and WebSockets for streaming data.

The API's `/virtual` routes simulate order placement and provide order/trade lists. These virtual orders are held in memory and disappear when the API process restarts.

## Repository structure

```text
steadfast-monorepo/
├── package.json              # Root install and development commands
├── package-lock.json         # Root npm dependency lockfile
├── setup.sh                  # Interactive macOS/Linux setup and run helper
├── start-all.sh              # Unix launcher
├── start-all.bat             # Windows launcher
├── steadfast-app/            # Vue frontend
│   └── src/pages/            # Landing, broker, trading, and settings views
├── steadfast-api/            # Express API
│   ├── routes/               # Flattrade, Shoonya, virtual, file update routes
│   └── symbols/              # Broker instrument symbol data
└── steadfast-websocket/      # Python broker streaming service
    ├── flattrade/            # Flattrade WebSocket integration
    └── shoonya/              # Shoonya WebSocket integration
```

## Requirements

- **Node.js 22.13 or newer** and npm. The API uses Node's built-in SQLite support.
- **Python 3** and pip for the WebSocket service.
- **Git** to clone the repository.
- The root `npm start` command uses Unix virtual-environment paths and is intended for macOS/Linux. Windows users can use `start-all.bat`.

Broker credentials and accounts are needed to use broker integrations. Do not commit credentials, session tokens, or other secrets.
Each repository ignores local `.env` files and private-key files; `.env.example` files remain available for non-secret templates. Git ignore rules do not protect files that are already tracked or staged, including the existing frontend environment files and WebSocket `.env`; keep secrets out of those files and review staged files before committing.

**Live trading:** Production Flattrade order placement and cancellation require `TRADING_ENABLED=true`; the production systemd unit enables this flag. Set it to `false` and restart the API service to disable trading. Production orders are restricted to NFO and BFO derivatives and the API rejects individual orders larger than ten lots, using the Flattrade scrip master. This is a per-order cap, not a cap on total positions, order count, or daily loss.

Predefined stop-loss and target controls are optional and default to off. When enabled, their point values are monitored by the browser and exit orders are submitted from the browser. The app must remain open with a working market-data connection; this is not broker-side protection and can stop working if the browser, network, or stream disconnects. If both controls are off, a live entry has no automatic stop-loss or target. Check order acknowledgements, positions, and any protective actions directly with Flattrade. Never commit or share broker credentials or session tokens.

Automatic exits require browser Web Locks and use a persistent per-symbol safety lock to prevent retries after an accepted, rejected, or uncertain submission. Verify orders and positions in Flattrade before using the trading page's reset control. Locks coordinate tabs in the same browser only; they do not coordinate other browsers, devices, or manual broker orders.

The optional Buy Both and Sell Both buttons submit separate CE and PE orders simultaneously; either leg can fail or remain unfilled independently. They are unavailable for manual Limit orders. Product type and click sounds are configured in Settings. The kill switch and automatic overtrade protection have been removed.

## Clone and install

Clone the repository and enter its directory:

```bash
git clone https://github.com/narenkram/steadfast-monorepo.git
cd steadfast-monorepo
```

Install the root runner and all service dependencies:

```bash
npm install
npm run install:all
```

`npm run install:all` installs the API and frontend npm dependencies, creates `steadfast-websocket/.venv`, and installs the Python requirements, including the checksum-pinned official Flattrade SDK. If the root dependencies are already installed, run only `npm run install:all`.

Alternatively, install services individually:

```bash
cd steadfast-api && npm install
cd ../steadfast-app && npm install
cd ../steadfast-websocket
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
```

Run the Python install commands from `steadfast-websocket`. On Windows, use the platform's virtual-environment activation command and install the same requirements; the `start-all.bat` helper is provided for Windows.

## Start the application

From the repository root on macOS/Linux:

```bash
npm start
```

This starts the API, frontend, and Python WebSocket service concurrently. Open **http://localhost:5173**. The Python service waits for broker selection in the application before connecting to the selected broker. Use **Ctrl+C** to stop the root command.

Root scripts can also start each service independently:

| Command | Purpose | Default address/port |
| --- | --- | --- |
| `npm run api` | Start the API in development mode | `http://localhost:3000` |
| `npm run app` | Start the Vite frontend | `http://localhost:5173` |
| `npm run websocket` | Start the Python broker WebSocket service | `5000` IPC; `8765` Flattrade / `8766` Shoonya |

The service-specific commands are also available. Run each from the repository root in a separate terminal:

```bash
cd steadfast-api && npm run dev
cd steadfast-app && npm run dev
cd steadfast-websocket && ENV=development .venv/bin/python main.py
```

For Windows, `start-all.bat` provides an interactive menu. The `start-all.sh` and `start-all.bat` stop functions terminate processes by name, including unrelated Node.js or Python processes; do not use them on a shared machine or an EC2 instance running other services. The interactive `setup.sh` helper provides install, update, and run options on macOS/Linux. Review any helper before using its update option, which pulls changes in the child repositories.

## Configuration

Configuration is service-specific:

- **API:** `NODE_ENV` must be `development` or `production`. `PORT` sets the API port (default `3000`), and `API_HOST` sets its listen address (default `127.0.0.1`, loopback required in production). `CORS_ORIGIN` sets the permitted browser origin; production requires an HTTPS origin and rejects state-changing requests without a matching `Origin` header. Development defaults to `http://localhost:5173`.
- **Frontend:** `VITE_BASE_URL` sets the API base URL and is used when deriving the production WebSocket URL. The production environment file defaults to `https://trade.nagabyte.com`. A production build requires an HTTPS origin without a path; set the value before building if deploying elsewhere.
- **WebSocket service:** `ENV` must be `development` or `production`. `API_BASE_URL` is required in production and should point to the local API, such as `http://127.0.0.1:3000`; development defaults to that address. `WS_ALLOWED_ORIGIN` is required in production and must match the browser's HTTPS origin. `WS_HOST` defaults to `127.0.0.1`. `FLATTRADE_WS_PORT` and `SHOONYA_WS_PORT` set the broker stream ports, defaulting to `8765` and `8766`; if changed, configure the same values in the API and update the reverse proxy and frontend URLs to match.
- **Broker sessions:** In production, set `FLATTRADE_CLIENT_ID`, `FLATTRADE_API_KEY`, and `FLATTRADE_API_SECRET` only in the API's protected server environment. The API saves the Flattrade session in a private SQLite database and restores it after restart until 6:00 AM India time. Flattrade may invalidate the session earlier. The Brokers page provides broker login and local logout; logout does not revoke the session at Flattrade. Tokens are not encrypted at rest; protect the database and backups. Flattrade's login URL necessarily includes the app key as required by its protocol. On first production load, the browser removes previously saved broker API keys, secrets and tokens from its local storage; configure them on the server first. Shoonya is unavailable in production until its login is migrated. Development retains the legacy browser-managed flow and must be kept private.
- **Internal credential handoff:** Set the same randomly generated `WEBSOCKET_INTERNAL_TOKEN` (32-256 URL-safe letters, digits, `_`, or `-`) in the API and WebSocket environments in production. Keep it in a protected environment file, never in the frontend or Git. Production's `API_BASE_URL` must be a loopback address. Without a token, development allows local credential access and must not be exposed to a network.

Origin checks and the internal token are not user authentication. Do not expose these services to the internet as-is: access control and end-to-end testing are still required. The disabled trading gate does not protect credentials or existing broker orders.

For the draft EC2 service and Caddy layout, its prerequisites, and cutover
safety checks, see [EC2 deployment preparation](deploy/README.md). It is not
yet approved for cutover or live trading.

## Useful frontend commands

Run these from `steadfast-app`:

| Command | Purpose |
| --- | --- |
| `npm run dev` | Start the Vite development server |
| `npm run build` | Build the frontend for production |
| `npm run preview` | Preview the production build locally |
| `npm run test:unit` | Run unit tests with Vitest |
| `npm run lint` | Run ESLint (the configured command also applies fixes) |
| `npm run format` | Format files under `src/` with Prettier |

## Troubleshooting

- **A service fails to start:** Confirm that all three project folders are present, dependencies are installed, and required ports are available.
- **The WebSocket service appears idle:** This is expected until the application selects a broker. Confirm the API is running and accessible on port `3000`.
- **The API cannot notify the Python service:** Ensure the Python service is running and local TCP port `5000` is available.
- **A broker stream cannot connect:** Verify the broker session, network access, and the selected broker's WebSocket port (`8765` or `8766`).
- **The frontend cannot reach the API:** Check that the API is running, `VITE_BASE_URL` points to it, and the API's CORS settings allow the frontend origin.
- **Symbol lookup fails:** Check that the expected instrument data files exist under `steadfast-api/symbols/`.
- **Python import/dependency errors:** Install requirements into `steadfast-websocket/.venv` and run the service using that environment.

## License and support

Refer to the individual service repositories and their license files for project-specific licensing and contribution information. For announcements, visit the [Telegram channel](https://t.me/steadfastapp).

