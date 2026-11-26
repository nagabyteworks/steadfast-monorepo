
#!/bin/bash

# Steadfast project setup and launcher for macOS

# Stop services when the script exits.
API_PID=""
APP_PID=""
WS_PID=""

APP_REPO="https://github.com/nagabyteworks/steadfast-app.git"
API_REPO="https://github.com/nagabyteworks/steadfast-api.git"
WS_REPO="https://github.com/nagabyteworks/steadfast-websocket.git"

# Always execute from the directory containing this script.
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR" || exit 1

# Check required tools.
check_requirements() {
    for tool in git node npm python3; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "ERROR: $tool is not installed or not in PATH."
            return 1
        fi
    done
    return 0
}

# Clone a repository if it does not exist.
clone_repo() {
    local name="$1"
    local url="$2"

    if [ ! -d "$name/.git" ]; then
        echo "Cloning $name..."
        git clone "$url" "$name" || return 1
    else
        echo "$name already exists. Skipping clone."
    fi
}

# Install dependencies for all repositories.
install_dependencies() {
    echo "Installing app dependencies..."
    (cd steadfast-app && npm install) || return 1

    echo "Installing API dependencies..."
    (cd steadfast-api && npm install) || return 1

    echo "Setting up WebSocket Python environment..."
    
    cd steadfast-websocket || return 1

    # Create an isolated Python environment.
    if [ ! -d ".venv" ]; then
        python3 -m venv .venv || return 1
    fi

    # Install Python dependencies inside the virtual environment.
    source .venv/bin/activate

    python -m pip install --upgrade pip || return 1
    python -m pip install -r requirements.txt || return 1

    deactivate
    cd "$PROJECT_DIR" || return 1

    return 0
}

# Install everything.
install_all() {
    echo ""
    echo "Cloning repositories..."

    clone_repo "steadfast-app" "$APP_REPO" || return 1
    clone_repo "steadfast-api" "$API_REPO" || return 1
    clone_repo "steadfast-websocket" "$WS_REPO" || return 1

    echo ""
    echo "Installing dependencies..."

    install_dependencies || return 1

    echo ""
    echo "All repositories and dependencies installed successfully!"
}

# Update all repositories.
update_all() {
    local repos=("steadfast-app" "steadfast-api" "steadfast-websocket")

    for repo in "${repos[@]}"; do
        if [ ! -d "$repo/.git" ]; then
            echo "ERROR: $repo does not exist. Run Install All first."
            return 1
        fi

        echo ""
        echo "Updating $repo..."

        git -C "$repo" pull origin main || return 1
    done

    echo ""
    echo "Installing updated dependencies..."

    install_dependencies || return 1

    echo ""
    echo "Update completed successfully!"
}

# Stop only the services started by this script.
stop_services() {
    echo ""
    echo "Stopping services..."

    for pid in "$API_PID" "$APP_PID" "$WS_PID"; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
        fi
    done

    # Wait for child processes to exit.
    for pid in "$API_PID" "$APP_PID" "$WS_PID"; do
        if [ -n "$pid" ]; then
            wait "$pid" 2>/dev/null
        fi
    done

    API_PID=""
    APP_PID=""
    WS_PID=""

    echo "All services stopped."
}

# Start all three services.
run_services() {
    if [ ! -f "steadfast-api/server.js" ] ||
       [ ! -f "steadfast-websocket/main.py" ]; then
        echo "ERROR: Required project files are missing."
        echo "Run Install All first."
        return 1
    fi

    if [ ! -d "steadfast-websocket/.venv" ]; then
        echo "ERROR: Python virtual environment is missing."
        echo "Run Install All first."
        return 1
    fi

    echo ""
    echo "Starting API..."

    (
        cd steadfast-api
        exec node server.js
    ) > api.log 2>&1 &

    API_PID=$!

    echo "API started. PID: $API_PID"

    echo "Starting App..."

    (
        cd steadfast-app
        exec npm run dev
    ) > app.log 2>&1 &

    APP_PID=$!

    echo "App started. PID: $APP_PID"

    echo "Starting WebSocket server..."

    (
        cd steadfast-websocket
        source .venv/bin/activate
        exec python main.py
    ) > websocket.log 2>&1 &

    WS_PID=$!

    echo "WebSocket started. PID: $WS_PID"

    echo ""
    echo "Waiting for services to initialize..."
    sleep 5

    echo ""
    echo "Opening browser..."

    open http://localhost:3000
    open http://localhost:5173

    echo ""
    echo "Services are running."
    echo "API logs: api.log"
    echo "App logs: app.log"
    echo "WebSocket logs: websocket.log"
    echo ""
    echo "Press ENTER to stop all services."

    read -r

    stop_services
}

# Main menu.
while true; do
    echo ""
    echo "======================================"
    echo "       STEADFAST PROJECT MANAGER"
    echo "======================================"
    echo "1. Install all"
    echo "2. Update and install dependencies"
    echo "3. Run existing version"
    echo "4. Exit"
    echo "======================================"

    read -r -p "Enter your choice (1-4): " choice

    case "$choice" in
        1)
            check_requirements && install_all
            ;;
        2)
            check_requirements && update_all
            ;;
        3)
            check_requirements && run_services
            ;;
        4)
            stop_services
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please try again."
            ;;
    esac
done

