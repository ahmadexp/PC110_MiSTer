#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mister_host="${MISTER_HOST:-root@mister.local}"
rbf_path="${repo_dir}/artifacts/PC110.rbf"
rom_dir="${repo_dir}/artifacts/roms"
stamp="$(date +%Y%m%d-%H%M%S)"
remote_stage="/media/fat/games/ao486"
remote_rbf="/media/fat/_Computer/IBM PC110_${stamp}.rbf"
remote_rbf_upload="/media/fat/_Computer/PC110.upload.rbf"

if [[ ! -s "${rbf_path}" || ! -s "${rom_dir}/boot0.rom" ||
      ! -s "${rom_dir}/boot1.rom" || ! -s "${rom_dir}/pc110_bios.bin" ]]; then
  echo "error: build the core and run scripts/prepare-roms.sh first" >&2
  exit 1
fi

# The browser-visible RBF name is IBM PC110, while the internal service name is
# AO486 so the core works with stock Main's x86 transport. Main therefore uses
# games/ao486 and AO486-named config files. Existing files are not deleted.

# Remove earlier PC110 builds before staging the new one so the core list
# does not accumulate stale bitstreams across rapid iteration.  Set
# KEEP_OLD_RBF=1 to retain them.
if [[ "${KEEP_OLD_RBF:-0}" != "1" ]]; then
  ssh "${mister_host}" \
    "rm -f /media/fat/_Computer/PC110_*.rbf /media/fat/_Computer/IBM\\ PC110_*.rbf"
fi

ssh "${mister_host}" "mkdir -p '${remote_stage}'"

scp "${rbf_path}" "${mister_host}:${remote_rbf_upload}"
ssh "${mister_host}" "mv '${remote_rbf_upload}' '${remote_rbf}'"
scp "${rom_dir}/boot0.rom" "${rom_dir}/boot1.rom" \
  "${rom_dir}/pc110_bios.bin" "${mister_host}:${remote_stage}/"
if [[ -s "${rom_dir}/pc110_font.bin" ]]; then
  scp "${rom_dir}/pc110_font.bin" "${mister_host}:${remote_stage}/"
fi

ssh "${mister_host}" "printf '${remote_stage}/pc110_bios.bin\\0' > /media/fat/config/AO486.f7 && \
  if [ -f '${remote_stage}/pc110_font.bin' ]; then \
    printf '${remote_stage}/pc110_font.bin\\0' > /media/fat/config/AO486.f6; \
  fi && \
  printf '\\004\\000\\000\\000' > /media/fat/config/uartmode.AO486 && \
  printf '\\000\\302\\001\\000\\022\\172\\000\\000\\000\\113\\000\\000' \
    > /media/fat/config/uartspeed.AO486 && \
  sync"

echo "Deployed ${remote_rbf}"
