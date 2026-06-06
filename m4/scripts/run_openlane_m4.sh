#!/usr/bin/env bash
# Reproduce M4 final OpenLane signoff (requires Linux/WSL2, OpenLane 2.3.10, sky130A).
# Run from repository root:
#   bash project/m4/scripts/run_openlane_m4.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "${ROOT}/project/m4"
export PDK_ROOT="${PDK_ROOT:?Set PDK_ROOT to your Sky130 PDK tree}"
python3 -m openlane synth/config.json 2>&1 | tee synth/openlane_run.log
echo "Done. Collect STA/area artifacts with codefest/cf07/scripts/collect_reports.sh on the new run directory."
