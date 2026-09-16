# Blueprint B — Croods: offline cluster from one USB stick

Build a Slurm cluster from **bare PCs with no internet** (e.g. a university network that blocks
unregistered devices). One USB stick installs every machine, fully offline.

Machines are named after **The Croods**: `grug` leads (head node), `gran` remembers (backups),
`eep`, `ugga`, `thunk` and `guy` do the work.

```
          [ switch — private 10.0.0.x, no internet ]
   |          |        |       |        |        |
  grug       gran     eep    ugga    thunk     guy
  head       backup   ─────── compute nodes ───────
  Slurm, NFS /home + /shared, time server
```

**Use this when:** machines can't reach the internet, or you want identical fresh installs.

## What you get
- Ubuntu Server 24.04 on every node, installed unattended from a boot menu
- Slurm with cgroup CPU/memory limits, Munge, OpenMPI
- Shared `/home` and `/shared` over NFS; nightly snapshots of `/home` on the backup machine
- Head node can be an existing Ubuntu 24.04 **Desktop** (keeps your files)
- Health check (`cluster-check`) and user tool (`cluster-add-user`)

## Files
| File | What |
|---|---|
| `cluster.env` | **the one file you edit**: names, IPs, hardware |
| `build.sh` | makes the USB image (on a PC with internet + docker) |
| `write-usb.sh` | writes the image to a stick |
| `test-vm.sh` | optional: try an install in a VM first |
| `payload/setup-headnode.sh` | turns an Ubuntu Desktop into the head node |
| `payload/scripts/node-setup.sh` | what every machine runs during install |

## Steps

### 1. Build the stick (PC with internet)
```bash
mkdir -p ~/hpc-usb-build
wget -P ~/hpc-usb-build https://releases.ubuntu.com/24.04.5/ubuntu-24.04.5-live-server-amd64.iso
nano cluster.env           # your names, IPs, hardware
./build.sh                 # ~30 min first time (downloads packages)
bash write-usb.sh /dev/sdX # your USB stick
cat ~/hpc-usb-build/secrets/admin-password.txt   # admin password, same on all machines
```

### 2. Cable
All machines on one switch. The head node's wired port goes to the switch.

### 3. Head node (existing Ubuntu 24.04 Desktop)
```bash
sudo bash "/media/$USER/<usb-name>/cluster/setup-headnode.sh"
```

### 4. Every other machine, one at a time
1. BIOS: storage mode **AHCI** (not RAID/RST), boot mode **UEFI**.
2. Boot from the USB (F12/F11/F9), pick **WIPE DISK and install eep …**.
3. It installs offline and powers off (~10 min SSD, 30+ min HDD). Remove the USB, power on.

Do one compute node and check it (step 5) before the rest.

### 5. Check (on the head node)
```bash
sudo -iu hpcadmin
cluster-check              # all green
sinfo                      # nodes idle
srun -N4 hostname          # four names
```

### 6. Add people
```bash
sudo cluster-add-user alice
```

Then add the software, templates and web portal: see [`platform/`](../../platform).

## Fixes
| Problem | Fix |
|---|---|
| Node `inval`, reason `Low RealMemory` | a RAM stick is missing: add `RealMemory=…` to that node's line in `cluster.env` |
| Newer Intel CPU (12th gen+) shows too few CPUs | add `CPUs=… CoresPerSocket=… ThreadsPerCore=1` to its line and its name to `NO_CORE_PINNING` |
| Node `down` / `drain` | `sudo scontrol update nodename=eep state=resume` |
| `munge` mismatch in `cluster-check` | clocks differ: `ssh eep chronyc sources` must show `^*` on the head node |
| Install stops, no disk found | BIOS storage mode is RAID/RST → set AHCI |
| Redo a machine | install it again from the USB — safe to repeat |

Changed a running cluster's `slurm.conf` by hand? Copy it to **every** node, then
`sudo systemctl restart slurmctld` (head) and `slurmd` (nodes). Rebuild the USB later so new installs match.

Logs: `/var/log/cluster-node-setup.log` on every machine.

## Lessons from the working example
Built on 6 office PCs (4× i7-7700, 1× i7-9700, 1× i7-12700) behind a campus network that blocks unregistered devices.
- **Mixed hardware is normal.** One PC was a RAM stick short, one had a hybrid CPU → per-node lines in `cluster.env`.
- **Hand out threads, not cores** (`CR_CPU_Memory`): 1-thread jobs otherwise take 2 threads, wasting a quarter of the cluster.
- **Hybrid CPUs:** Slurm 23.11 sees 16 of 20 threads on an i7-12700 → `config_overrides` + no core pinning on that node.
- **Old PCs:** some keep rebooting mid-install (bad hardware); set them aside rather than debugging for hours.
- **Internet when needed:** a laptop on the switch can share its Wi-Fi — see `platform/internet`.
