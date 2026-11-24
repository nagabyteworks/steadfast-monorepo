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

echo "Installing dependencies and building the frontend..."
npm ci --omit=dev --prefix steadfast-api
npm install --include=dev --no-package-lock --prefix steadfast-app
npm run build --prefix steadfast-app
python3 -m venv steadfast-websocket/.venv
steadfast-websocket/.venv/bin/python -m pip install -r steadfast-websocket/requirements.txt

echo "Restarting Steadfast services..."
sudo -A systemctl restart steadfast-api.service steadfast-websocket.service
systemctl is-active --quiet steadfast-api.service
systemctl is-active --quiet steadfast-websocket.service
echo "Deployment complete. Broker login must be repeated after the API restart."
