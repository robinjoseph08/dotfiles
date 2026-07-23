#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DOTFILES_REPO=$(cd "$SCRIPT_DIR/.." && pwd)
SETUP="$DOTFILES_REPO/setup.sh"
TEMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TEMP_ROOT"' EXIT

# Source only the setup functions. The script returns before changing the machine.
source "$SETUP"

fail() {
  echo "$1" >&2
  exit 1
}

make_brew_stub() {
  local path=$1

  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'EOF'
#!/bin/bash

printf '%s|NO_ASK=%s|NO_TRUST=%s\n' \
  "$*" \
  "${HOMEBREW_NO_ASK:-}" \
  "${HOMEBREW_NO_REQUIRE_TAP_TRUST:-}" >> "$BREW_LOG"

if [[ $1 == shellenv ]]; then
  printf 'export PATH="%s:$PATH"\n' "$BREW_SHELLENV_PATH"
  exit "${BREW_SHELLENV_STATUS:-0}"
fi

if [[ $1 == install && ${2:-} == --help ]]; then
  [[ $BREW_MODE == modern ]] && echo '      --no-ask'
  exit 0
fi

if [[ $1 == help && ${2:-} == trust ]]; then
  [[ $BREW_MODE == modern || $BREW_MODE == trust-fail ]]
  exit
fi

if [[ $1 == trust ]]; then
  [[ $BREW_MODE != trust-fail ]]
  exit
fi

if [[ $1 == install ]]; then
  [[ $BREW_MODE != install-fail ]]
  exit
fi

if [[ $1 == --prefix && ${2:-} == fzf ]]; then
  printf '%s\n' "$FZF_PREFIX"
  exit 0
fi

exit 0
EOF
  chmod +x "$path"
}

assert_dependency_list() {
  local log=$1
  local install_line

  install_line=$(grep '^install ' "$log" | tail -1)
  [[ $install_line == *' gh '* ]] || fail 'Expected gh in the Homebrew package list.'
  [[ $install_line == *' robinjoseph08/tap/wktr '* ]] || fail 'Expected wktr in the Homebrew package list.'
  [[ $install_line != *' kubectl '* ]] || fail 'Did not expect kubectl in the Homebrew package list.'
}

test_modern_homebrew_dependencies() (
  local bin="$TEMP_ROOT/modern/bin"
  local log="$TEMP_ROOT/modern/brew.log"

  make_brew_stub "$bin/brew"
  : > "$log"
  export PATH="$bin:/usr/bin:/bin"
  export BREW_LOG="$log"
  export BREW_MODE=modern
  export BREW_SHELLENV_PATH="$bin"
  unset HOMEBREW_NO_ASK HOMEBREW_NO_REQUIRE_TAP_TRUST

  setup_homebrew_dependencies >/dev/null

  grep -q '^trust --tap robinjoseph08/tap|' "$log"
  grep -q '^install --no-ask ' "$log"
  assert_dependency_list "$log"
)

test_legacy_homebrew_dependencies() (
  local bin="$TEMP_ROOT/legacy/bin"
  local log="$TEMP_ROOT/legacy/brew.log"
  local install_line

  make_brew_stub "$bin/brew"
  : > "$log"
  export PATH="$bin:/usr/bin:/bin"
  export BREW_LOG="$log"
  export BREW_MODE=legacy
  export BREW_SHELLENV_PATH="$bin"
  unset HOMEBREW_NO_ASK HOMEBREW_NO_REQUIRE_TAP_TRUST

  setup_homebrew_dependencies >/dev/null

  ! grep -q '^trust ' "$log"
  install_line=$(grep '^install ' "$log" | tail -1)
  [[ $install_line == *'NO_ASK=1|NO_TRUST=1' ]]
  [[ $install_line != *'--no-ask'* ]]
  assert_dependency_list "$log"
)

test_homebrew_failures_stop_installation() {
  local mode

  for mode in trust-fail install-fail; do
    if (
      local bin="$TEMP_ROOT/$mode/bin"
      local log="$TEMP_ROOT/$mode/brew.log"

      make_brew_stub "$bin/brew"
      : > "$log"
      export PATH="$bin:/usr/bin:/bin"
      export BREW_LOG="$log"
      export BREW_MODE="$mode"
      export BREW_SHELLENV_PATH="$bin"
      setup_homebrew_dependencies >/dev/null 2>&1
    ); then
      fail "Expected $mode to stop dependency setup."
    fi
  done
}

