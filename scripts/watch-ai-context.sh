#!/bin/bash

PID_FILE="/tmp/flowtrack-ai-context.pid"

if [ -f "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE")
  kill "$OLD_PID" 2>/dev/null
fi

echo $$ > "$PID_FILE"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPDATE_SCRIPT="$PROJECT_ROOT/scripts/update-ai-context.sh"

WATCH_DIRS=(
  "$PROJECT_ROOT/App"
  "$PROJECT_ROOT/Models"
  "$PROJECT_ROOT/ViewModels"
  "$PROJECT_ROOT/Managers"
  "$PROJECT_ROOT/Services"
  "$PROJECT_ROOT/Views"
)

echo "Project root:"
echo "$PROJECT_ROOT"
echo

echo "Update script:"
echo "$UPDATE_SCRIPT"
echo

if [ ! -f "$UPDATE_SCRIPT" ]; then
  echo "ERROR: update script not found."
  exit 1
fi

chmod +x "$UPDATE_SCRIPT"

echo "Running initial AI context update..."
"$UPDATE_SCRIPT"
echo

echo "Watching Swift files in:"
for dir in "${WATCH_DIRS[@]}"; do
  if [ -d "$dir" ]; then
    echo "$dir"
  else
    echo "Missing: $dir"
  fi
done

echo
echo "Press CTRL+C to stop."

fswatch -o "${WATCH_DIRS[@]}" | while read -r change; do
  echo
  echo "Swift change detected. Updating AI context..."
  "$UPDATE_SCRIPT"
done
