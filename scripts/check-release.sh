#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_dir}"

required=(
  PC110.qpf
  PC110.qsf
  PC110.sdc
  PC110.srf
  PC110.sv
  files.qip
  clean.bat
  LICENSE
  THIRD_PARTY_NOTICES.md
  rtl
  sys
)

for path in "${required[@]}"; do
  if [[ ! -e "${path}" ]]; then
    echo "error: required submission path is missing: ${path}" >&2
    exit 1
  fi
done

shopt -s nullglob
release_rbfs=(releases/PC110_????????.rbf)
if ((${#release_rbfs[@]} == 0)); then
  echo "error: no dated releases/PC110_YYYYMMDD.rbf artifact" >&2
  exit 1
fi

for rbf in "${release_rbfs[@]}"; do
  if [[ ! "$(basename "${rbf}")" =~ ^PC110_[0-9]{8}\.rbf$ ]]; then
    echo "error: invalid release filename: ${rbf}" >&2
    exit 1
  fi
  if [[ ! -s "${rbf}" ]] || (($(wc -c < "${rbf}") < 1000000)); then
    echo "error: release artifact is unexpectedly small: ${rbf}" >&2
    exit 1
  fi
done

if git ls-files | grep -Eiq \
  '(^|/)(pc110_bios|pc110_font|boot0|boot1)\.(bin|rom)$|personaware.*\.vhd$'; then
  echo "error: proprietary firmware or disk asset is tracked" >&2
  exit 1
fi

echo "PASS: MiSTer submission layout and firmware exclusion checks"
