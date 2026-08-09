#!/bin/sh
set -eu

fat_root=${FAT_ROOT:-/media/fat}
mister_cmd=${MISTER_CMD:-/dev/MiSTer_cmd}

if [ ! -d "${fat_root}" ] || [ ! -e "${mister_cmd}" ]; then
  echo "error: run this migration on a MiSTer Linux system" >&2
  exit 1
fi
if ! strings "${fat_root}/MiSTer" 2>/dev/null | grep -qx PC110; then
  echo "error: MiSTer Main does not recognize the PC110 x86 variant" >&2
  echo "       install a Main version containing Main_MiSTer#1272 first" >&2
  exit 1
fi

if [ "${SKIP_MENU_LOAD:-0}" != 1 ]; then
  timeout 3 sh -c "printf 'load_core /media/fat/menu.rbf\n' > '${mister_cmd}'" || true
  sleep 5
fi

stamp=$(date +%Y%m%d-%H%M%S)
backup_dir="${fat_root}/backup/IBM-PC110-identity-${stamp}"
old_home="${fat_root}/games/ao486"
new_home="${fat_root}/games/PC110"
config_dir="${fat_root}/config"
mkdir -p "${new_home}" "${config_dir}"

backup_file() {
  source_path=$1
  if [ -e "${source_path}" ]; then
    relative=${source_path#"${fat_root}/"}
    target_path="${backup_dir}/${relative}"
    mkdir -p "$(dirname -- "${target_path}")"
    cp -p "${source_path}" "${target_path}"
  fi
}

copy_if_missing() {
  filename=$1
  source_path="${old_home}/${filename}"
  target_path="${new_home}/${filename}"
  if [ ! -e "${target_path}" ] && [ -s "${source_path}" ]; then
    cp "${source_path}" "${target_path}"
    echo "Migrated ${filename}"
  fi
}

for filename in pc110_bios.bin pc110_font.bin boot0.rom boot1.rom \
                Personaware-disk.vhd Personaware-disk.cfg; do
  copy_if_missing "${filename}"
done

if [ -s "${new_home}/pc110_bios.bin" ]; then
  backup_file "${config_dir}/PC110.f7"
  printf '%s\0' "${new_home}/pc110_bios.bin" > "${config_dir}/PC110.f7.pc110-new"
  mv "${config_dir}/PC110.f7.pc110-new" "${config_dir}/PC110.f7"
fi
if [ -s "${new_home}/pc110_font.bin" ]; then
  backup_file "${config_dir}/PC110.f6"
  printf '%s\0' "${new_home}/pc110_font.bin" > "${config_dir}/PC110.f6.pc110-new"
  mv "${config_dir}/PC110.f6.pc110-new" "${config_dir}/PC110.f6"
fi

if [ ! -s "${config_dir}/PC110sys.cfg" ] && \
   [ -s "${new_home}/Personaware-disk.vhd" ]; then
  config_tmp="${config_dir}/PC110sys.cfg.pc110-new"
  dd if=/dev/zero of="${config_tmp}" bs=6148 count=1 2>/dev/null
  printf '\003\000\000\000' | dd of="${config_tmp}" bs=1 seek=0 conv=notrunc 2>/dev/null
  printf 'games/PC110/Personaware-disk.vhd\0' | \
    dd of="${config_tmp}" bs=1 seek=2052 conv=notrunc 2>/dev/null
  mv "${config_tmp}" "${config_dir}/PC110sys.cfg"
fi

backup_file "${config_dir}/uartmode.PC110"
printf '\004\000\000\000' > "${config_dir}/uartmode.PC110.pc110-new"
mv "${config_dir}/uartmode.PC110.pc110-new" "${config_dir}/uartmode.PC110"
backup_file "${config_dir}/uartspeed.PC110"
printf '\000\302\001\000\022\172\000\000\000\113\000\000' \
  > "${config_dir}/uartspeed.PC110.pc110-new"
mv "${config_dir}/uartspeed.PC110.pc110-new" "${config_dir}/uartspeed.PC110"

sync
echo
echo "PC110 identity migration completed."
echo "PC110 Home: ${new_home}"
echo "AO486 files were not changed."
if [ -d "${backup_dir}" ]; then
  echo "Replaced PC110 configuration was backed up under ${backup_dir}"
fi
