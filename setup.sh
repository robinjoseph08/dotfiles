#!/bin/bash

# Variables
DOTFILES_DIR=~/.dotfiles
OLD_DIR=$DOTFILES_DIR/old

# Ensure we're in the dotfiles directory
cd $DOTFILES_DIR

# List of dotfiles for home directory
FILES=''
FILES+=' .aliases'
FILES+=' .bash_profile'
FILES+=' .functions'
FILES+=' .gitconfig'
FILES+=' .inputrc'
FILES+=' .psqlrc'
FILES+=' .tmux.conf'
FILES+=' .vimrc'
FILES+=' .zshrc'

# List of programs to install with brew
BREW=''
BREW+=' awscli'
BREW+=' fd'
BREW+=' fzf'
BREW+=' gh'
BREW+=' herdr'
BREW+=' jq'
BREW+=' mise'
BREW+=' neovim'
BREW+=' reattach-to-user-namespace'
BREW+=' ripgrep'
BREW+=' robinjoseph08/tap/wktr'
BREW+=' tmux'
BREW+=' tree'
BREW+=' vim'
BREW+=' watch'
BREW+=' wget'
BREW+=' zsh'
BREW+=' zsh-completions'
BREW+=' zsh-syntax-highlighting'

# Checks if a file exists but isn't a symlink
function check_file () {
  [ -f "$1" ] && [ ! -h "$1" ]
}

echo
echo "Setting up dependencies..."
if [[ $OSTYPE == darwin* ]]; then
  if ! type brew > /dev/null 2>&1; then
    echo "Installing brew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [ -x /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
      eval "$(/usr/local/bin/brew shellenv)"
    else
      echo "Could not find Homebrew after installation." >&2
      exit 1
    fi
  fi

  BREW_INSTALL_ARGS=''
  if brew install --help 2>&1 | grep -q -- '--no-ask'; then
    BREW_INSTALL_ARGS='--no-ask'
  else
    export HOMEBREW_NO_ASK=1
  fi

  if brew help trust > /dev/null 2>&1; then
    echo "Trusting the robinjoseph08/tap tap..."
    if ! brew trust --tap robinjoseph08/tap; then
      echo "Could not trust robinjoseph08/tap." >&2
      exit 1
    fi
  else
    # Compatibility for Homebrew versions without the explicit trust command.
    export HOMEBREW_NO_REQUIRE_TAP_TRUST=1
  fi

  echo "Installing$BREW..."
  if ! brew install $BREW_INSTALL_ARGS $BREW; then
    echo "Could not install Homebrew dependencies." >&2
    exit 1
  fi
  if [ ! -d ~/.oh-my-zsh ]; then
    echo "Installing Oh My Zsh..."
    curl -L https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh | sh
    chsh -s /bin/zsh
  fi
  echo "Installing fzf extensions..."
  /usr/local/opt/fzf/install
fi
echo "...done"
echo

echo
echo "Copying home directory dotfiles..."
# Create directory to house current dotfiles
# as a backup so you can restore your previous
# setup
if [ ! -e $OLD_DIR ]; then
  echo "Creating directory for current dotfiles: $OLD_DIR..."
  mkdir $OLD_DIR
fi

for f in $FILES; do
  if check_file ~/$f; then
    echo "Copying old ~/$f into $OLD_DIR..."
    cp ~/$f $OLD_DIR/$f
  fi
  ln -sf $DOTFILES_DIR/$f ~/$f
done
echo "...done"
echo

if ! "$DOTFILES_DIR/scripts/setup-ai.sh"; then
  echo "Could not set up AI tools." >&2
  exit 1
fi

echo
echo "Setting up vim..."
if [ ! -d ~/.vim/bundle ]; then
  mkdir -p ~/.vim/bundle
  mkdir -p ~/.vim/undo
  cd $DOTFILES_DIR
  mkdir -p ~/.config/nvim
  ln -s $DOTFILES_DIR/.vimrc ~/.config/nvim/init.vim
  vim +PlugInstall +qall
