#!/bin/bash
# One cycle over instances 1..N:
#   1. skip any instance whose epos process is still running
#   2. move its finished z-auau_run_<n>.root into DATA_DIR/<dataset> with the next free index
#   3. start its next run (unless RESTART=0)
#
# Usage:  ./cycle_epos.sh [dataset]
#         RESTART=0 ./cycle_epos.sh     # move files only, start nothing
source "$(dirname "$0")/env.sh"
check_config

DEST=${1:-$DATASET}
RESTART=${RESTART:-1}

mkdir -p "$DATA_DIR/$DEST"

for n in $(seq 1 "$N"); do
    # Safety: never touch a root file while its epos process is alive
    if is_running "$n"; then
        echo "[epos$n] still running - skipped this cycle"
        continue
    fi
    harvest "$n" "$DEST"
    if [[ $RESTART == 1 ]]; then
        start_run "$n"
    fi
done
