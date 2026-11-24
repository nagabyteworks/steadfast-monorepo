#!/usr/bin/env bash

# Read-only Steadfast deployment diagnostics. Never call trading operations.

set -u

ROOT=/opt/steadfast
API="$ROOT/steadfast-api"
APP="$ROOT/steadfast-app"
WS="$ROOT/steadfast-websocket"
API_ENV=/etc/steadfast/api.env
WS_ENV=/etc/steadfast/websocket.env
CADDYFILE=/etc/caddy/Caddyfile
AUTH_FILE=/etc/caddy/steadfast-auth
DOMAIN=trade.nagabyte.com
API_URL=http://127.0.0.1:3001

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
API_CONFIGURED=unknown
API_HAS_SESSION=unknown

pass() {
    printf '[PASS] %s\n' "$1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
    printf '[FAIL] %s\n' "$1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

warn() {
    printf '[WARN] %s\n' "$1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

section() {
    printf '\n========== %s ==========\n' "$1"
}

check_command() {
    if command -v "$1" >/dev/null 2>&1; then
        pass "Command available: $1"
    else
        fail "Required command missing: $1"
    fi
}

check_file() {
    if [ -f "$1" ]; then
        pass "File exists: $1"
    else
        fail "Required file missing: $1"
    fi
}

run_project_command() {
    local directory="$1"
    shift
    if [ "$(id -u)" -eq 0 ] && command -v runuser >/dev/null 2>&1; then
        runuser -u ubuntu -- sh -c 'cd "$1" && shift && exec "$@"' sh "$directory" "$@"
    else
        (cd "$directory" && "$@")
    fi
}

http_status() {
    curl --silent --show-error --connect-timeout 3 --max-time 10 \
        --output /dev/null --write-out '%{http_code}' "$1" 2>/dev/null || printf '000'
}

port_rows() {
    local port="$1"
    ss -H -ltnp 2>/dev/null |
        awk -v port="$port" '$4 ~ (":" port "$") { print $4 "|" $NF }'
}

check_loopback_port() {
    local label="$1"
    local port="$2"
    local rows address process invalid=0
    local -a entries
    mapfile -t entries < <(port_rows "$port")
    if [ "${#entries[@]}" -eq 0 ]; then
        fail "$label is not listening on port $port"
        return
    fi
    for rows in "${entries[@]}"; do
        address="${rows%%|*}"
        process="${rows#*|}"
        printf 'Port %s: %s (%s)\n' "$port" "$address" "$process"
        case "$address" in
            127.*:*|localhost:*|'[::1]':*|'::1':*) ;;
            *) invalid=1 ;;
        esac
    done
    if [ "$invalid" -eq 0 ]; then
        pass "$label listens only on loopback"
    else
        fail "$label has a non-loopback listener on port $port"
    fi
}

check_public_port() {
    local label="$1"
    local port="$2"
    local rows address process public=0
    local -a entries
    mapfile -t entries < <(port_rows "$port")
    if [ "${#entries[@]}" -eq 0 ]; then
        fail "$label has no listener on port $port"
        return
    fi
    for rows in "${entries[@]}"; do
        address="${rows%%|*}"
        process="${rows#*|}"
        printf 'Port %s: %s (%s)\n' "$port" "$address" "$process"
        case "$address" in
            127.*:*|localhost:*|'[::1]':*|'::1':*) ;;
            *) public=1 ;;
        esac
    done
    if [ "$public" -eq 1 ]; then
        pass "$label has an externally reachable listener on port $port"
    else
        fail "$label is bound only to loopback on port $port"
    fi
}

check_service() {
    local unit="$1"
    local expected="$2"
    local state enabled details restarts
    state="$(systemctl is-active "$unit" 2>/dev/null || true)"
    enabled="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
    details="$(systemctl show "$unit" -p MainPID -p NRestarts -p ExecMainStartTimestamp -p MemoryCurrent --no-pager 2>/dev/null || true)"
    printf '%s: active=%s enabled=%s %s\n' "$unit" "${state:-unknown}" "${enabled:-unknown}" \
        "$(printf '%s' "$details" | tr '\n' ' ')"

    if [ "$expected" = "inactive" ]; then
        if [ "$state" = "inactive" ] && [ "$enabled" = "disabled" ]; then
            pass "$unit is inactive and disabled"
        elif [ "$state" = "active" ]; then
            warn "$unit remains active pending verified Steadfast cutover"
        else
            warn "$unit state is ${state:-unknown}; expected inactive/disabled after cutover"
        fi
        return
    fi

    if [ "$state" = "$expected" ]; then
        pass "$unit is $expected"
    else
        fail "$unit expected $expected but found ${state:-unknown}"
    fi

    restarts="$(printf '%s\n' "$details" | awk -F= '$1 == "NRestarts" { print $2 }')"
    if [ -n "$restarts" ] && [ "$restarts" -gt 0 ] 2>/dev/null; then
        warn "$unit has restarted $restarts time(s)"
    fi
}

