#!/bin/bash

PID_FILE="/tmp/flowtrack-ai-context.pid"

# Kill any existing watcher
if [ -f "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE")
  kill "$OLD_PID" 2>/dev/null
fi

# Save current PID
echo $$ > "$PID_FILE"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WATCH_DIRS=(
  "$PROJECT_ROOT/App"
  "$PROJECT_ROOT/Models"
  "$PROJECT_ROOT/ViewModels"
  "$PROJECT_ROOT/Managers"
  "$PROJECT_ROOT/Services"
  "$PROJECT_ROOT/Views"
)

echo "Watching Swift files in:"
for dir in "${WATCH_DIRS[@]}"; do
  [ -d "$dir" ] || continue
  echo "$dir"
done
echo
echo "Press CTRL+C to stop."

fswatch -o \
  "${WATCH_DIRS[@]}" \
| while read -r change; do
    "$PROJECT_ROOT/scripts/update-ai-context.sh"
  done
