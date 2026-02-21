# Chezmoi Conversion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Convert the dotfiles repo from setup.sh + symlinks to chezmoi with macOS and Debian Linux support.

**Architecture:** The repo root (`~/.dotfiles`) becomes the chezmoi source directory. Files are renamed to chezmoi conventions (`dot_`, `.tmpl`). OS-specific differences handled via Go templates. Package installation and one-time setup handled via `run_onchange_` and `run_once_` scripts.

**Tech Stack:** chezmoi, Go templates, bash, brew (macOS), apt (Debian)

**Design doc:** `docs/plans/2026-02-21-chezmoi-conversion-design.md`

---

### Task 1: Create chezmoi configuration files

**Files:**
- Create: `.chezmoi.toml.tmpl`
- Create: `.chezmoiignore`

**Step 1: Create `.chezmoi.toml.tmpl`**

```toml
# chezmoi configuration
# This file is a template that generates ~/.config/chezmoi/chezmoi.toml

sourceDir = {{ .chezmoi.sourceDir | quote }}
```

**Step 2: Create `.chezmoiignore`**

```
README.md
LICENSE
docs/
iterm.json
vscode.json
old/
setup.sh
```

**Step 3: Commit**

```bash
git add .chezmoi.toml.tmpl .chezmoiignore
git commit -m "add chezmoi configuration files"
```

---

### Task 2: Rename plain dotfiles (no templates needed)

**Files:**
- Rename: `.inputrc` → `dot_inputrc`
- Rename: `.psqlrc` → `dot_psqlrc`
- Rename: `.functions` → `dot_functions`

**Step 1: Rename files using git mv**

```bash
git mv .inputrc dot_inputrc
git mv .psqlrc dot_psqlrc
git mv .functions dot_functions
```

**Step 2: Commit**

```bash
git commit -m "rename plain dotfiles to chezmoi naming convention"
```

---

### Task 3: Convert .aliases to template

The `ls` alias uses `-G` (macOS BSD) vs `--color=auto` (Linux GNU).

**Files:**
- Delete: `.aliases`
- Create: `dot_aliases.tmpl`

**Step 1: Create `dot_aliases.tmpl`**

```
{{- if eq .chezmoi.os "darwin" -}}
alias ls="ls -G"
{{- else -}}
alias ls="ls --color=auto"
{{- end }}
alias gl="git log"
alias gs="git status"
alias ga="git add"
alias gc="git commit"
alias gp="git push"
alias gch="git checkout"
alias gf="git fetch"
alias gr="git rebase"
alias gb="git branch"
alias k='kubectl "--context=${KUBECTL_CONTEXT:-$(kubectl config current-context)}" ${KUBECTL_NAMESPACE/[[:alnum:]-]*/--namespace=${KUBECTL_NAMESPACE}}'
```

**Step 2: Remove old file and commit**

```bash
git rm .aliases
git add dot_aliases.tmpl
git commit -m "convert aliases to chezmoi template for cross-platform ls"
```

---

### Task 4: Convert .gitconfig to template

Credential helper differs: `osxkeychain` (macOS) vs `store` (Linux).

**Files:**
- Delete: `.gitconfig`
- Create: `dot_gitconfig.tmpl`

**Step 1: Create `dot_gitconfig.tmpl`**

```
[user]
  name = Robin Joseph
  email = robinmjoseph08@gmail.com
[credential]
{{- if eq .chezmoi.os "darwin" }}
  helper = osxkeychain
{{- else }}
  helper = store
{{- end }}
[push]
  default = simple
[alias]
  fixup = commit --amend -C HEAD
  undo = !git reset HEAD~1 --soft && git reset HEAD .
  wip = !git add . && git commit -am "wip"
[init]
  defaultBranch = master
```

**Step 2: Remove old file and commit**

```bash
git rm .gitconfig
git add dot_gitconfig.tmpl
git commit -m "convert gitconfig to chezmoi template for cross-platform credential helper"
```

---

### Task 5: Convert .tmux.conf to template

`reattach-to-user-namespace` is macOS-only. On Linux, use `xclip` for clipboard or skip clipboard integration (headless).

**Files:**
- Delete: `.tmux.conf`
- Create: `dot_tmux.conf.tmpl`

**Step 1: Create `dot_tmux.conf.tmpl`**

