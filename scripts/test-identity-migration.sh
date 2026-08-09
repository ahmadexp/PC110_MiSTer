#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! grep -q '"PC110;UART' "${repo_dir}/PC110.sv"; then
  echo "FAIL: PC110.sv does not advertise the PC110 service identity" >&2
  exit 1
fi
if grep -q '"AO486;UART' "${repo_dir}/PC110.sv"; then
  echo "FAIL: PC110.sv still advertises AO486" >&2
  exit 1
fi

test_root=$(mktemp -d -t pc110-identity-test.XXXXXX)
trap 'rm -rf "${test_root}"' EXIT
fat_root="${test_root}/fat"
old_home="${fat_root}/games/ao486"
new_home="${fat_root}/games/PC110"
mkdir -p "${old_home}" "${fat_root}/config"

printf 'PC110\n' > "${fat_root}/MiSTer"
printf 'bios-test\n' > "${old_home}/pc110_bios.bin"
printf 'font-test\n' > "${old_home}/pc110_font.bin"
printf 'boot0-test\n' > "${old_home}/boot0.rom"
printf 'boot1-test\n' > "${old_home}/boot1.rom"
printf 'disk-test\n' > "${old_home}/Personaware-disk.vhd"
printf 'HEADS = 2\nSECTORS = 32\nCYLINDERS = 128\n' \
  > "${old_home}/Personaware-disk.cfg"
touch "${test_root}/MiSTer_cmd"

FAT_ROOT="${fat_root}" MISTER_CMD="${test_root}/MiSTer_cmd" \
  SKIP_MENU_LOAD=1 "${repo_dir}/scripts/migrate-pc110-identity.sh"

for asset in pc110_bios.bin pc110_font.bin boot0.rom boot1.rom \
             Personaware-disk.vhd Personaware-disk.cfg; do
  cmp "${old_home}/${asset}" "${new_home}/${asset}"
done

test "$(wc -c < "${fat_root}/config/PC110sys.cfg" | tr -d ' ')" = 6148
test "$(dd if="${fat_root}/config/PC110sys.cfg" bs=1 skip=2052 count=35 2>/dev/null | tr -d '\000')" = \
  "games/PC110/Personaware-disk.vhd"
test "$(tr -d '\000' < "${fat_root}/config/PC110.f7")" = \
  "${new_home}/pc110_bios.bin"
test "$(tr -d '\000' < "${fat_root}/config/PC110.f6")" = \
  "${new_home}/pc110_font.bin"
test "$(wc -c < "${fat_root}/config/uartmode.PC110" | tr -d ' ')" = 4
test "$(wc -c < "${fat_root}/config/uartspeed.PC110" | tr -d ' ')" = 12

echo "PASS: PC110 identity and AO486-to-PC110 asset migration"
