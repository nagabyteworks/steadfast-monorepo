
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

# Verify repository, branch, remote and Git identity.
validate_repo() {
    local dir="$1"
    local branch

    git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
        die "Not a Git repository: $dir"

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

# Display repository changes.
show_changes() {
    local dir="$1"

    echo ""
    echo "========================================"
    echo "Repository: $dir"
    echo "========================================"

    git -C "$dir" status --short --branch
    git -C "$dir" diff --stat
    git -C "$dir" diff --cached --stat
}

# Stage, review, commit and push a repository.
commit_and_push() {
    local dir="$1"
    local message
    local answer

    show_changes "$dir"

    read -r -p "Stage and commit ALL changes in $dir? [y/N]: " answer

    [[ "$answer" == "y" || "$answer" == "Y" ]] ||
        die "Cancelled by user."

    # Stage modified, deleted and untracked files.
    git -C "$dir" add -A

    echo ""
    echo "Files staged for commit:"
    git -C "$dir" status --short

    echo ""
    git -C "$dir" diff --cached --stat

    # Review the actual staged changes before committing.
    git -C "$dir" diff --cached

    if ! git -C "$dir" diff --cached --quiet; then

        read -r -p "Commit message for $dir: " message

        [[ -n "$message" ]] ||
            die "Commit message cannot be empty."

        git -C "$dir" commit -m "$message"

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

# Step 1: Commit and push submodules.
for submodule in "${SUBMODULES[@]}"; do

    commit_and_push "$ROOT/$submodule"

done

# Step 2: Update parent repository submodule references.
echo ""
echo "========================================"
echo "UPDATING PARENT REPOSITORY"
echo "========================================"

show_changes "$ROOT"

read -r -p "Stage and commit parent repository changes? [y/N]: " answer

[[ "$answer" == "y" || "$answer" == "Y" ]] ||
    die "Cancelled before parent repository commit."

# Stage updated submodule references and other parent changes.
git -C "$ROOT" add -A

echo ""
echo "Parent repository staged changes:"
git -C "$ROOT" status --short
git -C "$ROOT" diff --cached

if ! git -C "$ROOT" diff --cached --quiet; then

    read -r -p "Parent repository commit message: " message

    [[ -n "$message" ]] ||
        die "Commit message cannot be empty."

    git -C "$ROOT" commit -m "$message"

else
    echo "No parent changes to commit."
fi

# Step 3: Push parent repository.
git -C "$ROOT" push origin main:main

echo ""
echo "========================================"
echo "ALL REPOSITORIES PUSHED SUCCESSFULLY"
echo "========================================"

echo ""
echo "Parent repository:"
git -C "$ROOT" status --short --branch

echo ""
echo "Submodule revisions:"
git -C "$ROOT" submodule status

echo ""
echo "IMPORTANT: No deployment or service restart was performed."
