# EPOS production

Runs N EPOS 4.0.3 Au+Au jobs in parallel forever and collects each finished ROOT file into one dataset folder (`z-auau_run_1.root`, `z-auau_run_2.root`, …).

## Requirements

- **ROOT ≥ 6.16** installed, with `source /path/to/root/bin/thisroot.sh` in `~/.bashrc`
- **System packages:**
  ```bash
  sudo apt install build-essential gfortran cmake curl zlib1g-dev
  ```
- **RAM:** ~17 GB per instance

FastJet 3.5.1, HepMC3 3.2.6 and [EPOS 4.0.3](https://klaus.pages.in2p3.fr/epos4/code/version.html) are downloaded and built automatically (~400 MB of downloads).

## Install

```bash
git clone https://github.com/aliu3203/epos-production epos-production && cd epos-production
nano config.env          # set DATA_DIR and N
./setup.sh
```

`setup.sh` builds everything into `install/`. It can be re-run safely and skips steps that are already done. The two stages can also be run on their own:

```bash
./setup.sh deps    # FastJet + HepMC3 (a few minutes, once per machine)
./setup.sh epos    # one EPOS build per instance (~1 min each on 24 cores)
```

## How instances work

FastJet and HepMC3 are installed once and shared. **EPOS is not shared:** each instance is its own complete EPOS build in `install/epos<n>/` (~4.5 GB). Instances running from one shared build use the same tables and crash.

Each instance has:

- `install/epos<n>/epos4.0.3/`: its own EPOS build; runs happen in its `auau200/` folder
- `$DATA_DIR/epos<n>/`: its output (`output.log`, ROOT file in progress)

**To add instances**, raise `N` in `config.env` and run `./setup.sh epos`. This builds only the new instances and leaves existing (possibly running) ones alone. To force a rebuild of specific instances, name them: `./setup.sh epos 2 4`. A running scheduler picks up the new `N` on its next cycle; run `./cycle_epos.sh` to start them right away.

**To lower `N`:** instances above `N` stop being restarted, but their current run still finishes, and its ROOT file stays in `$DATA_DIR/epos<n>/`. Move it into the dataset by hand, or run `RESTART=0 ./cycle_epos.sh` with the old `N` once those runs are done.

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
| `setup.sh` | builds FastJet + HepMC3 (`deps`) and one EPOS per instance (`epos`) |
| `epos_scheduler.sh` | runs `cycle_epos.sh` every `INTERVAL` |
| `cycle_epos.sh` | moves finished files, restarts idle instances |
| `env.sh` | shared paths + helpers (`start_run`, `harvest`, …) |
| `install/` | build output (not in git) |
| `$DATA_DIR/epos<n>/` | live output of instance n |
| `$DATA_DIR/$DATASET/` | collected ROOT files |

To change the physics, edit `auau_run.optns`. Each instance picks it up on its next run.
