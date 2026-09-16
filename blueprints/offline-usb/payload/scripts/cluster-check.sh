#!/bin/bash
# Health check for the whole cluster. Run on the head node as the admin user.
source /etc/cluster.env
ok()   { printf '  \e[32mOK\e[0m   %s\n' "$*"; }
bad()  { printf '  \e[31mFAIL\e[0m %s\n' "$*"; }

echo "== head node services"
for s in chrony munge nfs-server slurmctld; do
  systemctl is-active -q "$s" && ok "$s running" || bad "$s not running (sudo systemctl status $s)"
done

echo "== each machine"
while read -r h ip role _; do
  [ -z "$h" ] || [ "$role" = head ] && continue
  if ! ping -c1 -W1 "$ip" >/dev/null 2>&1; then bad "$h ($ip) no ping - cable/power/IP?"; continue; fi
  if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$h" true 2>/dev/null; then bad "$h ssh failed"; continue; fi
  ok "$h reachable"
  offset=$(ssh "$h" "chronyc -n tracking | awk '/System time/{print \$4}'")
  ssh "$h" "chronyc -n sources | grep -q '^\^\*'" && ok "$h time synced (offset ${offset}s)" || bad "$h not synced to head node"
  if [ "$role" = compute ]; then
    munge -n | ssh "$h" unmunge >/dev/null 2>&1 && ok "$h munge key matches" || bad "$h munge key/time mismatch"
    ssh "$h" "ls /home >/dev/null && mountpoint -q /home && mountpoint -q /shared" && ok "$h NFS /home and /shared mounted" || bad "$h NFS mounts missing"
    ssh "$h" "systemctl is-active -q slurmd" && ok "$h slurmd running" || bad "$h slurmd not running"
  fi
done <<< "$NODES"

echo "== slurm"
sinfo -N -o '%N %T %c %m %E'