check_recent_logs() {
    local unit="$1"
    local logs matches errors tracebacks expected_restarts ignored_tracebacks
    if ! logs="$(journalctl -u "$unit" --since '1 hour ago' -n 300 --no-pager -o cat 2>/dev/null)"; then
        warn "Cannot inspect recent logs for $unit without additional journal permissions"
        return
    fi

    errors="$(printf '%s\n' "$logs" | grep -Eic 'UnhandledPromiseRejection|Traceback|ModuleNotFoundError|Permission denied|Address already in use|Connection refused|CORS.*(error|denied)|authentication failed' || true)"
    tracebacks="$(printf '%s\n' "$logs" | grep -Eic 'Traceback' || true)"
    expected_restarts="$(printf '%s\n' "$logs" | grep -Fic 'Broker session changed; supervisor must restart' || true)"
    ignored_tracebacks="$tracebacks"
    if [ "$expected_restarts" -lt "$ignored_tracebacks" ]; then
        ignored_tracebacks="$expected_restarts"
    fi
    errors=$((errors - ignored_tracebacks))
    matches="$(printf '%s\n' "$logs" | grep -Eic '(^|[[:space:]])(error|fatal):' || true)"
    if [ "${errors:-0}" -gt 0 ] || [ "${matches:-0}" -gt 0 ]; then
        warn "$unit recent logs contain $((errors + matches)) matching error/exception message(s); raw logs suppressed"
    else
        pass "$unit has no matching recent error/exception messages"
    fi
}

section "SYSTEM"
printf 'Hostname: %s\n' "$(hostname)"
printf 'Date: %s\n' "$(date -Is)"
printf 'Uptime: %s\n' "$(uptime -p 2>/dev/null || uptime)"
printf 'OS: %s\n' "$( (lsb_release -ds 2>/dev/null || awk -F= '$1 == "PRETTY_NAME" {gsub(/"/, "", $2); print $2}' /etc/os-release) | head -1)"
printf 'Architecture: %s; CPUs: %s\n' "$(uname -m)" "$(nproc 2>/dev/null || echo unknown)"
printf 'Node.js: %s; npm: %s; system Python: %s; Caddy: %s\n' \
    "$(node --version 2>/dev/null || echo unavailable)" \
    "$(npm --version 2>/dev/null || echo unavailable)" \
    "$(python3 --version 2>&1 || echo unavailable)" \
    "$(caddy version 2>/dev/null | head -1 || echo unavailable)"
printf 'Logged-in users:\n'
who 2>/dev/null || true
printf 'Memory:\n'
free -h 2>/dev/null || true
printf 'Disk:\n'
df -h / 2>/dev/null || true
cpu_before="$(awk '/^cpu / { idle=$5+$6; total=0; for (i=2;i<=NF;i++) total+=$i; print total, idle }' /proc/stat 2>/dev/null)"
sleep 1
cpu_after="$(awk '/^cpu / { idle=$5+$6; total=0; for (i=2;i<=NF;i++) total+=$i; print total, idle }' /proc/stat 2>/dev/null)"
cpu_usage="$(awk -v before="$cpu_before" -v after="$cpu_after" 'BEGIN {
    split(before, b); split(after, a);
    dt=a[1]-b[1]; di=a[2]-b[2];
    if (dt > 0) printf "%.1f%%", 100*(dt-di)/dt; else print "unknown"
}')"
printf 'CPU usage over 1s sample: %s\n' "$cpu_usage"
available_mb="$(awk '/^MemAvailable:/ { print int($2/1024) }' /proc/meminfo 2>/dev/null)"
if [ -n "$available_mb" ] && [ "$available_mb" -ge 128 ]; then
    pass "At least 128 MiB memory is available"
else
    warn "Available memory is below 128 MiB or could not be measured"
