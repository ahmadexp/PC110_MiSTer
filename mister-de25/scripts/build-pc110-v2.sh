#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# The installed Platform V2 boot image uses the verified FDCD HPS partition.
# Preserve that hard-HPS implementation so a standalone PC110 build cannot
# accidentally emit a runtime RBF for the retired 078A boot platform.
export DE25_PC110_OUTPUT_RBF=${DE25_PC110_OUTPUT_RBF:-$platform_root/artifacts/pc110/IBM_PC110_20260828_RTC_UIP_FIX_FDCD.rbf}
export DE25_HPS_PARTITION_MODE=reuse
export DE25_HPS_PARTITION_QDB="$platform_root/artifacts/menu-v2/de25_mister_hps_fdcd_synth.qdb"
export DE25_EXPECTED_HPS_IO_HASH_FILE="$platform_root/platforms/fdcd.hps-io-hash"

if [[ ! -f $DE25_HPS_PARTITION_QDB ]]; then
    echo "Platform V2 HPS partition not found: $DE25_HPS_PARTITION_QDB" >&2
    echo "Run scripts/build-menu-v2.sh first." >&2
    exit 1
fi

exec "$platform_root/scripts/build-pc110.sh"
