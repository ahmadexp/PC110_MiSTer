#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/Main_MiSTer" >&2
  exit 2
fi

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
main_dir="$(cd "$1" && pwd)"
patch_dir="${repo_dir}/scripts/main-patches"
patches=(
  "${patch_dir}/0002-x86-recognize-PC110-as-an-x86-variant.patch"
)

git -C "${main_dir}" apply --check "${patches[@]}"
git -C "${main_dir}" apply "${patches[@]}"

echo "Applied PC110 x86-variant recognition to ${main_dir}"