Three sections need OS conditionals:

1. Line 11 — `default-command`:
```
{{- if eq .chezmoi.os "darwin" }}
set -g default-command "reattach-to-user-namespace -l zsh"
{{- end }}
```

2. Line 55 — copy-mode-vi `y` binding:
```
{{- if eq .chezmoi.os "darwin" }}
bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "reattach-to-user-namespace pbcopy"
{{- else }}
bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "xclip -selection clipboard 2>/dev/null || true"
{{- end }}
```

3. Line 84 — clipboard copy binding:
```
{{- if eq .chezmoi.os "darwin" }}
bind-key y run-shell "tmux save-buffer - | reattach-to-user-namespace pbcopy"
{{- else }}
bind-key y run-shell "tmux save-buffer - | xclip -selection clipboard 2>/dev/null || true"
{{- end }}
```

All other lines remain unchanged. Write the full file with these three template blocks.

**Step 2: Remove old file and commit**

```bash
git rm .tmux.conf
git add dot_tmux.conf.tmpl
git commit -m "convert tmux.conf to chezmoi template for cross-platform clipboard"
```

---

### Task 6: Convert .zshrc to template

Most complex template. OS-conditional blocks needed for: Homebrew init, FPATH, X11, Sublime, fzf paths, and version manager PATH entries for Linux git-based installs.

**Files:**
- Delete: `.zshrc`
- Create: `dot_zshrc.tmpl`

**Step 1: Create `dot_zshrc.tmpl`**

Key changes from the original `.zshrc`:

1. **Lines 83-84** — Homebrew (macOS only):
```
{{ if eq .chezmoi.os "darwin" -}}
# setup brew
eval "$(/opt/homebrew/bin/brew shellenv)"
{{ end -}}
```

2. **Lines 120-121** — FPATH autocompletion (macOS only for brew path):
```
{{ if eq .chezmoi.os "darwin" -}}
FPATH="$(brew --prefix)/share/zsh/site-functions:${FPATH}"
{{ end -}}
```

3. **Lines 125-126** — X11 (macOS only):
```
{{ if eq .chezmoi.os "darwin" -}}
# X11
export PATH="$PATH:/opt/X11/bin"
{{ end -}}
```

4. **Before version manager inits** — Add Linux PATH entries:
```
{{ if ne .chezmoi.os "darwin" -}}
# Version managers installed from git (Linux)
[ -d "$HOME/.nodenv/bin" ] && export PATH="$HOME/.nodenv/bin:$PATH"
[ -d "$HOME/.rbenv/bin" ] && export PATH="$HOME/.rbenv/bin:$PATH"
[ -d "$HOME/.pyenv/bin" ] && export PATH="$HOME/.pyenv/bin:$PATH"
[ -d "$HOME/.goenv/bin" ] && export PATH="$HOME/.goenv/bin:$PATH"
{{ end -}}
```

5. **Line 160** — Fix goenv to have a type guard (like nodenv/rbenv/pyenv):
```
type goenv > /dev/null 2>&1 && eval "$(goenv init -)"
```
(was `eval "$(goenv init -)"` without guard)

6. **Lines 171-172** — Sublime (macOS only):
```
{{ if eq .chezmoi.os "darwin" -}}
# sublime
export PATH="/Applications/Sublime Text.app/Contents/SharedSupport/bin:$PATH"
{{ end -}}
```

7. **After line 180** — Add Linux fzf paths:
```
{{ if ne .chezmoi.os "darwin" -}}
[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && source /usr/share/doc/fzf/examples/key-bindings.zsh
[ -f /usr/share/doc/fzf/examples/completion.zsh ] && source /usr/share/doc/fzf/examples/completion.zsh
{{ end -}}
```

All other lines (oh-my-zsh config, plugins, grep options, version manager inits, history, etc.) remain unchanged.

**Step 2: Remove old file and commit**

```bash
git rm .zshrc
git add dot_zshrc.tmpl
git commit -m "convert zshrc to chezmoi template for cross-platform support"
```

---

### Task 7: Convert .vimrc — fix fzf path and rename

The fzf plug path `/usr/local/opt/fzf` is the Intel macOS brew path. Replace with the cross-platform vim-plug approach.

**Files:**
- Rename+edit: `.vimrc` → `dot_vimrc`

