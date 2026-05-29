#!/bin/bash

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

CONTEXT_DIR="AI_CONTEXT"
MAPS_DIR="$CONTEXT_DIR/maps"

mkdir -p "$CONTEXT_DIR" "$MAPS_DIR"

DATE_NOW="$(date '+%Y-%m-%d %H:%M:%S')"

SOURCE_DIRS=(App Models ViewModels Managers Services Views)

swift_files() {
  find "${SOURCE_DIRS[@]}" -name "*.swift" -type f 2>/dev/null | sort
}

write_file_map_section() {
  local file="$1"
  local lines imports types funcs states

  lines=$(wc -l < "$file" | tr -d ' ')

  echo "### $file"
  echo "- Lines: $lines"

  imports=$(grep -E '^import ' "$file" | sed 's/^/- /' | head -15)
  [ -n "$imports" ] && echo "- Imports:" && echo "$imports"

  types=$(grep -nE '^[[:space:]]*(struct|class|enum|protocol|extension)[[:space:]]' "$file" | sed 's/^/- Line /' | head -50)
  [ -n "$types" ] && echo "- Types:" && echo "$types"

  funcs=$(grep -nE '^[[:space:]]*(private |fileprivate |internal |public |open )?(static )?(func|var|let)[[:space:]]' "$file" | sed 's/^/- Line /' | head -80)
  [ -n "$funcs" ] && echo "- Functions / Vars:" && echo "$funcs"

  states=$(grep -nE '@(State|Binding|Environment|Observable|ObservedObject|StateObject|Published|AppStorage|SceneStorage)' "$file" | sed 's/^/- Line /' | head -40)
  [ -n "$states" ] && echo "- SwiftUI State:" && echo "$states"

  echo
}

write_symbols_section() {
  local file="$1"

  echo "## $file"
  grep -nE '^[[:space:]]*(struct|class|enum|protocol|extension|func)[[:space:]]' "$file" | sed 's/^/- Line /'
  echo
}

write_full_map() {
  local title="$1"
  local output="$2"

  {
    echo "# $title"
    echo
    echo "Generated: $DATE_NOW"
    echo
    echo "## Swift Files"
    echo

    swift_files | while read -r file; do
      [ -f "$file" ] && write_file_map_section "$file"
    done
  } > "$output"
}

write_focused_map() {
  local output="$1"
  local title="$2"
  shift 2

  local temp_file
  temp_file="$(mktemp)"

  swift_files | while read -r file; do
    [ -f "$file" ] || continue

    for pattern in "$@"; do
      if [[ "$file" == *"$pattern"* ]]; then
        echo "$file" >> "$temp_file"
        break
      fi
    done
  done

  sort -u "$temp_file" > "$temp_file.sorted"

  {
    echo "# $title"
    echo
    echo "Generated: $DATE_NOW"
    echo
    echo "## Files"
    echo

    if [ ! -s "$temp_file.sorted" ]; then
      echo "_No matching Swift files found._"
      echo
    else
      while read -r file; do
        [ -f "$file" ] && write_file_map_section "$file"
      done < "$temp_file.sorted"
    fi
  } > "$output"

  rm -f "$temp_file" "$temp_file.sorted"
}

write_full_map "Project Map" "$CONTEXT_DIR/project-map.md"

{
  echo "# Swift Symbols"
  echo
  echo "Generated: $DATE_NOW"
  echo

  swift_files | while read -r file; do
    [ -f "$file" ] && write_symbols_section "$file"
  done
} > "$CONTEXT_DIR/swift-symbols.md"

write_focused_map "$MAPS_DIR/app-map.md"               "App Map"               "App/"
write_focused_map "$MAPS_DIR/models-map.md"            "Models Map"            "Models/"
write_focused_map "$MAPS_DIR/viewmodels-map.md"        "ViewModels Map"        "ViewModels/"
write_focused_map "$MAPS_DIR/managers-map.md"          "Managers Map"          "Managers/"
write_focused_map "$MAPS_DIR/services-map.md"          "Services Map"          "Services/"
write_focused_map "$MAPS_DIR/views-shared-map.md"      "Shared Views Map"      "Views/Shared/"

write_focused_map "$MAPS_DIR/onboarding-map.md"        "Onboarding Map"        "Onboarding" "HelpMode" "ContentView"
write_focused_map "$MAPS_DIR/capture-map.md"           "Capture Map"           "Capture" "CaptureSetup"
write_focused_map "$MAPS_DIR/review-map.md"            "Review & Timeline Map" "Review" "Timeline" "Marker"
write_focused_map "$MAPS_DIR/export-map.md"            "Export Map"            "Export"
write_focused_map "$MAPS_DIR/smart-suggestions-map.md" "Smart Suggestions Map" "SmartSetup"
write_focused_map "$MAPS_DIR/theme-map.md"             "Theme Map"             "Theme" "ColourLab" "Accent"

cat > "$CONTEXT_DIR/README.md" <<EOF
# AI Context Guide

Generated: $DATE_NOW

## Workflow

1. Read this README first.
2. Read the most relevant focused map from AI_CONTEXT/maps/ relative to the project root.
3. Only then open the specific .swift files needed.
4. Use AI_CONTEXT/project-map.md or AI_CONTEXT/swift-symbols.md only as a last resort.

## Focused Maps

- AI_CONTEXT/maps/app-map.md
- AI_CONTEXT/maps/models-map.md
- AI_CONTEXT/maps/viewmodels-map.md
- AI_CONTEXT/maps/managers-map.md
- AI_CONTEXT/maps/services-map.md
- AI_CONTEXT/maps/views-shared-map.md
- AI_CONTEXT/maps/onboarding-map.md
- AI_CONTEXT/maps/capture-map.md
- AI_CONTEXT/maps/review-map.md
- AI_CONTEXT/maps/export-map.md
- AI_CONTEXT/maps/smart-suggestions-map.md
- AI_CONTEXT/maps/theme-map.md

## Full Fallbacks

- AI_CONTEXT/project-map.md
- AI_CONTEXT/swift-symbols.md

## Codex Guidance

- Use focused maps as navigation indexes only.
- Do not read every file listed in a map unless the task genuinely requires it.
- Inspect the smallest set of real Swift files needed.
- Do not scan the whole project.
- Do not use git diff, git diff --cached, or git status unless Paul explicitly asks.
EOF

echo "Updated AI context:"
echo "$CONTEXT_DIR/README.md"
echo "$CONTEXT_DIR/project-map.md"
echo "$CONTEXT_DIR/swift-symbols.md"
echo "$MAPS_DIR/app-map.md"
echo "$MAPS_DIR/models-map.md"
echo "$MAPS_DIR/viewmodels-map.md"
echo "$MAPS_DIR/managers-map.md"
echo "$MAPS_DIR/services-map.md"
echo "$MAPS_DIR/views-shared-map.md"
echo "$MAPS_DIR/onboarding-map.md"
echo "$MAPS_DIR/capture-map.md"
echo "$MAPS_DIR/review-map.md"
echo "$MAPS_DIR/export-map.md"
echo "$MAPS_DIR/smart-suggestions-map.md"
echo "$MAPS_DIR/theme-map.md"
