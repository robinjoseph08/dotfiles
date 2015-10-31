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
FILES+=' .gitconfig'
FILES+=' .inputrc'
FILES+=' .tmux.conf'
FILES+=' .vimrc'
FILES+=' .zshrc'

# List of programs to install with brew
BREW=''
BREW+=' cmake'
BREW+=' nvm'
BREW+=' reattach-to-user-namespace'
BREW+=' tmux'
BREW+=' tree'
BREW+=' vim'
BREW+=' wget'
BREW+=' zsh'
BREW+=' zsh-completions'

# Checks if a file exists but isn't a symlink
function check_file () {
  [ -f $1 ] && [ ! -h $1 ]
}

echo
echo "Setting up dependencies..."
if [[ $OSTYPE == darwin* ]]; then
  if ! type brew > /dev/null 2>&1; then
    echo "Installing brew..."
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
  fi
  echo "Installing$BREW..."
  brew install $BREW 2> /dev/null
  if [ ! -d ~/.oh-my-zsh ]; then
    echo "Installing Oh My Zsh..."
    curl -L https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh | sh
    chsh -s /bin/zsh
  fi
  if [ ! -d ~/.rvm ]; then
    echo "Installing rvm..."
    \curl -sSL https://get.rvm.io | bash
  fi
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
if [ ! -d ~/.vim/bundle/Vundle.vim ]; then
  mkdir -p ~/.vim/bundle
  git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
  git clone https://github.com/Valloric/YouCompleteMe.git ~/.vim/bundle/YouCompleteMe
  cd ~/.vim/bundle/YouCompleteMe
  git submodule update --init --recursive
  ./install.sh
  cd $DOTFILES_DIR
  vim +PluginInstall +qall
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