**Step 1: Fix fzf plug line and rename**

Change line 19 from:
```vim
Plug '/usr/local/opt/fzf' | Plug 'junegunn/fzf.vim'
```
to:
```vim
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
```

Then rename:
```bash
git mv .vimrc dot_vimrc
```

**Step 2: Commit**

```bash
git add dot_vimrc
git commit -m "fix fzf plug path for cross-platform support and rename to chezmoi convention"
```

---

### Task 8: Convert .bash_profile to template

References `brew --prefix nvm` which is macOS-only. Guard brew-specific lines.

**Files:**
- Delete: `.bash_profile`
- Create: `dot_bash_profile.tmpl`

**Step 1: Create `dot_bash_profile.tmpl`**

```bash
# Aliases
source ~/.aliases

# Bash Prompt
export PS1="\h:\[\e[0;32m\]\W\[\e[00m\] \u\$ "

{{ if eq .chezmoi.os "darwin" -}}
# nvm
export NVM_DIR=~/.nvm
[ -s "$(brew --prefix nvm)/nvm.sh" ] && source "$(brew --prefix nvm)/nvm.sh"
{{ else -}}
# nvm
export NVM_DIR=~/.nvm
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
{{ end -}}

[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm" # Load RVM into a shell session *as a function*
[[ -s "$HOME/.avn/bin/avn.sh" ]] && source "$HOME/.avn/bin/avn.sh" # load avn
[[ -s "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env" # load rust
```

**Step 2: Remove old file and commit**

```bash
git rm .bash_profile
git add dot_bash_profile.tmpl
git commit -m "convert bash_profile to chezmoi template for cross-platform nvm path"
```

---

### Task 9: Set up oh-my-zsh theme and neovim config

**Files:**
- Move: `robin.zsh-theme` → `dot_oh-my-zsh/custom/themes/robin.zsh-theme`
- Create: `private_dot_config/nvim/symlink_init.vim.tmpl`

**Step 1: Create oh-my-zsh theme directory and move file**

```bash
mkdir -p dot_oh-my-zsh/custom/themes
git mv robin.zsh-theme dot_oh-my-zsh/custom/themes/robin.zsh-theme
```

**Step 2: Create neovim config symlink**

Create `private_dot_config/nvim/symlink_init.vim.tmpl` with content:

```
{{ .chezmoi.homeDir }}/.vimrc
```

This tells chezmoi to create `~/.config/nvim/init.vim` as a symlink pointing to `~/.vimrc`.

```bash
mkdir -p private_dot_config/nvim
```

Then write the file.

**Step 3: Commit**

```bash
git add dot_oh-my-zsh/ private_dot_config/
git commit -m "set up oh-my-zsh theme and neovim symlink in chezmoi structure"
```

---

### Task 10: Create package installation script

**Files:**
- Create: `run_onchange_install-packages.sh.tmpl`

**Step 1: Create `run_onchange_install-packages.sh.tmpl`**

```bash
#!/bin/bash
set -e

{{ if eq .chezmoi.os "darwin" -}}
# Install Homebrew if missing
if ! command -v brew &> /dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

echo "Installing brew packages..."
brew install awscli fd fzf jq kubectl neovim nodenv \
    reattach-to-user-namespace ripgrep tmux tree vim watch wget \
    zsh zsh-completions zsh-syntax-highlighting 2>/dev/null

echo "Installing goenv from HEAD..."
brew install --HEAD goenv 2>/dev/null

echo "Installing fzf extensions..."
"$(brew --prefix)"/opt/fzf/install --key-bindings --completion --no-update-rc --no-bash --no-fish

{{ else -}}
echo "Installing apt packages..."
sudo apt-get update
sudo apt-get install -y \
    curl git zsh tmux neovim vim \
    fzf ripgrep fd-find jq tree wget \
    zsh-syntax-highlighting \
    python3-pip xclip

# nodenv
if [ ! -d "$HOME/.nodenv" ]; then
    echo "Installing nodenv..."
    git clone https://github.com/nodenv/nodenv.git ~/.nodenv
    mkdir -p ~/.nodenv/plugins
    git clone https://github.com/nodenv/node-build.git ~/.nodenv/plugins/node-build
fi

# rbenv
if [ ! -d "$HOME/.rbenv" ]; then
    echo "Installing rbenv..."
    git clone https://github.com/rbenv/rbenv.git ~/.rbenv
    mkdir -p ~/.rbenv/plugins
    git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
fi

# pyenv
if [ ! -d "$HOME/.pyenv" ]; then
    echo "Installing pyenv..."
    curl https://pyenv.run | bash
fi

# goenv
if [ ! -d "$HOME/.goenv" ]; then
    echo "Installing goenv..."
    git clone https://github.com/go-nv/goenv.git ~/.goenv
fi

{{ end -}}
echo "Package installation complete."
```

