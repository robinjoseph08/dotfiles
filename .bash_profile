# Aliases
source ~/.aliases

# Bash Prompt
export PS1="\h:\[\e[0;32m\]\W\[\e[00m\] \u\$ "

# nvm
export NVM_DIR=~/.nvm
if command -v brew > /dev/null 2>&1; then
  NVM_SCRIPT="$(brew --prefix nvm)/nvm.sh"
  [ -s "$NVM_SCRIPT" ] && source "$NVM_SCRIPT"
  unset NVM_SCRIPT
fi

[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm" # Load RVM into a shell session *as a function*
[[ -s "$HOME/.avn/bin/avn.sh" ]] && source "$HOME/.avn/bin/avn.sh" # load avn
[[ -s "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env" # load rust
