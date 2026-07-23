#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DOTFILES_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
SETUP="$SCRIPT_DIR/setup-ai.sh"
TEMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TEMP_ROOT"' EXIT

assert_untouched() {
  local home=$1
  local expected=$2

  [ "$(cat "$home/.claude/CLAUDE.md")" = "$expected" ]
  [ ! -e "$home/old" ]
}

test_missing_sources_fail_before_mutation() {
  local home="$TEMP_ROOT/missing-source-home"
  mkdir -p "$home/.claude"
  printf 'original instructions\n' > "$home/.claude/CLAUDE.md"

  if HOME="$home" OLD_DIR="$home/old" DOTFILES_DIR="$TEMP_ROOT/missing-dotfiles" "$SETUP" >/dev/null 2>&1; then
    echo "Expected missing AI sources to fail preflight." >&2
    exit 1
  fi

  assert_untouched "$home" "original instructions"
}

test_invalid_pi_settings_fail_before_mutation() {
  local home="$TEMP_ROOT/invalid-json-home"
  mkdir -p "$home/.claude" "$home/.pi/agent"
  printf 'original instructions\n' > "$home/.claude/CLAUDE.md"
  printf '{}\n{"extraDocument":true}\n' > "$home/.pi/agent/settings.json"

  if HOME="$home" OLD_DIR="$home/old" DOTFILES_DIR="$DOTFILES_DIR" "$SETUP" >/dev/null 2>&1; then
    echo "Expected multiple Pi settings documents to fail preflight." >&2
    exit 1
  fi

  assert_untouched "$home" "original instructions"
}

test_app_icon_skill_disables_automatic_invocation() {
  grep -Fxq 'disable-model-invocation: true' "$DOTFILES_DIR/ai/skills/app-icon-design/SKILL.md"
}

test_migration_and_idempotence() {
  local home="$TEMP_ROOT/migration-home"
  local external="$TEMP_ROOT/external"
  local backups_before
  local backups_after

  mkdir -p \
    "$home/.pi/agent/extensions/local-only" \
    "$home/.agents" \
    "$external/skills"
  printf '{"lastChangelogVersion":"9.9.9","theme":"old","machineOnly":true}\n' > "$home/.pi/agent/settings.json"
  printf 'local extension\n' > "$home/.pi/agent/extensions/local-only/index.ts"
  touch "$external/skills/sentinel"
  ln -s "$external/skills" "$home/.agents/skills"

  HOME="$home" OLD_DIR="$home/old" DOTFILES_DIR="$DOTFILES_DIR" "$SETUP" >/dev/null

  [ ! -L "$home/.agents/skills" ]
  [ -f "$external/skills/sentinel" ]
  [ "$(readlink "$home/.pi/agent/extensions")" = "$DOTFILES_DIR/ai/pi/extensions" ]
  [ -f "$home/old/ai/.pi/agent/extensions/local-only/index.ts" ]
  [ "$(jq -r .lastChangelogVersion "$home/.pi/agent/settings.json")" = "9.9.9" ]
  [ "$(jq -r .theme "$home/.pi/agent/settings.json")" = "robin-iterm" ]
  [ "$(jq -r .machineOnly "$home/.pi/agent/settings.json")" = "true" ]
  [ ! -e "$home/.codex/skills" ]
  [ ! -e "$home/.codex/rules" ]

  backups_before=$(find "$home/old" -mindepth 1 | wc -l | tr -d ' ')
  HOME="$home" OLD_DIR="$home/old" DOTFILES_DIR="$DOTFILES_DIR" "$SETUP" >/dev/null
  backups_after=$(find "$home/old" -mindepth 1 | wc -l | tr -d ' ')
  [ "$backups_before" = "$backups_after" ]
}

test_missing_sources_fail_before_mutation
test_invalid_pi_settings_fail_before_mutation
test_app_icon_skill_disables_automatic_invocation
test_migration_and_idempotence

echo "AI setup tests passed."
