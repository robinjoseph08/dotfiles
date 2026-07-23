#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STATUSLINE="$SCRIPT_DIR/../ai/claude/statusline.sh"
TEMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TEMP_ROOT"' EXIT

render() {
  local usage=$1
  local size=$2

  jq -n \
    --argjson usage "$usage" \
    --argjson size "$size" \
    --arg cwd "$TEMP_ROOT" \
    '{
      model: {display_name: "Claude Test", id: "test"},
      effort: {level: "high"},
      version: "1.0.0",
      context_window: {current_usage: $usage, context_window_size: $size},
      workspace: {current_dir: $cwd}
    }' | "$STATUSLINE"
}

output=$(render null 100000)
[[ "$output" == *"ctx:0% (0/100k)"* ]]

output=$(render '{}' 0)
[[ "$output" == *"ctx:0% (0/200k)"* ]]

output=$(render '{"input_tokens":10000,"cache_creation_input_tokens":15000,"cache_read_input_tokens":25000}' 100000)
[[ "$output" == *"ctx:50% (50k/100k)"* ]]

echo "Claude status line tests passed."
