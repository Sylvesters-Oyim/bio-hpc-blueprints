# BioLab Cluster — Build & Operations Manual

**Version:** 0.1 (foundation)
**Intended home:** `biolab-cookbook/manual/BioLab_Cluster_Manual.md`
**Purpose:** A single, ordered, runnable procedure for building and operating the BioLab cluster. Follow it top to bottom and you (or anyone else, on any hardware) end up with the same working cluster.

---

## 0. How to read this manual

### Three principles this whole document obeys

1. **Own the science, rent the plumbing.** Our contribution is the biology and the methods. Scheduling, orchestration, containers, and resume-logic are solved problems — we adopt standard tools (Slurm, Apptainer, Nextflow) instead of rebuilding worse versions we alone would maintain.
2. **Measure, don't recall.** No step is documented from memory. We run a command, read the real output, then act. Memory blurs "we discussed X" with "X exists" — the machine never does.
3. **The playbook *is* the documentation.** We build the cluster *through* Ansible. The same file that provisions the cluster is the runbook, the reproducibility proof, and the home-lab replay button. There is no second "write it up" pass.

### The shape of every phase

Each phase below follows the same rhythm:

- **Goal** — the one observable outcome that means "done."
- **Why** — the reasoning, so the step makes sense and you can adapt it.
- **Do** — the exact actions/commands.
- **Verify** — the green light. **Do not proceed until Verify passes.**

---

## 1. Target architecture (the clean version)

```
  You
   │
   ▼
  Thin CLI  (biolab run …)              ← convenience wrapper only
   │
   ▼
  Nextflow / Snakemake                  ← orchestration: DAG, -resume, provenance
   │  (submits to)
   ▼
  Slurm  ──────► Apptainer              ← scheduler + container runtime (HPC standard)
   │
   ▼
  biolab core library (plain Python)    ← OUR biology: variants, structures, RINs, CRT
   │
   ▼
  Scientific outputs
```

**One-line rationale per layer**

- **CLI** — nice ergonomics; internally shells out to `nextflow run … -profile apptainer,slurm -resume`. No orchestration logic of its own.
- **Nextflow/Snakemake** — gives us skip-completed, resume, provenance, retries, Slurm submission, and cloud portability *for free*. This is the box we deliberately do **not** build.
- **Slurm** — the scheduler real HPC (including CHPC Lengau) runs. Node count is irrelevant; the *skill and interface* are what transfer.
- **Apptainer** — rootless, daemonless container runtime; the HPC standard. Docker stays on the dev laptop only.
- **biolab core library** — plain importable Python. This is where our intellectual contribution lives and the only software we truly own.

**What we are NOT building** (dropped as YAGNI until a concrete need appears): a custom workflow engine, hand-rolled skip/resume/provenance, a plugin architecture, "AI" as an architectural pillar, a cloud abstraction layer, and multi-user complexity.

> **Scope note for this cluster:** Jaguar and Lynx have no GPU. This cluster is for **pipeline development and light/CPU-bound work**. Production GPU molecular dynamics runs on **CHPC Lengau**. Same Slurm + Apptainer interface, so pipelines move between them unchanged.

---

## 2. This cluster — known facts

Facts are either **MEASURED** (read off the machine) or **PENDING** (not yet verified — do not treat as true).

### Jaguar — head / controller node — MEASURED

| Fact | Value |
|---|---|
| Hostname | `jaguar` |
| Role | head / controller / login / admin |
| OS | Ubuntu Server 24.04.4 LTS |
| Kernel | 6.17.0-35-generic |
| CPU | Intel Core i7-12700 — **20 logical CPUs** |
| RAM | ~16 GB (15 GiB usable) |
| GPU | none |
| Disk | 1 TB NVMe (`/dev/nvme0n1p2`, 915 G, 3 % used) |
| Campus IPv4 (Rhodes) | `146.231.75.232` |
| Tailscale IPv4 | `100.71.55.41` |
| Docker bridge | `172.17.0.1` |
| Admin user | `clusteradmin` |
| Slurm / munge / Apptainer / Nextflow | **NOT installed** (greenfield) |

### Lynx — compute node — PENDING

Run the Phase 0 inventory script on Lynx and paste the output back to complete this table. Do **not** assume "same as Jaguar."

