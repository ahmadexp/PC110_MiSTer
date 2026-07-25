#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /media/fat/games/AO486/.pc110-backup-TIMESTAMP" >&2
  exit 2
fi

mister_host="${MISTER_HOST:-root@192.168.1.74}"
remote_backup="$1"

case "${remote_backup}" in
  /media/fat/games/AO486/.pc110-backup-[0-9]*) ;;
  *)
    echo "error: refusing unexpected backup path: ${remote_backup}" >&2
    exit 1
    ;;
esac

ssh "${mister_host}" "test -d '${remote_backup}' && \
  test -s '${remote_backup}/boot0.rom' && \
  test -s '${remote_backup}/boot1.rom' && \
  cp -p '${remote_backup}/boot0.rom' /media/fat/games/AO486/boot0.rom && \
  cp -p '${remote_backup}/boot1.rom' /media/fat/games/AO486/boot1.rom && \
  if [ -f '${remote_backup}/.no-pc110_bios.bin' ]; then rm -f /media/fat/games/AO486/pc110_bios.bin; else cp -p '${remote_backup}/pc110_bios.bin' /media/fat/games/AO486/pc110_bios.bin; fi && \
  if [ -f '${remote_backup}/.no-pc110_font.bin' ]; then rm -f /media/fat/games/AO486/pc110_font.bin; else cp -p '${remote_backup}/pc110_font.bin' /media/fat/games/AO486/pc110_font.bin; fi && \
  if [ -f '${remote_backup}/.no-AO486.f6' ]; then rm -f /media/fat/config/AO486.f6; else cp -p '${remote_backup}/AO486.f6' /media/fat/config/AO486.f6; fi && \
  if [ -f '${remote_backup}/.no-AO486.f7' ]; then rm -f /media/fat/config/AO486.f7; else cp -p '${remote_backup}/AO486.f7' /media/fat/config/AO486.f7; fi && \
  sync"

echo "Restored AO486 assets from ${remote_backup}"
