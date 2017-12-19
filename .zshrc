# Path to your oh-my-zsh installation.
export ZSH=~/.oh-my-zsh

# Returns whether the given command is executable or aliased.
_has() {
  return $( whence $1 >/dev/null )
}

_append_to_path() {
  if [ -d $1 -a -z ${path[(r)$1]} ]; then
    path=($1 $path);
  fi
}

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
ZSH_THEME="af-magic"

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to disable bi-weekly auto-update checks.
# DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to change how often to auto-update (in days).
# export UPDATE_ZSH_DAYS=13

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
#ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# The optional three formats: "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git npm)

# User configuration

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# export MANPATH="/usr/local/man:$MANPATH"

source $ZSH/oh-my-zsh.sh

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# ssh
# export SSH_KEY_PATH="~/.ssh/dsa_id"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# Aliases
source ~/.aliases
source ~/.lob_aliases

# editor
export EDITOR=vim

# grep
GREP_OPTIONS=""
GREP_OPTIONS+=" --color=auto"
GREP_OPTIONS+=" --exclude-dir=.bzr"
GREP_OPTIONS+=" --exclude-dir=CVS"
GREP_OPTIONS+=" --exclude-dir=.git"
GREP_OPTIONS+=" --exclude-dir=.hg"
GREP_OPTIONS+=" --exclude-dir=.svn"
GREP_OPTIONS+=" --exclude-dir=node_modules"
GREP_OPTIONS+=" --exclude-dir=coverage"
GREP_OPTIONS+=" --exclude-dir=dist"
GREP_OPTIONS+=" --exclude-dir=vendor"
GREP_OPTIONS+=" --exclude=./newrelic_agent.log"
GREP_OPTIONS+=" --exclude=./npm-shrinkwrap.json"
GREP_OPTIONS+=" --exclude=./CHANGELOG.md"
GREP_OPTIONS+=" --exclude=./public/main.min.css"
GREP_OPTIONS+=" --exclude=./public/bundle.js"
export GREP_OPTIONS

# X11
export PATH="$PATH:/opt/X11/bin"

# nvm
export NVM_DIR=~/.nvm
source $NVM_DIR/nvm.sh

# avn
[[ -s "$HOME/.avn/bin/avn.sh" ]] && source "$HOME/.avn/bin/avn.sh"

# rvm
export PATH="$PATH:$HOME/.rvm/bin"
source ~/.rvm/scripts/rvm

# .inputrc
bindkey '^[OA' history-beginning-search-backward
bindkey '^[OB' history-beginning-search-forward

# zsh syntax highlighting
source /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Enable Elixir/Erlang REPL History
export ERL_AFLAGS="-kernel shell_history enabled"

# Add Go to Path
export PATH=$PATH:$(go env GOPATH)/bin
export GOPATH=$(go env GOPATH)

# Add Yarn to Path
export PATH="$PATH:`yarn global bin`"

# tabtab source for serverless package
# uninstall by removing these lines or running `tabtab uninstall serverless`
[[ -f /Users/stewart/picasso/node_modules/tabtab/.completions/serverless.zsh ]] && . /Users/stewart/picasso/node_modules/tabtab/.completions/serverless.zsh
# tabtab source for sls package
# uninstall by removing these lines or running `tabtab uninstall sls`
[[ -f /Users/stewart/picasso/node_modules/tabtab/.completions/sls.zsh ]] && . /Users/stewart/picasso/node_modules/tabtab/.completions/sls.zsh

# fzf via Homebrew
if [ -e /usr/local/opt/fzf/shell/completion.zsh ]; then
  source /usr/local/opt/fzf/shell/key-bindings.zsh
  source /usr/local/opt/fzf/shell/completion.zsh
fi

# fzf via local installation
if [ -e ~/.fzf ]; then
  _append_to_path ~/.fzf/bin
  source ~/.fzf/shell/key-bindings.zsh
  source ~/.fzf/shell/completion.zsh
fi

# fzf + ag configuration
if _has fzf && _has ag; then
  export FZF_DEFAULT_COMMAND='ag --nocolor -g ""'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_DEFAULT_OPTS='
  --color dark,hl:33,hl+:37,fg+:235,bg+:136,fg+:254
  --color info:254,prompt:37,spinner:108,pointer:235,marker:235
  '
fi
