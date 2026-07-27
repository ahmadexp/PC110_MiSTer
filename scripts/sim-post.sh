#!/usr/bin/env bash
# Full-system POST simulation: ao486 CPU + iobus + pc110_chipset + the
# modified l2_cache + a latency-modeled DDR, executing the real PC110
# flash image from the reset vector.  Traces every I/O access, memory
# write, carry-flag change, and executed EIP.
#
# Requires artifacts/roms/pc110_bios.bin (scripts/prepare-roms.sh) and
# artifacts/test/altera_mf.v (copied from the Quartus container's
# eda/sim_lib).
#
# Usage: scripts/sim-post.sh [cycles]   (default 2000000)

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${repo_dir}/artifacts/test"
cycles="${1:-2000000}"
mkdir -p "${build_dir}"

if [[ ! -s "${build_dir}/altera_mf.v" ]]; then
  echo "error: put Quartus eda/sim_lib/altera_mf.v at ${build_dir}/altera_mf.v" >&2
  exit 1
fi

xxd -p -c1 "${repo_dir}/artifacts/roms/pc110_bios.bin" > "${build_dir}/pc110_bios.hex"

{
  echo rtl/ao486/defines.v
  for d in rtl/ao486 rtl/ao486/memory rtl/ao486/pipeline; do
    ls "${repo_dir}/${d}"/*.v
  done | grep -v defines.v
  echo rtl/cache/l1_icache.v
  echo rtl/cache/l2_cache.v
  echo rtl/common/simple_fifo_mlab.v
  echo rtl/common/simple_fifo.v
  echo rtl/common/simple_mult.v
  echo rtl/soc/iobus.v
  echo rtl/soc/pit.v
  echo rtl/soc/pit_counter.v
  echo rtl/pc110/pc110_chipset.sv
  echo artifacts/test/altera_mf.v
  echo artifacts/test/cpu_export.v
  echo sim/pc110_post_tb.sv
} > "${build_dir}/post_tb.f"

if [[ ! -s "${build_dir}/cpu_export.v" ]]; then
  cat > "${build_dir}/cpu_export.v" << 'EOF'
// Simulation-only stand-in for the VHDL cpu_export debug module.
module cpu_export
(
    input clk, input rst_n, input new_export,
    input [31:0] eax, input [31:0] ebx, input [31:0] ecx, input [31:0] edx,
    input [31:0] esp, input [31:0] ebp, input [31:0] esi, input [31:0] edi,
    input [31:0] eip
);
endmodule
EOF
fi

cd "${repo_dir}"
iverilog -g2012 -I rtl/ao486 -s pc110_post_tb \
  -o "${build_dir}/pc110_post_tb" -f "${build_dir}/post_tb.f"
vvp "${build_dir}/pc110_post_tb" "+cycles=${cycles}"