**Step 2: Commit**

```bash
git add run_onchange_install-packages.sh.tmpl
git commit -m "add chezmoi run_onchange script for cross-platform package installation"
```

---

### Task 11: Create one-time setup scripts

**Files:**
- Create: `run_once_setup-oh-my-zsh.sh`
- Create: `run_once_setup-vim.sh`
- Create: `run_once_setup-macos.sh.tmpl`

**Step 1: Create `run_once_setup-oh-my-zsh.sh`**

```bash
#!/bin/bash
set -e

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Change default shell to zsh if not already
if [ "$SHELL" != "$(which zsh)" ]; then
    echo "Changing default shell to zsh..."
    chsh -s "$(which zsh)" || echo "Could not change shell. Run: chsh -s \$(which zsh)"
fi
```

**Step 2: Create `run_once_setup-vim.sh`**

```bash
#!/bin/bash
set -e

echo "Setting up vim..."

# Create vim directories
mkdir -p ~/.vim/bundle
mkdir -p ~/.vim/undo

# Install vim-plug if not present
if [ ! -f ~/.vim/autoload/plug.vim ]; then
    echo "Installing vim-plug..."
    curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
        https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
fi

# Install vim-plug for neovim if not present
mkdir -p ~/.local/share/nvim/site/autoload
if [ ! -f ~/.local/share/nvim/site/autoload/plug.vim ]; then
    curl -fLo ~/.local/share/nvim/site/autoload/plug.vim --create-dirs \
        https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
fi

# Install vim plugins
echo "Installing vim plugins..."
vim +PlugInstall +qall 2>/dev/null || true

echo "Vim setup complete."
```

**Step 3: Create `run_once_setup-macos.sh.tmpl`**

```bash
#!/bin/bash
{{ if ne .chezmoi.os "darwin" -}}
exit 0
{{ end -}}
set -e

# iTerm2 dynamic profile
echo "Setting up iTerm2..."
mkdir -p ~/Library/Application\ Support/iTerm2/DynamicProfiles
ln -f {{ .chezmoi.sourceDir }}/iterm.json ~/Library/Application\ Support/iTerm2/DynamicProfiles/iterm.json
echo "=== Make sure you set this profile as the default one in iTerm2 ==="

# Powerline Fonts
if [ -z "$(find ~/Library/Fonts -name '*Powerline*' 2>/dev/null)" ]; then
    echo "Installing Powerline Fonts..."
    TMPDIR=$(mktemp -d)
    git clone https://github.com/powerline/fonts.git --depth=1 "$TMPDIR"
    "$TMPDIR/install.sh"
    rm -rf "$TMPDIR"
fi

# Disable key press-and-hold
echo "Enabling key repeats on Mac..."
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

echo "macOS setup complete."
```

**Step 4: Commit**

```bash
git add run_once_setup-oh-my-zsh.sh run_once_setup-vim.sh run_once_setup-macos.sh.tmpl
git commit -m "add chezmoi run_once scripts for oh-my-zsh, vim, and macOS setup"
```

---

### Task 12: Create VS Code settings deployment script

VS Code settings path differs per OS. Keep `vscode.json` as source data, deploy via script.

**Files:**
- Create: `run_onchange_install-vscode-settings.sh.tmpl`

**Step 1: Create `run_onchange_install-vscode-settings.sh.tmpl`**

```bash
#!/bin/bash
# vscode.json hash: {{ include "vscode.json" | sha256sum }}
set -e

{{ if eq .chezmoi.os "darwin" -}}
VSCODE_DIR="$HOME/Library/Application Support/Code/User"
{{ else -}}
VSCODE_DIR="$HOME/.config/Code/User"
{{ end -}}

mkdir -p "$VSCODE_DIR"
cp {{ .chezmoi.sourceDir | quote }}/vscode.json "$VSCODE_DIR/settings.json"

echo "VS Code settings deployed to $VSCODE_DIR/settings.json"
```