| Fact | Value |
|---|---|
| Hostname | `lynx` (expected) |
| Role | compute |
| OS | _PENDING_ |
| CPU / logical CPUs | _PENDING_ |
| RAM | _PENDING_ |
| Disk | _PENDING_ |
| LAN IPv4 | _PENDING_ |
| Tailscale IPv4 | `100.121.100.74` (inferred from Jaguar's NFS export — **confirm**) |
| Admin user | `clusteradmin` (expected) |

### Shared storage — MEASURED

- NFS server active on Jaguar. Export: `/srv/biolab/shared  100.121.100.74(rw,sync,no_subtree_check)`
- Shared root: `/srv/biolab/shared` → contains `repos/`, `projects/`, `software/`

### Docker images present on Jaguar — MEASURED

`biolab/base:1.0`, `biolab/python-bio:1.0`, `biolab/blast:1.0`, `biolab/alignment:1.0`, `biolab/mmseqs2:1.0`, `biolab/docking:1.0`, `biolab/docking:1.1`, `biolab/pymol:1.0` (plus `bash`, `ubuntu:24.04`, `hello-world`).

> These are **kept** for now and become the source material for Apptainer images later. Note `docking` and `pymol` — not in earlier notes; the measurement caught them.

### Three decisions the measurement surfaced

1. **NFS is running over Tailscale, not the Gigabit LAN.** Every shared-storage read/write currently rides the WireGuard tunnel.
   - *Trade-off:* Tailscale = portable + encrypted + works if a node changes network, but adds CPU overhead and may not saturate Gigabit — which matters for large MD trajectory I/O. LAN export = faster, local only.
   - *Recommendation:* **Keep Tailscale for now** (it works; don't fix what isn't broken). Record "add a LAN NFS path over the Gigabit switch" as a *future tuning step*, to be taken only if/when shared I/O becomes a measured bottleneck. Also consider exporting to the Tailscale **subnet** or a hostname rather than a single hard-coded IP, so a changed Lynx IP doesn't silently break the mount.
2. **Foundation is greenfield.** Nothing scheduler-related is installed, so Phase 1 (Reset) is purely repo/code hygiene — there is no infrastructure to tear down.
3. **Image inventory is larger than remembered.** Eight `biolab/*` images exist. The Apptainer conversion list (later phase) must cover all eight, not five.

---

## 3. Phase 0 — Inventory (measure every node)

**Goal:** A saved, read-only state report for each node, committed to the repo.

**Why:** Every later decision (Slurm resources, NFS layout, what to reset) depends on real state. This script is also your first reusable tool — run it any time you touch the cluster to see what changed.

**Do:** Save this as `biolab-cookbook/tools/inventory.sh`, then run on **each node**.

```bash
#!/usr/bin/env bash
# BioLab cluster inventory — READ ONLY. Changes nothing.
echo "=== IDENTITY ==="; hostnamectl 2>/dev/null | grep -E 'hostname|Operating|Kernel'; echo "IPs:"; hostname -I
echo "=== CPU / MEM ==="; lscpu | grep -E 'Model name|^CPU\(s\)'; free -h | head -2; echo "cores: $(nproc)"
echo "=== GPU ==="; command -v nvidia-smi >/dev/null && nvidia-smi -L || echo "no GPU / no nvidia-smi"
echo "=== SLURM ==="; command -v sinfo >/dev/null && { sinfo; scontrol show config 2>/dev/null | grep -E 'ClusterName|ControlMachine|SlurmctldHost'; } || echo "slurm NOT installed"
echo "=== SLURM/MUNGE SERVICES ==="; systemctl is-active slurmctld slurmd munge 2>/dev/null
echo "=== MUNGE AUTH ==="; command -v munge >/dev/null && munge -n | unmunge 2>/dev/null | grep STATUS || echo "munge NOT installed"
echo "=== APPTAINER ==="; command -v apptainer >/dev/null && apptainer --version || { command -v singularity >/dev/null && singularity --version || echo "NOT installed"; }
echo "=== DOCKER ==="; command -v docker >/dev/null && docker images 2>/dev/null || echo "docker not installed / not permitted"
echo "=== NFS MOUNTS ==="; mount | grep -i nfs || echo "no nfs mounts on this node"
echo "--- exports (controller only) ---"; cat /etc/exports 2>/dev/null || echo "no /etc/exports here"
echo "=== DISK ==="; df -h | grep -vE 'tmpfs|udev|loop'
echo "=== NEXTFLOW ==="; command -v nextflow >/dev/null && nextflow -version 2>/dev/null | grep version || echo "nextflow NOT installed"
```

```bash
chmod +x tools/inventory.sh
./tools/inventory.sh | tee inventory_$(hostname)_$(date +%F).txt
```

**Verify:**
- [x] Jaguar report captured (done).
- [ ] Lynx report captured. **← next action.** Also run `ssh clusteradmin@lynx hostname` from Jaguar to confirm cross-node SSH.

---

## 4. Phase 1 — Reset to a clean baseline

**Goal:** The repos contain only (a) biology domain code we keep and (b) a thin CLI stub — no custom-engine code.

**Why:** We changed direction. Any orchestration code we started must go, so it can't quietly become load-bearing again. But **we verify before we delete** — the earlier reset list contained *guessed* paths, and deleting a guessed path can destroy real work.

### Step 1 — Locate what actually exists (read-only)

```bash
cd /srv/biolab/shared/repos/biolab-platform
tree -L 3 .                                   # see the real structure
find . -name '*.py' | xargs grep -l -E 'orchestrat|workflow.?engine|def run_workflow|build_dag' 2>/dev/null
ls -R workflows 2>/dev/null || echo "no workflows/ dir"
find . -type d -name plugins 2>/dev/null
ls services/ai docker/alphafold 2>/dev/null || echo "no AI scaffolding"
cat cli/biolab 2>/dev/null | head -40         # inspect the CLI
```

### Step 2 — Decide per item, then act

Work through this table. **If a path doesn't exist, there is nothing to do — move on.**

| Item | Verify it exists | Action if present |
|---|---|---|
| Custom workflow engine code | `grep` above finds orchestration logic | **Delete** the engine module(s). Replaced by Nextflow. |
| CLI orchestration (`cli/biolab`) | `cat` shows `workflow run …` logic | **Strip** orchestration; keep only `biolab version` and a thin passthrough. Nextflow launcher comes later. |
| Skip / resume / provenance code | grep for `resume`, `checksum`, `skip` | **Delete if hand-rolled.** Nextflow owns this. |
| Plugin scaffolding (`plugins/`) | `find` above | **Delete** if empty/unused. |
| AI pillar dirs (`services/ai`, `docker/alphafold`) | `ls` above | **Delete** empty scaffolding. AI is just a future workflow step, not a layer. |
| Cloud scaffolding | `find . -iname '*cloud*'` | **Delete** if present. |
| **Domain code** (reference, structure, variants) | `ls services/*/` | **KEEP.** Do not delete. Mark for refactor into the `biolab` library in Phase 3. |
| Docker images | (from Phase 0) | **KEEP.** Apptainer conversion happens later; deleting now loses working tools. |

> **Demote, don't destroy:** the structure/reference/variant logic is your validated thesis work (it worked for CYP2C9/CYP2C19). It stops being an "engine service" and becomes a plain library function — a conceptual move, not a deletion.

### Step 3 — Record the reset

```bash
git add -A && git commit -m "reset: remove custom-engine scaffolding; keep domain logic for library refactor"
```

**Verify:**
- [ ] `tree` shows no `workflows/`, `plugins/`, `services/ai`, cloud scaffolding.
- [ ] `cli/biolab version` still works; it contains no orchestration.
- [ ] Domain modules (reference/structure/variants) still present and untouched.
- [ ] Reset committed to git.

---

## 5. Phase 2 — Cluster foundation (Ansible-first)

**Goal:** `ansible-playbook site.yml` provisions the cluster from a near-bare node, and afterwards:

```bash
srun -N2 hostname          # prints "jaguar" and "lynx"
```

**Why:** That single command proves the whole foundation at once — controller, compute node, scheduler, munge auth, and shared storage all working together. We build it *through* Ansible so the build and its documentation are the same artifact.

### Decisions to lock before writing playbooks

1. **NFS network path** — keep Tailscale now (see §2 decision 1). ✅ default
2. **User model** — single-user for the thesis: jobs run as `clusteradmin` (or the `jaguar` research user). Multi-user is deferred. ✅ default
3. **Munge key** — generate once on Jaguar; Ansible distributes the identical key to Lynx (Slurm auth requires a shared key). 
4. **Slurm topology** — `jaguar` = controller (runs `slurmctld`) **and** a compute node; `lynx` = compute (`slurmd`). One partition to start.

> Resource parameters in `slurm.conf` (CPUs, RealMemory per node) need **Lynx's measured specs**. Jaguar = 20 CPUs. Finalize the template after Phase 0 on Lynx.

### The Ansible-first rule

You do **not** need Ansible fluency to start. A first role that installs packages and drops config files is barely harder than typing the commands — you're just writing them in a file instead of a terminal. The skill compounds from there.

### Repo skeleton

```
biolab-cluster/                 # new repo (or biolab-cookbook/cluster/)
├── ansible.cfg
├── inventory/
│   └── hosts.ini
├── group_vars/
│   └── all.yml
├── site.yml
├── roles/
│   ├── common/                 # hostnames, /etc/hosts, base packages, users
│   ├── munge/                  # install + shared key + service
│   ├── nfs/                    # assert exports (Jaguar) + mounts (Lynx)  [mostly exists]
│   ├── slurm/                  # slurm.conf, controller + compute, services
│   └── apptainer/              # install Apptainer
└── templates/
    ├── hosts.j2
    └── slurm.conf.j2
```

### Starter files

`inventory/hosts.ini`
```ini
[controller]
jaguar ansible_host=100.71.55.41

[compute]
lynx   ansible_host=100.121.100.74   # CONFIRM Lynx Tailscale IP in Phase 0

[cluster:children]
controller
compute

[cluster:vars]
ansible_user=clusteradmin
ansible_python_interpreter=/usr/bin/python3
```

`ansible.cfg`
```ini
[defaults]
inventory = inventory/hosts.ini
host_key_checking = False
retry_files_enabled = False
```

`site.yml`
```yaml
- name: BioLab cluster foundation
  hosts: cluster
  become: true
  roles:
    - common
    - munge
    - nfs
    - slurm
    - apptainer
```

`roles/common/tasks/main.yml` — safe to run today (node-agnostic):
```yaml
- name: Ensure /etc/hosts has cluster names
  ansible.builtin.blockinfile:
    path: /etc/hosts
    block: |
      {{ hostvars['jaguar'].ansible_host }} jaguar
      {{ hostvars['lynx'].ansible_host }}   lynx
    marker: "# {mark} BIOLAB CLUSTER HOSTS"

- name: Install base packages
  ansible.builtin.apt:
    name: [build-essential, git, curl, htop, tree, nfs-common]
    state: present
    update_cache: true
```

### Sub-phases (order of execution)

1. **`common`** — hosts file, base packages. *Verify:* `ansible cluster -m ping` returns green from Jaguar.
2. **`munge`** — install; generate key on Jaguar; copy identical key to Lynx (mode `0400`, owner `munge`); start service. *Verify:* `munge -n | ssh lynx unmunge | grep STATUS` → `Success`.
3. **`nfs`** — assert Jaguar's export and Lynx's mount of `/srv/biolab/shared` (largely already in place). *Verify:* a file written on Jaguar appears on Lynx.
4. **`slurm`** — render `slurm.conf` from measured node specs; start `slurmctld` on Jaguar, `slurmd` on both. *Verify:* `sinfo` shows both nodes `idle`.
5. **`apptainer`** — install from the official apt repo. *Verify:* `apptainer run docker://hello-world` succeeds on both nodes.

**Milestone Verify (the whole phase):**
```bash
sinfo                       # both nodes idle
srun -N2 hostname           # prints jaguar and lynx
```
Green here = the architecture is validated. Everything after this stands on proven ground.

---

## 6. What comes after the foundation (staged, not yet detailed)

These become full sections once Phase 2 is green. Listed here so the order is fixed:

- **Phase 3 — `biolab` core library.** Refactor the kept domain code (reference retrieval, structure discovery/selection/prep, variant FASTA, RINs) into a clean, importable, unit-tested Python package. No orchestration inside it. Add **database-release capture** (ClinVar / gnomAD / PharmVar) to provenance from day one — pharmacogenomics annotations shift between releases.
- **Phase 4 — First Nextflow spike (`structure`, CYP2C9).** Smallest possible pipeline. Run it, interrupt it, re-run with `-resume`, confirm it skips completed work. This *retires the custom engine idea with proof*. Don't polish it.
- **Phase 5 — Apptainer conversion.** Convert the eight `biolab/*` Docker images (base, python-bio, blast, alignment, mmseqs2, docking ×2, pymol) to Apptainer `.sif`, versioned in shared storage.
- **Phase 6 — Real workflows.** Docking → MD → network analysis, each as a Nextflow pipeline submitting to Slurm, calling the `biolab` library.

---

## Appendix A — Operating conventions

- **Every session starts with `tools/inventory.sh`** on any node you'll touch. State first, action second.
- **Every change is an Ansible change.** If you fix something by hand, port it into a role before you forget — otherwise the cluster and its documentation drift apart.
- **Nothing is "done" without a green Verify.** A phase you can't verify is a phase you can't reproduce.
- **Provenance = automatic + authored.** The engine records *what* ran (tool, version, params, DB release). *Why* a tool was chosen is authored — an ADR in `biolab-cookbook`, not runtime metadata.