fi
disk_used_percent="$(df -P / 2>/dev/null | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }')"
if [ -n "$disk_used_percent" ] && [ "$disk_used_percent" -lt 90 ]; then
    pass "Root filesystem usage is below 90%"
else
    warn "Root filesystem is at least 90% full or could not be measured"
fi

for command_name in bash curl git node npm python3 ss systemctl caddy; do
    check_command "$command_name"
done
if command -v docker >/dev/null 2>&1; then
    pass "Optional command available: docker"
else
    warn "Optional command unavailable: docker"
fi
if [ -x "$WS/.venv/bin/python" ]; then
    pass "WebSocket virtual-environment Python is available"
else
    fail "WebSocket virtual-environment Python is missing"
fi
if python3 -m pip --version >/dev/null 2>&1; then
    pass "System Python pip is available"
else
    warn "System Python pip is unavailable; component virtual environment is used"
fi
available_kb="$(df -Pk / 2>/dev/null | awk 'NR == 2 { print $4 }')"
if [ -n "$available_kb" ] && [ "$available_kb" -ge 1048576 ]; then
    pass "At least 1 GiB disk space is available"
else
    warn "Less than 1 GiB disk space is available or could not be measured"
fi

section "GIT AND DEPLOYMENT"
for repository in "$ROOT" "$API" "$APP" "$WS"; do
    if ! git -C "$repository" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        fail "Git repository unavailable: $repository"
        continue
    fi
    branch="$(git -C "$repository" branch --show-current 2>/dev/null)"
    commit="$(git -C "$repository" rev-parse --short HEAD 2>/dev/null)"
    dirty="$(git -C "$repository" status --porcelain --untracked-files=normal 2>/dev/null | awk 'END { print NR+0 }')"
    printf '%s: branch=%s commit=%s dirty_paths=%s\n' "$repository" "${branch:-detached}" "${commit:-unknown}" "$dirty"
    if [ "$dirty" -gt 0 ]; then
        warn "$repository has uncommitted changes; diagnostic output omits file contents"
    else
        pass "$repository is clean"
    fi
done

if git -C "$ROOT" submodule status >/dev/null 2>&1; then
    submodules="$(git -C "$ROOT" submodule status)"
    if printf '%s\n' "$submodules" | grep -Eq '^[-]'; then
        fail "One or more Git submodules are uninitialized"
    elif printf '%s\n' "$submodules" | grep -Eq '^[+]'; then
        warn "One or more submodule worktrees differ from the parent commit"
    else
        pass "Git submodules are initialized at recorded commits"
    fi
else
    fail "Unable to inspect Git submodules"
fi

for required in \
    "$API/server.js" "$API/package.json" "$APP/src/main.js" "$APP/package.json" \
    "$API/package-lock.json" "$APP/package-lock.json" "$APP/dist/index.html" \
    "$WS/main.py" "$WS/config.py" "$WS/requirements.txt" \
    "$ROOT/deploy/Caddyfile" "$ROOT/deploy/diagnostics.sh" \
    "$ROOT/deploy/systemd/steadfast-api.service" "$ROOT/deploy/systemd/steadfast-websocket.service"; do
    check_file "$required"
done

if [ -f "$API_ENV" ] && [ -f "$WS_ENV" ]; then
    pass "Both service environment files exist; contents are not displayed"
    api_env_mode="$(stat -c '%a:%U:%G' "$API_ENV" 2>/dev/null || true)"
    ws_env_mode="$(stat -c '%a:%U:%G' "$WS_ENV" 2>/dev/null || true)"
    printf 'API environment metadata: %s\nWebSocket environment metadata: %s\n' \
        "${api_env_mode:-unavailable}" "${ws_env_mode:-unavailable}"
    if [ "$api_env_mode" = "640:root:steadfast-api" ]; then
        pass "API environment file is restricted to its service group"
    else
        warn "API environment file permissions/ownership differ from root:steadfast-api 0640"
    fi
    if [ "$ws_env_mode" = "640:root:steadfast-ws" ]; then
        pass "WebSocket environment file is restricted to its service group"
    else
        warn "WebSocket environment file permissions/ownership differ from root:steadfast-ws 0640"
    fi
else
    fail "One or more required service environment files are missing"
fi

for repository in "$ROOT" "$API" "$APP" "$WS"; do
    tracked_env_files="$(git -C "$repository" ls-files | grep -Ec '(^|/)\.env$' || true)"
    if [ "${tracked_env_files:-0}" -eq 0 ]; then
        pass "No exact .env files are tracked in $repository"
    else
        fail "One or more exact .env files are tracked in $repository"
    fi
