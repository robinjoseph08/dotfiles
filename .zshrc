# Path to your oh-my-zsh installation.
export ZSH=~/.oh-my-zsh

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
#ZSH_THEME="robbyrussell"
ZSH_THEME="robin"

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
# ENABLE_CORRECTION="true"

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

# setup brew
eval "$(/opt/homebrew/bin/brew shellenv)"

# aliases
source ~/.aliases

# functions
source ~/.functions

# editor
export EDITOR=vim

# less
export LESS="-XR"

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
GREP_OPTIONS+=" --exclude-dir=_build"
GREP_OPTIONS+=" --exclude-dir=deps"
GREP_OPTIONS+=" --exclude=./newrelic_agent.log"
GREP_OPTIONS+=" --exclude=./npm-shrinkwrap.json"
GREP_OPTIONS+=" --exclude=./CHANGELOG.md"
GREP_OPTIONS+=" --exclude=./public/main.min.css"
GREP_OPTIONS+=" --exclude=./public/bundle.js"
GREP_OPTIONS+=" --exclude=./public/bundle.js.map"
export GREP_OPTIONS

# autocompletion
autoload -U compinit && compinit
autoload -U bashcompinit && bashcompinit

# X11
export PATH="$PATH:/opt/X11/bin"

# nodenv
type nodenv > /dev/null 2>&1 && eval "$(nodenv init -)"

# rbenv
type rbenv > /dev/null 2>&1 && eval "$(rbenv init -)"

# .inputrc
bindkey '^[OA' history-beginning-search-backward
bindkey '^[OB' history-beginning-search-forward

# zsh syntax highlighting
[ -f /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && source /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
[ -f /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# yarn
export PATH="$PATH:$HOME/.yarn/bin"

# aws
export AWS_REGION=us-west-2

# go and goenv
export GOENV_DISABLE_GOROOT=1
export GOENV_DISABLE_GOPATH=1
eval "$(goenv init -)"
export GOPATH=$HOME/go
export PATH="$PATH:$GOPATH/bin"

# rust
[[ -s "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env" # load rust

# kubernetes
type kubectl > /dev/null 2>&1 && source <(kubectl completion zsh)

# sublime
export PATH="/Applications/Sublime Text.app/Contents/SharedSupport/bin:$PATH"

# curl
# format to pretty-print timings
# curl -w "$CURL_TIMINGS" -o /dev/null https://google.com
export CURL_TIMINGS='\n            time_namelookup:  %{time_namelookup}\n               time_connect:  %{time_connect}\n            time_appconnect:  %{time_appconnect}\n           time_pretransfer:  %{time_pretransfer}\n              time_redirect:  %{time_redirect}\n         time_starttransfer:  %{time_starttransfer}\n                            ----------\n                 time_total:  %{time_total}\n\n'

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
# filter out gitignored files
export FZF_DEFAULT_COMMAND='ag --hidden --ignore .git -g ""'

# timestamps for history
HIST_FORMAT="'%Y-%m-%d %T:'$(echo -e '\t')"
alias history="fc -t "$HIST_FORMAT" -il 1"
