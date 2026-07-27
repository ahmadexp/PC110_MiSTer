#!/usr/bin/env bash
# Synthesize on the native x86-64 build host instead of the local emulated
# Quartus container.  The host runs the same ghcr.io/raetro/quartus:mister
# image, so the toolchain is identical; only the speed differs (no x86
# translation, many more cores).
#
# Usage: scripts/build-remote.sh
# Env:   BUILD_HOST (default user@192.168.1.169), BUILD_DIR (default
#        ~/PC110-Mister), QUARTUS_IMAGE

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_host="${BUILD_HOST:-user@192.168.1.169}"
build_dir="${BUILD_DIR:-PC110-Mister}"
quartus_image="${QUARTUS_IMAGE:-ghcr.io/raetro/quartus:mister}"

# Sources only: the project files, RTL, and sim.  Build products, vendor
# trees, and the unrelated Personaware-EN repository stay local.
rsync -az --delete \
  --include='*/' \
  --include='*.sv' --include='*.v' --include='*.vhd' --include='*.qip' \
  --include='*.qpf' --include='*.qsf' --include='*.sdc' --include='*.srf' \
  --include='*.tcl' --include='*.mif' --include='*.hex' --include='*.sh' \
  --exclude='*' \
  --exclude='Personaware-EN/' --exclude='upstream-*/' --exclude='artifacts/' \
  "${repo_dir}/" "${build_host}:${build_dir}/"

ssh "${build_host}" "cd '${build_dir}' && \
  docker run --rm -v \"\$PWD:/build\" -w /build '${quartus_image}' \
    quartus_sh --flow compile PC110.qpf > build.log 2>&1; \
  tail -3 build.log; test -s output_files/PC110.rbf"

mkdir -p "${repo_dir}/artifacts"
scp -q "${build_host}:${build_dir}/output_files/PC110.rbf" \
  "${repo_dir}/artifacts/PC110.rbf"
scp -q "${build_host}:${build_dir}/output_files/PC110.sta.summary" \
  "${repo_dir}/artifacts/PC110.sta.summary" 2>/dev/null || true

echo "Built ${repo_dir}/artifacts/PC110.rbf"
shasum -a 256 "${repo_dir}/artifacts/PC110.rbf"