done

section "SYSTEMD"
check_service steadfast-api.service active
check_service steadfast-websocket.service active
check_service caddy.service active
check_service scalpx.service inactive

for unit in steadfast-api.service steadfast-websocket.service caddy.service scalpx.service; do
    check_recent_logs "$unit"
done

section "LISTENING PORTS"
check_loopback_port "Steadfast API" 3001
check_loopback_port "Python IPC" 5000
check_public_port "Caddy HTTP" 80
check_public_port "Caddy HTTPS" 443

port_3000="$(port_rows 3000)"
if [ -n "$port_3000" ]; then
    printf 'Port 3000: %s\n' "$(printf '%s\n' "$port_3000" | tr '\n' ' ')"
    warn "Port 3000 remains occupied; retain scalpX until Steadfast cutover is verified"
else
    pass "Port 3000 is not occupied"
fi

port_8765="$(port_rows 8765)"
if [ -z "$port_8765" ]; then
    if [ "$API_HAS_SESSION" = "true" ]; then
        warn "Port 8765 is closed despite an API session; broker authentication is not verified"
    else
        warn "Port 8765 is closed pending an authenticated broker session"
    fi
else
    while IFS= read -r row; do
        address="${row%%|*}"
        process="${row#*|}"
        printf 'Port 8765: %s (%s)\n' "$address" "$process"
        case "$address" in
            127.*:*|localhost:*|'[::1]':*|'::1':*) pass "Broker WebSocket listener is loopback-only";;
            *) fail "Broker WebSocket listener is not loopback-only";;
        esac
    done <<< "$port_8765"
fi

port_8766="$(port_rows 8766)"
if [ -z "$port_8766" ]; then
    pass "Disabled production Shoonya port 8766 is closed"
else
    warn "Unexpected production listener detected on port 8766"
fi

section "FRONTEND BUILD"
INDEX="$APP/dist/index.html"
if [ -f "$INDEX" ]; then
    pass "Production index exists"
    printf 'Build timestamp: %s\n' "$(stat -c '%y' "$INDEX" 2>/dev/null || echo unknown)"
    asset_failures=0
    while IFS= read -r reference; do
        [ -n "$reference" ] || continue
        asset_path="$APP/dist/${reference#/}"
        if [ -f "$asset_path" ]; then
            pass "Referenced frontend asset exists: $reference"
        else
            fail "Referenced frontend asset is missing: $reference"
            asset_failures=$((asset_failures + 1))
        fi
    done < <(grep -oE '(src|href)="/[^"]+"' "$INDEX" 2>/dev/null | sed -E 's/^[^=]+="//; s/"$//')
    if [ "$asset_failures" -eq 0 ]; then
        pass "All root HTML asset references resolve"
    fi
else
    fail "Production frontend index is missing"
fi

if [ -f "$APP/.env.production" ] && grep -q '^VITE_BASE_URL=https://trade\.nagabyte\.com$' "$APP/.env.production"; then
    pass "Production frontend API base URL uses the configured HTTPS domain"
else
    fail "Production frontend API base URL is missing or incorrect"
fi
if grep -R -Eq 'localhost:(3000|5173)|127\.0\.0\.1:3001' "$APP/dist" --include='*.js' --include='*.css' 2>/dev/null; then
    fail "Production assets contain a localhost API endpoint"
else
    pass "No localhost API endpoint is embedded in production assets"
fi
if grep -R -q 'https://trade.nagabyte.com' "$APP/dist" --include='*.js' --include='*.html' 2>/dev/null; then
    pass "Production assets contain the configured public domain"
else
    warn "Configured public domain was not found in built assets"
fi

section "API"
root_status="$(http_status "$API_URL/")"
if [ "$root_status" = "200" ]; then
    pass "API root returned HTTP 200"
else
    fail "API root expected HTTP 200 but returned $root_status"
fi
api_root_time="$(curl --silent --show-error --connect-timeout 3 --max-time 5 \
    --output /dev/null --write-out '%{time_total}' "$API_URL/" 2>/dev/null || echo unknown)"
printf 'API root response time: %ss\n' "$api_root_time"

