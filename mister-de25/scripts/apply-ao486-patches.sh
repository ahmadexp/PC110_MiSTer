#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
source_dir=${1:-"$root_dir/upstream/cores/AO486"}

if grep -q 'DE25_AGILEX_PLL' "$source_dir/ao486.sv"; then
    exit 0
fi
latest_patch=$(find "$root_dir/patches/AO486" -name '*.patch' -type f 2>/dev/null | sort | tail -1)
if [[ -z $latest_patch ]]; then
    echo "No ao486 compatibility patch found" >&2
    exit 1
fi
git -C "$source_dir" apply --check --ignore-whitespace "$latest_patch"
git -C "$source_dir" apply --ignore-whitespace "$latest_patch"
