#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Extract values from JSON
model_display=$(echo "$input" | jq -r '.model.display_name')
model_id=$(echo "$input" | jq -r '.model.id')
effort_level=$(echo "$input" | jq -r '.effort.level // empty')
version=$(echo "$input" | jq -r '.version')
usage=$(echo "$input" | jq '.context_window.current_usage')
context_window_size=$(echo "$input" | jq -r '.context_window.context_window_size')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')

# Simplify model name (e.g., "Claude Opus 4.5" -> "Opus 4.5")
model_short=$(echo "$model_display" | sed 's/^Claude //')

# Append reasoning effort if the model supports it (e.g., "Opus 4.5 (high)")
if [ -n "$effort_level" ]; then
    model_short="$model_short ($effort_level)"
fi

# Calculate current context window usage.
if ! [[ "$context_window_size" =~ ^[0-9]+$ ]] || [ "$context_window_size" -le 0 ]; then
    context_window_size=200000
fi

current=0
if [ "$usage" != "null" ]; then
    current=$(echo "$usage" | jq -r '
        [.input_tokens // 0, .cache_creation_input_tokens // 0, .cache_read_input_tokens // 0]
        | if all(.[]; type == "number" and . >= 0) then (add | floor) else 0 end
    ')
fi

pct=$((current * 100 / context_window_size))

# Format token count (e.g., 19000 -> "19k")
if [ "$current" -ge 1000 ]; then
    current_k=$((current / 1000))
    current_display="${current_k}k"
else
    current_display="$current"
fi

# Format total size (e.g., 200000 -> "200k")
if [ "$context_window_size" -ge 1000 ]; then
    size_k=$((context_window_size / 1000))
    size_display="${size_k}k"
else
    size_display="$context_window_size"
fi

context_info="ctx:$pct% ($current_display/$size_display)"

# Get git branch (skip optional locks to avoid blocking)
# In worktrees, .git is a file, not a directory
if [ -e "$current_dir/.git" ]; then
    branch=$(cd "$current_dir" && git --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || echo "detached")
else
    branch="no-git"
fi

# Get project name (basename of current directory)
project=$(basename "$current_dir")

# Get current timestamp
timestamp=$(date +"%H:%M:%S")

# Define rainbow colors (ANSI escape codes)
RED='\033[31m'
ORANGE='\033[38;5;208m'
YELLOW='\033[33m'
GREEN='\033[32m'
CYAN='\033[36m'
BLUE='\033[34m'
PURPLE='\033[35m'
RESET='\033[0m'

# Output the status line with rainbow colors
printf "${RED}%s${RESET} | ${ORANGE}claude v%s${RESET} | ${YELLOW}%s${RESET} | ${GREEN}%s${RESET} | ${CYAN}%s${RESET} | ${BLUE}%s${RESET}" "$model_short" "$version" "$context_info" "$branch" "$project" "$timestamp"
