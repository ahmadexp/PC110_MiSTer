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
if ! strings "${fat_root}/MiSTer" 2>/dev/null | grep -qx PC110; then
  echo "error: installed MiSTer Main does not recognize the PC110 x86 variant" >&2
  echo "       update Main to a version containing Main_MiSTer#1272 first" >&2
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

# Remove duplicate menu entries only after copying every old PC110 RBF into
# the timestamped backup directory.
for existing_core in "${fat_root}/_Computer/IBM PC110"*.rbf \
                     "${fat_root}/_Computer/PC110_"*.rbf; do
  if [ ! -e "${existing_core}" ]; then
    continue
  fi
  existing_relative=${existing_core#"${fat_root}/"}
  backup_existing "${existing_relative}"
  rm -f "${existing_core}"
done

install_payload "_Computer/IBM PC110_20260808.rbf"
install_payload "games/PC110/Personaware-disk.vhd"
install_payload "games/PC110/Personaware-disk.cfg"

mkdir -p "${fat_root}/config" "${fat_root}/games/PC110"

# Migrate only explicitly PC110-named assets from the former AO486 Home. This
# leaves a normal AO486 installation and all of its configuration untouched.
for asset in pc110_bios.bin pc110_font.bin boot0.rom boot1.rom; do
  old_asset="${fat_root}/games/ao486/${asset}"
  new_asset="${fat_root}/games/PC110/${asset}"
  if [ ! -e "${new_asset}" ] && [ -s "${old_asset}" ]; then
    cp "${old_asset}" "${new_asset}"
  fi
done

bios_path="${fat_root}/games/PC110/pc110_bios.bin"
font_path="${fat_root}/games/PC110/pc110_font.bin"
if [ -s "${bios_path}" ]; then
  backup_existing "config/PC110.f7"
  printf '%s\0' "${bios_path}" > "${fat_root}/config/PC110.f7.pc110-new"
  mv "${fat_root}/config/PC110.f7.pc110-new" "${fat_root}/config/PC110.f7"
  echo "Configured the existing PC110 BIOS image."
else
  echo "warning: ${bios_path} is missing" >&2
  echo "Prepare and copy your own IBM PC110 ROM files before starting the core." >&2
fi

if [ -s "${font_path}" ]; then
  backup_existing "config/PC110.f6"
  printf '%s\0' "${font_path}" > "${fat_root}/config/PC110.f6.pc110-new"
  mv "${fat_root}/config/PC110.f6.pc110-new" "${fat_root}/config/PC110.f6"
  echo "Configured the existing PC110 font ROM image."
fi

# Main's x86 configuration is a version word followed by six 1024-byte image
# paths. On a new installation, preselect PersonaWare as IDE 0-0 (slot 2).
if [ ! -s "${fat_root}/config/PC110sys.cfg" ]; then
  config_tmp="${fat_root}/config/PC110sys.cfg.pc110-new"
  dd if=/dev/zero of="${config_tmp}" bs=6148 count=1 2>/dev/null
  printf '\003\000\000\000' | dd of="${config_tmp}" bs=1 seek=0 conv=notrunc 2>/dev/null
  printf 'games/PC110/Personaware-disk.vhd\0' | \
    dd of="${config_tmp}" bs=1 seek=2052 conv=notrunc 2>/dev/null
  mv "${config_tmp}" "${fat_root}/config/PC110sys.cfg"
fi

backup_existing "config/uartmode.PC110"
printf '\004\000\000\000' > "${fat_root}/config/uartmode.PC110.pc110-new"
mv "${fat_root}/config/uartmode.PC110.pc110-new" \
  "${fat_root}/config/uartmode.PC110"
backup_existing "config/uartspeed.PC110"
printf '\000\302\001\000\022\172\000\000\000\113\000\000' \
  > "${fat_root}/config/uartspeed.PC110.pc110-new"
mv "${fat_root}/config/uartspeed.PC110.pc110-new" \
  "${fat_root}/config/uartspeed.PC110"

sync
echo
echo "IBM PC110 MiSTer package installed."
echo "Core: /media/fat/_Computer/IBM PC110_20260808.rbf"
echo "Disk: /media/fat/games/PC110/Personaware-disk.vhd"
if [ -d "${backup_dir}" ]; then
  echo "Replaced files were backed up under ${backup_dir}"
fi
echo "Open IBM PC110 from the MiSTer Computer menu."
