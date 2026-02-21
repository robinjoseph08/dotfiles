# Dotfiles

User configurations managed with [chezmoi](https://www.chezmoi.io/), supporting macOS and Debian Linux.

## Quick Start

### Fresh machine (macOS or Debian)

Install chezmoi and apply dotfiles in one command:

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
- macOS-specific: iTerm2 profile, Powerline fonts, key repeat settings

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

## Prerequisites

- macOS: Xcode Command Line Tools (`xcode-select --install`)
- Debian: `curl` and `git` (`sudo apt-get install -y curl git`)
