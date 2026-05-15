IMPORTANT FOR RUNNING OPENLANE 2 NOT IMPORTANT FOR CODEFEST 7 TURN IN

OpenLane 2 report snapshots for CF07 live here after you run a full Classic flow.

1) From Linux or WSL (Docker running): bash ../scripts/run_openlane.sh
2) Then: bash ../scripts/collect_reports.sh

collect_reports.sh copies final/metrics.csv (OpenLane 2 canonical path) into this folder
as metrics.csv and as final/reports/metrics.csv, plus Yosys synthesis and OpenROAD STA reports.

This machine did not run OpenLane; populate this directory using the steps above, then commit.
