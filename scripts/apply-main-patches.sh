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
  "${patch_dir}/0001-IDE-honor-explicit-core-geometry.patch"
  "${patch_dir}/0002-x86-add-an-explicit-PC110-machine-profile.patch"
  "${patch_dir}/0003-IDE-complete-diagnostic-and-read-verify-commands.patch"
  "${patch_dir}/0004-scaler-avoid-the-errno-macro-in-a-field-name.patch"
)

git -C "${main_dir}" apply --check "${patches[@]}"
git -C "${main_dir}" apply "${patches[@]}"

echo "Applied the PC110 Main integration to ${main_dir}"
