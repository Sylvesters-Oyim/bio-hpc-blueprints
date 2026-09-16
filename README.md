# bio-hpc-blueprints

**Build a small HPC cluster for structural bioinformatics from ordinary PCs — and make it easy for a lab to use.**

Two working blueprints and one shared platform, each taken from a real cluster and made generic so you
can copy the pattern. Scripts are short on purpose: read them top to bottom and you know what they do.

![Slurm](https://img.shields.io/badge/Slurm-scheduler-2C6FBB)
![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-E95420?logo=ubuntu&logoColor=white)
![Ansible](https://img.shields.io/badge/Ansible-playbook-EE0000?logo=ansible&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)

## Pick a blueprint

| | [A — Penguins 🐧](blueprints/networked-ansible) | [B — Croods 🪨](blueprints/offline-usb) |
|---|---|---|
| Starting point | PCs already running Ubuntu | bare PCs (disks get wiped) |
| Network | LAN or VPN (e.g. Tailscale), internet available | private switch, **no internet** |
| Tool | Ansible, run from the controller | one USB stick, unattended install menu |
| Example | 2 nodes: `skipper`, `kowalski` | 6 machines: `grug`, `gran`, `eep`, `ugga`, `thunk`, `guy` |
| Shared storage, backups, cgroup limits | ⏳ not done yet | ✅ |
| Status | foundation done (munge + Slurm) | ✅ complete, in use |

Node names follow a theme per cluster — the Penguins of Madagascar and The Croods — which makes
machines easy to tell apart and label.

Both give you the same thing at the end: **Slurm + shared folders**. Then add the platform.

## The platform (works on either)
[`platform/`](platform) — what makes the cluster useful to biologists:
- **Software** packed for offline use: AutoDock Vina, GROMACS, fpocket, US-align, ESM-2, RDKit, PyTorch (CPU)
- **9 job templates** with example data: docking, pocket detection, MD, ESM mutation scan, FoldX, Rosetta, structure similarity, task farm
- **Web portal**: see the cluster live, submit jobs by form, view tables, plots and 3D structures
- **Cluster 101**: a one-page offline course with real results

## Layout
```
blueprints/
  networked-ansible/   A — Penguins: Ansible playbook (uid, munge, slurm)
  offline-usb/         B — Croods: cluster.env → build.sh → USB → install every machine
platform/
  software/            build + install the science environment
  templates/           00_hello … 08_task_farm
  portal/              web UI
  course/              Cluster 101
  internet/            temporary internet through a laptop
```

## Quick start
1. Choose a blueprint and follow its README until `sinfo` shows your nodes idle.
2. Follow [`platform/README.md`](platform/README.md): software → portal.
3. Open the portal, run **Hello cluster**, then **Docking** with the example data.

## Measured on the Croods example (44 CPU threads, no GPU)
| Workload | Speed |
|---|---|
| GROMACS MD, 19 000 atoms, one 20-thread node | ~80 ns/day |
| Vina docking, exhaustiveness 8 | ~1–5 min per ligand per thread, 44 at once |
| ESM-2 650M full mutation scan, 76 residues | ~2 min |

## Security notes
- Secrets (munge key, admin SSH key, passwords) are generated at build time into `~/hpc-usb-build/secrets` and are **never** committed.
- The portal listens on the head node's `localhost` only.

## Author
Sylvesters Ochieng Oyim

## License
[MIT](LICENSE)
