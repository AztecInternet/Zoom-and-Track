#!/bin/bash

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTEXT_DIR="$PROJECT_ROOT/AI_CONTEXT"
OUTPUT_FILE="$CONTEXT_DIR/project-map.md"
SYMBOLS_FILE="$CONTEXT_DIR/swift-symbols.md"
SOURCE_DIRS=(
  "$PROJECT_ROOT/App"
  "$PROJECT_ROOT/Models"
  "$PROJECT_ROOT/ViewModels"
  "$PROJECT_ROOT/Managers"
  "$PROJECT_ROOT/Services"
  "$PROJECT_ROOT/Views"
)

mkdir -p "$CONTEXT_DIR"

DATE_NOW="$(date '+%Y-%m-%d %H:%M:%S')"

swift_files() {
  for dir in "${SOURCE_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    find "$dir" -name "*.swift" -type f -print
  done | sort
}

{
  echo "# Project Map"
  echo
  echo "Generated: $DATE_NOW"
  echo
  echo "## Swift Files"
  echo

  while read -r file; do
      rel="${file#$PROJECT_ROOT/}"
      lines=$(wc -l < "$file" | tr -d ' ')
      echo "### $rel"
      echo "- Lines: $lines"

      imports=$(grep -E '^import ' "$file" | sed 's/^/- /' | head -20)
      if [ -n "$imports" ]; then
        echo "- Imports:"
        echo "$imports"
      fi

      types=$(grep -nE '^[[:space:]]*(struct|class|enum|protocol|extension)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$file" | sed 's/^/- Line /' | head -80)
      if [ -n "$types" ]; then
        echo "- Types:"
        echo "$types"
      fi

      functions=$(grep -nE '^[[:space:]]*(private |fileprivate |internal |public |open )?(static )?(func|var)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$file" | sed 's/^/- Line /' | head -120)
      if [ -n "$functions" ]; then
        echo "- Functions / Vars:"
        echo "$functions"
      fi

      states=$(grep -nE '@(State|Binding|Environment|Observable|ObservedObject|StateObject|Published|AppStorage|SceneStorage)' "$file" | sed 's/^/- Line /' | head -80)
      if [ -n "$states" ]; then
        echo "- SwiftUI State / Bindings:"
        echo "$states"
      fi

      echo
    done < <(swift_files)
} > "$OUTPUT_FILE"

{
  echo "# Swift Symbols"
  echo
  echo "Generated: $DATE_NOW"
  echo

  while read -r file; do
      rel="${file#$PROJECT_ROOT/}"
      echo "## $rel"
      echo

      grep -nE '^[[:space:]]*(struct|class|enum|protocol|extension|func)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$file" \
        | sed 's/^/- Line /'

      echo
    done < <(swift_files)
} > "$SYMBOLS_FILE"

echo "Updated AI context:"
echo "$OUTPUT_FILE"
echo "$SYMBOLS_FILE"