health_body="$(curl --silent --show-error --connect-timeout 3 --max-time 5 "$API_URL/health" 2>/dev/null || true)"
health_status="$(http_status "$API_URL/health")"
if [ "$health_status" = "200" ] && [ "$health_body" = '{"status":"ok"}' ]; then
    pass "API health endpoint returned its non-sensitive success response"
else
    fail "API health endpoint did not return HTTP 200 with the expected response"
fi

internal_status="$(http_status "$API_URL/flattrade/websocketData")"
if [ "$internal_status" = "403" ]; then
    pass "Internal broker-session endpoint rejects unauthenticated access"
else
    fail "Internal broker-session endpoint expected HTTP 403 without its token; got $internal_status"
fi

debug_status="$(http_status "$API_URL/flattrade/test")"
if [ "$debug_status" = "404" ]; then
    pass "Production Flattrade debug endpoint is unavailable"
else
    fail "Production Flattrade debug endpoint should return HTTP 404; got $debug_status"
fi

account_json="$(curl --silent --show-error --connect-timeout 3 --max-time 5 "$API_URL/flattrade/account" 2>/dev/null || true)"
account_flags="$(printf '%s' "$account_json" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const x=JSON.parse(s);process.stdout.write(`${x.configured===true},${x.hasSession===true}`)}catch{process.stdout.write("unknown,unknown")}})' 2>/dev/null || echo 'unknown,unknown')"
IFS=, read -r API_CONFIGURED API_HAS_SESSION <<< "$account_flags"
if [ "$API_CONFIGURED" = "true" ]; then
    pass "Server-managed Flattrade credentials are configured (values suppressed)"
    broker_auth_status="$(http_status "$API_URL/flattrade/auth")"
    if [ "$broker_auth_status" = "302" ]; then
        pass "Flattrade authorization endpoint is available"
    else
        fail "Flattrade authorization endpoint expected HTTP 302 but returned $broker_auth_status"
    fi
elif [ "$API_CONFIGURED" = "false" ]; then
    warn "Server-managed Flattrade credentials are not configured"
else
    warn "Could not determine server-managed Flattrade configuration"
fi
if [ "$API_HAS_SESSION" = "true" ]; then
    pass "API reports a server-managed Flattrade session is present"
    fund_response="$(curl --silent --show-error --connect-timeout 3 --max-time 10 \
        --request POST --header "Origin: https://$DOMAIN" --header 'Content-Type: application/json' \
        --data '{}' "$API_URL/flattrade/fundLimit" 2>/dev/null || true)"
    fund_stat="$(printf '%s' "$fund_response" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const x=JSON.parse(s);process.stdout.write(String(x.stat||""))}catch{}})' 2>/dev/null || true)"
    if [ "$fund_stat" = "Ok" ]; then
        pass "Read-only Flattrade session check succeeded; account data suppressed"
    else
        warn "Flattrade session was not validated by the read-only account check"
    fi
else
    warn "No Flattrade session is available; broker checks are blocked pending user authentication"
fi

auth_status="$(http_status "$API_URL/flattrade/websocketData")"
if [ "$auth_status" = "403" ]; then
    pass "API rejects requests to internal credentials without the internal token"
fi

section "CADDY AND HTTPS"
if [ -f "$CADDYFILE" ]; then
    pass "Active Caddyfile exists"
else
    fail "Active Caddyfile is missing"
fi
if grep -Eiq '^[[:space:]]*basic_auth([[:space:]]|\{)|^[[:space:]]*basicauth([[:space:]]|\{)' "$CADDYFILE" 2>/dev/null; then
    pass "Active Caddy configuration contains a Basic Auth directive"
else
    fail "Active Caddy configuration does not enforce Basic Auth"
fi
if [ -f "$AUTH_FILE" ]; then
    auth_metadata="$(stat -c '%a:%U:%G' "$AUTH_FILE" 2>/dev/null || true)"
    auth_hash_count="$(awk 'NF == 2 && $2 ~ /^\$2[aby]\$/ { n++ } END { print n+0 }' "$AUTH_FILE" 2>/dev/null)"
    caddy_user="$(systemctl show caddy.service -p User --value 2>/dev/null || true)"
    caddy_group="$(systemctl show caddy.service -p Group --value 2>/dev/null || true)"
    auth_readable=0
    if [ -n "$caddy_user" ] && [ "$(id -u)" -eq 0 ] && command -v runuser >/dev/null 2>&1; then
        if runuser -u "$caddy_user" -- test -r "$AUTH_FILE"; then
            auth_readable=1
        fi
    elif [ -r "$AUTH_FILE" ]; then
        auth_readable=1
    fi
    if [ "$auth_metadata" = "640:root:$caddy_group" ] && [ "$auth_hash_count" -gt 0 ] && [ "$auth_readable" -eq 1 ]; then
        pass "Basic Auth file has restricted permissions and bcrypt entries"
    else
        fail "Basic Auth file permissions or hashed-entry format are invalid"
    fi
