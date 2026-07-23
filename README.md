# Dotfiles

User configurations that are tailored to my liking.

## Usage

```bash
cd ~
git clone git@github.com:robinjoseph08/dotfiles.git .dotfiles
cd .dotfiles
./setup.sh
```

To install only the shared AI configuration:

```bash
./scripts/setup-ai.sh
```

The standalone AI setup requires `jq`.

## What does it do?

* Installs command-line dependencies with Homebrew on macOS
* Backs up existing configuration under `old/`
* Symlinks shell, terminal, editor, and application configuration
* Sets up Vim, Neovim, Zsh, iTerm2, VS Code, Herdr, and wktr
* Sets up shared AI instructions and skills
* Sets up Claude Code settings, commands, and status line
* Sets up Pi settings, packages, keybindings, extensions, and themes
* Makes shared skills available to Codex

See [`ai/README.md`](ai/README.md) for what is shared and what intentionally remains local.

## Platforms supported

- [x] macOS
- [x] Linux, without platform-specific dependency or application setup

On Linux, the setup script links portable configuration and skips macOS-only steps. Optional setup is also skipped when its required tools are unavailable. Install any desired command-line dependencies with your system package manager.

## Prerequisites

* macOS
  * Xcode (and the Command Line Tools)
