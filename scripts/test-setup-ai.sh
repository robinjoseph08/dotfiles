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
  local fixture="$TEMP_ROOT/migration-dotfiles"
  local external_skill="$TEMP_ROOT/external-linked-skill"
  local backups_before
  local backups_after

  mkdir -p "$fixture"
  cp -R "$DOTFILES_DIR/ai" "$fixture/ai"

  mkdir -p \
    "$external_skill" \
    "$home/.pi/agent/extensions/local-only" \
    "$home/.agents/skills/local-agent-skill" \
    "$home/.claude/skills/local-claude-skill"
  printf '{"lastChangelogVersion":"9.9.9","theme":"old","machineOnly":true}\n' > "$home/.pi/agent/settings.json"
  printf 'local extension\n' > "$home/.pi/agent/extensions/local-only/index.ts"
  printf 'agent skill\n' > "$home/.agents/skills/local-agent-skill/SKILL.md"
  printf 'claude skill\n' > "$home/.claude/skills/local-claude-skill/SKILL.md"
  printf 'linked skill\n' > "$external_skill/SKILL.md"
  printf 'nested target\n' > "$TEMP_ROOT/nested-target"
  ln -s "$TEMP_ROOT/nested-target" "$external_skill/nested-link"
  ln -s "$external_skill" "$home/.agents/skills/linked-agent-skill"
  ln -s "$fixture/ai/skills/tdd" "$home/.agents/skills/tdd"
  ln -s ../../.agents/skills/local-agent-skill "$home/.claude/skills/local-agent-skill"

  HOME="$home" OLD_DIR="$home/old" DOTFILES_DIR="$fixture" "$SETUP" >/dev/null

  [ "$(readlink "$home/.agents/skills")" = "$fixture/ai/skills" ]
  [ "$(readlink "$home/.claude/skills")" = "$fixture/ai/skills" ]
  [ -f "$fixture/ai/skills/local-agent-skill/SKILL.md" ]
  [ -f "$fixture/ai/skills/local-claude-skill/SKILL.md" ]
  [ -f "$fixture/ai/skills/linked-agent-skill/SKILL.md" ]
  [ ! -L "$fixture/ai/skills/linked-agent-skill" ]
  [ -L "$fixture/ai/skills/linked-agent-skill/nested-link" ]
  [ -f "$home/.agents/skills/local-agent-skill/SKILL.md" ]
  [ -f "$home/.claude/skills/local-claude-skill/SKILL.md" ]
  [ "$(readlink "$home/.pi/agent/extensions")" = "$fixture/ai/pi/extensions" ]
  [ -f "$home/old/ai/.pi/agent/extensions/local-only/index.ts" ]
  [ "$(jq -r .lastChangelogVersion "$home/.pi/agent/settings.json")" = "9.9.9" ]
  [ "$(jq -r .theme "$home/.pi/agent/settings.json")" = "robin-iterm" ]
  [ "$(jq -r .machineOnly "$home/.pi/agent/settings.json")" = "true" ]
  [ ! -e "$home/.codex/skills" ]
  [ ! -e "$home/.codex/rules" ]

  backups_before=$(find "$home/old" -mindepth 1 | wc -l | tr -d ' ')
  HOME="$home" OLD_DIR="$home/old" DOTFILES_DIR="$fixture" "$SETUP" >/dev/null
  backups_after=$(find "$home/old" -mindepth 1 | wc -l | tr -d ' ')
  [ "$backups_before" = "$backups_after" ]
}

test_failed_skill_import_is_retryable() {
  local home="$TEMP_ROOT/retry-home"
  local fixture="$TEMP_ROOT/retry-dotfiles"
  local fake_bin="$TEMP_ROOT/retry-bin"
  local real_cp

  mkdir -p "$fixture" "$fake_bin" "$home/.agents/skills/retry-skill"
  cp -R "$DOTFILES_DIR/ai" "$fixture/ai"
  printf 'retry skill\n' > "$home/.agents/skills/retry-skill/SKILL.md"
  real_cp=$(command -v cp)

  cat > "$fake_bin/cp" <<EOF
#!/bin/bash
for argument in "\$@"; do
  case "\$argument" in
    */retry-skill)
      destination="\${!#}"
      mkdir -p "\$destination"
      printf 'partial\n' > "\$destination/PARTIAL"
      exit 1
      ;;
  esac
done
exec "$real_cp" "\$@"
EOF
  chmod +x "$fake_bin/cp"

  if HOME="$home" OLD_DIR="$home/old" DOTFILES_DIR="$fixture" PATH="$fake_bin:$PATH" "$SETUP" >/dev/null 2>&1; then
    echo "Expected interrupted skill import to fail." >&2
    exit 1
  fi

  [ ! -e "$fixture/ai/skills/retry-skill" ]
  if find "$fixture/ai/skills" -maxdepth 1 -name '.skill-migration.*' | grep -q .; then
    echo "Interrupted skill import left temporary files behind." >&2
    exit 1
  fi

  HOME="$home" OLD_DIR="$home/old" DOTFILES_DIR="$fixture" "$SETUP" >/dev/null

  [ -f "$fixture/ai/skills/retry-skill/SKILL.md" ]
  [ "$(readlink "$home/.agents/skills")" = "$fixture/ai/skills" ]
  [ "$(readlink "$home/.claude/skills")" = "$fixture/ai/skills" ]
}

test_missing_sources_fail_before_mutation
test_invalid_pi_settings_fail_before_mutation
test_app_icon_skill_disables_automatic_invocation
test_migration_and_idempotence
test_failed_skill_import_is_retryable

echo "AI setup tests passed."
