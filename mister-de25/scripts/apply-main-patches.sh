#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
source_dir=${1:-"$root_dir/upstream/Main_MiSTer"}
latest_patch=$(find "$root_dir/patches/Main_MiSTer" -name '*.patch' \
  -type f | sort | tail -1)

# Later patches intentionally modify lines introduced by earlier patches, so
# their reverse checks need not continue to match after the complete series is
# present. The final patch can only apply after all its prerequisites.
if git -C "$source_dir" apply --reverse --check "$latest_patch" 2>/dev/null; then
  exit 0
fi

for patch_file in "$root_dir"/patches/Main_MiSTer/*.patch; do
  if git -C "$source_dir" apply --reverse --check "$patch_file" 2>/dev/null; then
    continue
  fi
  git -C "$source_dir" apply --check "$patch_file"
  git -C "$source_dir" apply "$patch_file"
done
