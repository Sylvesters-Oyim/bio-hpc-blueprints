#!/bin/bash
# Sets up one cluster machine from the USB.   node-setup.sh <hostname> <payload-dir> <repo-dir>
# LIVE=0: inside the installer (services enabled, started at first boot)
# LIVE=1: on the running Desktop head node (services started now)
set -euo pipefail

HOST="$1"; PAYLOAD="$2"; REPO="$3"
LIVE="${LIVE:-0}"
export DEBIAN_FRONTEND=noninteractive
exec > >(tee -a /var/log/cluster-node-setup.log) 2>&1

# shellcheck source=/dev/null
source "$PAYLOAD/cluster.env"
log() { echo "[node-setup $HOST] $*"; }

IP=""; ROLE=""
while read -r h ip r _; do
  [ "$h" = "$HOST" ] && { IP="$ip"; ROLE="$r"; }
done <<< "$NODES"
[ -n "$ROLE" ] || { echo "Unknown host $HOST (not in cluster.env)"; exit 1; }
HEAD=$(awk '$3=="head"{print $1}' <<< "$NODES")
log "role=$ROLE ip=$IP live=$LIVE"

# ---------------------------------------------------------------- identity
echo "$HOST" > /etc/hostname
{
  echo "127.0.0.1 localhost"
  echo "::1       localhost ip6-localhost ip6-loopback"
  echo
  echo "# $CLUSTER_NAME private network"
  while read -r h ip _; do [ -n "$h" ] && echo "$ip  $h"; done <<< "$NODES"
} > /etc/hosts
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
echo "$TIMEZONE" > /etc/timezone

# ---------------------------------------------------------------- fixed UIDs
ensure_account() { # name uid home
  local name=$1 uid=$2 home=$3 other
  other=$(getent group "$uid" | cut -d: -f1 || true)
  if [ -n "$other" ] && [ "$other" != "$name" ]; then
    echo "ERROR: GID $uid is already used by group '$other' on this machine. Change ${name^^}_UID in cluster.env and rebuild."; exit 1
  fi
  other=$(getent passwd "$uid" | cut -d: -f1 || true)
  if [ -n "$other" ] && [ "$other" != "$name" ]; then
    echo "ERROR: UID $uid is already used by user '$other' on this machine. Change ${name^^}_UID in cluster.env and rebuild."; exit 1
  fi
  if getent group "$name" >/dev/null; then
    [ "$(getent group "$name" | cut -d: -f3)" = "$uid" ] || groupmod -g "$uid" "$name"
  else
    groupadd --system -g "$uid" "$name"
  fi
  if id "$name" >/dev/null 2>&1; then
    [ "$(id -u "$name")" = "$uid" ] || usermod -u "$uid" -g "$uid" "$name"
  else
    useradd --system -u "$uid" -g "$uid" -d "$home" -s /usr/sbin/nologin "$name"
  fi
}
if [ "$ROLE" != backup ]; then
  ensure_account munge "$MUNGE_UID" /nonexistent
  ensure_account slurm "$SLURM_UID" /nonexistent
fi

# Admin user: servers get it from autoinstall as UID 1000, renumber it.
if id "$ADMIN_USER" >/dev/null 2>&1; then
  old_uid=$(id -u "$ADMIN_USER"); old_gid=$(id -g "$ADMIN_USER")
  if [ "$old_uid" != "$ADMIN_UID" ]; then
    getent passwd "$ADMIN_UID" >/dev/null && { echo "ERROR: UID $ADMIN_UID already taken; change ADMIN_UID"; exit 1; }
    groupmod -g "$ADMIN_UID" "$(id -gn "$ADMIN_USER")"
    usermod -u "$ADMIN_UID" -g "$ADMIN_UID" "$ADMIN_USER"
    find / -xdev \( -uid "$old_uid" -o -gid "$old_gid" \) -exec chown -h "$ADMIN_UID:$ADMIN_UID" {} + 2>/dev/null || true
  fi
else
  groupadd -g "$ADMIN_UID" "$ADMIN_USER"
  useradd -m -u "$ADMIN_UID" -g "$ADMIN_UID" -s /bin/bash -c "HPC Admin" "$ADMIN_USER"
  echo "$ADMIN_USER:$(cat "$PAYLOAD/secrets/admin-password.txt")" | chpasswd
