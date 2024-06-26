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
BREW+=' jq'
BREW+=' kubectl'
BREW+=' neovim'
BREW+=' nodenv'
BREW+=' reattach-to-user-namespace'
BREW+=' ripgrep'
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
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  echo "Installing$BREW..."
  brew install $BREW 2> /dev/null
  echo "Installing goenv from HEAD..."
  brew install --HEAD goenv 2> /dev/null
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
echo "Setting up iTerm2..."
mkdir -p ~/Library/Application\ Support/iTerm2/DynamicProfiles
if check_file '~/Library/Application Support/iTerm2/DynamicProfiles/iterm.json'; then
  echo "Copying old iterm.json into $OLD_DIR..."
  cp ~/Library/Application\ Support/iTerm2/DynamicProfiles/iterm.json $OLD_DIR
fi
# This must be a hard link because iTerm can't read symlinks
ln -f $DOTFILES_DIR/iterm.json ~/Library/Application\ Support/iTerm2/DynamicProfiles
echo "=== Make sure you set this profile as the default one in iTerm2 ==="
echo "...done"
echo

echo
echo "Setting up VS Code..."
mkdir -p ~/Library/Application\ Support/Code/User
if check_file '~/Library/Application Support/Code/User/settings.json'; then
  echo "Copying old settings.json into $OLD_DIR..."
  cp ~/Library/Application\ Support/Code/User/settings.json $OLD_DIR/vscode.json
fi
ln -sf $DOTFILES_DIR/vscode.json ~/Library/Application\ Support/Code/User/settings.json
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
