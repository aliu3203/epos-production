# EPOS production

Runs N EPOS 4.0.3 Au+Au jobs in parallel forever and collects each finished ROOT file into one dataset folder (`z-auau_run_1.root`, `z-auau_run_2.root`, …).

## Requirements

- **ROOT ≥ 6.16** installed, with `source /path/to/root/bin/thisroot.sh` in `~/.bashrc`
- **System packages:**
  ```bash
  sudo apt install build-essential gfortran cmake curl zlib1g-dev
  ```
- **EPOS 4.0.3 tarball** (`epos4.0.3.tar`). It isn't public; request it at https://klaus.pages.in2p3.fr/epos4/
- **RAM:** ~17 GB per instance

FastJet 3.5.1 and HepMC3 3.2.6 are downloaded and built automatically.

## Install

```bash
git clone <this repo> epos-production && cd epos-production
cp /path/to/epos4.0.3.tar .
nano config.env          # set DATA_DIR (and N)
./setup.sh
```

`setup.sh` builds everything into `install/` (~4 GB). It can be re-run safely and skips steps that are already done. The two stages can also be run on their own:

```bash
./setup.sh deps    # FastJet + HepMC3 (a few minutes, once per machine)
./setup.sh epos    # EPOS from the tarball (~1 min on 24 cores)
```

## How instances work

There is **one** FastJet, **one** HepMC3 and **one** EPOS build, shared by all instances. An instance is just a pair of folders, created automatically the first time it starts:

- `install/runs/epos<n>/`: run card + EPOS scratch files
- `$DATA_DIR/epos<n>/`: its output (`output.log`, ROOT file in progress)

**To change the number of instances**, edit `N` in `config.env`. Nothing needs rebuilding. A running scheduler picks up the new `N` on its next cycle; run `./cycle_epos.sh` to start new instances right away.

When lowering `N`, let the removed instances' current runs finish and collect their files first (`RESTART=0 ./cycle_epos.sh` *before* lowering `N`); otherwise their last ROOT file stays in `$DATA_DIR/epos<n>/`.

## Run

```bash
nohup ./epos_scheduler.sh > scheduler.log 2>&1 &
```

## Monitor / stop

```bash
tail -f scheduler.log                         # scheduler
tail -f $DATA_DIR/epos1/output.log            # instance 1
ps -eo pid,etime,rss,args | grep Xepos        # running jobs
pkill -f epos_scheduler.sh                    # stop scheduler (running jobs finish)
RESTART=0 ./cycle_epos.sh                     # collect remaining files, start nothing
```

## Layout

| Path | What |
|---|---|
| `config.env` | machine settings (N, data disk, interval) |
| `auau_run.optns` | run card (30–40 % central Au+Au, 200 GeV, 1000 events/file) |
| `setup.sh` | builds FastJet + HepMC3 (`deps`) and EPOS (`epos`) |
| `epos_scheduler.sh` | runs `cycle_epos.sh` every `INTERVAL` |
| `cycle_epos.sh` | moves finished files, restarts idle instances |
| `env.sh` | shared paths + helpers (`start_run`, `harvest`, …) |
| `install/` | build output (not in git) |
| `$DATA_DIR/epos<n>/` | live output of instance n |
| `$DATA_DIR/$DATASET/` | collected ROOT files |

To change the physics, edit `auau_run.optns`. Each instance picks it up on its next run.