else
    fail "Basic Auth credential file is missing"
fi
if grep -Eiq 'remote_ip|client_ip|@untrusted' "$CADDYFILE" 2>/dev/null; then
    fail "Active Caddy configuration contains an IP allowlist"
else
    pass "Active Caddy configuration has no IP allowlist"
fi
if grep -Fq 'reverse_proxy 127.0.0.1:3001' "$CADDYFILE" 2>/dev/null; then
    pass "Caddy configuration routes API traffic to loopback port 3001"
else
    fail "Caddy configuration does not route to the Steadfast API on port 3001"
fi
if grep -Eq '@api[[:space:]]+path.*(/health|/flattrade/)' "$CADDYFILE" 2>/dev/null; then
    pass "Caddy API matcher includes the health and broker API routes"
else
    fail "Caddy API matcher is missing required API paths"
fi
if grep -Fq "$APP/dist" "$CADDYFILE" 2>/dev/null && grep -Eq 'try_files .*index\.html' "$CADDYFILE" 2>/dev/null; then
    pass "Caddy configuration serves frontend assets with SPA fallback"
else
    fail "Caddy configuration is missing the frontend root or SPA fallback"
fi
for header in X-Content-Type-Options X-Frame-Options Referrer-Policy; do
    if grep -Fq "$header" "$CADDYFILE" 2>/dev/null; then
        pass "Caddy security header is configured: $header"
    else
        warn "Caddy security header is missing: $header"
    fi
done
site_definitions="$(grep -Ec "^[[:space:]]*$DOMAIN[[:space:]]*\\{" "$CADDYFILE" 2>/dev/null || true)"
if [ "${site_definitions:-0}" -eq 1 ]; then
    pass "Exactly one site definition exists in the active Caddyfile"
else
    warn "Expected one site definition; found ${site_definitions:-0}"
fi
if caddy validate --config "$CADDYFILE" --adapter caddyfile >/dev/null 2>&1; then
    pass "Active Caddy configuration validates"
else
    fail "Active Caddy configuration failed validation"
fi

if getent ahosts "$DOMAIN" >/dev/null 2>&1; then
    pass "Public domain resolves in DNS"
else
    fail "Public domain does not resolve in DNS"
fi
http_redirect_status="$(http_status "http://$DOMAIN/")"
case "$http_redirect_status" in
    301|302|307|308) pass "HTTP redirects to HTTPS (HTTP $http_redirect_status)";;
    000) fail "HTTP endpoint did not respond";;
    *) fail "HTTP expected an HTTPS redirect but returned $http_redirect_status";;
esac
https_status="$(http_status "https://$DOMAIN/")"
if [ "$https_status" != "000" ]; then
    pass "HTTPS connected with certificate verification (HTTP $https_status)"
else
    fail "HTTPS connection or certificate verification failed"
fi
if [ "$https_status" = "401" ]; then
    pass "Unauthenticated public request is rejected by Basic Auth"
else
    fail "Unauthenticated public request expected HTTP 401 but returned $https_status"
fi
warn "Authenticated public request was not attempted; credentials are not read or supplied by diagnostics"
spa_status="$(http_status "https://$DOMAIN/manage-brokers")"
if [ "$spa_status" = "401" ]; then
    pass "Public SPA route is behind the expected Basic Auth gate"
else
    fail "Unauthenticated SPA route expected HTTP 401 but returned $spa_status"
fi
public_api_status="$(http_status "https://$DOMAIN/flattrade/account")"
if [ "$public_api_status" = "401" ]; then
    pass "Public API route is behind the expected Basic Auth gate"
else
    fail "Unauthenticated public API route expected HTTP 401 but returned $public_api_status"
fi
warn "Authenticated frontend asset and API proxy behavior was not tested without credentials"

