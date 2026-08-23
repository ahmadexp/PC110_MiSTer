#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
catalog=${1:-"$root_dir/core-catalog.tsv"}
destination=${2:-"$root_dir/upstream/cores"}

mkdir -p "$destination"

while IFS=$'\t' read -r tier name repository purpose; do
  if [[ -z "$tier" || "$tier" == \#* ]]; then
    continue
  fi

  core_dir="$destination/$name"
  if [[ -d "$core_dir/.git" ]]; then
    git -C "$core_dir" fetch --depth 1 origin
    git -C "$core_dir" reset --keep FETCH_HEAD
  else
    git clone --depth 1 "$repository" "$core_dir"
  fi

  printf '%s\t%s\t%s\n' "$tier" "$name" "$purpose"
done < "$catalog"
