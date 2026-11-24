#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$ROOT"

trap 'echo "Deployment failed. Services or files may be partially updated; inspect them before retrying." >&2' ERR

if [[ "$ROOT" != /opt/steadfast ]]; then
    echo "Deploy from /opt/steadfast, as required by the production service units." >&2
    exit 1
fi

if [[ "$(git branch --show-current)" != main ]]; then
    echo "Deployment requires the main branch to be checked out." >&2
    exit 1
fi

if [[ -n "$(git status --porcelain --untracked-files=normal --ignore-submodules=none)" ]]; then
    echo "Deployment requires a clean working tree, including submodules; preserve and resolve local changes first." >&2
    exit 1
fi

for unit in steadfast-api.service steadfast-websocket.service; do
    if [[ "$(systemctl show "$unit" --property=LoadState --value)" != loaded ]]; then
        echo "$unit is not installed or could not be loaded." >&2
        exit 1
    fi
done

echo "Fetching origin/main..."
git fetch --no-recurse-submodules origin +refs/heads/main:refs/remotes/origin/main
if ! git merge-base --is-ancestor HEAD origin/main; then
    echo "Local main is not an ancestor of origin/main; resolve the divergence before deploying." >&2
    exit 1
fi
git merge --ff-only origin/main
git submodule update --init --recursive

if [[ "$(systemctl show steadfast-api.service --property=StateDirectory --value)" != "steadfast-api" ]] ||
   [[ "$(systemctl show steadfast-api.service --property=StateDirectoryMode --value)" != "0700" ]]; then
    echo "The installed API unit needs StateDirectory=steadfast-api and StateDirectoryMode=0700. Review and update it, then run systemctl daemon-reload; see deploy/README.md." >&2
    exit 1
fi

echo "Installing dependencies and building the frontend..."
node -e 'const [major, minor] = process.versions.node.split(".").map(Number); if (major < 22 || (major === 22 && minor < 13)) { console.error("Node.js 22.13 or newer is required."); process.exit(1); }'
npm ci --omit=dev --prefix steadfast-api
npm install --include=dev --no-package-lock --prefix steadfast-app
python3 -m venv steadfast-websocket/.venv
steadfast-websocket/.venv/bin/python -m pip install -r steadfast-websocket/requirements.txt
npm run build --prefix steadfast-app

echo "Restarting Steadfast services..."
sudo -A systemctl restart steadfast-api.service steadfast-websocket.service
for attempt in {1..30}; do
    if systemctl is-active --quiet steadfast-api.service &&
       systemctl is-active --quiet steadfast-websocket.service &&
       curl --fail --silent --show-error --max-time 2 http://127.0.0.1:3001/health >/dev/null 2>&1; then
        echo "Deployment complete. Verify the broker session and stream before trading."
        exit 0
    fi
    sleep 1
done
echo "Services did not become ready. Check the API and WebSocket systemd logs before retrying." >&2
exit 1