section "PYTHON AND IPC"
if [ -x "$WS/.venv/bin/python" ]; then
    python_version="$("$WS/.venv/bin/python" --version 2>&1)"
    printf 'WebSocket runtime: %s\n' "$python_version"
    if "$WS/.venv/bin/python" -m pip check >/dev/null 2>&1; then
        pass "WebSocket virtual-environment dependencies pass pip check"
    else
        fail "WebSocket virtual-environment dependencies have conflicts"
    fi
    if "$WS/.venv/bin/python" -c 'import ast,pathlib; files=[p for p in pathlib.Path(".").rglob("*.py") if ".venv" not in p.parts]; [ast.parse(p.read_text(), filename=str(p)) for p in files]' >/dev/null 2>&1; then
        pass "Python source files parse successfully"
    else
        fail "Python syntax validation failed"
    fi
else
    fail "WebSocket virtual environment is unavailable"
fi

if [ -r "$WS_ENV" ]; then
    if grep -Eq '^API_BASE_URL=http://127\.0\.0\.1:3001/?$' "$WS_ENV"; then
        pass "WebSocket API base URL uses loopback port 3001"
    else
        fail "WebSocket API base URL is missing or not loopback port 3001"
    fi
    if grep -q '^WS_HOST=127\.0\.0\.1$' "$WS_ENV"; then
        pass "WebSocket host configuration is loopback-only"
    else
        fail "WebSocket host configuration is missing or not loopback-only"
    fi
    if grep -q '^WEBSOCKET_INTERNAL_TOKEN=.' "$WS_ENV"; then
        pass "Internal IPC token is configured; value suppressed"
    else
        fail "Internal IPC token is missing"
    fi
else
    warn "Run diagnostics with secure access to the WebSocket environment file to validate its settings"
fi
if [ -r "$API_ENV" ] && [ -r "$WS_ENV" ]; then
    api_internal_token="$(awk -F= '$1 == "WEBSOCKET_INTERNAL_TOKEN" { value=$2 } END { print value }' "$API_ENV")"
    ws_internal_token="$(awk -F= '$1 == "WEBSOCKET_INTERNAL_TOKEN" { value=$2 } END { print value }' "$WS_ENV")"
    if [ -n "$api_internal_token" ] && [ "$api_internal_token" = "$ws_internal_token" ]; then
        pass "API and WebSocket internal tokens match; values suppressed"
    else
        fail "API and WebSocket internal tokens are missing or do not match"
    fi
    unset api_internal_token ws_internal_token
else
    warn "Run diagnostics with secure access to both environment files to compare internal tokens"
fi
ws_recent_logs="$(journalctl -u steadfast-websocket.service --since '15 minutes ago' --no-pager -o cat 2>/dev/null || true)"
if printf '%s\n' "$ws_recent_logs" | grep -q 'Broker session received'; then
    pass "Python recently retrieved a broker session from the API"
else
    warn "Python has not logged a recent broker session retrieval"
fi
if printf '%s\n' "$ws_recent_logs" | grep -q 'app is connected'; then
    pass "Python recently logged the broker WebSocket open acknowledgement"
else
    warn "Broker WebSocket authentication acknowledgement is not verified"
fi
if printf '%s\n' "$ws_recent_logs" | grep -q 'Broker selection request received' &&
    printf '%s\n' "$ws_recent_logs" | grep -q 'Selected broker: flattrade' &&
    printf '%s\n' "$ws_recent_logs" | grep -q 'Broker session received'; then
    pass "Flattrade session update reached Python through the local IPC restart flow"
else
    warn "API-to-Python session-update IPC delivery is not verified in recent logs"
fi
unset ws_recent_logs
ws_requires="$(systemctl show steadfast-websocket.service -p Requires --value --no-pager 2>/dev/null || true)"
ws_after="$(systemctl show steadfast-websocket.service -p After --value --no-pager 2>/dev/null || true)"
if [[ " $ws_requires " == *" steadfast-api.service "* ]] && [[ " $ws_after " == *" steadfast-api.service "* ]]; then
    pass "WebSocket unit is ordered after and requires the API service"
else
    warn "WebSocket unit does not declare the expected API dependency"
fi

quote_timestamp="$(
    journalctl -u steadfast-websocket.service --since '24 hours ago' --no-pager -o json 2>/dev/null |
        python3 -c 'import datetime,json,re,sys; last=None; pattern=re.compile(r"^[A-Za-z0-9_.|:-]+:\\s*[-+]?\\d+(?:\\.\\d+)?$"); 
