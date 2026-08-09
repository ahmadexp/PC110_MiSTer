#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
personaware_image="${1:-}"
output_dir="${2:-${repo_dir}/dist}"
bundle_date=20260808
bundle_name="IBM-PC110-MiSTer-Ready-${bundle_date}"
core_source="${repo_dir}/releases/PC110_20260808.rbf"
expected_core_sha=19df353c0986874ddf2abbd7cd1163292712f04a4283a6e104d7a16080b37e9c
expected_vhd_sha=bb080741f5aac4a6cf9a47672a496c64ab4e332cd7e8535ce9d658e5707867e0

if [[ -z "${personaware_image}" ]]; then
  echo "usage: $0 /path/to/Personaware-English-2.0.img [OUTPUT_DIRECTORY]" >&2
  exit 2
fi
if [[ ! -f "${personaware_image}" ]]; then
  echo "error: PersonaWare image not found: ${personaware_image}" >&2
  exit 1
fi
for command in python3 sha256sum; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "error: required command not found: ${command}" >&2
    exit 1
  fi
done

core_sha=$(sha256sum "${core_source}" | awk '{print $1}')
vhd_sha=$(sha256sum "${personaware_image}" | awk '{print $1}')
if [[ "${core_sha}" != "${expected_core_sha}" ]]; then
  echo "error: release core checksum mismatch: ${core_sha}" >&2
  exit 1
fi
if [[ "${vhd_sha}" != "${expected_vhd_sha}" ]]; then
  echo "error: expected PersonaWare English 2.0.6 (${expected_vhd_sha})" >&2
  echo "       found ${vhd_sha}" >&2
  exit 1
fi
if [[ $(wc -c < "${personaware_image}") -ne 4194304 ]]; then
  echo "error: PersonaWare image must be exactly 4 MiB" >&2
  exit 1
fi

stage_root=$(mktemp -d -t pc110-mister-package.XXXXXX)
trap 'rm -rf "${stage_root}"' EXIT
package_root="${stage_root}/${bundle_name}"
mkdir -p "${package_root}/payload/_Computer" \
  "${package_root}/payload/games/PC110" "${package_root}/tools"

cp "${repo_dir}/packaging/mister-ready/install.sh" "${package_root}/install.sh"
cp "${repo_dir}/packaging/mister-ready/README.txt" "${package_root}/README.txt"
cp "${repo_dir}/scripts/prepare-roms.sh" "${package_root}/tools/prepare-roms.sh"
cp "${repo_dir}/scripts/migrate-pc110-identity.sh" \
  "${package_root}/tools/migrate-pc110-identity.sh"
cp "${repo_dir}/LICENSE" "${repo_dir}/THIRD_PARTY_NOTICES.md" "${package_root}/"
cp "${core_source}" "${package_root}/payload/_Computer/IBM PC110_20260808.rbf"
cp "${personaware_image}" "${package_root}/payload/games/PC110/Personaware-disk.vhd"
cp "${repo_dir}/examples/personaware-4mib.cfg" \
  "${package_root}/payload/games/PC110/Personaware-disk.cfg"

(
  cd "${package_root}"
  find payload -type f -print0 | sort -z | xargs -0 sha256sum > PAYLOAD.sha256
)

if find "${package_root}" -type f | grep -Eiq \
  '/(pc110_bios|pc110_font|boot0|boot1)\.(bin|rom)$'; then
  echo "error: proprietary PC110 ROM file entered the package" >&2
  exit 1
fi

mkdir -p "${output_dir}"
zip_path="${output_dir}/${bundle_name}.zip"
python3 - "${package_root}" "${zip_path}" <<'PY'
from pathlib import Path
import sys
import zipfile

root = Path(sys.argv[1])
output = Path(sys.argv[2])
timestamp = (2026, 8, 8, 0, 0, 0)
with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for source in sorted(path for path in root.rglob("*") if path.is_file()):
        relative = source.relative_to(root.parent).as_posix()
        info = zipfile.ZipInfo(relative, timestamp)
        info.create_system = 3
        executable = source.name.endswith(".sh")
        info.external_attr = (0o100755 if executable else 0o100644) << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, source.read_bytes())
PY

(
  cd "${output_dir}"
  sha256sum "${bundle_name}.zip" > "SHA256SUMS-${bundle_date}.txt"
)
python3 - "${zip_path}" "${expected_core_sha}" "${expected_vhd_sha}" <<'PY'
from pathlib import Path
import hashlib
import sys
import zipfile

archive_path = Path(sys.argv[1])
expected_core = sys.argv[2]
expected_vhd = sys.argv[3]
with zipfile.ZipFile(archive_path) as archive:
    names = set(archive.namelist())
    roots = {name.split("/", 1)[0] for name in names}
    if len(roots) != 1:
        raise SystemExit("package must contain one top-level directory")
    root = next(iter(roots))
    core = archive.read(f"{root}/payload/_Computer/IBM PC110_20260808.rbf")
    vhd = archive.read(f"{root}/payload/games/PC110/Personaware-disk.vhd")
    if hashlib.sha256(core).hexdigest() != expected_core:
        raise SystemExit("packaged core failed checksum verification")
    if hashlib.sha256(vhd).hexdigest() != expected_vhd:
        raise SystemExit("packaged VHD failed checksum verification")
    forbidden = ("pc110_bios.bin", "pc110_font.bin", "boot0.rom", "boot1.rom")
    if any(name.lower().endswith(forbidden) for name in names):
        raise SystemExit("package contains a forbidden IBM ROM file")
print(f"Verified {archive_path}")
PY

echo "Built ${zip_path}"
echo "Checksums: ${output_dir}/SHA256SUMS-${bundle_date}.txt"
