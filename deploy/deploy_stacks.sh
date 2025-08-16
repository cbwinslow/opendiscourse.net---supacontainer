#!/usr/bin/env bash
# Simple wrapper to deploy all stacks placed under deploy/stacks/
# Usage: sudo ./deploy/deploy_stacks.sh [start|stop|restart|status] [stack-name]
set -euo pipefail

ACTION="${1:-start}"
STACK_NAME="${2:-}"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_DIR="${BASE_DIR}/stacks"

if [ ! -d "$STACKS_DIR" ]; then
  echo "No stacks directory found at $STACKS_DIR"
  exit 1
fi

run_compose() {
  local stack_path="$1"
  local cmd="$2"
  echo "==> [$stack_path] docker compose $cmd"
  pushd "$stack_path" >/dev/null 2>&1
  # Ensure .env file is present (fallback to parent's .env if available)
  if [ ! -f .env ] && [ -f "$BASE_DIR/../.env" ]; then
    cp "$BASE_DIR/../.env" .env || true
  fi
  case "$cmd" in
    start)
      docker compose up -d --remove-orphans
      ;;
    stop)
      docker compose down
      ;;
    restart)
      docker compose down
      docker compose up -d --remove-orphans
      ;;
    status)
      docker compose ps
      ;;
    *)
      echo "Unknown command: $cmd"
      popd >/dev/null 2>&1
      return 1
      ;;
  esac
  popd >/dev/null
}

# If a specific stack name was provided, operate only on that stack.
if [ -n "$STACK_NAME" ]; then
  STACK_PATH="$STACKS_DIR/$STACK_NAME"
  if [ -d "$STACK_PATH" ]; then
    run_compose "$STACK_PATH" "$ACTION"
  else
    echo "Stack '$STACK_NAME' not found in $STACKS_DIR"
    exit 1
  fi
  exit 0
fi

# Otherwise iterate all first-level stack directories
for d in "$STACKS_DIR"/*/; do
  [ -d "$d" ] || continue
  # strip trailing slash for nicer output
  run_compose "${d%/}" "$ACTION" || echo "Warning: command failed for stack ${d%/}"
done

echo "All stacks processed."