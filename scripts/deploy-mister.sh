#!/usr/bin/env bash
# shellcheck disable=SC2029
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mister_host="${MISTER_HOST:-root@mister.local}"
rbf_path="${repo_dir}/artifacts/PC110.rbf"
rom_dir="${repo_dir}/artifacts/roms"
stamp="$(date +%Y%m%d-%H%M%S)"
remote_stage="/media/fat/games/PC110"
remote_rbf="/media/fat/_Computer/IBM PC110_${stamp}.rbf"
remote_rbf_upload="/media/fat/_Computer/PC110.upload.rbf"

if [[ ! -s "${rbf_path}" || ! -s "${rom_dir}/boot0.rom" ||
      ! -s "${rom_dir}/boot1.rom" || ! -s "${rom_dir}/pc110_bios.bin" ]]; then
  echo "error: build the core and run scripts/prepare-roms.sh first" >&2
  exit 1
fi

# The browser-visible RBF name is IBM PC110 and the internal service identity is
# PC110. Main recognizes PC110 as an x86 variant, so it uses the shared x86
# transport with independent PC110 Home, selector, disk and UART configuration.

if [[ "${ALLOW_UNSUPPORTED_MAIN:-0}" != "1" ]]; then
  if ! ssh "${mister_host}" \
    "strings /media/fat/MiSTer 2>/dev/null | grep -qx PC110"; then
    echo "error: MiSTer Main does not recognize the PC110 x86 variant" >&2
    echo "       install a Main build containing MiSTer-devel/Main_MiSTer#1272" >&2
    echo "       or set ALLOW_UNSUPPORTED_MAIN=1 for a deliberate override" >&2
    exit 1
  fi
fi

# Back up earlier PC110 builds before removing them so the core list does not
# accumulate stale bitstreams across rapid iteration. Set KEEP_OLD_RBF=1 to
# retain them in the Computer directory.
if [[ "${KEEP_OLD_RBF:-0}" != "1" ]]; then
  ssh "${mister_host}" "set -e; backup=/media/fat/backup/pc110-deploy-${stamp}; \
    mkdir -p \"\$backup\"; \
    for old in /media/fat/_Computer/PC110_*.rbf /media/fat/_Computer/IBM\\ PC110_*.rbf; do \
      [ -e \"\$old\" ] || continue; mv \"\$old\" \"\$backup/\"; \
    done"
fi

ssh "${mister_host}" "mkdir -p '${remote_stage}' /media/fat/config"

scp "${rbf_path}" "${mister_host}:${remote_rbf_upload}"
ssh "${mister_host}" "mv '${remote_rbf_upload}' '${remote_rbf}'"
scp "${rom_dir}/boot0.rom" "${rom_dir}/boot1.rom" \
  "${rom_dir}/pc110_bios.bin" "${mister_host}:${remote_stage}/"
if [[ -s "${rom_dir}/pc110_font.bin" ]]; then
  scp "${rom_dir}/pc110_font.bin" "${mister_host}:${remote_stage}/"
fi

ssh "${mister_host}" "printf '${remote_stage}/pc110_bios.bin\\0' > /media/fat/config/PC110.f7 && \
  if [ -f '${remote_stage}/pc110_font.bin' ]; then \
    printf '${remote_stage}/pc110_font.bin\\0' > /media/fat/config/PC110.f6; \
  fi && \
  printf '\\004\\000\\000\\000' > /media/fat/config/uartmode.PC110 && \
  printf '\\000\\302\\001\\000\\022\\172\\000\\000\\000\\113\\000\\000' \
    > /media/fat/config/uartspeed.PC110 && \
  sync"

echo "Deployed ${remote_rbf}"
