#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${repo_dir}/artifacts/test"
mkdir -p "${build_dir}"

iverilog -g2012 -Wall \
  -s pc110_chipset_tb \
  -o "${build_dir}/pc110_chipset_tb" \
  "${repo_dir}/rtl/pc110/pc110_chipset.sv" \
  "${repo_dir}/sim/pc110_chipset_tb.sv"

vvp "${build_dir}/pc110_chipset_tb"
