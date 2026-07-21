# BioLab Cluster

**Infrastructure-as-code for the BioLab Slurm cluster.** The playbook *is* the
documentation: run it and you get a working Slurm cluster; read it and you know
exactly how it was built.

![Ansible](https://img.shields.io/badge/Ansible-playbook-EE0000?logo=ansible&logoColor=white)
![Slurm](https://img.shields.io/badge/Slurm-24.11.5-2C6FBB)
![Apptainer](https://img.shields.io/badge/Apptainer-HPC-1D3557)
![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-E95420?logo=ubuntu&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)

> **Guiding principle — own the science, rent the plumbing.** Scheduling,
> orchestration and containers are solved problems, so we adopt standard tools
> (Slurm, Apptainer, Nextflow) instead of rebuilding worse versions. The
> playbook is the runbook, the reproducibility proof, and the home-lab replay
> button — there is no second "write it up" pass.

---

## What this builds

A small, reproducible HPC cluster for **pipeline development and CPU-bound
bioinformatics** (production GPU molecular dynamics runs on CHPC Lengau — same
Slurm + Apptainer interface, so pipelines move unchanged).

```
  You
   │  ansible-playbook site.yml
   ▼
  Slurm  ──────►  Apptainer          ← scheduler + rootless container runtime (HPC standard)
   │
   ▼
  biolab core library (plain Python) ← the biology: variants, structures, RINs, CRT
   │
   ▼
  Scientific outputs
```

Munge provides the shared-secret auth Slurm daemons use to trust each other;
NFS (`/srv/biolab/shared`) is the single source of truth for containers,
modules, workflows and reference data.

## The cluster

| | Jaguar (controller) | Lynx (compute) |
|---|---|---|
| Role | head / login / `slurmctld` + compute | compute (`slurmd`) |
| OS | Ubuntu Server 24.04 LTS | Ubuntu (26.04) |
| CPU | Intel i7-12700 — 20 logical | 20 logical |
| Tailscale IPv4 | `100.71.55.41` | `100.121.100.74` |
| Admin user | `clusteradmin` (UID aligned to 1001) | `clusteradmin` |

Slurm is **built from one pinned source version on every node** (24.11.5) — the
controller and compute node run different Ubuntu releases, and Slurm forbids a
compute node newer than its controller, so distro packages won't do.

## Repository layout

```
biolab-cluster/
├── ansible.cfg
├── site.yml                     # master playbook (run role-by-role via --tags)
├── inventory/
│   └── hosts.ini                # controller + compute nodes and their specs
├── group_vars/
│   └── all.yml                  # pinned Slurm version, cluster name, UID policy
├── roles/
│   ├── uid_align/               # break-glass admin + align clusteradmin UID
│   ├── munge/                   # install + shared key + service
│   └── slurm/                   # source-build Slurm, config, systemd units, services
│       └── templates/           # slurm.conf.j2, slurmctld/slurmd .service.j2
└── docs/
    ├── BioLab_Cluster_Manual.md   # bare metal → working Slurm/Apptainer/NFS cluster
    └── BioLab_Platform_Manual.md  # the software platform above the cluster
```

## Prerequisites

Run from **Jaguar** (it has passwordless key + sudo into itself and Lynx):

```bash
cd biolab-cluster
sudo apt install -y ansible
ansible-galaxy collection install community.general ansible.posix
```

## Quickstart — run role-by-role, verify at each checkpoint

> Do **not** run everything at once the first time. Each step has a green light
> you must see before moving on.

```bash
# 1. Safety net FIRST: a break-glass admin so the UID change can't lock you out
ansible-playbook site.yml --tags safety
ssh biolabadmin@lynx 'sudo -n true && echo BREAK-GLASS-WORKS'   # must print this

# 2. Align clusteradmin UID across nodes (the one risky step; the net above protects it)
ansible-playbook site.yml --tags uid
ssh clusteradmin@lynx 'id'                                      # must show uid=1001

# 3. Munge shared-secret auth
ansible-playbook site.yml --tags munge
ssh clusteradmin@jaguar 'munge -n | ssh lynx unmunge | grep STATUS'   # Success

# 4. Build + start Slurm (slow: compiles from source, a few min per node)
ansible-playbook site.yml --tags slurm
```

## The milestone — cluster is UP when this works

```bash
sinfo                 # both nodes idle
srun -N2 hostname     # prints: jaguar  and  lynx
```

Green here means the whole foundation — controller, compute node, scheduler,
munge auth and shared storage — is validated.

## Adding a node later (including GPU)

1. Add one line under `[compute]` in `inventory/hosts.ini` with its `node_addr`,
   `slurm_cpus`, `slurm_realmem` (for a GPU box also add `slurm_gres=gpu:1`).
2. Ensure Jaguar has passwordless key + sudo into it (same bootstrap as Lynx).
3. GPU only: install the NVIDIA driver on that box and uncomment `GresTypes=gpu`
   in `roles/slurm/templates/slurm.conf.j2`.
4. Re-run `ansible-playbook site.yml`. No rebuild of existing nodes.

## Documentation

- **[docs/BioLab_Cluster_Manual.md](docs/BioLab_Cluster_Manual.md)** — the full
  build & operations manual: bare metal → working Slurm + Apptainer + NFS.
- **[docs/BioLab_Platform_Manual.md](docs/BioLab_Platform_Manual.md)** — the
  software platform above the cluster: containers, workflows, modules, provenance.

## Notes on this repository

Assembled from the working configuration into the canonical Ansible layout the
manuals describe. Three small files were **added during assembly** because the
roles referenced them but they weren't in the original set — each is marked with
a `NOTE:` header: `roles/munge/handlers/main.yml`,
`roles/slurm/handlers/main.yml`, and the `slurmctld/slurmd` systemd unit
templates. Review the systemd units before production use.

## Author

**Sylvesters Ochieng Oyim** — Rhodes University

## License

Released under the [MIT License](LICENSE).
