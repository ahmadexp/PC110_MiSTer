#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
	echo "usage: $0 /path/to/install2rel [root@mister]" >&2
	exit 2
fi

package_dir="$(cd "$1" && pwd)"
mister_host="${2:-root@192.168.10.251}"
arm_zip="${package_dir}/Linux-arm/arstech-utils-arm-2-12.zip"
dev_zip="${package_dir}/4developers/4developers-2-32.zip"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
stage_dir="$(mktemp -d)"
trap 'rm -rf "${stage_dir}"' EXIT

if [[ ! -f "${arm_zip}" || ! -f "${dev_zip}" ]]; then
	echo "install2rel is missing the expected Linux-arm or 4developers archive" >&2
	exit 1
fi

unzip -q -j "${arm_zip}" '*/arsenum4' '*/isarw' -d "${stage_dir}"
unzip -q -j "${dev_zip}" '*/linux-pi/libarsusb4.so' -d "${stage_dir}"

ssh "${mister_host}" 'mkdir -p /media/fat/linux/pc110-pcmcia'
scp "${stage_dir}/arsenum4" "${stage_dir}/isarw" \
	"${stage_dir}/libarsusb4.so" "${script_dir}/start-vendor.sh" \
	"${script_dir}/pc110-pcmcia.cfg.example" \
	"${script_dir}/sundisk-sdp3b.cis.hex" \
	"${script_dir}/cf-jvr101.cis.hex" \
	"${mister_host}:/media/fat/linux/pc110-pcmcia/"
ssh "${mister_host}" '
	set -e
	cd /media/fat/linux/pc110-pcmcia
	chmod 700 arsenum4 isarw start-vendor.sh
	chmod 600 libarsusb4.so
	if [ ! -e pc110-pcmcia.cfg ]; then
		cp pc110-pcmcia.cfg.example pc110-pcmcia.cfg
	fi
'

echo "Installed the user-supplied ARS runtime on ${mister_host}."
echo "No vendor file was copied into the PC110 core repository."
