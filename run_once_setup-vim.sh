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
