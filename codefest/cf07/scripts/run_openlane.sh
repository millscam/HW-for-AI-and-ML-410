#!/usr/bin/env bash
# OpenLane 2 Classic flow (RTL→GDSII) for CF07 synth_top.
# Requires: Docker (or Docker Desktop + WSL2 integration), Python 3.
# PDK is fetched under ${PDK_ROOT:-$HOME/.volare} on first run.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# Yosys/ABC is known to fail with "Can't open ABC output file .../output.blif" when the
# repo path contains spaces (ABC mishandles script paths). Fail fast with a clear fix.
if [[ "${ROOT}" == *" "* ]]; then
  echo "run_openlane.sh: project path must not contain spaces (Yosys ABC breaks). Current:" >&2
  echo "  ${ROOT}" >&2
  echo "Fix: copy the repo to a path without spaces, then run again. Example:" >&2
  echo "  mkdir -p ~/projects" >&2
  echo "  cp -a \"$ROOT\" ~/projects/cf07" >&2
  echo "  cd ~/projects/cf07/synth && bash ../scripts/run_openlane.sh" >&2
  exit 1
fi
export PDK_ROOT="${PDK_ROOT:-$HOME/.volare}"
python3 -m pip install --user -q "openlane>=2"
python3 -m openlane --dockerized --pdk-root "$PDK_ROOT" "$ROOT/openlane/config.json"
