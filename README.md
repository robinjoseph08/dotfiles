# Dotfiles

User configurations that are tailored to my liking.

## Usage

```bash
cd ~
git clone https://github.com/robinjoseph08/dotfiles.git .dotfiles
cd .dotfiles
./setup.sh
```

## What does it do?

* Installs necessary dependencies
  * Homebrew
  * tmux
  * vim
  * zsh
  * [Oh My Zsh](https://github.com/robbyrussell/oh-my-zsh)
  * [rvm](http://rvm.io/)
  * [nvm](https://github.com/creationix/nvm)
* Copies old dot files that aren't symlinks
* Symlinks new dot files
* Sets up vim and all the plugins
* Sets up zsh

## Platforms supported

- [x] Mac OS X
- [ ] Ubuntu

## Prerequisites

* Mac OS X
  * Xcode (and the Command Line Tools)
