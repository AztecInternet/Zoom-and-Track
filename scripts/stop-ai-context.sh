#!/bin/bash

PID_FILE="/tmp/flowtrack-ai-context.pid"

if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  kill "$PID" 2>/dev/null && echo "Stopped watcher (PID $PID)"
  rm "$PID_FILE"
else
  echo "No watcher running"
fi
