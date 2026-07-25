#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mister_host="${MISTER_HOST:-root@192.168.1.74}"
rbf_path="${repo_dir}/artifacts/PC110.rbf"
rom_dir="${repo_dir}/artifacts/roms"
stamp="$(date +%Y%m%d-%H%M%S)"
remote_stage="/media/fat/games/PC110"
remote_backup="/media/fat/games/AO486/.pc110-backup-${stamp}"

if [[ ! -s "${rbf_path}" || ! -s "${rom_dir}/boot0.rom" ||
      ! -s "${rom_dir}/boot1.rom" || ! -s "${rom_dir}/pc110_bios.bin" ]]; then
  echo "error: build the core and run scripts/prepare-roms.sh first" >&2
  exit 1
fi

ssh "${mister_host}" "mkdir -p '${remote_stage}' '${remote_backup}' && \
  cp -p /media/fat/games/AO486/boot0.rom '${remote_backup}/' && \
  cp -p /media/fat/games/AO486/boot1.rom '${remote_backup}/' && \
  if [ -f /media/fat/games/AO486/pc110_bios.bin ]; then cp -p /media/fat/games/AO486/pc110_bios.bin '${remote_backup}/'; else touch '${remote_backup}/.no-pc110_bios.bin'; fi && \
  if [ -f /media/fat/games/AO486/pc110_font.bin ]; then cp -p /media/fat/games/AO486/pc110_font.bin '${remote_backup}/'; else touch '${remote_backup}/.no-pc110_font.bin'; fi && \
  if [ -f /media/fat/config/AO486.f6 ]; then cp -p /media/fat/config/AO486.f6 '${remote_backup}/'; else touch '${remote_backup}/.no-AO486.f6'; fi && \
  if [ -f /media/fat/config/AO486.f7 ]; then cp -p /media/fat/config/AO486.f7 '${remote_backup}/'; else touch '${remote_backup}/.no-AO486.f7'; fi"

scp "${rbf_path}" "${mister_host}:/media/fat/_Computer/PC110_${stamp}.rbf"
scp "${rom_dir}/boot0.rom" "${rom_dir}/boot1.rom" \
  "${rom_dir}/pc110_bios.bin" "${mister_host}:${remote_stage}/"
if [[ -s "${rom_dir}/pc110_font.bin" ]]; then
  scp "${rom_dir}/pc110_font.bin" "${mister_host}:${remote_stage}/"
fi

# The installed 2022 Main binary recognizes the AO486 identifier only, so it
# loads boot*.rom from games/AO486.  Replace those two files only after making
# the timestamped backup above.
ssh "${mister_host}" "cp '${remote_stage}/boot0.rom' /media/fat/games/AO486/boot0.rom && \
  cp '${remote_stage}/boot1.rom' /media/fat/games/AO486/boot1.rom && \
  cp '${remote_stage}/pc110_bios.bin' /media/fat/games/AO486/pc110_bios.bin && \
  if [ -f '${remote_stage}/pc110_font.bin' ]; then cp '${remote_stage}/pc110_font.bin' /media/fat/games/AO486/pc110_font.bin; fi && \
  printf '/media/fat/games/AO486/pc110_bios.bin\\0' > /media/fat/config/AO486.f7 && \
  if [ -f /media/fat/games/AO486/pc110_font.bin ]; then \
    printf '/media/fat/games/AO486/pc110_font.bin\\0' > /media/fat/config/AO486.f6; \
  fi && sync"

echo "Deployed /media/fat/_Computer/PC110_${stamp}.rbf"
echo "Previous AO486 ROMs: ${remote_backup}"