for line in sys.stdin:
 try:
  row=json.loads(line); message=row.get("MESSAGE","")
  if pattern.match(str(message)):
   last=int(row.get("__REALTIME_TIMESTAMP","0"))/1_000_000
 except (ValueError,TypeError):
  pass
print(datetime.datetime.fromtimestamp(last,datetime.timezone.utc).isoformat() if last else "")' 2>/dev/null || true
)"
if [ -n "$quote_timestamp" ]; then
    pass "Market-data quote observed; latest logged quote timestamp: $quote_timestamp"
else
    warn "No valid market-data quote timestamp is available in recent WebSocket logs"
fi
warn "WebSocket reconnection state is not exposed as a health metric"

section "SECURITY AND PUBLIC PORTS"
if [ -r "$API_ENV" ]; then
    trading_flag="$(awk -F= '$1 == "TRADING_ENABLED" { value=$2 } END { print value }' "$API_ENV")"
elif [ "$(id -u)" -eq 0 ]; then
    trading_flag="$(awk -F= '$1 == "TRADING_ENABLED" { value=$2 } END { print value }' "$API_ENV" 2>/dev/null)"
else
    trading_flag=""
fi
if [ "$trading_flag" = "false" ]; then
    pass "TRADING_ENABLED is false"
elif [ -z "$trading_flag" ]; then
    warn "TRADING_ENABLED could not be read; run diagnostics with appropriate file access"
else
    fail "TRADING_ENABLED is not false"
fi
if grep -q 'process.env.NODE_ENV === "production"' "$API/middleware/requireTradingEnabled.js" 2>/dev/null; then
    pass "API production trading gate is present"
else
    fail "API production trading gate was not found"
fi
if grep -Eiq 'placeOrder|cancelOrder|modifyOrder' "$API/middleware/requireTradingEnabled.js" 2>/dev/null; then
    warn "Trading gate source references order operations; review before changing"
else
    pass "Diagnostics do not call order placement, modification, or cancellation"
fi

section "AUTOMATED TESTS"
if run_project_command "$API" npm test >/dev/null 2>&1; then
    pass "API automated tests passed"
else
    fail "API automated tests failed"
fi
if run_project_command "$APP" npm run test:unit -- --run >/dev/null 2>&1; then
    pass "Frontend unit tests passed"
else
    fail "Frontend unit tests failed"
fi
if run_project_command "$WS" "$WS/.venv/bin/python" -m unittest discover >/dev/null 2>&1; then
    pass "Python unit tests passed"
else
    fail "Python unit tests failed"
fi
if run_project_command "$APP" env ESLINT_USE_FLAT_CONFIG=false \
    node node_modules/eslint/bin/eslint.js src/pages/app/ManageBrokersView.vue >/dev/null 2>&1; then
    pass "Modified frontend view passed ESLint without autofixing"
else
    warn "Modified frontend view did not pass ESLint; run the command directly to inspect diagnostics"
fi
if node -e 'const p=require(process.argv[1]); process.exit(p.scripts?.lint ? 0 : 1)' "$API/package.json" >/dev/null 2>&1; then
    pass "API lint script is available"
else
    warn "API package does not define a lint script"
fi
if find "$APP/src" -type f \( -name '*.ts' -o -name '*.tsx' \) -print -quit | grep -q .; then
    warn "TypeScript sources exist; no type-check was run by this diagnostic"
else
    pass "Frontend has no TypeScript sources requiring a type-check"
fi
if systemd-analyze verify "$ROOT/deploy/systemd/steadfast-api.service" \
    "$ROOT/deploy/systemd/steadfast-websocket.service" >/dev/null 2>&1; then
    pass "Checked-in systemd units validate"
else
    fail "Checked-in systemd unit validation failed"
fi
if bash -n "$ROOT/deploy/diagnostics.sh"; then
    pass "Deployment diagnostics script passes bash syntax validation"
else
    fail "Deployment diagnostics script has a Bash syntax error"
fi

section "SUMMARY"
printf 'PASS: %s\nFAIL: %s\nWARN: %s\n' "$PASS_COUNT" "$FAIL_COUNT" "$WARN_COUNT"
if [ "$FAIL_COUNT" -gt 0 ]; then
    printf 'OVERALL RESULT: FAIL\n'
    exit 1
elif [ "$WARN_COUNT" -gt 0 ]; then
    printf 'OVERALL RESULT: WARN\n'
else
    printf 'OVERALL RESULT: PASS\n'
fi
