# Platform — science software, job templates, web portal, course

Everything **above** Slurm. Works on either blueprint once the cluster has a shared `/shared` and `/home`.

| Folder | What | Install |
|---|---|---|
| `software/` | Vina, GROMACS, fpocket, US-align, ESM-2, RDKit, PyTorch (CPU)… packed for offline use | `bash build-env.sh` (PC with internet) → `bash install.sh admin@head-node` |
| `templates/` | 9 ready-to-run workflows with example data | copied to `/shared/template` by the portal installer |
| `portal/` | web UI: live cluster status, submit jobs by form, results with plots and 3D viewer | on the head node: `sudo bash install.sh` |
| `course/` | "Cluster 101" — one offline HTML page, with real results from the example cluster | open `course/cluster101.html` |
| `internet/` | give an offline cluster temporary internet through a laptop | see below |

## Order
1. `software/` → 2. `portal/` (also installs templates and course) → 3. try `00_hello` in the portal.

## How the pieces fit
```
browser ── portal (runs as you, over SSH) ──┐
terminal ───────────────────────────────────┼─► ~/jobs/<name>/ = copy of a template ──► ./submit.sh ──► Slurm
                                             │        settings.env · input/ · results/
/shared/apps/sbio  (software)  /shared/models (ESM weights)  /shared/template (templates)
```

## Templates
Every template has the same shape, so learning one teaches all:
```
settings.env   the few things you change
input/         example data (public PDB entries)
submit.sh      submits everything, chains steps with Slurm dependencies
results/       tables (.tsv), plots (.png), structures
```

## Portal
- Listens on `localhost:8080` of the head node only. From another PC: `ssh -L 8080:localhost:8080 you@head-node`.
- Login = the user's cluster password (checked by SSH). Each action runs as that user, so the portal has no special rights.

## Internet through a laptop (offline blueprint)
```bash
# laptop plugged into the switch
bash internet/laptop-share-internet.sh on  hpcadmin@10.0.0.1    # all nodes online
bash internet/laptop-share-internet.sh off hpcadmin@10.0.0.1
```
`cluster-internet` is installed on every node by the offline blueprint. Check your network's rules first.

## Licences
- FoldX and Rosetta (templates 02, 05) need a free academic licence you accept yourself: put them in `/shared/apps/foldx` and `/shared/apps/rosetta`.
- `portal/static/3Dmol-min.js` is [3Dmol.js](https://3dmol.csb.pitt.edu) (BSD-3-Clause), bundled for offline use.
- Example structures are from the [RCSB PDB](https://www.rcsb.org) (1HSG, 1UBQ, 1PGA, 2GB1, 2OCJ, 1L2Y).

## Status
| Part | State |
|---|---|
| software, templates 00/01/03/04/06/07/08, portal, course, internet toggle | ✅ tested on the Croods cluster |
| templates 02 (FoldX) and 05 (Rosetta) | ⚠️ parsers tested with sample output; not run (licence) |
| NFS on the Penguins (Ansible) blueprint | ⏳ not done yet — needed there first |
