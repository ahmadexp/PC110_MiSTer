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
  "${patch_dir}/0001-IDE-complete-common-no-data-ATA-commands.patch"
)

git -C "${main_dir}" apply --check "${patches[@]}"
git -C "${main_dir}" apply "${patches[@]}"

echo "Applied the generic Main compatibility patches to ${main_dir}"
