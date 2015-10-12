# Aliases
source ~/.aliases

# Bash Prompt
export PS1="\h:\[\e[0;32m\]\W\[\e[00m\] \u\$ "

# nvm
export NVM_DIR=~/.nvm
source $(brew --prefix nvm)/nvm.sh

[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm" # Load RVM into a shell session *as a function*
