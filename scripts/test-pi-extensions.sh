#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DOTFILES_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
PI_BIN=${PI_BIN:-$(command -v pi)}
TEMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TEMP_ROOT"' EXIT

PI_ENTRY=$(node -e 'console.log(require("node:fs").realpathSync(process.argv[1]))' "$PI_BIN")
PI_PACKAGE_DIR=$(cd "$(dirname "$PI_ENTRY")/.." && pwd)
PI_DEPENDENCIES="$PI_PACKAGE_DIR/node_modules/@earendil-works"

for package in pi-ai pi-tui; do
  if [ ! -d "$PI_DEPENDENCIES/$package" ]; then
    echo "Could not find $package beside the installed Pi package." >&2
    exit 1
  fi
done

cp -R "$DOTFILES_DIR/ai/pi/extensions" "$TEMP_ROOT/extensions"
mkdir -p "$TEMP_ROOT/node_modules/@earendil-works"
ln -s "$PI_PACKAGE_DIR" "$TEMP_ROOT/node_modules/@earendil-works/pi-coding-agent"
ln -s "$PI_DEPENDENCIES/pi-ai" "$TEMP_ROOT/node_modules/@earendil-works/pi-ai"
ln -s "$PI_DEPENDENCIES/pi-tui" "$TEMP_ROOT/node_modules/@earendil-works/pi-tui"

tests=()
while IFS= read -r test_file; do
  tests[${#tests[@]}]="$test_file"
done < <(find "$TEMP_ROOT/extensions" -name '*.test.ts' -type f -print | sort)

if [ "${#tests[@]}" -eq 0 ]; then
  echo "No Pi extension tests found." >&2
  exit 1
fi

node --test "${tests[@]}"
