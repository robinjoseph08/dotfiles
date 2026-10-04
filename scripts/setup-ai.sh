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

migrate_skill_entries() {
  local source_directory=$1
  local entry
  local destination
  local temporary
  local candidate

  if [ ! -d "$source_directory" ]; then
    return
  fi

  for entry in "$source_directory"/*; do
    destination="$AI_DIR/skills/$(basename "$entry")"

    if [ -e "$destination" ] || [ -L "$destination" ]; then
      continue
    fi

    if [ -L "$entry" ] && [ ! -e "$entry" ]; then
      continue
    fi

    temporary=$(mktemp -d "$AI_DIR/skills/.skill-migration.XXXXXX")
    candidate="$temporary/$(basename "$entry")"
    echo "Importing locally installed skill $(basename "$entry")..."

    if ! cp -RH "$entry" "$candidate"; then
      rm -rf "$temporary"
      return 1
    fi

    if ! mv "$candidate" "$destination"; then
      rm -rf "$temporary"
      return 1
    fi

    rmdir "$temporary"
  done
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
    "$AI_DIR/AGENTS.md" \
    "$AI_DIR/claude/settings.json" \
    "$AI_DIR/claude/statusline.sh" \
    "$AI_DIR/claude/commands/squash-merge-worktree.md" \
    "$AI_DIR/pi/APPEND_SYSTEM.md" \
    "$AI_DIR/pi/settings.json" \
    "$AI_DIR/pi/models.json" \
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
  validate_single_json_object "$AI_DIR/pi/models.json"
  validate_single_json_object "$AI_DIR/pi/keybindings.json"

  for path in "$AI_DIR/pi/themes"/*.json; do
    validate_single_json_object "$path"
  done
}

preflight_existing_json() {
  local destination=$1

  if [ -e "$destination" ] || [ -L "$destination" ]; then
    validate_single_json_object "$destination"
  fi
}

preflight_sources
preflight_existing_json "$HOME/.pi/agent/settings.json"
preflight_existing_json "$HOME/.pi/agent/models.json"

echo
echo "Setting up AI tools..."

# Shared instructions go in each agent's global slot. Claude Code has no
# user-level AGENTS.md, so it reads them through ~/.claude/CLAUDE.md.
link_path "$AI_DIR/AGENTS.md" "$HOME/.claude/CLAUDE.md"
link_path "$AI_DIR/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"
link_path "$AI_DIR/AGENTS.md" "$HOME/.codex/AGENTS.md"

# ~/AGENTS.md used to hold the shared instructions, but both agents treat it as a
# project file for anything under $HOME, which loaded the instructions twice.
for old_source in "$AI_DIR/AGENTS.md" "$AI_DIR/CLAUDE.md"; do
  if [ -L "$HOME/AGENTS.md" ] && [ "$(readlink "$HOME/AGENTS.md")" = "$old_source" ]; then
    echo "Removing $HOME/AGENTS.md..."
    rm "$HOME/AGENTS.md"
  fi
done

# Shared skills are canonical in this repository. Import skills from the old
# per-entry layout before linking the whole directory into both agent locations.
migrate_skill_entries "$HOME/.agents/skills"
migrate_skill_entries "$HOME/.claude/skills"
link_path "$AI_DIR/skills" "$HOME/.agents/skills"
link_path "$AI_DIR/skills" "$HOME/.claude/skills"

# Claude Code configuration that is safe to share.
link_path "$AI_DIR/claude/settings.json" "$HOME/.claude/settings.json"
link_path "$AI_DIR/claude/statusline.sh" "$HOME/.claude/statusline.sh"
link_directory_entries "$AI_DIR/claude/commands" "$HOME/.claude/commands"

# Pi configuration. Authentication, sessions, trust, and installed package caches stay local.
link_path "$AI_DIR/pi/APPEND_SYSTEM.md" "$HOME/.pi/agent/APPEND_SYSTEM.md"
link_path "$AI_DIR/pi/settings.json" "$HOME/.pi/agent/settings.json"
link_path "$AI_DIR/pi/models.json" "$HOME/.pi/agent/models.json"
link_path "$AI_DIR/pi/keybindings.json" "$HOME/.pi/agent/keybindings.json"
link_path "$AI_DIR/pi/extensions" "$HOME/.pi/agent/extensions"
link_directory_entries "$AI_DIR/pi/themes" "$HOME/.pi/agent/themes"

echo "...done"
echo
