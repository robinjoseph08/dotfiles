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
FILES+=' .inputrc'
FILES+=' .vimrc'
FILES+=' .zshrc'

# List of programs to install with brew
BREW=''
BREW+=' nvm'
BREW+=' reattach-to-user-namespace'
BREW+=' tmux'
BREW+=' tree'
BREW+=' vim'
BREW+=' wget'
BREW+=' zsh'
BREW+=' zsh-completions'

function indent {
  sed "s/^/  /g"
}

echo
echo "Setting up dependencies..."
if [[ $OSTYPE == darwin* ]]; then
  if ! type brew > /dev/null 2>&1; then
    echo "Installing brew..." | indent
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)" | indent
  fi
  echo "Installing$BREW..." | indent
  brew install $BREW 2> /dev/null
  if [ ! -d ~/.oh-my-zsh ]; then
    echo "Installing Oh My Zsh..." | indent
    curl -L https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh | sh
    chsh -s /bin/zsh
  fi
  if [ ! -d ~/.rvm ]; then
    echo "Installing rvm..." | indent
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
  if [ -f ~/$f ]; then
    echo "Copying old ~/$f into $OLD_DIR..." | indent
    cp ~/$f $OLD_DIR/$f
  fi
  cp $DOTFILES_DIR/$f ~/$f
done
echo "...done"
echo

echo
echo "Setting up vim..."
if [ ! -d ~/.vim/bundle/Vundle.vim ]; then
  mkdir -p ~/.vim/bundle
  git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim | indent
  vim +PluginInstall +qall | indent
fi
echo "...done"
echo

echo
echo "Setting up zsh..."
mkdir -p ~/.oh-my-zsh/custom/themes
if [ -f ~/.oh-my-zsh/custom/themes/robin.zsh-theme ]; then
  echo "Copying old robin.zsh-theme into $OLD_DIR..." | indent
  cp ~/.oh-my-zsh/custom/themes/robin.zsh-theme $OLD_DIR
fi
cp $DOTFILES_DIR/robin.zsh-theme ~/.oh-my-zsh/custom/themes
echo "...done"
echo
