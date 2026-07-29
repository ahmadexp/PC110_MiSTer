#!/usr/bin/env bash
# Synthesize on the native x86-64 build host instead of the local emulated
# Quartus container.  The host runs the same ghcr.io/raetro/quartus:mister
# image, so the toolchain is identical; only the speed differs (no x86
# translation, many more cores).
#
# Usage: scripts/build-remote.sh
# Env:   BUILD_HOST (required, for example user@quartus-builder.local),
#        BUILD_DIR (default ~/PC110-Mister), QUARTUS_IMAGE
#        FAST=1  drop the inherited timing-closure effort (physical
#                synthesis, final placement optimization, ECO timing) and
#                use the fast fitter.  Cuts fit time substantially for the
#                functional-debug loop.  The CPU clock already misses
#                closure and works anyway, so this only affects how hard
#                the fitter chases unmet timing - verify each fast build
#                still POSTs before trusting it; use a default (full) build
#                for anything shipped.

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_host="${BUILD_HOST:-}"
build_dir="${BUILD_DIR:-PC110-Mister}"
quartus_image="${QUARTUS_IMAGE:-ghcr.io/raetro/quartus:mister}"
fast="${FAST:-0}"

if [[ -z "${build_host}" ]]; then
  echo "error: set BUILD_HOST to an SSH-accessible x86-64 build host" >&2
  exit 2
fi

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

# Fast-iteration overrides.  Appended to the working-copy QSF so they win
# over the inherited assignments (Quartus honors the last assignment of a
# given name).  Removed again before the next rsync overwrites the QSF.
if [[ "${fast}" == "1" ]]; then
  ssh "${build_host}" "cd '${build_dir}' && cat >> PC110.qsf <<'EOF'

# --- FAST build overrides (scripts/build-remote.sh FAST=1) ---
set_global_assignment -name FITTER_EFFORT \"FAST_FIT\"
set_global_assignment -name PHYSICAL_SYNTHESIS_COMBO_LOGIC OFF
set_global_assignment -name PHYSICAL_SYNTHESIS_COMBO_LOGIC_FOR_AREA OFF
set_global_assignment -name PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION OFF
set_global_assignment -name PHYSICAL_SYNTHESIS_REGISTER_RETIMING OFF
set_global_assignment -name PHYSICAL_SYNTHESIS_ASYNCHRONOUS_SIGNAL_PIPELINING OFF
set_global_assignment -name PHYSICAL_SYNTHESIS_EFFORT NORMAL
set_global_assignment -name FINAL_PLACEMENT_OPTIMIZATION NEVER
set_global_assignment -name ECO_OPTIMIZE_TIMING OFF
set_global_assignment -name ROUTER_TIMING_OPTIMIZATION_LEVEL MINIMUM
EOF"
fi

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
