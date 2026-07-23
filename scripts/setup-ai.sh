#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DOTFILES_DIR=${DOTFILES_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}
AI_DIR="$DOTFILES_DIR/ai"
OLD_DIR=${OLD_DIR:-"$DOTFILES_DIR/old"}

shopt -s nullglob

backup_path() {
  local destination=$1
  local relative=${destination#"$HOME"/}
  local backup="$OLD_DIR/ai/$relative"
  local suffix=1

  mkdir -p "$(dirname "$backup")"

  while [ -e "$backup" ] || [ -L "$backup" ]; do
    backup="$OLD_DIR/ai/$relative.$suffix"
    suffix=$((suffix + 1))
  done

  echo "Backing up $destination to $backup..."
  mv "$destination" "$backup"
}

link_path() {
  local source=$1
  local destination=$2

  mkdir -p "$(dirname "$destination")"

  if [ -L "$destination" ] && [ "$(readlink "$destination")" = "$source" ]; then
    return
  fi

  if [ -e "$destination" ] || [ -L "$destination" ]; then
    backup_path "$destination"
  fi

  echo "Linking $destination..."
  ln -s "$source" "$destination"
}

ensure_real_directory() {
  local directory=$1

  if [ -L "$directory" ] || { [ -e "$directory" ] && [ ! -d "$directory" ]; }; then
    backup_path "$directory"
  fi

  mkdir -p "$directory"
}

link_directory_entries() {
  local source_directory=$1
  local destination_directory=$2
  local entry

  ensure_real_directory "$destination_directory"

  for entry in "$source_directory"/*; do
    link_path "$entry" "$destination_directory/$(basename "$entry")"
  done
}

copy_if_missing() {
  local source=$1
  local destination=$2

  if [ -e "$destination" ] || [ -L "$destination" ]; then
    echo "Leaving existing $destination untouched."
    return
  fi

  mkdir -p "$(dirname "$destination")"
  echo "Copying starter config to $destination..."
  cp "$source" "$destination"
}

require_source_file() {
  local path=$1

  if [ ! -f "$path" ]; then
    echo "Required AI configuration file is missing: $path" >&2
    exit 1
  fi
}

require_source_directory() {
  local path=$1

  if [ ! -d "$path" ]; then
    echo "Required AI configuration directory is missing: $path" >&2
    exit 1
  fi
}

validate_single_json_object() {
  local path=$1

  if ! jq -s -e 'length == 1 and (.[0] | type == "object")' "$path" >/dev/null; then
    echo "Expected one JSON object in $path." >&2
    exit 1
  fi
}

preflight_sources() {
  local path

  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required to set up AI tools." >&2
    exit 1
  fi

  for path in \
    "$AI_DIR/CLAUDE.md" \
    "$AI_DIR/claude/settings.json" \
    "$AI_DIR/claude/statusline.sh" \
    "$AI_DIR/claude/commands/squash-merge-worktree.md" \
    "$AI_DIR/pi/AGENTS.md" \
    "$AI_DIR/pi/settings.json" \
    "$AI_DIR/pi/keybindings.json" \
    "$AI_DIR/pi/themes/robin-iterm.json" \
    "$AI_DIR/pi/extensions/claude-style-footer/index.ts" \
    "$AI_DIR/pi/extensions/history-search/index.ts" \
    "$AI_DIR/pi/extensions/inline-skills/index.ts" \
    "$AI_DIR/pi/extensions/nested-context-files/index.ts" \
    "$AI_DIR/skills/ship-it/SKILL.md"; do
    require_source_file "$path"
  done

  for path in \
    "$AI_DIR/skills" \
    "$AI_DIR/claude/commands" \
    "$AI_DIR/pi/extensions" \
    "$AI_DIR/pi/themes"; do
    require_source_directory "$path"
  done

  validate_single_json_object "$AI_DIR/claude/settings.json"
  validate_single_json_object "$AI_DIR/pi/settings.json"
  validate_single_json_object "$AI_DIR/pi/keybindings.json"

  for path in "$AI_DIR/pi/themes"/*.json; do
    validate_single_json_object "$path"
  done
}

preflight_json_settings() {
  local source=$1
  local destination=$2

  if [ ! -e "$destination" ] && [ ! -L "$destination" ]; then
    return
  fi

  validate_single_json_object "$destination"
  if ! jq -s -e 'length == 2 and (.[0] * .[1] | type == "object")' "$destination" "$source" >/dev/null; then
    echo "Could not merge $destination; leaving all AI configuration untouched." >&2
    exit 1
  fi
}

merge_json_settings() {
  local source=$1
  local destination=$2
  local temporary

  if [ ! -e "$destination" ] && [ ! -L "$destination" ]; then
    copy_if_missing "$source" "$destination"
    return
  fi

  temporary=$(mktemp)
  if ! jq -s '.[0] * .[1]' "$destination" "$source" > "$temporary"; then
    rm -f "$temporary"
    echo "Could not merge $destination; leaving it untouched." >&2
    exit 1
  fi

  if [ ! -L "$destination" ] && cmp -s "$destination" "$temporary"; then
    rm -f "$temporary"
    return
  fi

  backup_path "$destination"
  echo "Updating managed settings in $destination..."
  mv "$temporary" "$destination"
}

preflight_sources
preflight_json_settings "$AI_DIR/pi/settings.json" "$HOME/.pi/agent/settings.json"

echo
echo "Setting up AI tools..."

# Shared instructions used by Claude Code and agents that discover ~/AGENTS.md.
link_path "$AI_DIR/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
link_path "$AI_DIR/CLAUDE.md" "$HOME/AGENTS.md"

# Shared skills are canonical in this repository and linked into both locations.
link_directory_entries "$AI_DIR/skills" "$HOME/.agents/skills"
link_directory_entries "$AI_DIR/skills" "$HOME/.claude/skills"

# Claude Code configuration that is safe to share.
link_path "$AI_DIR/claude/settings.json" "$HOME/.claude/settings.json"
link_path "$AI_DIR/claude/statusline.sh" "$HOME/.claude/statusline.sh"
link_directory_entries "$AI_DIR/claude/commands" "$HOME/.claude/commands"

# Pi configuration. Authentication, sessions, trust, and installed package caches stay local.
link_path "$AI_DIR/pi/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"
merge_json_settings "$AI_DIR/pi/settings.json" "$HOME/.pi/agent/settings.json"
link_path "$AI_DIR/pi/keybindings.json" "$HOME/.pi/agent/keybindings.json"
link_path "$AI_DIR/pi/extensions" "$HOME/.pi/agent/extensions"
link_directory_entries "$AI_DIR/pi/themes" "$HOME/.pi/agent/themes"

echo "...done"
echo
