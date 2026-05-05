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

echo "Watching Swift files in:"
echo "$PROJECT_ROOT"
echo
echo "Press CTRL+C to stop."

fswatch -o \
  --exclude "$PROJECT_ROOT/.git" \
  --exclude "$PROJECT_ROOT/AI_CONTEXT" \
  --exclude "$PROJECT_ROOT/DerivedData" \
  "$PROJECT_ROOT" \
| while read -r change; do
    "$PROJECT_ROOT/scripts/update-ai-context.sh"
  done
