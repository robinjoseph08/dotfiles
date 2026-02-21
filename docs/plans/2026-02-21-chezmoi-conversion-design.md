# Chezmoi Conversion Design

## Goal

Convert the dotfiles repo from a custom `setup.sh` + symlink approach to chezmoi, with support for both macOS and Debian Linux (headless/SSH-only).

## Approach

Full chezmoi with Go templates for OS-conditional sections. Single source of truth — no duplicated files.

## Repository Structure

```
~/.dotfiles/
├── .chezmoi.toml.tmpl
├── .chezmoiignore
├── dot_aliases
├── dot_bash_profile
├── dot_functions
├── dot_gitconfig.tmpl
├── dot_inputrc
├── dot_psqlrc
├── dot_tmux.conf.tmpl
├── dot_vimrc
├── dot_zshrc.tmpl
├── dot_oh-my-zsh/
│   └── custom/
│       └── themes/
│           └── robin.zsh-theme
├── private_dot_config/
│   └── nvim/
│       └── init.vim
├── run_onchange_install-packages.sh.tmpl
├── run_once_setup-vim.sh.tmpl
├── run_once_setup-oh-my-zsh.sh
├── run_once_setup-macos.sh.tmpl          # iTerm2, Powerline fonts, key repeat (macOS only)
├── README.md
└── LICENSE
```

### Naming Conventions

- `dot_` prefix: deployed as `.filename`
- `.tmpl` suffix: processed as Go template
- `run_onchange_`: re-runs when file content changes
- `run_once_`: runs only on first `chezmoi apply`
- `private_dot_config/`: `~/.config/` with restricted permissions

## Templated Files

Only 3 config files need templates:

### dot_gitconfig.tmpl

Credential helper: `osxkeychain` on macOS, `store` on Linux.

### dot_zshrc.tmpl

OS-conditional blocks for:
- Homebrew init (macOS only)
- zsh-syntax-highlighting source path (brew vs apt location)
- zsh-completions FPATH (brew vs system)
- fzf keybindings/completions path
- Version manager paths work the same on both OSes

### dot_tmux.conf.tmpl

`reattach-to-user-namespace` wrapper only on macOS.

## Scripts

### run_onchange_install-packages.sh.tmpl

- macOS: Installs Homebrew if missing, then `brew install` for all packages including goenv from HEAD
- Debian: `apt-get install` for available packages, git-clone-based installs for nodenv/rbenv/pyenv/goenv

### run_once_setup-oh-my-zsh.sh

Installs Oh My Zsh if `~/.oh-my-zsh` doesn't exist. Same on both OSes.

### run_once_setup-vim.sh.tmpl

Creates `~/.vim/bundle`, `~/.vim/undo`, installs vim-plug, runs `PlugInstall`.

### run_once_setup-macos.sh.tmpl

macOS-only (guarded by template). Handles:
- iTerm2 dynamic profile hard link
- Powerline fonts installation
- Key repeat `defaults write` settings

## .chezmoiignore

```
{{ if ne .chezmoi.os "darwin" }}
iterm.json
{{ end }}

README.md
LICENSE
docs/
```

## VS Code Settings

Managed via chezmoi. Path differs per OS:
- macOS: `~/Library/Application Support/Code/User/settings.json`
- Linux: `~/.config/Code/User/settings.json`

Handled with `private_dot_config/Code/User/settings.json` on Linux. macOS path handled via a symlink or `exact_` directory mapping.

## Install Workflow

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply robinjoseph08 --source ~/.dotfiles
```

## Day-to-Day Workflow

- Edit files in `~/.dotfiles`
- `chezmoi apply` to deploy
- `chezmoi diff` to preview
- `chezmoi update` to pull + apply

## What Gets Removed

- `setup.sh` (replaced by chezmoi scripts)
- `old/` directory (chezmoi handles backups)

## README Update

Update README.md with:
- New chezmoi-based install instructions for macOS and Debian
- Supported platforms section updated
- Day-to-day workflow commands
- Remove old setup.sh references