The `# vscode.json hash:` comment includes the file hash. When `vscode.json` changes, the hash changes, triggering `run_onchange_`.

**Step 2: Commit**

```bash
git add run_onchange_install-vscode-settings.sh.tmpl
git commit -m "add chezmoi run_onchange script for cross-platform VS Code settings deployment"
```

---

### Task 13: Clean up old files

**Files:**
- Delete: `setup.sh`
- Delete: `old/` directory

**Step 1: Remove old files**

```bash
git rm setup.sh
git rm -r old/
```

**Step 2: Commit**

```bash
git commit -m "remove setup.sh and old/ directory, replaced by chezmoi"
```

---

### Task 14: Update README.md

**Files:**
- Modify: `README.md`

**Step 1: Rewrite README.md**

```markdown
# Dotfiles

User configurations managed with [chezmoi](https://www.chezmoi.io/), supporting macOS and Debian Linux.

## Quick Start

### Fresh machine (macOS or Debian)

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply robinjoseph08/dotfiles --source ~/.dotfiles
```

### From this repo

```bash
git clone git@github.com:robinjoseph08/dotfiles.git ~/.dotfiles
chezmoi init --source ~/.dotfiles
chezmoi apply
```

## What does it do?

- Installs necessary dependencies (Homebrew on macOS, apt on Debian)
  - tmux, vim, neovim, zsh, fzf, ripgrep, jq, and more
  - [Oh My Zsh](https://github.com/ohmyzsh/ohmyzsh)
  - Version managers: nodenv, rbenv, pyenv, goenv
- Deploys dotfiles for zsh, vim, tmux, git, and more
- Sets up Neovim with shared vimrc
- Configures VS Code settings
- macOS: sets up iTerm2 profile, Powerline fonts, key repeat settings

## Day-to-Day Usage

```bash
chezmoi apply          # Deploy changes
chezmoi diff           # Preview changes before applying
chezmoi update         # Pull from git and apply
chezmoi edit ~/.zshrc  # Edit a managed file
```

## Platforms Supported

- [x] macOS
- [x] Debian Linux (headless/SSH)

## What's Included

| Config | Description |
|--------|-------------|
| `.zshrc` | Zsh config with Oh My Zsh, custom theme, plugins |
| `.vimrc` | Vim/Neovim with 40+ plugins via vim-plug |
| `.tmux.conf` | Tmux with vi bindings, mouse support |
| `.gitconfig` | Git aliases and platform-specific credential helper |
| `.aliases` | Shell aliases for git, kubectl, ls |
| `.functions` | Custom shell functions |
| `.inputrc` | Readline config |
| `.psqlrc` | PostgreSQL client config |
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "update README for chezmoi-based setup with macOS and Debian support"
```

---

### Task 15: Verify with chezmoi

**Step 1: Ensure chezmoi is installed**

```bash
# macOS
brew install chezmoi
# or
sh -c "$(curl -fsLS get.chezmoi.io)"
```

**Step 2: Initialize chezmoi with the source directory**

```bash
chezmoi init --source ~/.dotfiles
```

Expected: No errors. Creates `~/.config/chezmoi/chezmoi.toml`.

**Step 3: Preview what chezmoi would deploy**

```bash
chezmoi diff
```

Expected: Shows the diff between current home directory state and what chezmoi would deploy. Review that:
- All dotfiles are listed
- Template substitutions are correct for the current OS
- No unexpected files

**Step 4: Verify template rendering**

```bash
chezmoi cat ~/.zshrc | head -20
chezmoi cat ~/.gitconfig
chezmoi cat ~/.tmux.conf | grep -A1 "default-command"
chezmoi cat ~/.aliases | head -1
```

Expected: Templates render correctly for the current OS (macOS).

**Step 5: Dry run apply**

```bash
chezmoi apply --dry-run --verbose
```

Expected: Shows what would be done without making changes. Verify scripts would run correctly.

**Step 6: Apply (if dry run looks good)**

```bash
chezmoi apply --verbose
```

Expected: All files deployed, scripts executed successfully.
