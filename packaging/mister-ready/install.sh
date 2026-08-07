#!/bin/sh
set -eu

package_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
payload_dir="${package_dir}/payload"
fat_root=${FAT_ROOT:-/media/fat}
mister_cmd=${MISTER_CMD:-/dev/MiSTer_cmd}

if [ ! -d "${fat_root}" ] || [ ! -e "${mister_cmd}" ]; then
  echo "error: run this installer on a MiSTer Linux system" >&2
  exit 1
fi
if ! command -v sha256sum >/dev/null 2>&1; then
  echo "error: sha256sum is required" >&2
  exit 1
fi

cd "${package_dir}"
sha256sum -c PAYLOAD.sha256

echo "Switching MiSTer to the menu before copying the disk image."
if [ "${SKIP_MENU_LOAD:-0}" != 1 ]; then
  timeout 3 sh -c "printf 'load_core /media/fat/menu.rbf\n' > '${mister_cmd}'" || true
  sleep 5
fi

stamp=$(date +%Y%m%d-%H%M%S)
backup_dir="${fat_root}/backup/IBM-PC110-${stamp}"

backup_existing() {
  backup_relative=$1
  backup_source="${fat_root}/${backup_relative}"
  if [ -e "${backup_source}" ]; then
    backup_target="${backup_dir}/${backup_relative}"
    mkdir -p "$(dirname -- "${backup_target}")"
    cp -p "${backup_source}" "${backup_target}"
  fi
}

install_payload() {
  install_relative=$1
  backup_existing "${install_relative}"
  install_source="${payload_dir}/${install_relative}"
  install_target="${fat_root}/${install_relative}"
  install_temporary="${install_target}.pc110-new"
  mkdir -p "$(dirname -- "${install_target}")"
  cp "${install_source}" "${install_temporary}"
  sync
  mv "${install_temporary}" "${install_target}"
  install_source_sha=$(sha256sum "${install_source}" | awk '{print $1}')
  install_target_sha=$(sha256sum "${install_target}" | awk '{print $1}')
  if [ "${install_source_sha}" != "${install_target_sha}" ]; then
    echo "error: installed file failed verification: ${install_relative}" >&2
    exit 1
  fi
}

install_payload "_Computer/IBM PC110_20260729.rbf"
install_payload "games/ao486/Personaware-disk.vhd"
install_payload "games/ao486/Personaware-disk.cfg"

mkdir -p "${fat_root}/config" "${fat_root}/games/ao486"

bios_path="${fat_root}/games/ao486/pc110_bios.bin"
font_path="${fat_root}/games/ao486/pc110_font.bin"
if [ -s "${bios_path}" ]; then
  backup_existing "config/AO486.f7"
  printf '%s\0' "${bios_path}" > "${fat_root}/config/AO486.f7.pc110-new"
  mv "${fat_root}/config/AO486.f7.pc110-new" "${fat_root}/config/AO486.f7"
  echo "Configured the existing PC110 BIOS image."
else
  echo "warning: ${bios_path} is missing" >&2
  echo "Prepare and copy your own IBM PC110 ROM files before starting the core." >&2
fi

if [ -s "${font_path}" ]; then
  backup_existing "config/AO486.f6"
  printf '%s\0' "${font_path}" > "${fat_root}/config/AO486.f6.pc110-new"
  mv "${fat_root}/config/AO486.f6.pc110-new" "${fat_root}/config/AO486.f6"
  echo "Configured the existing PC110 font ROM image."
fi

sync
echo
echo "IBM PC110 MiSTer package installed."
echo "Core: /media/fat/_Computer/IBM PC110_20260729.rbf"
echo "Disk: /media/fat/games/ao486/Personaware-disk.vhd"
if [ -d "${backup_dir}" ]; then
  echo "Replaced files were backed up under ${backup_dir}"
fi
echo "Open IBM PC110 from the MiSTer Computer menu."