fi
usermod -aG sudo -s /bin/bash "$ADMIN_USER"
if [ "$ROLE" != head ]; then
  # Local home on nodes: admin console/SSH login must work even when the head node (NFS /home) is down.
  if [ "$(getent passwd "$ADMIN_USER" | cut -d: -f6)" != "/var/lib/$ADMIN_USER" ]; then
    usermod -d "/var/lib/$ADMIN_USER" -m "$ADMIN_USER" 2>/dev/null || {
      mkdir -p "/var/lib/$ADMIN_USER"; usermod -d "/var/lib/$ADMIN_USER" "$ADMIN_USER"; }
    chown "$ADMIN_UID:$ADMIN_UID" "/var/lib/$ADMIN_USER"; chmod 750 "/var/lib/$ADMIN_USER"
  fi
fi
if [ "$ROLE" = head ]; then
  rm -f /etc/sudoers.d/90-cluster-admin   # head node faces the internet: sudo asks for the password
else
  mkdir -p /etc/sudoers.d
  echo "$ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-cluster-admin
  chmod 440 /etc/sudoers.d/90-cluster-admin
fi

# ---------------------------------------------------------------- packages (offline)
mkdir -p /mnt/cluster-repo
if ! mountpoint -q /mnt/cluster-repo; then mount --bind "$REPO" /mnt/cluster-repo; fi
disabled=()
for f in /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do
  [ -e "$f" ] || continue
  mv "$f" "$f.cluster-disabled"; disabled+=("$f")
done
[ -s /etc/apt/sources.list ] && { mv /etc/apt/sources.list /etc/apt/sources.list.cluster-disabled; disabled+=(/etc/apt/sources.list); }
echo "deb [trusted=yes] file:/mnt/cluster-repo ./" > /etc/apt/sources.list.d/cluster-usb.list

restore_sources() {
  rm -f /etc/apt/sources.list.d/cluster-usb.list
  for f in "${disabled[@]}"; do [ -e "$f.cluster-disabled" ] && mv "$f.cluster-disabled" "$f"; done
  mountpoint -q /mnt/cluster-repo && umount /mnt/cluster-repo || true
}
trap restore_sources EXIT

apt-get update
case "$ROLE" in
  head)    PKGS="$COMMON_PKGS $HEAD_PKGS" ;;
  compute) PKGS="$COMMON_PKGS $COMPUTE_PKGS" ;;
  backup)  PKGS="$COMMON_PKGS $BACKUP_PKGS" ;;
esac
if [ "$LIVE" = 0 ]; then
  # fresh server: bring everything to the same patch level as the repo
  apt-get -y -o Dpkg::Options::=--force-confold dist-upgrade
fi
# shellcheck disable=SC2086
apt-get -y -o Dpkg::Options::=--force-confold install $PKGS
apt-get -y install openssh-server   # Desktop doesn't ship an SSH server

# ---------------------------------------------------------------- network
if [ "$LIVE" = 0 ]; then
  : # servers: static netplan written by autoinstall
