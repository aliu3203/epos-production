#!/bin/bash
# Build everything: FastJet, HepMC3, EPOS (from the tarball), and the N run directories.
# Re-running is safe; finished steps are skipped.
#
# Usage:  ./setup.sh
set -euo pipefail
source "$(dirname "$0")/env.sh"

FASTJET_VERSION=3.5.1
HEPMC3_VERSION=3.2.6
FASTJET_URL=https://fastjet.fr/repo/fastjet-$FASTJET_VERSION.tar.gz
HEPMC3_URL=https://hepmc.web.cern.ch/hepmc/releases/HepMC3-$HEPMC3_VERSION.tar.gz

step() { echo; echo "==> $*"; }

fetch() {  # fetch <url> <file>
    [[ -f $2 ]] || { curl -fL --retry 3 -o "$2.part" "$1" && mv "$2.part" "$2"; }
}

# ---------------------------------------------------------------- prerequisites
step "Checking prerequisites"
check_config
for tool in gcc g++ gfortran make cmake curl tar; do
    command -v "$tool" > /dev/null || die "'$tool' not found. Install system packages (see README)."
done
command -v root-config > /dev/null \
    || die "ROOT not found. Run: source /path/to/root/bin/thisroot.sh"
[[ -f $EPOS_TARBALL ]] || die "EPOS tarball not found at $EPOS_TARBALL"
echo "ROOT $(root-config --version) | $(cmake --version | head -1) | $JOBS build jobs"
mkdir -p "$DEPS_DIR/src" "$DATA_DIR" || die "cannot create $DATA_DIR"

# ---------------------------------------------------------------------- FastJet
step "FastJet $FASTJET_VERSION"
if [[ -x $FASTJET_PREFIX/bin/fastjet-config ]]; then
    echo "already installed"
else
    cd "$DEPS_DIR/src"
    fetch "$FASTJET_URL" "fastjet-$FASTJET_VERSION.tar.gz"
    rm -rf "fastjet-$FASTJET_VERSION"
    tar xzf "fastjet-$FASTJET_VERSION.tar.gz"
    cd "fastjet-$FASTJET_VERSION"
    ./configure --prefix="$FASTJET_PREFIX"
    make -j"$JOBS"
    make install
fi

# ---------------------------------------------------------------------- HepMC3
step "HepMC3 $HEPMC3_VERSION"
if [[ -f $HepMC3_DIR/HepMC3Config.cmake ]]; then
    echo "already installed"
else
    cd "$DEPS_DIR/src"
    fetch "$HEPMC3_URL" "HepMC3-$HEPMC3_VERSION.tar.gz"
    rm -rf "HepMC3-$HEPMC3_VERSION" hepmc3-build
    tar xzf "HepMC3-$HEPMC3_VERSION.tar.gz"
    cmake -S "HepMC3-$HEPMC3_VERSION" -B hepmc3-build \
        -DCMAKE_INSTALL_PREFIX="$HEPMC3_PREFIX" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_BUILD_TYPE=Release \
        -DHEPMC3_ENABLE_ROOTIO=OFF \
        -DHEPMC3_ENABLE_PROTOBUFIO=OFF \
        -DHEPMC3_ENABLE_PYTHON=OFF \
        -DHEPMC3_BUILD_EXAMPLES=OFF \
        -DHEPMC3_ENABLE_TEST=OFF
    cmake --build hepmc3-build -j"$JOBS"
    cmake --install hepmc3-build
fi

# ------------------------------------------------------------------------- EPOS
step "EPOS $EPOVSN"
if [[ ! -f $EPO/CMakeLists.txt ]]; then
    echo "unpacking $EPOS_TARBALL"
    tar xf "$EPOS_TARBALL" -C "$INSTALL_DIR"
    [[ -f $EPO/CMakeLists.txt ]] || die "tarball did not unpack to $EPO"
fi

# The stock wrapper uses fixed seeds, so every run would produce identical events.
sed -i -E "s/^(seed[ij])=[0-9]+/\1=\`date '+%N'\`/" "$EPO/scripts/epos.in"
grep -q "^seedj=\`date" "$EPO/scripts/epos.in" || die "could not patch random seeds in scripts/epos.in"
echo "random seeds patched"

cmake -S "$EPO" -B "$BUILD_DIR" \
    -DCMAKE_INSTALL_PREFIX="$BIN_DIR" \
    -DCOMPILE_OPTION=BASIC \
    -DCMAKE_BUILD_TYPE=Release \
    -DFASTSYS="$FASTJET_PREFIX" \
    -DHepMC3_DIR="$HepMC3_DIR" \
    -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
    -DCMAKE_INSTALL_MESSAGE=LAZY
cmake --build "$BUILD_DIR" -j"$JOBS"
cmake --install "$BUILD_DIR"

step "Verifying EPOS build"
[[ -x ${EPO}bin/Xepos && -x $EPOS_BIN ]] || die "EPOS binaries missing after install"
grep -q "^seedj=\`date" "$EPOS_BIN" || die "installed $EPOS_BIN still has fixed seeds"
if ldd "${EPO}bin/Xepos" | grep "not found"; then
    die "Xepos has unresolved libraries (above)"
fi
echo "OK"

# ------------------------------------------------------------- run directories
step "Creating $N run directories"
mkdir -p "$DATA_DIR/$DATASET"
for n in $(seq 1 "$N"); do
    mkdir -p "$RUNS_DIR/epos$n" "$DATA_DIR/epos$n"
    cp "$REPO_DIR/auau_run.optns" "$RUNS_DIR/epos$n/auau_run_$n.optns"
    echo "  epos$n: card $RUNS_DIR/epos$n  output $DATA_DIR/epos$n"
done

step "Done. Start production with:"
echo "  nohup ./epos_scheduler.sh > scheduler.log 2>&1 &"
