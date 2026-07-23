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

link_test_command() {
  local bin=$1
  local command_name=$2
  local command_path

  command_path=$(type -P "$command_name")
  ln -s "$command_path" "$bin/$command_name"
}

make_success_stub() {
  local path=$1

  cat > "$path" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$path"
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

test_platform_detection() (
  OSTYPE=darwin24
  is_macos || fail 'Expected Darwin to be detected as macOS.'

  OSTYPE=linux-gnu
  if is_macos; then
    fail 'Expected Linux not to be detected as macOS.'
  fi
)

test_non_macos_setup_omits_platform_steps() (
  OSTYPE=linux-gnu

  setup_homebrew_dependencies() { fail 'Homebrew setup should be omitted on Linux.'; }
  setup_fzf_extensions() { fail 'fzf Homebrew setup should be omitted on Linux.'; }
  setup_iterm2() { fail 'iTerm2 setup should be omitted on Linux.'; }
  setup_vscode() { fail 'macOS VS Code setup should be omitted on Linux.'; }
  setup_powerline_fonts() { fail 'Powerline font setup should be omitted on Linux.'; }
  setup_macos_preferences() { fail 'macOS preferences should be omitted on Linux.'; }
  setup_wktr() { fail 'macOS-specific wktr config should be omitted on Linux.'; }

  setup_platform_dependencies >/dev/null
  setup_platform_configuration >/dev/null
  setup_wktr_configuration >/dev/null
)

test_macos_setup_runs_platform_steps() (
  local calls=''
  local home="$TEMP_ROOT/macos-platform-home"

  export HOME="$home"
  OSTYPE=darwin24
  mkdir -p "$HOME/.oh-my-zsh"

  setup_homebrew_dependencies() { calls+=' homebrew'; }
  setup_fzf_extensions() { calls+=' fzf'; }
  setup_iterm2() { calls+=' iterm'; }
  setup_vscode() { calls+=' vscode'; }
  setup_powerline_fonts() { calls+=' fonts'; }
  setup_macos_preferences() { calls+=' preferences'; }
  setup_wktr() { calls+=' wktr'; }

  setup_platform_dependencies >/dev/null
  setup_platform_configuration >/dev/null
  setup_wktr_configuration >/dev/null

  [[ $calls == ' homebrew fzf iterm vscode fonts preferences wktr' ]] ||
    fail "Unexpected macOS setup calls:$calls"
)

test_macos_installs_missing_oh_my_zsh() (
  local calls=''
  local home="$TEMP_ROOT/macos-oh-my-zsh-home"

  export HOME="$home"
  OSTYPE=darwin24
  mkdir -p "$HOME"

  setup_homebrew_dependencies() { calls+=' homebrew'; }
  setup_fzf_extensions() { calls+=' fzf'; }
  curl() { printf '%s\n' 'mkdir -p "$HOME/.oh-my-zsh"'; }
  chsh() {
    [[ $* == '-s /bin/zsh' ]] || fail "Unexpected chsh arguments: $*"
    calls+=' chsh'
  }

  setup_platform_dependencies >/dev/null

  [[ -d $HOME/.oh-my-zsh ]]
  [[ $calls == ' homebrew chsh fzf' ]] ||
    fail "Unexpected missing-Oh-My-Zsh setup calls:$calls"
)

test_missing_optional_tools_are_skipped() (
  local bin="$TEMP_ROOT/missing-tools-bin"
  local dependency
  local home
  local output
  local present_dependency

  mkdir -p "$bin"
  link_test_command "$bin" mkdir
  link_test_command "$bin" ln

  home="$TEMP_ROOT/missing-ai-home"
  mkdir -p "$home"
  output=$(HOME="$home" PATH="$bin" setup_ai_tools)
  [[ $output == *'Skipping AI tool setup because jq is unavailable.'* ]]

  for dependency in curl git make vim; do
    bin="$TEMP_ROOT/missing-$dependency-bin"
    home="$TEMP_ROOT/missing-$dependency-home"
    mkdir -p "$bin" "$home"
    link_test_command "$bin" mkdir
    link_test_command "$bin" ln

    for present_dependency in curl git make vim; do
      if [[ $present_dependency != "$dependency" ]]; then
        make_success_stub "$bin/$present_dependency"
      fi
    done

    output=$(HOME="$home" PATH="$bin" setup_vim)
    [[ $output == *"Skipping Vim plugin setup because $dependency is unavailable."* ]]
    [[ -L $home/.config/nvim/init.vim ]]
    [[ ! -e $home/.vim/bundle ]]
  done

  home="$TEMP_ROOT/missing-zsh-home"
  mkdir -p "$home"
  output=$(HOME="$home" setup_zsh_theme)
  [[ $output == *'Skipping the custom Zsh theme because Oh My Zsh is unavailable.'* ]]
  [[ ! -e $home/.oh-my-zsh ]]
)

test_available_optional_tools_are_configured() (
  local ai_dotfiles="$TEMP_ROOT/available-ai-dotfiles"
  local bin="$TEMP_ROOT/available-tools-bin"
  local home="$TEMP_ROOT/available-tools-home"

  mkdir -p "$ai_dotfiles/scripts" "$bin" "$home/.oh-my-zsh/custom/themes"
  link_test_command "$bin" mkdir
  link_test_command "$bin" ln
  make_success_stub "$bin/curl"
  make_success_stub "$bin/git"
  make_success_stub "$bin/make"
  make_success_stub "$bin/jq"
  cat > "$bin/vim" <<'EOF'
#!/bin/bash
: > "$VIM_LOG"
EOF
  chmod +x "$bin/vim"
  cat > "$ai_dotfiles/scripts/setup-ai.sh" <<'EOF'
#!/bin/bash
: > "$AI_SETUP_LOG"
EOF
  chmod +x "$ai_dotfiles/scripts/setup-ai.sh"

  HOME="$home" PATH="$bin" DOTFILES_DIR="$ai_dotfiles" AI_SETUP_LOG="$home/ai-setup" setup_ai_tools
  [[ -f $home/ai-setup ]]

  HOME="$home" PATH="$bin" DOTFILES_DIR="$DOTFILES_REPO" VIM_LOG="$home/vim-setup" setup_vim >/dev/null
  [[ -f $home/vim-setup ]]
  [[ -d $home/.vim/bundle ]]
  [[ -L $home/.config/nvim/init.vim ]]

  HOME="$home" DOTFILES_DIR="$DOTFILES_REPO" OLD_DIR="$home/old" setup_zsh_theme >/dev/null
  [[ $(readlink "$home/.oh-my-zsh/custom/themes/robin.zsh-theme") == "$DOTFILES_REPO/robin.zsh-theme" ]]
)

test_linux_entrypoint_omits_incompatible_steps() (
  local bin="$TEMP_ROOT/linux-entrypoint-bin"
  local dotfiles
  local home="$TEMP_ROOT/linux-entrypoint-home"
  local marker="$TEMP_ROOT/linux-entrypoint-macos-command"
  local platform_command

  dotfiles="$home/.dotfiles"
  mkdir -p "$bin" "$home"
  cp -R "$DOTFILES_REPO" "$dotfiles"
  link_test_command "$bin" cp
  link_test_command "$bin" ln
  link_test_command "$bin" mkdir

  for platform_command in brew chsh curl defaults find git; do
    cat > "$bin/$platform_command" <<EOF
#!/bin/bash
printf '%s\n' '$platform_command' >> '$marker'
exit 97
EOF
    chmod +x "$bin/$platform_command"
  done

  if ! HOME="$home" OSTYPE=linux-gnu PATH="$bin" /bin/bash "$dotfiles/setup.sh" \
    >"$home/setup.out" 2>"$home/setup.err"; then
    fail "Expected the Linux setup entrypoint to succeed: $(cat "$home/setup.err")"
  fi

  [[ ! -s $home/setup.err ]]
  [[ ! -e $marker ]]
  [[ -L $home/.zshrc ]]
  [[ -L $home/.config/herdr/config.toml ]]
  [[ -L $home/.config/nvim/init.vim ]]
  [[ ! -e $home/.config/wktr/config.yaml ]]
  [[ ! -e "$home/Library/Application Support/iTerm2" ]]
  [[ ! -e "$home/Library/Application Support/Code" ]]
)

test_aliases_omit_macos_ls_flags_on_linux() (
  unalias ls 2>/dev/null || true

  OSTYPE=linux-gnu
  source "$DOTFILES_REPO/.aliases"
  if alias ls >/dev/null 2>&1; then
    fail 'Expected the macOS ls alias to be omitted on Linux.'
  fi

  OSTYPE=darwin24
  source "$DOTFILES_REPO/.aliases"
  [[ $(alias ls) == "alias ls='ls -G'" ]]
)

test_shell_and_tmux_guards() {
  grep -Fq 'if command -v brew > /dev/null 2>&1; then' "$DOTFILES_REPO/.bash_profile"
  grep -Fq '[[ -f "$ZSH/oh-my-zsh.sh" ]]' "$DOTFILES_REPO/.zshrc"
  grep -Fq 'command -v mise > /dev/null 2>&1' "$DOTFILES_REPO/.zshrc"
  grep -Fq 'if command -v brew > /dev/null 2>&1; then' "$DOTFILES_REPO/.zshrc"
  grep -Fq "if-shell 'command -v reattach-to-user-namespace >/dev/null 2>&1'" "$DOTFILES_REPO/.tmux.conf"
  grep -Fq "'bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel'" "$DOTFILES_REPO/.tmux.conf"
}

test_git_credential_helper_uses_git_exec_path() (
  local exec_path="$TEMP_ROOT/git-exec-path"
  local helper
  local log="$TEMP_ROOT/git-credential.log"

  mkdir -p "$exec_path"
  cat > "$exec_path/git-credential-osxkeychain" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$CREDENTIAL_LOG"
cat >/dev/null
EOF
  chmod +x "$exec_path/git-credential-osxkeychain"

  helper=$(git config -f "$DOTFILES_REPO/.gitconfig" --get credential.helper)
  GIT_EXEC_PATH="$exec_path" CREDENTIAL_LOG="$log" /bin/sh -c "${helper#!} get" </dev/null
  [[ $(cat "$log") == get ]]

  GIT_EXEC_PATH="$TEMP_ROOT/missing-git-exec-path" /bin/sh -c "${helper#!} get" </dev/null
)

test_modern_homebrew_dependencies
test_legacy_homebrew_dependencies
test_homebrew_failures_stop_installation
test_noninteractive_homebrew_bootstrap
test_broken_homebrew_candidate_is_rejected
test_fzf_extensions_use_brew_prefix
test_wktr_migration_and_idempotence
test_wktr_directory_is_untouched
test_wktr_config_semantics
test_platform_detection
test_non_macos_setup_omits_platform_steps
test_macos_setup_runs_platform_steps
test_macos_installs_missing_oh_my_zsh
test_missing_optional_tools_are_skipped
test_available_optional_tools_are_configured
test_linux_entrypoint_omits_incompatible_steps
test_aliases_omit_macos_ls_flags_on_linux
test_shell_and_tmux_guards
test_git_credential_helper_uses_git_exec_path

echo "Setup tests passed."