fi
echo "...done"
echo

echo
echo "Setting up zsh..."
mkdir -p ~/.oh-my-zsh/custom/themes
if check_file ~/.oh-my-zsh/custom/themes/robin.zsh-theme; then
  echo "Copying old robin.zsh-theme into $OLD_DIR..."
  cp ~/.oh-my-zsh/custom/themes/robin.zsh-theme $OLD_DIR
fi
ln -sf $DOTFILES_DIR/robin.zsh-theme ~/.oh-my-zsh/custom/themes
echo "...done"
echo

echo
echo "Setting up herdr..."
if ! mkdir -p ~/.config/herdr; then
  echo "Could not create ~/.config/herdr; leaving the existing config untouched." >&2
  exit 1
fi
if [ -d ~/.config/herdr/config.toml ]; then
  echo "~/.config/herdr/config.toml is a directory; leaving it untouched." >&2
  exit 1
fi
if check_file ~/.config/herdr/config.toml; then
  echo "Copying old herdr config.toml into $OLD_DIR/herdr.toml..."
  if ! cp ~/.config/herdr/config.toml $OLD_DIR/herdr.toml; then
    echo "Could not back up the existing herdr config; leaving it untouched." >&2
    exit 1
  fi
fi
if ! ln -sf $DOTFILES_DIR/herdr.toml ~/.config/herdr/config.toml; then
  echo "Could not link the herdr config." >&2
  exit 1
fi
echo "...done"
echo

echo
echo "Setting up wktr..."
if ! mkdir -p ~/.config/wktr; then
  echo "Could not create ~/.config/wktr; leaving the existing config untouched." >&2
  exit 1
fi
if [ -d ~/.config/wktr/config.yaml ]; then
  echo "~/.config/wktr/config.yaml is a directory; leaving it untouched." >&2
  exit 1
fi
if check_file ~/.config/wktr/config.yaml; then
  echo "Copying old wktr config.yaml into $OLD_DIR/wktr.yaml..."
  if ! cp ~/.config/wktr/config.yaml $OLD_DIR/wktr.yaml; then
    echo "Could not back up the existing wktr config; leaving it untouched." >&2
    exit 1
  fi
fi
if ! ln -sf $DOTFILES_DIR/wktr.yaml ~/.config/wktr/config.yaml; then
  echo "Could not link the wktr config." >&2
  exit 1
fi
echo "...done"
echo

echo
echo "Setting up iTerm2..."
mkdir -p "$HOME/Library/Application Support/iTerm2/DynamicProfiles"
if check_file "$HOME/Library/Application Support/iTerm2/DynamicProfiles/iterm.json"; then
  echo "Copying old iterm.json into $OLD_DIR..."
  cp "$HOME/Library/Application Support/iTerm2/DynamicProfiles/iterm.json" "$OLD_DIR"
fi
# This must be a hard link because iTerm can't read symlinks
ln -f "$DOTFILES_DIR/iterm.json" "$HOME/Library/Application Support/iTerm2/DynamicProfiles"
echo "=== Make sure you set this profile as the default one in iTerm2 ==="
echo "...done"
echo

echo
echo "Setting up VS Code..."
mkdir -p "$HOME/Library/Application Support/Code/User"
if check_file "$HOME/Library/Application Support/Code/User/settings.json"; then
  echo "Copying old settings.json into $OLD_DIR..."
  cp "$HOME/Library/Application Support/Code/User/settings.json" "$OLD_DIR/vscode.json"
fi
ln -sf "$DOTFILES_DIR/vscode.json" "$HOME/Library/Application Support/Code/User/settings.json"
echo "...done"
echo

if [ -z "$(find ~/Library/Fonts -name '*Powerline*')" ]; then
  echo
  echo "Installing Powerline Fonts..."
  git clone https://github.com/powerline/fonts.git --depth=1
  cd fonts
  ./install.sh
  cd ..
  rm -rf fonts
  echo "...done"
  echo
fi

echo
echo "Enabling key repeats on Mac..."
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
echo "...done"
echo