else
  mapfile -t eths < <(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="ethernet"{print $1}')
  [ "${#eths[@]}" -gt 0 ] || { echo "No wired network port found for the cluster network"; exit 1; }
  dev="${CLUSTER_DEV:-}"
  if [ -z "$dev" ] && [ "${#eths[@]}" -eq 1 ]; then
    dev="${eths[0]}"
  elif [ -z "$dev" ]; then
    echo "Several wired ports found. Which one is plugged into the CLUSTER switch?"
    for i in "${!eths[@]}"; do
      d=${eths[$i]}
      echo "  $((i+1))) $d  mac=$(cat /sys/class/net/$d/address)  cable=$(cat /sys/class/net/$d/carrier 2>/dev/null)  ip=$(ip -4 -br addr show $d | awk '{print $3}')"
    done
    read -r -p "Number: " n </dev/tty
    dev="${eths[$((n-1))]}"
  fi
  [ -n "$dev" ] || { echo "No port chosen"; exit 1; }
  if ip route show default | grep -q " dev $dev "; then
    echo "WARNING: $dev currently carries this machine's internet route."
    read -r -p "Use it for the cluster anyway? (yes/no): " a </dev/tty
    [ "$a" = yes ] || exit 1
  fi
  log "cluster network on $dev"
  nmcli connection delete cluster-lan >/dev/null 2>&1 || true
  nmcli connection add type ethernet ifname "$dev" con-name cluster-lan \
    ipv4.method manual ipv4.addresses "$IP/$NETMASK_BITS" ipv4.never-default yes \
    ipv6.method disabled connection.autoconnect yes
  nmcli connection up cluster-lan || log "cluster-lan not up yet (cable unplugged?) - it will connect when plugged in"
  hostnamectl set-hostname "$HOST"
fi

# ---------------------------------------------------------------- time
if [ "$ROLE" = head ]; then
  cat > /etc/chrony/chrony.conf <<EOF
# Time master for $CLUSTER_NAME
driftfile /var/lib/chrony/chrony.drift
# internet time when the head node is online; its own clock when not
pool ntp.ubuntu.com iburst maxsources 2
pool 2.pool.ntp.org iburst maxsources 2
local stratum 8 orphan
manual
allow $SUBNET_PREFIX.0/$NETMASK_BITS
makestep 1 3
rtcsync
EOF
else
  cat > /etc/chrony/chrony.conf <<EOF
# Follow the head node only (no internet)
server $HEAD iburst
driftfile /var/lib/chrony/chrony.drift
makestep 1 -1
rtcsync
EOF
  systemctl enable chrony-wait.service
fi
systemctl enable chrony.service

# ---------------------------------------------------------------- munge
if [ "$ROLE" != backup ]; then
  install -d -o munge -g munge -m 0700 /etc/munge
  install -o munge -g munge -m 0400 "$PAYLOAD/secrets/munge.key" /etc/munge/munge.key
  if [ "$ROLE" = compute ]; then
    mkdir -p /etc/systemd/system/munge.service.d
    cat > /etc/systemd/system/munge.service.d/10-wait-for-time.conf <<EOF
[Unit]
Wants=chrony-wait.service
After=chrony-wait.service
EOF
  fi
  systemctl enable munge.service
fi

# ---------------------------------------------------------------- slurm
if [ "$ROLE" = head ] || [ "$ROLE" = compute ]; then
  install -d -m 0755 /etc/slurm
  install -m 0644 "$PAYLOAD/files/slurm.conf" /etc/slurm/slurm.conf
  install -m 0644 "$PAYLOAD/files/cgroup.conf" /etc/slurm/cgroup.conf
  # Hybrid CPUs: core pinning would squeeze jobs onto the wrong threads
  [[ " $NO_CORE_PINNING " == *" $HOST "* ]] && sed -i 's/^ConstrainCores=yes/ConstrainCores=no/' /etc/slurm/cgroup.conf
  install -d -o slurm -g slurm -m 0755 /var/log/slurm
fi
if [ "$ROLE" = head ]; then
  install -d -o slurm -g slurm -m 0755 /var/spool/slurmctld
  systemctl enable slurmctld.service
fi
if [ "$ROLE" = compute ]; then
  install -d -m 0755 /var/spool/slurmd /scratch
  chmod 1777 /scratch
  mkdir -p /etc/systemd/system/slurmd.service.d
  cat > /etc/systemd/system/slurmd.service.d/10-cluster.conf <<EOF
[Unit]
RequiresMountsFor=/home /shared
After=munge.service remote-fs.target
EOF
  systemctl enable slurmd.service
fi

# ---------------------------------------------------------------- storage
mkdir -p /shared
if [ "$ROLE" = head ]; then
  chmod 1777 /shared
  cat > /etc/exports <<EOF
# $CLUSTER_NAME exports (managed by node-setup.sh)
/home   $SUBNET_PREFIX.0/$NETMASK_BITS(rw,sync,no_subtree_check,root_squash) $(awk '$3=="backup"{print $2}' <<< "$NODES")(ro,sync,no_subtree_check,no_root_squash)
/shared $SUBNET_PREFIX.0/$NETMASK_BITS(rw,sync,no_subtree_check,root_squash)
EOF
  systemctl enable nfs-server.service
else
  sed -i '/# cluster-nfs$/d' /etc/fstab
  if [ "$ROLE" = backup ]; then
    mkdir -p /mnt/head-home /backup
    echo "$HEAD:/home /mnt/head-home nfs ro,_netdev,nofail,x-systemd.mount-timeout=30 0 0 # cluster-nfs" >> /etc/fstab
    install -m 0755 "$PAYLOAD/scripts/backup-home.sh" /usr/local/sbin/backup-home.sh
    echo "30 2 * * * root /usr/local/sbin/backup-home.sh >> /var/log/backup-home.log 2>&1" > /etc/cron.d/backup-home
  else
    # Plain mounts, not automounts: hardened services (chrony, ...) set up /home namespaces at start
    # and fail if /home is an automount whose server is unreachable.
    echo "$HEAD:/home   /home   nfs defaults,_netdev,nofail,x-systemd.mount-timeout=30 0 0 # cluster-nfs" >> /etc/fstab
    echo "$HEAD:/shared /shared nfs defaults,_netdev,nofail,x-systemd.mount-timeout=30 0 0 # cluster-nfs" >> /etc/fstab
    # Retry the mounts every 2 minutes (e.g. head node booted after this node) and start slurmd once they are up.
    install -m 0755 "$PAYLOAD/scripts/cluster-mount-retry.sh" /usr/local/sbin/cluster-mount-retry
    cat > /etc/systemd/system/cluster-mount-retry.service <<EOF
[Unit]
Description=Retry cluster NFS mounts and start slurmd when ready
After=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/cluster-mount-retry
EOF
    cat > /etc/systemd/system/cluster-mount-retry.timer <<EOF
[Unit]
Description=Retry cluster NFS mounts every 2 minutes
[Timer]
OnBootSec=90
OnUnitActiveSec=120
[Install]
WantedBy=timers.target
EOF
    systemctl enable cluster-mount-retry.timer
  fi
fi
if [ -f /etc/idmapd.conf ]; then
  sed -i -E "s/^#? *Domain *=.*/Domain = $CLUSTER_NAME/" /etc/idmapd.conf
  grep -q "^Domain = $CLUSTER_NAME" /etc/idmapd.conf || sed -i "/^\[General\]/a Domain = $CLUSTER_NAME" /etc/idmapd.conf
fi

# ---------------------------------------------------------------- ssh
install -d -m 0755 /etc/ssh/authorized_keys
install -m 0644 "$PAYLOAD/secrets/admin_ed25519.pub" "/etc/ssh/authorized_keys/$ADMIN_USER"
mkdir -p /etc/ssh/sshd_config.d
echo "AuthorizedKeysFile .ssh/authorized_keys /etc/ssh/authorized_keys/%u" > /etc/ssh/sshd_config.d/10-cluster.conf
if [ "$ROLE" = head ]; then
  home=$(getent passwd "$ADMIN_USER" | cut -d: -f6)
  install -d -o "$ADMIN_USER" -g "$ADMIN_USER" -m 0700 "$home/.ssh"
  install -o "$ADMIN_USER" -g "$ADMIN_USER" -m 0600 "$PAYLOAD/secrets/admin_ed25519" "$home/.ssh/id_ed25519"
  install -o "$ADMIN_USER" -g "$ADMIN_USER" -m 0644 "$PAYLOAD/secrets/admin_ed25519.pub" "$home/.ssh/id_ed25519.pub"
  printf 'Host %s\n  StrictHostKeyChecking accept-new\n' "$(awk 'NF{print $1}' <<< "$NODES" | paste -sd' ')" > "$home/.ssh/config"
  chown "$ADMIN_USER:$ADMIN_USER" "$home/.ssh/config"
  install -m 0755 "$PAYLOAD/scripts/cluster-add-user.sh" /usr/local/sbin/cluster-add-user
  install -m 0755 "$PAYLOAD/scripts/cluster-check.sh" /usr/local/bin/cluster-check
  install -m 0644 "$PAYLOAD/cluster.env" /etc/cluster.env
  echo "ssh" > /etc/pdsh/rcmd_default 2>/dev/null || true
fi
systemctl enable ssh.service 2>/dev/null || true

# ---------------------------------------------------------------- version lock
# Keep cluster-critical packages identical on every machine, even if the head node runs apt upgrade.
for pkg in slurmctld slurmd slurm-client slurm-wlm-basic-plugins munge libmunge2 openmpi-bin; do
  dpkg-query -W -f='${db:Status-Status}' "$pkg" 2>/dev/null | grep -q '^installed$' && apt-mark hold "$pkg" >/dev/null
done

if [ "$ROLE" = head ]; then
  printf '%s\n' "PermitRootLogin no" "MaxAuthTries 4" \
    "# After every user has an SSH key installed, change this to: PasswordAuthentication no" \
    "PasswordAuthentication yes" > /etc/ssh/sshd_config.d/20-head-hardening.conf
fi

# ---------------------------------------------------------------- platform hooks
# Science software lives on /shared (see platform/software); put it on everyone's PATH.
echo 'export PATH=$PATH:/shared/apps/sbio/bin' > /etc/profile.d/sbio.sh
install -m 0755 "$PAYLOAD/scripts/cluster-internet" /usr/local/sbin/cluster-internet

# ---------------------------------------------------------------- never sleep
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

if [ "$LIVE" = 1 ]; then
  systemctl daemon-reload
  systemctl restart chrony
  [ "$ROLE" != backup ] && systemctl restart munge
  [ "$ROLE" = head ] && { exportfs -ra; systemctl restart nfs-server slurmctld; }
  systemctl reload ssh 2>/dev/null || true
fi

log "done"
