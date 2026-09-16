# Blueprint A — Penguins: networked cluster with Ansible

Turn PCs that **already run Ubuntu and can reach each other** (same LAN or a VPN such as
Tailscale) into a Slurm cluster, from one control machine.

Machines are named after the **Penguins of Madagascar**: `skipper` (controller), `kowalski` (compute), `rico` (future GPU node).

**Use this when:** machines are already installed, have internet, and may run different Ubuntu versions.

## What it sets up
| Step | Tag | Why |
|---|---|---|
| Spare admin account | `safety` | lets you back in if the UID change goes wrong |
| Same admin UID everywhere | `uid` | jobs and shared files are owned by UID number, not name |
| Munge | `munge` | shared key so Slurm daemons trust each other |
| Slurm (built from source) | `slurm` | one version on every node, whatever the Ubuntu release |

## Before you start
On the controller:
```bash
sudo apt install -y ansible
ansible-galaxy collection install community.general ansible.posix
```
The controller needs passwordless SSH + sudo into every node as `clusteradmin`.

## Steps
1. Edit `inventory/hosts.ini`: one line per machine (`slurmd -C` on a node prints its CPUs and memory).
2. Edit `group_vars/all.yml`: cluster name, controller name, admin user.
3. Run one step at a time and check before continuing:
```bash
ansible-playbook site.yml --tags safety
ssh breakglass@kowalski 'sudo -n true && echo OK'        # must print OK

ansible-playbook site.yml --tags uid
ssh clusteradmin@kowalski id                              # uid=1001 on every node

ansible-playbook site.yml --tags munge
munge -n | ssh kowalski unmunge | grep STATUS             # Success

ansible-playbook site.yml --tags slurm                  # slow: compiles Slurm
```

**Done when:**
```bash
sinfo                 # all nodes idle
srun -N2 hostname     # prints skipper and kowalski
```

## Add a node
Add a line to `inventory/hosts.ini`, give the controller SSH access, re-run `ansible-playbook site.yml`.

## Status
| Part | State |
|---|---|
| Admin UID, munge, Slurm | ✅ done, used on a 2-node cluster (2× i7-12700 over Tailscale) |
| cgroup CPU/memory limits | ⏳ not done yet (`task/none` for now) |
| NFS shared `/home` and `/shared` | ⏳ not done yet — needed before `platform/` works here |
| Apptainer containers | ⏳ not done yet |
| Nextflow / Snakemake | ⏳ not done yet |
| GPU node | ⏳ not done yet (commented example in inventory) |

Until NFS is done, see `blueprints/offline-usb` for a working NFS, cgroup and backup setup to copy.

## Lessons from the working example
- Different Ubuntu releases ship different Slurm versions; a compute node newer than the controller is refused → build from source.
- Change UIDs only after the spare admin works; a wrong UID can lock you out of your own home folder.
