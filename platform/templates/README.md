# Cluster templates

Every folder works the same way:

    cp -r /shared/template/01_docking ~/jobs/my-docking
    cd ~/jobs/my-docking
    nano settings.env        # change settings (optional)
    ./submit.sh              # run on the cluster
    squeue --me              # watch
    ls results/              # results appear here

Each comes with example data in `input/`, so `./submit.sh` works straight away.
Or do all of this in the web portal (`platform/portal`).

| Folder | What it does | Example run time |
|---|---|---|
| 00_hello | Test every node | seconds |
| 01_docking | Vina docking / virtual screening | 5 ligands: ~5 min |
| 02_foldx_scan | All single mutants, FoldX ΔΔG *(needs FoldX)* | 56 aa: ~1 h |
| 03_md | GROMACS protein MD + plots | 1 ns ubiquitin: ~25 min |
| 04_esm_scan | Mutation effects from sequence (ESM-2) | 76 aa: ~2 min |
| 05_rosetta_ddg | Accurate ΔΔG for a shortlist *(needs Rosetta)* | 5 mutations: ~1 h |
| 06_pockets | Find druggable pockets (fpocket) | seconds |
| 07_similarity | All-vs-all TM-score (US-align) | seconds |
| 08_task_farm | Run any list of commands in parallel | – |

## Example cluster (Croods, see `blueprints/offline-usb`)
| | Threads | Memory for jobs |
|---|---|---|
| eep, ugga | 8 each (i7-7700) | 14.8 GB each |
| thunk | 8 (i7-7700) | 11.5 GB |
| guy | 20 (i7-12700, fastest) | 14.8 GB |
| **Total** | **44** | **~56 GB** |

No GPUs. Best at many independent jobs (screening, scans); MD runs on one node at a time.
Measured: MD 80 ns/day for 19 000 atoms on guy · docking ~1–5 min per ligand per thread.

## Software
Installed for everyone in `/shared/apps/sbio` (Vina, Meeko, Open Babel, RDKit, GROMACS,
fpocket, US-align, ESM, PyTorch, Biopython, MDAnalysis, OpenMM, PDBFixer, pandas, matplotlib).
In a terminal: `source /shared/apps/sbio/bin/activate`.

Offline cluster needs internet (e.g. `pip install`)? See `platform/internet`.

FoldX and Rosetta need a free academic licence you accept yourself:
put FoldX at `/shared/apps/foldx/foldx`, Rosetta in `/shared/apps/rosetta`.

## Slurm basics
    squeue --me              my jobs
    scancel 123              cancel job 123
    sinfo -N                 node states
    srun -c 4 --pty bash     interactive shell on a node
