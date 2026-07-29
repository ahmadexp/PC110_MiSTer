#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 PC110_BIOS_256K [PC110_FONT_ROM_1M]" >&2
  exit 2
fi

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${repo_dir}/artifacts/roms"
bios_path="$1"
font_path="${2:-}"
expected_bios_sha="232101c88466f311bcc32fbc215a4d7569f695ce19f9c07ca67ce2aee5232312"
prepared_bios_sha="e906af0cb235ef490b9d5d24eab300bcf865bd112dd8a096bdf1890816933eaa"

file_size() {
  if stat -f '%z' "$1" >/dev/null 2>&1; then
    stat -f '%z' "$1"
  else
    stat -c '%s' "$1"
  fi
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

if [[ "$(file_size "${bios_path}")" != "262144" ]]; then
  echo "error: PC110 BIOS must be exactly 262144 bytes" >&2
  exit 1
fi

bios_sha="$(sha256_file "${bios_path}")"
if [[ "${bios_sha}" != "${expected_bios_sha}" ]]; then
  echo "error: unsupported PC110 BIOS SHA-256: ${bios_sha}" >&2
  echo "expected IBM 39H4551 image: ${expected_bios_sha}" >&2
  exit 1
fi

mkdir -p "${out_dir}"
cp "${bios_path}" "${out_dir}/pc110_bios.bin"

# Two size-preserving compatibility patches are applied to the prepared copy;
# the supplied IBM image remains untouched.
#
# F000:8145 normally sends CMOS-7B setup requests through a second gate that
# depends on the PC110 system-management controller. The CPU core has no SMM,
# so route
# a set bit directly to the existing Easy-Setup loader at F000:817C.
branch_bytes="$(od -An -tx1 -j $((0x38145)) -N 2 "${out_dir}/pc110_bios.bin" | tr -d ' \n')"
if [[ "${branch_bytes}" != "7514" ]]; then
  echo "error: unexpected Easy-Setup branch bytes: ${branch_bytes}" >&2
  exit 1
fi
printf '\x35' | dd of="${out_dir}/pc110_bios.bin" bs=1 seek=$((0x38146)) \
  conv=notrunc status=none

# The relocated loader opens EC/ED through INT 15h AX=5380h, an SMM-era
# indirection that does not reliably complete on the current platform. Replace
# its first
# eight bytes with an equivalent direct "out 00FBh,80h", which opens the
# modeled VL82C420 configuration bank before indices 11h/12h are programmed.
unlock_bytes="$(od -An -tx1 -j $((0x3DDE6)) -N 8 "${out_dir}/pc110_bios.bin" | tr -d ' \n')"
if [[ "${unlock_bytes}" != "b88053bb0180cd15" ]]; then
  echo "error: unexpected Easy-Setup unlock bytes: ${unlock_bytes}" >&2
  exit 1
fi
printf '\xBA\xFB\x00\xB0\x80\xEE\x90\x90' |
  dd of="${out_dir}/pc110_bios.bin" bs=1 seek=$((0x3DDE6)) \
    conv=notrunc status=none

prepared_sha="$(sha256_file "${out_dir}/pc110_bios.bin")"
if [[ "${prepared_sha}" != "${prepared_bios_sha}" ]]; then
  echo "error: prepared BIOS SHA-256 mismatch: ${prepared_sha}" >&2
  exit 1
fi

# During early POST the 256 KiB flash is linearly decoded at C0000-FFFFF.
# MiSTer Main loads boot1 at C0000 and boot0 at F0000, so the exact split is
# 192 KiB + 64 KiB.  POST later copies the VGA image from E0000 to C0000.
dd if="${out_dir}/pc110_bios.bin" of="${out_dir}/boot1.rom" bs=65536 count=3 status=none
dd if="${out_dir}/pc110_bios.bin" of="${out_dir}/boot0.rom" bs=65536 skip=3 count=1 status=none

if [[ -n "${font_path}" ]]; then
  if [[ "$(file_size "${font_path}")" != "1048576" ]]; then
    echo "error: PC110 font ROM must be exactly 1048576 bytes" >&2
    exit 1
  fi
  cp "${font_path}" "${out_dir}/pc110_font.bin"
fi

printf 'Prepared %s (%s bytes)\n' "${out_dir}/boot1.rom" "$(file_size "${out_dir}/boot1.rom")"
printf 'Prepared %s (%s bytes)\n' "${out_dir}/boot0.rom" "$(file_size "${out_dir}/boot0.rom")"
printf 'Prepared %s (%s bytes)\n' "${out_dir}/pc110_bios.bin" "$(file_size "${out_dir}/pc110_bios.bin")"
if [[ -f "${out_dir}/pc110_font.bin" ]]; then
  printf 'Prepared %s (%s bytes)\n' "${out_dir}/pc110_font.bin" "$(file_size "${out_dir}/pc110_font.bin")"
fi
