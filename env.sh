# Shared environment and helpers. Sourced by every script; do not run directly.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/config.env"

DATA_DIR="${DATA_DIR%/}"
DEPS_DIR="$INSTALL_DIR/deps"
FASTJET_PREFIX="$DEPS_DIR/fastjet"
HEPMC3_PREFIX="$DEPS_DIR/hepmc3"
RUNS_DIR="$INSTALL_DIR/runs"

export EPOVSN=4.0.3
export EPO="$INSTALL_DIR/epos$EPOVSN/"
export BUILD_DIR="$INSTALL_DIR/epos-build"
export BIN_DIR="$EPO"
export HepMC3_DIR="$HEPMC3_PREFIX/share/HepMC3/cmake"
export FASTSYS="$FASTJET_PREFIX"
export FASTJET_DIR="$FASTJET_PREFIX"
export PATH="$FASTJET_PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$HEPMC3_PREFIX/lib:$FASTJET_PREFIX/lib${ROOTSYS:+:$ROOTSYS/lib}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

EPOS_BIN="${EPO}bin/epos"

die() { echo "ERROR: $*" >&2; exit 1; }

check_config() {
    [[ -n $DATA_DIR ]] || die "set DATA_DIR in config.env"
    [[ $N =~ ^[1-9][0-9]*$ ]] || die "N in config.env must be a positive integer"
}

# Is instance <n> still generating events?
is_running() {
    pgrep -f -- "$EPOS_BIN -root auau_run_$1\$" > /dev/null
}

# Move instance <n>'s finished ROOT file to DATA_DIR/<dest> under the next free index.
# flock keeps two harvesters from claiming the same index.
harvest() {
    local n=$1 dest="$DATA_DIR/$2"
    local src="$DATA_DIR/epos$n/z-auau_run_$n.root"
    if [[ ! -f $src ]]; then
        echo "[epos$n] no root file to move"
        return
    fi
    (
        flock 9
        local i=1
        while [[ -e "$dest/z-auau_run_$i.root" ]]; do ((i++)); done
        mv "$src" "$dest/z-auau_run_$i.root"
        echo "[epos$n] moved root file -> $2/z-auau_run_$i.root"
    ) 9>"$dest/.movelock"
}

# Launch the next run of instance <n> in the background.
# Instances share one EPOS build; each only needs its own run dir (card + scratch
# files) and output dir, created here, so raising N in config.env is enough to add one.
# The card is re-copied every run so edits to auau_run.optns apply from the next run.
# Subshell: HTO/CHK must point at this instance's own output dir only.
start_run() {
    local n=$1
    mkdir -p "$RUNS_DIR/epos$n" "$DATA_DIR/epos$n"
    cp "$REPO_DIR/auau_run.optns" "$RUNS_DIR/epos$n/auau_run_$n.optns"
    (
        export JIN="$DATA_DIR/" OPT=./ HTO="$DATA_DIR/epos$n/" CHK="$DATA_DIR/epos$n/"
        cd "$RUNS_DIR/epos$n" || exit 1
        nohup "$EPOS_BIN" -root "auau_run_$n" > "${CHK}output.log" 2>&1 &
    )
    echo "[epos$n] new run started"
}
