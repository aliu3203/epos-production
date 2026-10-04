#!/bin/bash
# Run cycle_epos.sh every INTERVAL, forever.
#
# Start:  nohup ./epos_scheduler.sh > scheduler.log 2>&1 &
# Watch:  tail -f scheduler.log
# Stop:   pkill -f epos_scheduler.sh   (running simulations keep going)
#
# Optional args override config.env:  ./epos_scheduler.sh [dataset] [interval]
source "$(dirname "$0")/env.sh"
check_config

DEST=${1:-$DATASET}
INTERVAL=${2:-$INTERVAL}

is_built 1 || die "EPOS not built. Run ./setup.sh first."
[[ -d $DATA_DIR ]] || die "DATA_DIR $DATA_DIR not found (disk not mounted?)"

while true; do
    echo "=== cycle started $(date '+%F %T') ==="
    "$REPO_DIR/cycle_epos.sh" "$DEST"
    echo "=== sleeping $INTERVAL ==="
    sleep "$INTERVAL"
done
