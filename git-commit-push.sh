
#!/usr/bin/env bash

# Steadfast: Commit and push all repositories to origin/main.
# This script does NOT deploy or restart services.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

SUBMODULES=(
    "steadfast-api"
    "steadfast-app"
    "steadfast-websocket"
)

die() {
    echo "ERROR: $*" >&2
    exit 1
}

trap 'echo "ERROR: Commit or push failed. Some repositories may already have been committed or pushed; inspect their state before retrying." >&2' ERR

# Verify repository, branch, remote and Git identity.
validate_repo() {
    local dir="$1"
    local branch
    local top_level

    top_level="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" ||
        die "Not a Git repository: $dir"
    [[ "$top_level" == "$dir" ]] ||
        die "Repository is not initialized at $dir"

    branch="$(git -C "$dir" branch --show-current)"

    [[ "$branch" == "main" ]] ||
        die "$dir is on '$branch', not main."

    git -C "$dir" remote get-url origin >/dev/null 2>&1 ||
        die "Missing origin remote in $dir"

    [[ -n "$(git -C "$dir" config user.name || true)" ]] ||
        die "Git user.name is not configured in $dir"

    [[ -n "$(git -C "$dir" config user.email || true)" ]] ||
        die "Git user.email is not configured in $dir"
}

# Stage, commit and push a repository.
commit_and_push() {
    local dir="$1"

    # Stage modified, deleted and untracked files.
    git -C "$dir" add -A

    if ! git -C "$dir" diff --cached --quiet; then
        git -C "$dir" commit --quiet -m "$message"
    else
        echo "No changes to commit in $dir."
    fi

    # Push local main to remote main.
    # No force push is performed.
    git -C "$dir" push origin main:main

    echo "Successfully pushed $dir."
}

echo "========================================"
echo "STEADFAST GIT COMMIT AND PUSH"
echo "========================================"

cd "$ROOT"

# Validate parent repository.
validate_repo "$ROOT"

# Validate every submodule before modifying anything.
for submodule in "${SUBMODULES[@]}"; do

    dir="$ROOT/$submodule"

    [[ -d "$dir" ]] ||
        die "Submodule directory not found: $dir"

    validate_repo "$dir"

done

echo ""
echo "Preflight validation successful."
echo "All repositories are on main."
echo "All modified, deleted and untracked files in these repositories will be staged."

read -r -p "Commit message for all repositories: " message ||
    die "Could not read commit message."
[[ "$message" =~ [^[:space:]] ]] ||
    die "Commit message cannot be empty."

# Step 1: Commit and push submodules.
for submodule in "${SUBMODULES[@]}"; do

    commit_and_push "$ROOT/$submodule"

done

# Step 2: Commit and push parent repository with updated submodule references.
echo ""
echo "========================================"
echo "UPDATING PARENT REPOSITORY"
echo "========================================"

commit_and_push "$ROOT"

echo ""
echo "========================================"
echo "ALL REPOSITORIES PUSHED SUCCESSFULLY"
echo "========================================"

echo ""
echo "IMPORTANT: No deployment or service restart was performed."
