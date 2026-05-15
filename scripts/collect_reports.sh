#!/usr/bin/env bash
# Copy key OpenLane 2 artifacts from the latest run into ../synth/ for version control.
# OpenLane 2 places aggregate metrics at <run>/final/metrics.csv (not under final/reports/).
# This script also mirrors metrics into synth/final/reports/metrics.csv for the path you asked for.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESIGN_DIR="$ROOT/openlane"
RUN_DIR="${1:-}"
if [[ -z "${RUN_DIR}" ]]; then
  RUN_DIR="$(ls -td "${DESIGN_DIR}/runs"/* 2>/dev/null | head -1 || true)"
fi
if [[ -z "${RUN_DIR}" || ! -d "${RUN_DIR}" ]]; then
  echo "No run directory found under ${DESIGN_DIR}/runs. Run scripts/run_openlane.sh first." >&2
  exit 1
fi

OUT="$ROOT/synth"
mkdir -p "${OUT}/final/reports" "${OUT}/synthesis" "${OUT}/sta"

if [[ -f "${RUN_DIR}/final/metrics.csv" ]]; then
  cp -f "${RUN_DIR}/final/metrics.csv" "${OUT}/metrics.csv"
  cp -f "${RUN_DIR}/final/metrics.csv" "${OUT}/final/reports/metrics.csv"
else
  echo "Warning: ${RUN_DIR}/final/metrics.csv missing (flow may not have completed)." >&2
fi

SYN="$(find "${RUN_DIR}" -maxdepth 1 -type d -name '*-yosys-synthesis' 2>/dev/null | head -1 || true)"
if [[ -n "${SYN}" ]]; then
  [[ -f "${SYN}/reports/stat.json" ]] && cp -f "${SYN}/reports/stat.json" "${OUT}/synthesis/yosys_stat.json"
  [[ -f "${SYN}/reports/pre_synth_chk.rpt" ]] && cp -f "${SYN}/reports/pre_synth_chk.rpt" "${OUT}/synthesis/pre_synth_chk.rpt"
fi

while IFS= read -r -d '' dir; do
  name="$(basename "${dir}")"
  if [[ -f "${dir}/summary.rpt" ]]; then
    cp -f "${dir}/summary.rpt" "${OUT}/sta/${name}_summary.rpt"
  fi
  while IFS= read -r -d '' chk; do
    corner="$(basename "$(dirname "${chk}")")"
    safe="${name}__${corner}"
    cp -f "${chk}" "${OUT}/sta/${safe}__checks.rpt"
  done < <(find "${dir}" -mindepth 2 -maxdepth 2 -name 'checks.rpt' -print0 2>/dev/null || true)
done < <(find "${RUN_DIR}" -maxdepth 1 -type d \( -name '*-openroad-staprepnr' -o -name '*-openroad-stamidpnr' -o -name '*-openroad-stapostpnr' \) -print0 2>/dev/null || true)

echo "Copied reports from: ${RUN_DIR}"
echo "Into: ${OUT}"
