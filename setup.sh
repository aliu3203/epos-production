#!/bin/bash
# Download and build the software.
#   FastJet + HepMC3: built once, shared by all instances.
#   EPOS: one complete, separate build per instance in install/epos<n>/
#         (instances sharing a build crash on shared tables).
#
# Usage:  ./setup.sh               # deps + EPOS for instances 1..N
#         ./setup.sh deps          # FastJet + HepMC3 only (once per machine)
#         ./setup.sh epos          # build EPOS for any of instances 1..N not built yet
#         ./setup.sh epos 3 7      # (re)build instances 3 and 7 (refused while they run)
#
# Re-running is safe; finished steps are skipped.
set -euo pipefail
source "$(dirname "$0")/env.sh"

FASTJET_VERSION=3.5.1
HEPMC3_VERSION=3.2.6
FASTJET_URL=https://fastjet.fr/repo/fastjet-$FASTJET_VERSION.tar.gz
HEPMC3_URL=https://hepmc.web.cern.ch/hepmc/releases/HepMC3-$HEPMC3_VERSION.tar.gz
# "Download EPOS4.0.3" link on https://klaus.pages.in2p3.fr/epos4/code/version.html
EPOS_URL=https://box.in2p3.fr/s/g8aNMit2fKXLHYP/download
EPOS_SHA256=785e77c1f09c72a4252ebf45230261e7a8654d9888533aeb8b4d0dd90cdda715

step() { echo; echo "==> $*"; }

fetch() {  # fetch <url> <file>
    [[ -f $2 ]] || { curl -fL --retry 3 -o "$2.part" "$1" && mv "$2.part" "$2"; }
}

need_tools() {
    for tool in "$@"; do
        command -v "$tool" > /dev/null || die "'$tool' not found. Install system packages (see README)."
    done
}

# ------------------------------------------------------------------------- deps
build_deps() {
    need_tools gcc g++ make cmake curl tar
    mkdir -p "$DEPS_DIR/src"

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
}

# ------------------------------------------------------------------------- EPOS
epos_tarball() {  # print the tarball path, downloading + verifying it if needed
    if [[ -n $EPOS_TARBALL ]]; then
        [[ -f $EPOS_TARBALL ]] || die "EPOS_TARBALL not found: $EPOS_TARBALL"
        echo "$EPOS_TARBALL"
        return
    fi
    local tarball="$DEPS_DIR/src/epos$EPOVSN.tgz"
    mkdir -p "$DEPS_DIR/src"
    fetch "$EPOS_URL" "$tarball" >&2
    echo "$EPOS_SHA256  $tarball" | sha256sum -c --quiet >&2 \
        || die "checksum mismatch for $tarball (delete it to re-download)"
    echo "$tarball"
}

build_instance() {  # build_instance <n>
    local n=$1
    step "EPOS $EPOVSN: instance $n -> $INSTALL_DIR/epos$n"
    use_instance "$n"

    if [[ ! -f $EPO/CMakeLists.txt ]]; then
        mkdir -p "$MYDIR"
        tar xf "$(epos_tarball)" -C "$MYDIR"
        [[ -f $EPO/CMakeLists.txt ]] || die "tarball did not unpack to $EPO"
    fi

    # The stock wrapper uses fixed seeds, so every run would produce identical events.
    sed -i -E "s/^(seed[ij])=[0-9]+/\1=\`date '+%N'\`/" "$EPO/scripts/epos.in"
    grep -q "^seedj=\`date" "$EPO/scripts/epos.in" || die "could not patch random seeds in scripts/epos.in"

    cmake -S "$EPO" -B "$BUILD_DIR" \
        -DCMAKE_INSTALL_PREFIX="$BIN_DIR" \
        -DCOMPILE_OPTION=BASIC \
        -DCMAKE_BUILD_TYPE=Release \
        -DFASTSYS="$FASTJET_PREFIX" \
        -DHepMC3_DIR="$HepMC3_DIR" \
        -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
        -DCMAKE_INSTALL_MESSAGE=LAZY > "$MYDIR/build.log"
    cmake --build "$BUILD_DIR" -j"$JOBS" >> "$MYDIR/build.log" 2>&1 \
        || die "build failed, see $MYDIR/build.log"
    cmake --install "$BUILD_DIR" >> "$MYDIR/build.log"

    is_built "$n" || die "EPOS binaries missing after install (see $MYDIR/build.log)"
    grep -q "^seedj=\`date" "$EPOS_BIN" || die "installed $EPOS_BIN still has fixed seeds"
    if ldd "${EPO}bin/Xepos" | grep "not found"; then
        die "Xepos has unresolved libraries (above)"
    fi
    mkdir -p "$RUN_DIR"
    echo "OK (random seeds patched, libraries resolved)"
}

build_epos() {  # build_epos [n...]   (default: 1..N)
    need_tools gcc g++ gfortran make cmake curl tar
    command -v root-config > /dev/null \
        || die "ROOT not found. Run: source /path/to/root/bin/thisroot.sh"
    [[ -x $FASTJET_PREFIX/bin/fastjet-config && -f $HepMC3_DIR/HepMC3Config.cmake ]] \
        || die "FastJet/HepMC3 missing. Run: ./setup.sh deps"
    echo "ROOT $(root-config --version) | $(cmake --version | head -1) | $JOBS build jobs"

    if [[ $# -eq 0 ]]; then
        # Default: only add missing instances, never touch ones that may be running.
        for n in $(seq 1 "$N"); do
            if is_built "$n"; then
                echo "instance $n: already built"
            else
                build_instance "$n"
            fi
        done
        return
    fi
    for n in "$@"; do
        [[ $n =~ ^[1-9][0-9]*$ ]] || die "instance must be a positive integer, got '$n'"
        is_running "$n" && die "instance $n is running; rebuild it after its run ends"
        build_instance "$n"
    done
}

# ------------------------------------------------------------------------------
check_config
case "${1:-all}" in
    deps) build_deps ;;
    epos) shift; build_epos "$@" ;;
    all)  build_deps; build_epos ;;
    *)    die "usage: ./setup.sh [deps | epos [n...]]" ;;
esac

step "Done. Start production with:"
echo "  nohup ./epos_scheduler.sh > scheduler.log 2>&1 &"
