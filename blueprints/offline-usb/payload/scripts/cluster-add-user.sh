#!/bin/bash
# Create a cluster user with the same UID/GID on every machine.
#   sudo cluster-add-user <username> [uid]
# Run on the head node. Homes live on the head node and are shared by NFS.
set -euo pipefail
source /etc/cluster.env

[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
name="${1:?usage: cluster-add-user <username> [uid]}"
if [ -n "${2:-}" ]; then uid=$2; else
  uid=$(awk -F: '$3>=2001 && $3<60000 {print $3}' /etc/passwd | sort -n | tail -1)
  uid=$(( ${uid:-2000} + 1 ))
fi
getent passwd "$uid" >/dev/null && { echo "UID $uid already used"; exit 1; }

groupadd -g "$uid" "$name"
useradd -m -u "$uid" -g "$uid" -s /bin/bash "$name"
echo "Set a password for $name (used to log in to the head node):"
passwd "$name"

while read -r h ip role _; do
  [ -z "$h" ] || [ "$role" = head ] && continue
  echo "-> $h"
  sudo -u "$ADMIN_USER" ssh -o ConnectTimeout=5 "$h" \
    "sudo groupadd -g $uid $name && sudo useradd -M -u $uid -g $uid -d /home/$name -s /bin/bash $name" \
    || echo "   !! $h unreachable - run this there later: groupadd -g $uid $name && useradd -M -u $uid -g $uid -d /home/$name -s /bin/bash $name"
done <<< "$NODES"
echo "User $name created with UID/GID $uid"
