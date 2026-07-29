#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mister_host="${MISTER_HOST:-root@192.168.1.74}"
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

# The core identifies itself as PC110, so Main keeps every asset under the
# PC110 name: boot ROMs in games/PC110 and remembered FC6/FC7 paths in
# config/PC110.f6 and PC110.f7. No other core's assets are touched.
#
# Main's x86 support (IDE image mounting, CMOS) activates by core name, so a
# Main binary that recognizes PC110 is required; see docs/STATUS.md.

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

ssh "${mister_host}" "printf '${remote_stage}/pc110_bios.bin\\0' > /media/fat/config/PC110.f7 && \
  if [ -f '${remote_stage}/pc110_font.bin' ]; then \
    printf '${remote_stage}/pc110_font.bin\\0' > /media/fat/config/PC110.f6; \
  fi && sync"

echo "Deployed ${remote_rbf}"
