#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 PERSONAWARE_DISK_VHD [PARTITION_BYTE_OFFSET]" >&2
  exit 2
fi

image_path="$1"
partition_offset="${2:-16384}"

if [[ ! -f "${image_path}" ]]; then
  echo "error: disk image not found: ${image_path}" >&2
  exit 1
fi

for tool in mcopy mtype perl; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "error: required tool not found: ${tool}" >&2
    exit 1
  fi
done

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
config_path="${tmp_dir}/CONFIG.SYS"
backup_path="${image_path}.pre-noems"

mcopy -o -i "${image_path}@@${partition_offset}" ::CONFIG.SYS "${config_path}"

if tr -d '\r\032' < "${config_path}" |
   grep -Fqx 'DEVICE=C:\DOS\EMM386.EXE NOEMS'; then
  echo "CONFIG.SYS already uses EMM386 NOEMS"
  exit 0
fi

old_line='DEVICE=C:\DOS\EMM386.EXE RAM I=B000-B7FF X=DC00-DFFF X=E000-EFFF FRAME=CC00'
if ! tr -d '\r\032' < "${config_path}" | grep -Fqx "${old_line}"; then
  echo "error: expected EMM386 configuration was not found" >&2
  exit 1
fi

if [[ ! -e "${backup_path}" ]]; then
  cp -p "${image_path}" "${backup_path}"
fi

perl -pi -e \
  's/^DEVICE=C:\\DOS\\EMM386\.EXE RAM I=B000-B7FF X=DC00-DFFF X=E000-EFFF FRAME=CC00\r?$/DEVICE=C:\\DOS\\EMM386.EXE NOEMS\r/' \
  "${config_path}"
mcopy -o -i "${image_path}@@${partition_offset}" "${config_path}" ::CONFIG.SYS

if ! mtype -i "${image_path}@@${partition_offset}" ::CONFIG.SYS |
     tr -d '\r\032' | grep -Fqx 'DEVICE=C:\DOS\EMM386.EXE NOEMS'; then
  echo "error: CONFIG.SYS verification failed; backup is ${backup_path}" >&2
  exit 1
fi

echo "Patched ${image_path}"
echo "Backup: ${backup_path}"
