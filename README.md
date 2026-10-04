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

`setup.sh` builds everything into `install/` (~6 GB). It can be re-run safely and skips steps that are already done.

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
| `setup.sh` | builds deps + EPOS, creates run dirs |
| `epos_scheduler.sh` | runs `cycle_epos.sh` every `INTERVAL` |
| `cycle_epos.sh` | moves finished files, restarts idle instances |
| `install/` | build output (not in git) |
| `$DATA_DIR/epos<n>/` | live output of instance n |
| `$DATA_DIR/$DATASET/` | collected ROOT files |

To change the physics, edit `auau_run.optns` and re-run `./setup.sh`. The change applies from each instance's next run.