test_noninteractive_homebrew_bootstrap() (
  local curl_bin="$TEMP_ROOT/bootstrap/curl-bin"
  local install_bin="$TEMP_ROOT/bootstrap/homebrew/bin"
  local log="$TEMP_ROOT/bootstrap/brew.log"
  local template="$TEMP_ROOT/bootstrap/brew-template"
  local marker="$TEMP_ROOT/bootstrap/noninteractive"

  make_brew_stub "$template"
  mkdir -p "$curl_bin"
  cat > "$curl_bin/curl" <<'EOF'
#!/bin/bash
cat <<INSTALL
[ "\$NONINTERACTIVE" = 1 ] || exit 97
mkdir -p "$BREW_INSTALL_BIN"
cp "$BREW_TEMPLATE" "$BREW_INSTALL_BIN/brew"
chmod +x "$BREW_INSTALL_BIN/brew"
touch "$BREW_INSTALL_MARKER"
INSTALL
EOF
  chmod +x "$curl_bin/curl"
  : > "$log"

  export PATH="$curl_bin:/usr/bin:/bin"
  export HOMEBREW_PATHS="$install_bin/brew"
  export BREW_INSTALL_BIN="$install_bin"
  export BREW_INSTALL_MARKER="$marker"
  export BREW_TEMPLATE="$template"
  export BREW_LOG="$log"
  export BREW_MODE=modern
  export BREW_SHELLENV_PATH="$install_bin"

  setup_homebrew_dependencies >/dev/null

  [[ -f $marker ]]
  [[ $(command -v brew) == "$install_bin/brew" ]]
  assert_dependency_list "$log"
)

test_broken_homebrew_candidate_is_rejected() (
  local broken="$TEMP_ROOT/candidates/broken/brew"
  local good="$TEMP_ROOT/candidates/good/brew"
  local log="$TEMP_ROOT/candidates/brew.log"

  make_brew_stub "$broken"
  make_brew_stub "$good"
  : > "$log"
  export PATH="/usr/bin:/bin"
  export HOMEBREW_PATHS="$broken $good"
  export BREW_LOG="$log"
  export BREW_MODE=modern
  export BREW_SHELLENV_PATH="$(dirname "$good")"
  export BREW_SHELLENV_STATUS=1

  if setup_brew_environment; then
    fail 'Expected failing Homebrew shellenv candidates to be rejected.'
  fi
)

test_fzf_extensions_use_brew_prefix() (
  local bin="$TEMP_ROOT/fzf/bin"
  local prefix="$TEMP_ROOT/fzf/prefix"
  local log="$TEMP_ROOT/fzf/brew.log"
  local marker="$TEMP_ROOT/fzf/installed"

  make_brew_stub "$bin/brew"
  mkdir -p "$prefix"
  cat > "$prefix/install" <<EOF
#!/bin/bash
touch "$marker"
EOF
  chmod +x "$prefix/install"
  : > "$log"
  export PATH="$bin:/usr/bin:/bin"
  export BREW_LOG="$log"
  export BREW_MODE=modern
  export BREW_SHELLENV_PATH="$bin"
  export FZF_PREFIX="$prefix"

  setup_fzf_extensions
  [[ -f $marker ]]
  grep -q '^--prefix fzf|' "$log"
)

test_wktr_migration_and_idempotence() (
  local home="$TEMP_ROOT/wktr-home"

  export HOME="$home"
  DOTFILES_DIR="$DOTFILES_REPO"
  OLD_DIR="$home/old"
  mkdir -p "$home/.config/wktr" "$OLD_DIR"
  printf 'old config\n' > "$home/.config/wktr/config.yaml"

  setup_wktr >/dev/null

  [[ $(cat "$OLD_DIR/wktr.yaml") == 'old config' ]]
  [[ $(readlink "$home/.config/wktr/config.yaml") == "$DOTFILES_REPO/wktr.yaml" ]]

  setup_wktr >/dev/null
  [[ $(cat "$OLD_DIR/wktr.yaml") == 'old config' ]]
  [[ $(readlink "$home/.config/wktr/config.yaml") == "$DOTFILES_REPO/wktr.yaml" ]]
)

test_wktr_directory_is_untouched() {
  local home="$TEMP_ROOT/wktr-directory-home"

  mkdir -p "$home/.config/wktr/config.yaml" "$home/old"
  if (
    export HOME="$home"
    DOTFILES_DIR="$DOTFILES_REPO"
    OLD_DIR="$home/old"
    setup_wktr >/dev/null 2>&1
  ); then
    fail 'Expected a directory at the wktr config path to stop setup.'
  fi
  [[ -d $home/.config/wktr/config.yaml ]]
  [[ ! -e $home/old/wktr.yaml ]]
}

test_wktr_config_semantics() {
  grep -Fxq 'worktree_directory: /Users/robinjoseph/.worktrees' "$DOTFILES_REPO/wktr.yaml"
  grep -Fxq 'branch_prefix: wktr/' "$DOTFILES_REPO/wktr.yaml"
  grep -Fxq '  direction: vertical' "$DOTFILES_REPO/wktr.yaml"
  grep -Fxq '    - command: pi' "$DOTFILES_REPO/wktr.yaml"
}

test_modern_homebrew_dependencies
test_legacy_homebrew_dependencies
test_homebrew_failures_stop_installation
test_noninteractive_homebrew_bootstrap
test_broken_homebrew_candidate_is_rejected
test_fzf_extensions_use_brew_prefix
test_wktr_migration_and_idempotence
test_wktr_directory_is_untouched
test_wktr_config_semantics

echo "Setup tests passed."
